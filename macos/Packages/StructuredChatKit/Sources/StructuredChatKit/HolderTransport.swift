import Darwin
import Foundation

/// holder（ADR 0233）を起動する。holderはこのアプリ自身の実行ファイルを`--session-holder`で起動したもの。
public enum HolderLauncher {
    /// 起動して`READY`を待つ。失敗時はholderを止める（子はholderの終了で標準入力を失う）。
    public static func spawn(spec: HolderSpawnSpec, executable: String, timeout: TimeInterval = 15) throws -> HolderRecord {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--session-holder"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // holderが先に終了した後のspec書き込みがSIGPIPEで本体を落とさないようにする。
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { throw HolderError.launchFailed(String(describing: error)) }
        let encoded: Data
        do { encoded = try JSONEncoder().encode(spec) } catch { process.terminate(); throw HolderError.launchFailed("spec") }
        try? input.fileHandleForWriting.write(contentsOf: encoded)
        try? input.fileHandleForWriting.close()

        let box = LineBox()
        let done = DispatchSemaphore(value: 0)
        let reader = output.fileHandleForReading
        Thread.detachNewThread {
            var buffer = Data()
            while true {
                guard let chunk = try? reader.read(upToCount: 4096), !chunk.isEmpty else { break }
                buffer.append(chunk)
                if let newline = buffer.firstIndex(of: 0x0A) {
                    box.value = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8)
                    break
                }
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success, let line = box.value else {
            process.terminate()
            throw HolderError.launchFailed("holderの準備完了を確認できません")
        }
        try? reader.close()
        guard line.hasPrefix("READY "), let data = line.dropFirst(6).data(using: .utf8) else {
            throw HolderError.launchFailed(line)
        }
        return try HolderRecord.decode(data)
    }

    private final class LineBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var value: String? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }
}

/// 子の起動をholder経由にする設定（常駐プロセスだけが持つ）。nilなら従来どおり直接起動する。
public struct ProcessHolderPolicy: Sendable {
    public let executable: String
    public let recordDirectory: String
    public let socketDirectory: String
    /// 計画的なホスト更新の間、新しいholderの起動を止める門（nilなら止めない）。
    public let launchGate: HandoverGate?

    public init(executable: String, recordDirectory: String, socketDirectory: String, launchGate: HandoverGate? = nil) {
        self.executable = executable
        self.recordDirectory = recordDirectory
        self.socketDirectory = socketDirectory
        self.launchGate = launchGate
    }

    /// 同じ設定で、起動を`gate`で止められるようにしたもの。
    public func gated(by gate: HandoverGate) -> ProcessHolderPolicy {
        ProcessHolderPolicy(
            executable: executable, recordDirectory: recordDirectory, socketDirectory: socketDirectory, launchGate: gate)
    }

    public func transport(
        command: String, arguments: [String], environment: [String: String], workingDirectory: String?,
        metadata: [String: String]
    ) -> HolderTransport {
        let spec = HolderSpawnSpec(
            command: command, arguments: arguments, environment: environment, workingDirectory: workingDirectory,
            metadata: metadata, recordDirectory: recordDirectory, socketDirectory: socketDirectory)
        return HolderTransport(source: .launch(spec: spec, executable: executable), launchGate: launchGate)
    }
}

/// 探索記録の一覧と生存判定（新しい常駐プロセスが起動時に採用候補を集める）。
public enum HolderCatalog {
    public static func records(in recordDirectory: String) -> [HolderRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: recordDirectory)) ?? []
        return names.sorted().compactMap { name in
            let path = (recordDirectory as NSString).appendingPathComponent(name + "/holder.json")
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return try? HolderRecord.decode(data)
        }
    }

    /// holderプロセスが存在するか。権限が無い場合も存在とみなす。
    public static func isAlive(_ record: HolderRecord) -> Bool {
        kill(record.holderPID, 0) == 0 || errno == EPERM
    }
}

/// holder経由で子を扱う`LineDelimitedTransport`。起動（launching）と引き継ぎ（adopting）の2通り。
/// 受信は`HolderLinePump`でpull型にし、処理済みseqをholderへ確認として返す。
public final class HolderTransport: LineDelimitedTransport, @unchecked Sendable {
    public enum Source: Sendable {
        case launch(spec: HolderSpawnSpec, executable: String)
        case adopt(record: HolderRecord, fromSeq: UInt64)
    }

    public enum EndReason: Sendable, Equatable { case exited, evicted, disconnected }

    private let source: Source
    private let pump: HolderLinePump
    private let lock = NSLock()
    private var client: HolderClient?
    private var record: HolderRecord?
    private var info: HolderAttachInfo?
    private var exitStatus: Int32?
    private var endReason: EndReason?
    private var lastConfirmed: UInt64
    /// 閉鎖または引き継ぎで自分から手放した。以後の切断は所有権の喪失として扱わない。
    private var released = false
    /// 計画的更新の確定中。新しい送信を受け付けない（確定後の送信は新ホストから見えない）。
    private var sendsBlocked = false
    private var inFlightSends = 0
    private var exitLastSeq: UInt64?
    private var sawUnknownSend = false
    private var ownershipLostHandler: (@Sendable (EndReason) -> Void)?

    public let receivedLines: AsyncStream<Data>

    private let launchGate: HandoverGate?

    public init(source: Source, launchGate: HandoverGate? = nil) {
        self.source = source
        self.launchGate = launchGate
        let start: UInt64
        if case .adopt(_, let fromSeq) = source { start = fromSeq } else { start = 0 }
        lastConfirmed = start
        let box = ConfirmBox()
        pump = HolderLinePump(startSeq: start) { box.report($0) }
        receivedLines = AsyncStream(unfolding: { [pump] in await pump.next() })
        box.transport = self
    }

    private final class ConfirmBox: @unchecked Sendable {
        weak var transport: HolderTransport?
        func report(_ seq: UInt64) { transport?.processed(seq) }
    }

    // MARK: - 状態の参照

    public var holderRecord: HolderRecord? { lock.withLock { record } }
    public var attachInfo: HolderAttachInfo? { lock.withLock { info } }
    public var processIdentifier: Int32? { lock.withLock { info?.childPID } }
    public var endedReason: EndReason? { lock.withLock { endReason } }
    /// 接続時点で、holderが保持量の上限により子の出力の読み取りを止めていたか。
    public var wasBackpressuredOnAttach: Bool { lock.withLock { info?.backpressured ?? false } }
    public var unknownSendIDs: [UUID] { lock.withLock { info?.unknownSendIDs ?? [] } }

    /// 引き継ぎ側: 旧ホストが反映済みの番号（`fromSeq`）より後の行が、holderに欠けずに残っているか。
    /// 欠けていれば理由を返す（引き継ぐと受信を取りこぼす）。接続前・`launch`では常にnil。
    public func adoptionContinuityFault() -> String? {
        guard case .adopt(_, let applied) = source, let info = attachInfo else { return nil }
        if info.firstRetainedSeq > applied &+ 1 {
            return "holderが保持する行が足りません（保持の先頭=\(info.firstRetainedSeq)、必要=\(applied + 1)）。受信を取りこぼすので引き継げません"
        }
        if info.lastSeq < applied {
            return "holderの最後の行の番号(\(info.lastSeq))が反映済みの番号(\(applied))より小さいので引き継げません"
        }
        return nil
    }

    /// この接続で、書き込みが届いたか確認できなかった送信があったか（再送していない。更新のゲートで使う）。
    public var hasUnknownSend: Bool { lock.withLock { sawUnknownSend } }
    /// 他の常駐プロセスに書込権を取られた、またはholderとの接続が切れたときに呼ばれる。
    /// 子の終了ではない。受信は終端せず、呼び出し側は起動し直さずに復旧待ちとして扱うこと。
    public func setOwnershipLossHandler(_ handler: @escaping @Sendable (EndReason) -> Void) {
        lock.withLock { ownershipLostHandler = handler }
    }
    /// 消費側が処理を終えた最後のseq。
    public var processedSeq: UInt64 { pump.lastHandedOut }

    // MARK: - LineDelimitedTransport

    public func start() throws {
        // 計画的な更新の確定中は、新しいholderを作らない（確定後に作ると、新ホストが把握できない子が残る）。
        // 起動が終わるまで件数に数え、更新側が確定点の作成前に待てるようにする。
        if case .launch = source, let gate = launchGate {
            guard gate.beginLaunch() else { throw HolderError.handoverInProgress }
            defer { gate.endLaunch() }
            try connect()
        } else {
            try connect()
        }
    }

    private func connect() throws {
        let holderRecord: HolderRecord
        let fromSeq: UInt64
        switch source {
        case .launch(let spec, let executable):
            holderRecord = try HolderLauncher.spawn(spec: spec, executable: executable)
            fromSeq = 0
        case .adopt(let existing, let from):
            holderRecord = existing
            fromSeq = from
        }
        let connected = try HolderClient.connect(socketPath: holderRecord.socketPath, fromSeq: fromSeq)
        lock.withLock {
            record = holderRecord
            info = connected.attach
            client = connected
        }
        connected.startReader(
            onLine: { [pump] seq, data in pump.push(seq: seq, data: data) },
            onExited: { [weak self, pump] status, last in
                // 終了通知は全行の後に届く。ここで受信を終端し、消費側が最後の行を処理して確認を返せるようにする。
                self?.lock.withLock { self?.exitStatus = status; self?.exitLastSeq = last }
                pump.finish()
            },
            onEnd: { [weak self] reason in self?.ended(reason) })
    }

    public func send(_ data: Data) async throws {
        guard let client = lock.withLock({ self.client }) else { throw LineDelimitedProcessTransportError.notStarted }
        let admitted = lock.withLock { () -> Bool in
            if sendsBlocked { return false }
            inFlightSends += 1
            return true
        }
        guard admitted else { throw HolderError.handoverInProgress }
        defer { lock.withLock { inFlightSends -= 1 } }
        let sendID = UUID()
        let epoch = client.attach.epoch
        let reply: HolderReply
        do {
            reply = try await client.request { .write(epoch: epoch, requestID: $0, sendID: sendID, data: data) }
        } catch {
            // 書き込みが届いたか確認できない。再送しない。
            lock.withLock { sawUnknownSend = true }
            throw HolderError.sendResultUnknown(sendID)
        }
        switch reply {
        case .written: return
        case .failed(let reason): throw HolderError.sendFailed(reason)
        case .notWriter: throw HolderError.notWriter
        case .unknown:
            lock.withLock { sawUnknownSend = true }
            throw HolderError.sendResultUnknown(sendID)
        case .ok, .text: throw HolderError.malformedFrame
        }
    }

    public func interrupt() async { _ = try? await signal(.interrupt) }

    /// 子を終了して切り離す（通常の閉鎖）。計画的更新では使わず`releaseForHandover()`を使う。
    /// 終了を（有限時間）待ち、最後まで確認を返してholderを終わらせ、受信を終端する。
    public func close() async {
        lock.withLock { released = true }
        _ = try? await signal(.terminate)
        for _ in 0..<60 where lock.withLock({ exitLastSeq }) == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let last = lock.withLock({ exitLastSeq }) { confirm(through: last) }
        pump.finish()
        // 確認がholderへ届く前に閉じないよう、少しだけ待つ。
        try? await Task.sleep(for: .milliseconds(50))
        lock.withLock { client }?.disconnect()
    }

    public func stderrTail() async -> String? {
        guard let client = lock.withLock({ self.client }),
              let reply = try? await client.request({ .stderrTail(requestID: $0) }),
              case .text(let text) = reply else { return nil }
        return text
    }

    public func terminationStatus() async -> Int32? { lock.withLock { exitStatus } }

    private func signal(_ kind: HolderSignal) async throws -> HolderReply? {
        guard let client = lock.withLock({ self.client }) else { return nil }
        let epoch = client.attach.epoch
        return try await client.request { .signal(epoch: epoch, requestID: $0, kind: kind) }
    }

    // MARK: - 計画的更新

    /// 新しい送信を止め、処理中の送信が終わるのを待ち（有限時間）、受信を止めて、処理済みの最後のseqを返す。
    /// 処理中の送信が終わらなければ、その送信はholder側で結果不明として残る（引き継ぎ側は再送しない）。
    /// 消費側が時間内に処理を終えなければnil（送信と受信を再開してから返る。更新は中止する）。
    public func quiesce(timeout: Duration = .seconds(30)) async -> UInt64? {
        lock.withLock { sendsBlocked = true }
        for _ in 0..<200 where lock.withLock({ inFlightSends }) > 0 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if let applied = await pump.quiesce(timeout: timeout) { return applied }
        resumeAfterQuiesce()
        return nil
    }

    /// 確定に失敗して継続する。
    public func resumeAfterQuiesce() {
        lock.withLock { sendsBlocked = false }
        pump.resume()
    }

    /// 確定したseqまでをholderから破棄させる。
    public func confirm(through seq: UInt64) {
        let client = lock.withLock { () -> HolderClient? in
            lastConfirmed = max(lastConfirmed, seq)
            return self.client
        }
        client?.fire(.confirm(epoch: client?.attach.epoch ?? 0, seq: seq))
    }

    /// 不可逆の確定後に呼ぶ。書込権を手放して切断する。受信の終了は消費側へ通知しない（子は生きている）。
    public func releaseForHandover() {
        let client = lock.withLock { () -> HolderClient? in
            released = true
            return self.client
        }
        client?.fire(.detach(epoch: client?.attach.epoch ?? 0))
        client?.disconnect()
    }

    // MARK: - 内部

    fileprivate func processed(_ seq: UInt64) {
        let (target, shouldConfirm): (HolderClient?, Bool) = lock.withLock {
            // 処理済みは毎回確認する。まとめると、保持量の上限で止まったholderが確認待ちのまま進まなくなる。
            let due = seq > lastConfirmed
            if due { lastConfirmed = seq }
            return (client, due)
        }
        if shouldConfirm, let target { target.fire(.confirm(epoch: target.attach.epoch, seq: seq)) }
    }

    private func ended(_ reason: HolderClient.EndReason) {
        let (mapped, handler) = lock.withLock { () -> (EndReason, (@Sendable (EndReason) -> Void)?) in
            let mapped: EndReason = switch reason {
            case .exited: .exited
            case .evicted: .evicted
            case .disconnected: .disconnected
            }
            endReason = mapped
            // 自分で手放した（閉鎖・引き継ぎ）ときと、子の終了は所有権の喪失ではない。
            return (mapped, (released || mapped == .exited) ? nil : ownershipLostHandler)
        }
        // 子の終了は`exited`通知で終端済み。退去・切断は子の終了ではないので、受信を終端しない
        // （終端すると呼び出し側が終了と誤認し、再開・再生成で二重の子を作り得る）。
        if mapped != .exited { handler?(mapped) }
    }
}
