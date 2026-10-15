import AgentDomain
import Darwin
import Dispatch
import Foundation
import os

public actor PTYManager: PTYManagerProtocol {
    private let terminalMode: PTYTerminalMode
    private var sessions: [SessionID: ChildProcess] = [:]
    /// 起動直後の実行ファイル。`exec` で置き換わったら「コマンドが動いている」とみなす。
    private var spawnedImages: [SessionID: String] = [:]
    private let streamCache = StreamCache()
    private let outputGates = OSAllocatedUnfairLock(initialState: [SessionID: OutputGate]())
    // セッションごとの stdin 書き込み用シリアルキュー。ブロッキング write(2) を actor 外へ
    // オフロードしつつ、同一セッションへの書き込み順序（バイト順）を直列に保証する。
    // read/exit ハンドラ用の queue とは別にすることで、詰まった write が出力の drain や
    // 終了検知を巻き込んで止めないようにする。
    private var writeQueues: [SessionID: DispatchQueue] = [:]

    // read ハンドラ 1 回あたりの最大読み取りバイト（= 出力 AsyncStream の 1 要素の最大バイト）。
    static let readBufferSize = 4096

    public init(terminalMode: PTYTerminalMode = .raw) { self.terminalMode = terminalMode }

    /// 子プロセスを spawn して SessionID を返す。
    ///
    /// セッションのライフサイクル契約:
    /// - 子プロセス終了時は `sessions` / `StreamCache` からエントリが削除される。
    ///   削除は exit code が exit stream に流れる「前」に完了するため、消費側が
    ///   exit を観測した時点で `write`/`resize` は `PTYError.sessionNotFound` を投げ、
    ///   `getWinsize` は nil を返す。
    /// - 同一の明示 `id` での重複 spawn は last-wins: レジストリとストリームは新しい
    ///   セッションで置き換えられ、旧 child が生存していても本マネージャからは操作
    ///   できなくなる。旧 child の終了時の後始末は pid を照合するため、置き換え後の
    ///   新セッションを誤って削除しない（終了後に同一 ID で respawn する再起動フロー
    ///   を想定した契約）。
    public func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        let sessionID = id ?? SessionID()
        let (masterFD, pid) = try Self.openPTYAndSpawnChild(
            command: command,
            args: args,
            env: env,
            initialSize: initialSize,
            terminalMode: terminalMode,
            workingDirectory: workingDirectory
        )

        // 出力は捨てない（ADR 0212）。途中が欠けると無関係な制御列ができ、端末が誤応答する。
        // 表示の消費が追いつくまで出力ゲートが read source を停止する。
        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        // 終了コードは 1 要素のみ発行されるため上限不要（unbounded のまま）。
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()

        streamCache.register(id: sessionID, output: outputStream, exit: exitStream)

        // read/exit ハンドラは同一シリアルキューに載せて直列化する。
        // 別キューだと exit 検知の readSource.cancel() が未配送の読み取りイベントを
        // 抑止し、終了直前の出力を取りこぼす競合が起きる。
        let queue = DispatchQueue(label: "PTYKit.session.\(sessionID.rawValue.uuidString)")
        // masterFD の close は readSource の cancel ハンドラに一元化し、close 済みかを
        // このフラグで共有する。exit ハンドラの drain が close 後 (= OS に再利用された
        // 可能性のある fd 番号) に触れないようにするためのガード。
        let masterFDClosed = OSAllocatedUnfairLock(initialState: false)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        let gate = OutputGate(readSource: readSource)
        outputContinuation.onTermination = { _ in gate.abandon() }
        Self.configureReadSource(
            readSource: readSource,
            gate: gate,
            masterFD: masterFD,
            masterFDClosed: masterFDClosed,
            outputContinuation: outputContinuation
        )
        readSource.resume()

        let exitSource = makeExitSource(
            sessionID: sessionID,
            pid: pid,
            masterFD: masterFD,
            queue: queue,
            masterFDClosed: masterFDClosed,
            gate: gate,
            outputContinuation: outputContinuation,
            exitContinuation: exitContinuation
        )
        exitSource.resume()

        var child = ChildProcess(
            id: sessionID,
            pid: pid,
            masterFD: masterFD,
            outputStream: outputStream,
            exitStream: exitStream,
            outputContinuation: outputContinuation,
            exitContinuation: exitContinuation,
            readSource: readSource,
            exitSource: exitSource
        )
        child.outputGate = gate
        // このセッション専用の write キューを（respawn 時は last-wins で）差し替える。
        // 旧セッションで詰まっている write が新セッションの write を巻き込まないよう、
        // 新セッションには必ず新しいキューを割り当てる。
        writeQueues[sessionID] = DispatchQueue(label: "PTYKit.write.\(sessionID.rawValue.uuidString)")
        let oldGate = outputGates.withLock { $0.updateValue(gate, forKey: sessionID) }
        // 旧ストリームの既存バッファは残し、以後の配送を止めてから読取制限を解除する。
        sessions[sessionID]?.outputContinuation.finish()
        oldGate?.abandon()
        sessions[sessionID] = child
        spawnedImages[sessionID] = Posix.executablePath(pid: child.pid)
        return sessionID
    }

    /// 終了した子のレジストリ / ストリームキャッシュ掃除。pid の一致を確認し、
    /// 同一 ID で respawn 済みの新セッションを stale な後始末で誤って消さない。
    private func finishSession(id: SessionID, pid: pid_t) {
        guard let child = sessions[id], child.pid == pid else { return }
        sessions.removeValue(forKey: id)
        outputGates.withLock { $0[id] = nil }
        spawnedImages.removeValue(forKey: id)
        streamCache.remove(id: id)
        writeQueues.removeValue(forKey: id)
    }

    /// PTY を開き、スレーブ側へ子プロセスを posix_spawn する。
    /// spawn 失敗時は両 fd を close してからエラーを伝播する。成功時はスレーブ fd を
    /// close し (子側へ dup2 済み)、マスター fd と pid を返す。
    private static func openPTYAndSpawnChild(
        command: String,
        args: [String],
        env: [String: String],
        initialSize: PTYInitialSize?,
        terminalMode: PTYTerminalMode,
        workingDirectory: String?
    ) throws -> (masterFD: Int32, pid: pid_t) {
        let (masterFD, slaveFD): (Int32, Int32)
        if let size = initialSize {
            (masterFD, slaveFD) = try Posix.openPTY(cols: size.cols, rows: size.rows, terminalMode: terminalMode)
        } else {
            (masterFD, slaveFD) = try Posix.openPTY(terminalMode: terminalMode)
        }

        let pid: pid_t
        do {
            pid = try Posix.spawn(
                command: command,
                args: args,
                env: env,
                masterFD: masterFD,
                slaveFD: slaveFD,
                workingDirectory: workingDirectory,
                terminalMode: terminalMode
            )
        } catch {
            close(masterFD)
            close(slaveFD)
            throw error
        }

        close(slaveFD)
        return (masterFD, pid)
    }

    /// マスター fd の出力を AsyncStream へ中継する readSource を構築する (resume は呼び出し側)。
    /// masterFD の close は cancel ハンドラに一元化されている。
    private static func configureReadSource(
        readSource: DispatchSourceRead,
        gate: OutputGate,
        masterFD: Int32,
        masterFDClosed: OSAllocatedUnfairLock<Bool>,
        outputContinuation: AsyncStream<Data>.Continuation
    ) {
        readSource.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
            while true {
                let count = read(masterFD, &buffer, Self.readBufferSize)
                if count > 0 {
                    gate.record(count)
                    outputContinuation.yield(Data(buffer[0..<count]))
                    return
                }
                if count < 0 && errno == EINTR {
                    continue
                }
                gate.cancel()
                return
            }
        }
        readSource.setCancelHandler {
            masterFDClosed.withLock { closed in
                if !closed {
                    close(masterFD)
                    closed = true
                }
            }
        }
    }

    /// 子プロセスの終了を検知して残出力の drain・ストリームの finish・レジストリ掃除を
    /// 行う exitSource を構築する (resume は呼び出し側)。readSource と同一キューに載せること。
    private func makeExitSource(
        sessionID: SessionID,
        pid: pid_t,
        masterFD: Int32,
        queue: DispatchQueue,
        masterFDClosed: OSAllocatedUnfairLock<Bool>,
        gate: OutputGate,
        outputContinuation: AsyncStream<Data>.Continuation,
        exitContinuation: AsyncStream<Int32>.Continuation
    ) -> DispatchSourceProcess {
        let exitSource = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: queue
        )
        exitSource.setEventHandler { [weak self] in
            var status: Int32 = 0
            // read 側の EINTR retry と対称に、シグナル割り込みでは失敗扱いにせず再試行する。
            var waitResult = waitpid(pid, &status, 0)
            while waitResult < 0 && errno == EINTR {
                waitResult = waitpid(pid, &status, 0)
            }
            let code: Int32
            if waitResult == pid {
                code = Posix.exitCode(from: status)
            } else {
                code = -1
            }
            // PTY カーネルバッファに残った終了直前の出力を読み切ってから read 側を止める
            // (readSource と同一シリアルキュー上なので read ハンドラとは競合しない)。
            if masterFDClosed.withLock({ !$0 }) {
                Self.drainRemainingOutput(masterFD: masterFD, gate: gate, into: outputContinuation)
            }
            gate.cancel() // close は cancel ハンドラのみが行う
            exitSource.cancel() // handler が exitSource 自身を捕捉する自己 retain をここで解放する
            outputContinuation.finish()
            // レジストリ掃除を完了させてから exit code を流す。これにより消費側が
            // exit を観測した時点で write/resize が sessionNotFound になる契約を保証する。
            let manager = self
            Task {
                await manager?.finishSession(id: sessionID, pid: pid)
                exitContinuation.yield(code)
                exitContinuation.finish()
            }
        }
        return exitSource
    }

    /// exit 検知時点で PTY カーネルバッファに残っている未配送出力を非ブロッキングで
    /// 読み取る。親の終了後も子孫が書き続け、表示が遅れている場合は上限で打ち切り、
    /// 残りを捨てる。消費が追いついている間は従来どおり読む（ADR 0212）。
    static func drainRemainingOutput(
        masterFD: Int32,
        gate: OutputGate,
        into continuation: AsyncStream<Data>.Continuation
    ) {
        let flags = fcntl(masterFD, F_GETFL)
        guard flags >= 0, fcntl(masterFD, F_SETFL, flags | O_NONBLOCK) >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: readBufferSize)
        while true {
            let count = read(masterFD, &buffer, readBufferSize)
            if count > 0 {
                gate.record(count)
                continuation.yield(Data(buffer[0..<count]))
                if gate.snapshot.pendingBytes >= OutputGate.highWater { return }
                continue
            }
            if count < 0 && errno == EINTR {
                continue
            }
            return
        }
    }

    public func write(_ data: Data, to id: SessionID) async throws {
        guard let session = sessions[id] else {
            throw PTYError.sessionNotFound
        }
        let fd = session.masterFD
        // ブロッキング write(2) を actor 外のセッション専用シリアルキューへオフロードする。
        // これで stdin を読まない子への大量 write が actor（sessions/spawn/kill）を停止させない。
        // ・順序保証: 同一セッションの write は同一シリアルキューに投入されるため、投入順＝
        //   実行順＝バイト順が保たれる。
        // ・部分書き込み: 1 回の writeAll が offset ループで EAGAIN/短い write を最後まで書き切る。
        // await の間 actor は解放され、別セッションの操作を処理できる。継続の resume は書き込み
        // 完了時（またはエラー時）にキュー側スレッドから行い、そこで actor へ復帰する。
        let queue = writeQueues[id] ?? {
            let created = DispatchQueue(label: "PTYKit.write.\(id.rawValue.uuidString)")
            writeQueues[id] = created
            return created
        }()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try Posix.writeAll(fd: fd, data: data)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func kill(_ id: SessionID) async {
        guard let session = sessions[id] else { return }
        Posix.terminateGroup(pid: session.pid)
    }

    public func hangUp(_ id: SessionID) async {
        guard let session = sessions[id] else { return }
        Posix.hangUpGroup(pid: session.pid)
    }

    public func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        guard let session = sessions[id] else { return nil }
        return Posix.getWinsize(fd: session.masterFD)
    }

    public func hasChildProcesses(_ id: SessionID) async -> Bool {
        guard let session = sessions[id] else { return false }
        if Posix.hasChildProcesses(pid: session.pid) { return true }
        // `exec sleep 30` のようにシェル自身がコマンドに置き換わった場合。
        let image = Posix.executablePath(pid: session.pid)
        return image != nil && image != spawnedImages[id]
    }

    public func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        guard let session = sessions[id] else {
            throw PTYError.sessionNotFound
        }
        try Posix.resize(fd: session.masterFD, cols: cols, rows: rows)
        // interactive は制御端末の前景へ ioctl が通知する。raw の既存経路だけ明示送信する。
        if terminalMode == .raw { Darwin.kill(session.pid, SIGWINCH) }
    }

    /// 登録済みセッションの子プロセス pid。
    /// App/環境層が spawn 済みセッションの live pid を読み出して descriptor へ永続化する
    /// （起動時 reconcile の生存孤児 reap に使う）ために public。actor 隔離下にあるため
    /// `sessions` への参照はシリアライズされ、データ競合を生まない。未登録 ID では nil。
    public func pid(for id: SessionID) -> pid_t? {
        sessions[id]?.pid
    }

    // MARK: - テスト用観測アクセサ (@testable 経由でのみ使用)

    /// 登録済みセッション数。
    internal var sessionCount: Int {
        sessions.count
    }

    /// StreamCache にストリームが残っているか。
    internal nonisolated func hasCachedStreams(for id: SessionID) -> Bool {
        streamCache.outputStream(for: id) != nil || streamCache.exitStream(for: id) != nil
    }

    public nonisolated func outputStream(for id: SessionID) -> AsyncStream<Data> {
        streamCache.outputStream(for: id) ?? AsyncStream { $0.finish() }
    }

    public nonisolated func acknowledgeOutput(_ count: Int, for id: SessionID) {
        outputGates.withLock { $0[id] }?.acknowledge(count)
    }

    internal nonisolated func outputGate(for id: SessionID) -> OutputGate? {
        outputGates.withLock { $0[id] }
    }

    public nonisolated func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        streamCache.exitStream(for: id) ?? AsyncStream { $0.finish() }
    }

    /// 起動中の全 PTY 子プロセスをプロセスグループ単位で終了し、完了を待つ。
    /// `exitSource` が `waitpid` するため、ここでは `waitpid` せず `isAlive` のみで判定する。
    public func terminateAllAndWait(timeout: Duration) async {
        let children = Array(sessions.values)
        guard !children.isEmpty else { return }

        for child in children {
            Posix.terminateGroup(pid: child.pid)
        }

        let pollInterval = Duration.milliseconds(50)
        let deadline = ContinuousClock.now + timeout

        func survivingPIDs() -> [pid_t] {
            children.compactMap { Posix.isAlive(pid: $0.pid) ? $0.pid : nil }
        }

        // SIGTERM の猶予ポーリング。キャンセルされたら CancellationError を握りつぶさず
        // 即 break し、下の SIGKILL パスへ抜ける（`try?` だと sleep が即 throw を返し続けて
        // deadline までビジーループ＝ホットスピンになるため使わない）。
        while !survivingPIDs().isEmpty, ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }

        for pid in survivingPIDs() {
            Posix.killGroup(pid: pid)
        }

        // SIGKILL 後の reap 待ちも同様に、キャンセルされたら即抜ける（ホットスピン回避）。
        let killGraceDeadline = ContinuousClock.now + Duration.milliseconds(500)
        while !survivingPIDs().isEmpty, ContinuousClock.now < killGraceDeadline {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }

        for child in children {
            // exit ハンドラの finishSession と同じ pid 照合。ポーリング中の await の間に
            // 同一 ID で respawn された新セッションを誤って消さない。
            if sessions[child.id]?.pid == child.pid {
                sessions.removeValue(forKey: child.id)
                outputGates.withLock { [id = child.id] in $0[id] = nil }
                streamCache.remove(id: child.id)
                writeQueues.removeValue(forKey: child.id)
            }
            if !Posix.isAlive(pid: child.pid) {
                child.outputGate?.cancel()
                child.exitSource.cancel()
            }
        }
    }
}
