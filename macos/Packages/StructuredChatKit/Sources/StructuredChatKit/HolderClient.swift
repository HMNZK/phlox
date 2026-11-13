import Darwin
import Foundation

/// holderへの1接続（常駐側）。接続・hello・attachは同期で行い、以後は読み取りスレッドが受信フレームを配る。
final class HolderClient: @unchecked Sendable {
    enum EndReason: Sendable, Equatable { case exited, evicted, disconnected }

    let attach: HolderAttachInfo
    let holderID: String
    let holderPID: Int32

    private let descriptor: Int32
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var nextRequestID: UInt64 = 0
    private var pending: [UInt64: CheckedContinuation<HolderReply, Error>] = [:]
    /// 切断が要求された（以後の送受信は拒否する）。fdは、読み取りスレッドと書き込み中の送信が全て終わってから閉じる。
    private var closed = false
    private var ended = false
    private var readerActive = false
    private var activeWrites = 0
    private var descriptorClosed = false

    private init(descriptor: Int32, attach: HolderAttachInfo, holderID: String, holderPID: Int32) {
        self.descriptor = descriptor
        self.attach = attach
        self.holderID = holderID
        self.holderPID = holderPID
    }

    /// 接続して書込権を取る。`fromSeq`より後の保持行は`startReader`後に届く。
    static func connect(socketPath: String, fromSeq: UInt64, handshakeTimeout: TimeInterval = 5) throws -> HolderClient {
        let descriptor = try HolderSocket.connect(path: socketPath)
        var timeout = timeval(tv_sec: Int(handshakeTimeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        do {
            try HolderWire.writeAll(descriptor, HolderWire.encode(HolderRequest.hello(version: HolderProtocol.version)))
            guard let hello = try HolderWire.readFrame(descriptor, as: HolderFrame.self) else {
                throw HolderError.connectionFailed("握手: helloを受け取れません(errno \(errno))")
            }
            guard case .hello(let version, let holderID, let holderPID, _) = hello else {
                throw HolderError.connectionFailed("握手: helloの代わりに別のフレームが届きました")
            }
            guard version == HolderProtocol.version else { throw HolderError.incompatibleVersion(version) }
            try HolderWire.writeAll(descriptor, HolderWire.encode(HolderRequest.attach(fromSeq: fromSeq)))
            guard let attached = try HolderWire.readFrame(descriptor, as: HolderFrame.self) else {
                throw HolderError.connectionFailed("握手: attachedを受け取れません(errno \(errno))")
            }
            guard case .attached(let info) = attached else {
                throw HolderError.connectionFailed("握手: attachedの代わりに別のフレームが届きました")
            }
            var none = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
            return HolderClient(descriptor: descriptor, attach: info, holderID: holderID, holderPID: holderPID)
        } catch {
            close(descriptor)
            throw error
        }
    }

    /// 読み取りスレッドを始める。`onEnd`は1回だけ呼ばれる。
    func startReader(
        onLine: @escaping @Sendable (UInt64, Data) -> Void,
        onExited: @escaping @Sendable (Int32, UInt64) -> Void,
        onEnd: @escaping @Sendable (EndReason) -> Void
    ) {
        // スレッドが動き出す前に切断されても、fdを読み取りスレッドの外で閉じてしまわないよう、先に登録する。
        lock.lock()
        let alreadyClosed = closed
        if !alreadyClosed { readerActive = true }
        lock.unlock()
        if alreadyClosed {
            failAll()
            onEnd(.disconnected)
            return
        }
        Thread.detachNewThread { [self] in
            var reason = EndReason.disconnected
            readLoop: while let frame = try? HolderWire.readFrame(descriptor, as: HolderFrame.self) {
                switch frame {
                case .line(let seq, let data): onLine(seq, data)
                case .reply(let id, let result):
                    lock.lock(); let continuation = pending.removeValue(forKey: id); lock.unlock()
                    continuation?.resume(returning: result)
                case .exited(let status, let lastSeq):
                    onExited(status, lastSeq)
                    reason = .exited
                case .evicted:
                    reason = .evicted
                    break readLoop
                case .hello, .attached: break
                }
            }
            // 以後の読み取りは無い。fdを閉じる（番号が再利用されても、この接続の読み書きが他の接続へ届かない）。
            lock.lock()
            readerActive = false
            lock.unlock()
            disconnect()
            failAll()
            onEnd(reason)
        }
    }

    private func failAll() {
        lock.lock()
        ended = true
        let all = pending
        pending = [:]
        lock.unlock()
        for continuation in all.values { continuation.resume(throwing: HolderError.disconnected) }
    }

    private func sendFrame(_ request: HolderRequest) throws {
        let data = try HolderWire.encode(request)
        writeLock.lock()
        defer { writeLock.unlock() }
        lock.lock()
        guard !closed else { lock.unlock(); throw HolderError.disconnected }
        activeWrites += 1
        lock.unlock()
        defer {
            lock.lock()
            activeWrites -= 1
            closeDescriptorIfIdleLocked()
            lock.unlock()
        }
        try HolderWire.writeAll(descriptor, data)
    }

    func request(_ build: @escaping @Sendable (UInt64) -> HolderRequest) async throws -> HolderReply {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HolderReply, Error>) in
            lock.lock()
            if closed || ended {
                lock.unlock()
                continuation.resume(throwing: HolderError.disconnected)
                return
            }
            nextRequestID += 1
            let id = nextRequestID
            pending[id] = continuation
            lock.unlock()
            do { try sendFrame(build(id)) } catch {
                lock.lock(); let removed = pending.removeValue(forKey: id); lock.unlock()
                removed?.resume(throwing: HolderError.disconnected)
            }
        }
    }

    /// 応答を待たない送信（確認・切り離し）。
    func fire(_ request: HolderRequest) { try? sendFrame(request) }

    /// 接続を閉じる。子は終了しない。
    func disconnect() {
        lock.lock()
        if !closed {
            closed = true
            // 読み取り・書き込み中のスレッドを即座に起こす（fdはまだ閉じない）。
            if !descriptorClosed { shutdown(descriptor, SHUT_RDWR) }
        }
        closeDescriptorIfIdleLocked()
        lock.unlock()
    }

    /// fdは、読み取りスレッドと書き込み中の送信が全て抜けてから、一度だけ閉じる。
    /// 使用中に閉じると、空いた番号が別の接続（他のテスト・他のholder）に再利用され、読み書きが他の接続へ届く。
    private func closeDescriptorIfIdleLocked() {
        guard closed, !readerActive, activeWrites == 0, !descriptorClosed else { return }
        descriptorClosed = true
        Darwin.close(descriptor)
    }
}

/// holderから届いた行を、消費側が「次を要求した」時だけ渡す。消費側が次を要求した＝前の行の処理が完了、という判定に使う。
/// 計画的更新では`quiesce()`で受信を止め、処理済みの最後のseqを確定する。
final class HolderLinePump: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(seq: UInt64, data: Data)] = []
    private var waiter: CheckedContinuation<Data?, Never>?
    private var quiesceWaiters: [(id: UUID, continuation: CheckedContinuation<UInt64?, Never>)] = []
    private var paused = false
    private var finished = false
    private var consumerStarted = false
    private var consumerEnded = false
    private var pushed: UInt64
    private var handedOut: UInt64
    /// 消費側が処理を終えた最後のseqを通知する（確認の送信用）。
    private let onProcessed: @Sendable (UInt64) -> Void

    init(startSeq: UInt64, onProcessed: @escaping @Sendable (UInt64) -> Void) {
        pushed = startSeq
        handedOut = startSeq
        self.onProcessed = onProcessed
    }

    var lastHandedOut: UInt64 { lock.withLock { handedOut } }

    func push(seq: UInt64, data: Data) {
        lock.lock()
        // 再接続の再送や重複は捨てる。
        guard !finished, seq > pushed else { lock.unlock(); return }
        pushed = seq
        if let waiting = waiter, !paused {
            waiter = nil
            handedOut = seq
            lock.unlock()
            waiting.resume(returning: data)
            return
        }
        queue.append((seq, data))
        lock.unlock()
    }

    func finish() {
        lock.lock()
        finished = true
        if let waiting = waiter, queue.isEmpty {
            waiter = nil
            consumerEnded = true
            lock.unlock()
            waiting.resume(returning: nil)
            return
        }
        lock.unlock()
    }

    func next() async -> Data? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                lock.lock()
                consumerStarted = true
                let processed = handedOut
                if !paused, !queue.isEmpty {
                    let entry = queue.removeFirst()
                    handedOut = entry.seq
                    lock.unlock()
                    onProcessed(processed)
                    continuation.resume(returning: entry.data)
                    return
                }
                if finished, queue.isEmpty {
                    consumerEnded = true
                    let waiting = quiesceWaiters
                    quiesceWaiters = []
                    lock.unlock()
                    onProcessed(processed)
                    for waiting in waiting { waiting.continuation.resume(returning: processed) }
                    continuation.resume(returning: nil)
                    return
                }
                // 待機に入る前に取り消されていた場合、取消しハンドラは既に走り終えている。ここで待つと永久に起きない。
                if Task.isCancelled {
                    consumerEnded = true
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                waiter = continuation
                let waiting = quiesceWaiters
                quiesceWaiters = []
                lock.unlock()
                onProcessed(processed)
                for waiting in waiting { waiting.continuation.resume(returning: processed) }
            }
        } onCancel: {
            lock.lock()
            let waiting = waiter
            waiter = nil
            if waiting != nil { consumerEnded = true }
            lock.unlock()
            waiting?.resume(returning: nil)
        }
    }

    /// 受信の受け渡しを止め、消費側が最後に渡した行の処理を終えて次を要求して待機に入るまで待つ。
    /// 戻り値は処理済みの最後のseq。`timeout`までに消費側が処理を終えなければnil（受け渡しは止めたまま。
    /// 呼び出し側は`resume()`で再開するか、更新を中止する）。
    func quiesce(timeout: Duration = .seconds(30)) async -> UInt64? {
        let id = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UInt64?, Never>) in
            lock.lock()
            paused = true
            if waiter != nil || !consumerStarted || consumerEnded {
                let value = handedOut
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                quiesceWaiters.append((id, continuation))
                lock.unlock()
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
                    lock.lock()
                    let index = quiesceWaiters.firstIndex { $0.id == id }
                    let expired = index.map { quiesceWaiters.remove(at: $0) }
                    lock.unlock()
                    expired?.continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 確定に失敗して継続するとき、受信の受け渡しを再開する。
    func resume() {
        lock.lock()
        paused = false
        if let waiting = waiter, !queue.isEmpty {
            waiter = nil
            let entry = queue.removeFirst()
            handedOut = entry.seq
            lock.unlock()
            waiting.resume(returning: entry.data)
            return
        }
        lock.unlock()
    }
}
