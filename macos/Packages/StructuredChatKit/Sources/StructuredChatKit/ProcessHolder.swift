import Darwin
import Foundation

/// 子プロセス1つの親・標準入出力の所有者（ADR 0233）。プロトコルは解釈しない。
/// 受信行に通し番号を付けて有限に保持し、書込権（世代）を持つ接続だけに書込・信号を許す。
/// 子の標準入力は閉じず、常駐側の切断・入れ替えで子を終了しない。
public final class ProcessHolder: @unchecked Sendable {
    private struct Entry { let seq: UInt64; let data: Data }
    private enum SendState { case accepted, written, failed(String) }

    /// 1接続の所有。fdは`serve`スレッドが読み終えて、書き込み中の送信も無くなってから一度だけ閉じる。
    /// 使用中に閉じると、空いた番号が別の接続（他のholder・他のテスト）に再利用され、
    /// 読み取りが他の接続のデータを横取りし、書き込みが他の接続へ届く。
    private final class Connection: @unchecked Sendable {
        let descriptor: Int32
        var epoch: UInt64 = 0
        private let queue = DispatchQueue(label: "ProcessHolder.connection")
        private let lock = NSLock()
        /// 切断が要求された（以後の送信は捨てる）。
        private var closed = false
        /// `serve`スレッドが読み取り中。
        private var serving = true
        private var activeWrites = 0
        private var descriptorClosed = false

        init(descriptor: Int32) { self.descriptor = descriptor }

        func send(_ frame: HolderFrame) {
            queue.async { [self] in
                // 符号化できないフレーム（上限超過など）を黙って捨てると、行の欠落になる。接続を閉じて、受け手に切断として見せる
                // （受け手は所有権の喪失として復旧待ちにし、子は終了しない）。
                guard let data = try? HolderWire.encode(frame) else { close(); return }
                lock.lock()
                guard !closed else { lock.unlock(); return }
                activeWrites += 1
                lock.unlock()
                let written = (try? HolderWire.writeAll(descriptor, data)) != nil
                lock.lock()
                activeWrites -= 1
                closeDescriptorIfIdleLocked()
                lock.unlock()
                if !written { close() }
            }
        }

        /// 先に積んだフレームを送り切ってから閉じる。
        func closeAfterFlush() { queue.async { [self] in close() } }

        /// 切断を要求する。読み取り・書き込み中のスレッドは起こすが、fdは使用中が無くなるまで閉じない。
        func close() {
            lock.lock()
            if !closed {
                closed = true
                if !descriptorClosed { shutdown(descriptor, SHUT_RDWR) }
            }
            closeDescriptorIfIdleLocked()
            lock.unlock()
        }

        /// `serve`スレッドが読み取りを終えた。
        func finishServing() {
            lock.lock()
            serving = false
            lock.unlock()
            close()
        }

        private func closeDescriptorIfIdleLocked() {
            guard closed, !serving, activeWrites == 0, !descriptorClosed else { return }
            descriptorClosed = true
            Darwin.close(descriptor)
        }
    }

    private let spec: HolderSpawnSpec
    public let holderID: String
    private let transport: LineDelimitedProcessTransport
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var retainedBytes = 0
    private var lastSeq: UInt64 = 0
    /// 保持量が上限に達し、子の出力の読み取りを止めているか（確認で空くまで子の進行も止まる）。
    private var readingPaused = false
    private var confirmedSeq: UInt64 = 0
    private var exitStatus: Int32?
    private var epoch: UInt64 = 0
    private var active: Connection?
    private var sends: [UUID: SendState] = [:]
    private var sendOrder: [UUID] = []
    private var listener: Int32 = -1
    private var acceptStarted = false
    private var childPID: Int32 = 0
    private var socketPath = ""
    private var recordPath = ""
    private var finished = false
    /// 子の終了状態を常駐側が受け取り、確認済み番号を最後まで進めたか。
    private var exitAcknowledged = false
    /// 書込権を持つ接続が終了を要求した。この終了は常駐側が確認済みとみなす（確認を待たずにholderを終われる）。
    private var terminateRequested = false
    private let done = DispatchSemaphore(value: 0)
    /// 子の終了後、常駐側の確認が無くてもholderを残す最長時間。
    private let orphanLinger: TimeInterval

    public init(spec: HolderSpawnSpec, orphanLinger: TimeInterval = 24 * 60 * 60) {
        self.spec = spec
        self.holderID = "h-" + UUID().uuidString.prefix(8).lowercased()
        self.orphanLinger = orphanLinger
        self.transport = LineDelimitedProcessTransport(
            command: spec.command, arguments: spec.arguments, environment: spec.environment,
            workingDirectory: spec.workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }

    /// 子とソケットを起動し、探索記録を書く。呼び出し後すぐ接続を受け付ける。
    public func start() throws -> HolderRecord {
        let recordDirectory = (spec.recordDirectory as NSString).appendingPathComponent(holderID)
        try HolderDirectory.ensurePrivate(spec.recordDirectory)
        try HolderDirectory.ensurePrivate(recordDirectory)
        try HolderDirectory.ensurePrivate(spec.socketDirectory)
        socketPath = (spec.socketDirectory as NSString).appendingPathComponent(holderID + ".sock")
        recordPath = (recordDirectory as NSString).appendingPathComponent("holder.json")

        do { try transport.start() } catch { throw HolderError.launchFailed(String(describing: error)) }
        childPID = transport.processIdentifier ?? 0

        do { try listen() } catch {
            // 受け付けられないholderは残さない（子が誰にも触れられなくなるため）。
            Task { await self.transport.close() }
            throw error
        }
        let record = HolderRecord(
            holderID: holderID, protocolVersion: HolderProtocol.version, holderPID: getpid(), childPID: childPID,
            socketPath: socketPath, startedAt: Date(), metadata: spec.metadata)
        do { try writeRecord(record) } catch {
            closeListener()
            Task { await self.transport.close() }
            throw error
        }
        Task.detached { [self] in await pumpOutput() }
        Thread.detachNewThread { [self] in acceptLoop() }
        Thread.detachNewThread { [self] in keepFilesFresh() }
        return record
    }

    /// OSの定期掃除（一定期間使われない一時ファイルの削除）でソケットが消えないよう、時々更新する。
    private func keepFilesFresh() {
        while true {
            Thread.sleep(forTimeInterval: 60 * 60)
            lock.lock(); let isFinished = finished; lock.unlock()
            if isFinished { return }
            utimes(socketPath, nil)
        }
    }

    /// holderが終了するまで待つ（`--session-holder`のmain用）。
    public func waitUntilFinished() { done.wait() }

    // MARK: - 受信行の保持

    private func pumpOutput() async {
        for await line in transport.receivedLines { append(line) }
        let status = await transport.terminationStatus() ?? -1
        let (target, last) = markExited(status)
        target?.send(.exited(status: status, lastSeq: last))
        evaluateFinish()
        let linger = orphanLinger
        DispatchQueue.global().asyncAfter(deadline: .now() + linger) { [self] in finish() }
    }

    private func markExited(_ status: Int32) -> (Connection?, UInt64) {
        lock.withLock {
            exitStatus = status
            if terminateRequested { exitAcknowledged = true }
            return (active, lastSeq)
        }
    }

    /// 確認前の行は捨てない（データ損失になるため）。上限に達したら子の出力の読み取りを止め、
    /// 子はパイプが満杯になった時点で進行が止まる。確認で空くと再開する。
    private func append(_ data: Data) {
        let (entry, target, pause) = lock.withLock { () -> (Entry, Connection?, Bool) in
            lastSeq += 1
            let entry = Entry(seq: lastSeq, data: data)
            entries.append(entry)
            retainedBytes += data.count
            let pause = retainedBytes >= spec.retentionLimit && !readingPaused
            if pause { readingPaused = true }
            return (entry, active, pause)
        }
        if pause { transport.setReadingPaused(true) }
        target?.send(.line(seq: entry.seq, data: data))
    }

    private func confirm(_ connection: Connection, epoch value: UInt64, seq: UInt64) {
        let (resume, finishable) = lock.withLock { () -> (Bool, Bool) in
            guard active === connection, epoch == value else { return (false, false) }
            if seq > confirmedSeq {
                confirmedSeq = min(seq, lastSeq)
                var drop = 0
                while drop < entries.count, entries[drop].seq <= confirmedSeq {
                    retainedBytes -= entries[drop].data.count
                    drop += 1
                }
                if drop > 0 { entries.removeFirst(drop) }
            }
            if exitStatus != nil, confirmedSeq >= lastSeq { exitAcknowledged = true }
            let resume = readingPaused && retainedBytes < spec.retentionLimit / 2
            if resume { readingPaused = false }
            return (resume, exitStatus != nil && exitAcknowledged)
        }
        if resume { transport.setReadingPaused(false) }
        if finishable { finish() }
    }

    private func detach(_ connection: Connection, epoch value: UInt64) {
        let isWriter = lock.withLock { () -> Bool in
            guard active === connection, epoch == value else { return false }
            active = nil
            return true
        }
        if isWriter { connection.closeAfterFlush() }
    }

    // MARK: - 接続

    private func listen() throws {
        unlink(socketPath)
        var address = try HolderSocket.address(socketPath)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw HolderError.launchFailed("socket \(errno)") }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        // umaskは変えない（プロセス全体の設定で、他のスレッドのディレクトリ作成を壊す）。ソケットは0700のディレクトリの中で作り、直後にchmodする。
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 8) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw HolderError.launchFailed("bind/listen \(code)")
        }
        chmod(socketPath, 0o600)
        listener = descriptor
    }

    /// 受付を終える。fdは受付スレッドが使い終えてから閉じる（使用中に閉じると番号が再利用され、別の接続を受け付けてしまう）。
    private func closeListener() {
        lock.lock()
        let descriptor = listener
        listener = -1
        let acceptRunning = acceptStarted
        lock.unlock()
        if descriptor >= 0, !acceptRunning { Darwin.close(descriptor) }
        unlink(socketPath)
    }

    private func acceptLoop() {
        lock.lock()
        let descriptor = listener
        if descriptor >= 0 { acceptStarted = true }
        lock.unlock()
        guard descriptor >= 0 else { return }  // 起動前に閉じられた（fdは閉じる側が閉じ済み）
        defer { Darwin.close(descriptor) }
        while true {
            lock.lock(); let isOpen = listener == descriptor; lock.unlock()
            guard isOpen else { return }
            // 閉じる要求を、acceptが起こされるかどうかに依存せず見つける（macOSでは別スレッドの閉鎖で起きない場合がある）。
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 200) > 0 else { continue }
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                switch errno {
                // 一時的な失敗でacceptを止めない（止めると、以後の接続の握手が応答なしで期限切れになる）。
                case EINTR, EAGAIN, ECONNABORTED, EPROTO: continue
                case EMFILE, ENFILE, ENOBUFS, ENOMEM:
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                default: return
                }
            }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            var noSigpipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
            guard HolderSocket.peerIsSameUser(client) else { Darwin.close(client); continue }
            let connection = Connection(descriptor: client)
            Thread.detachNewThread { [self] in serve(connection) }
        }
    }

    private func serve(_ connection: Connection) {
        defer { connection.finishServing() }
        guard let first = try? HolderWire.readFrame(connection.descriptor, as: HolderRequest.self),
              case .hello(let version) = first, version == HolderProtocol.version else { return }
        connection.send(.hello(version: HolderProtocol.version, holderID: holderID, holderPID: getpid(), childPID: childPID))
        // 要求は接続ごとに、この専用スレッドで順に処理する（書込の順序を保つ）。協調スレッドプールの空きに
        // 接続の確立（attach）が依存しないので、同じプロセス内でholderを使っても詰まらない。
        while let request = try? HolderWire.readFrame(connection.descriptor, as: HolderRequest.self) {
            handle(request, from: connection)
        }
        lock.lock()
        if active === connection { active = nil }
        lock.unlock()
    }

    private func isWriter(_ connection: Connection, epoch value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active === connection && epoch == value
    }

    /// asyncな操作の完了を、呼び出しスレッド（専用スレッド）で待つ。
    private func runBlocking(_ body: @escaping @Sendable () async -> Void) {
        let done = DispatchSemaphore(value: 0)
        Task {
            await body()
            done.signal()
        }
        done.wait()
    }

    private func handle(_ request: HolderRequest, from connection: Connection) {
        switch request {
        case .hello:
            break
        case .attach(let fromSeq):
            attach(connection, fromSeq: fromSeq)
        case .write(let value, let requestID, let sendID, let data):
            runBlocking { [self] in
                let reply = await write(connection, epoch: value, sendID: sendID, data: data)
                connection.send(.reply(requestID: requestID, result: reply))
            }
        case .signal(let value, let requestID, let kind):
            guard isWriter(connection, epoch: value) else {
                connection.send(.reply(requestID: requestID, result: .notWriter))
                return
            }
            if kind == .terminate { lock.withLock { terminateRequested = true } }
            runBlocking { [self] in
                switch kind {
                case .interrupt: await transport.interrupt()
                case .terminate: await transport.close()
                }
                connection.send(.reply(requestID: requestID, result: .ok))
            }
        case .confirm(let value, let seq):
            confirm(connection, epoch: value, seq: seq)
        case .stderrTail(let requestID):
            runBlocking { [self] in
                let text = await transport.stderrTail()
                connection.send(.reply(requestID: requestID, result: .text(text)))
            }
        case .detach(let value):
            detach(connection, epoch: value)
        }
    }

    private func attach(_ connection: Connection, fromSeq: UInt64) {
        lock.lock()
        epoch += 1
        connection.epoch = epoch
        let previous = active
        active = connection
        let unknown = sends.compactMap { entry -> UUID? in
            if case .accepted = entry.value { return entry.key } else { return nil }
        }
        let first = entries.first?.seq ?? (lastSeq + 1)
        let info = HolderAttachInfo(
            epoch: epoch, firstRetainedSeq: first, lastSeq: lastSeq, backpressured: readingPaused,
            exitStatus: exitStatus, unknownSendIDs: unknown, childPID: childPID)
        // 切替の間に届いた行と順序が混ざらないよう、ロック内で送信キューへ積む。
        connection.send(.attached(info))
        for entry in entries where entry.seq > fromSeq { connection.send(.line(seq: entry.seq, data: entry.data)) }
        if let status = exitStatus { connection.send(.exited(status: status, lastSeq: lastSeq)) }
        lock.unlock()
        if let previous, previous !== connection {
            previous.send(.evicted)
            previous.closeAfterFlush()
        }
    }

    private enum WriteDecision { case rejected, replay(HolderReply), proceed }

    private func beginSend(_ connection: Connection, epoch value: UInt64, sendID: UUID) -> WriteDecision {
        lock.withLock {
            guard active === connection, epoch == value else { return .rejected }
            if let existing = sends[sendID] {
                switch existing {
                case .written: return .replay(.written)
                case .failed(let reason): return .replay(.failed(reason))
                case .accepted: return .replay(.unknown)
                }
            }
            sends[sendID] = .accepted
            sendOrder.append(sendID)
            if sendOrder.count > 512 {
                let stale = sendOrder.removeFirst()
                if case .accepted = sends[stale] {} else { sends.removeValue(forKey: stale) }
            }
            return .proceed
        }
    }

    private func finishSend(_ sendID: UUID, _ state: SendState) {
        lock.withLock { sends[sendID] = state }
    }

    private func write(_ connection: Connection, epoch value: UInt64, sendID: UUID, data: Data) async -> HolderReply {
        switch beginSend(connection, epoch: value, sendID: sendID) {
        case .rejected: return .notWriter
        case .replay(let reply): return reply
        case .proceed: break
        }
        do {
            try await transport.send(data)
            finishSend(sendID, .written)
            return .written
        } catch {
            let reason = String(describing: error)
            finishSend(sendID, .failed(reason))
            return .failed(reason)
        }
    }

    // MARK: - 終了

    private func evaluateFinish() {
        lock.lock()
        let ready = exitStatus != nil && exitAcknowledged
        lock.unlock()
        if ready { finish() }
    }

    private func finish() {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        let target = active
        lock.unlock()
        target?.closeAfterFlush()
        closeListener()
        unlink(recordPath)
        rmdir((recordPath as NSString).deletingLastPathComponent)
        done.signal()
    }

    private func writeRecord(_ record: HolderRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let temporary = recordPath + ".tmp"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw HolderError.launchFailed("record \(errno)") }
        defer { Darwin.close(descriptor) }
        try HolderWire.writeAll(descriptor, data)
        guard fsync(descriptor) == 0, rename(temporary, recordPath) == 0 else {
            throw HolderError.launchFailed("record rename \(errno)")
        }
    }
}

public extension HolderRecord {
    static func decode(_ data: Data) throws -> HolderRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HolderRecord.self, from: data)
    }
}

/// `--session-holder`プロセスの入口。標準入力から`HolderSpawnSpec`を読み、準備完了を1行で標準出力へ返す。
public enum ProcessHolderMain {
    public static func run() -> Never {
        // 親（常駐側）のプロセスグループ・端末から切り離す。親の終了や更新で巻き込まれない。
        _ = setsid()
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let holder: ProcessHolder
        let record: HolderRecord
        do {
            let spec = try JSONDecoder().decode(HolderSpawnSpec.self, from: input)
            holder = ProcessHolder(spec: spec)
            record = try holder.start()
        } catch {
            FileHandle.standardOutput.write(Data("ERROR \(error)\n".utf8))
            exit(1)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        FileHandle.standardOutput.write(Data("READY \(json)\n".utf8))
        let null = open("/dev/null", O_RDWR)
        if null >= 0 { dup2(null, STDIN_FILENO); dup2(null, STDOUT_FILENO); dup2(null, STDERR_FILENO) }
        holder.waitUntilFinished()
        exit(0)
    }
}
