import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// continuation を一度だけ resume するための Sendable な小ヘルパ。
/// NWConnection/NWListener の stateUpdateHandler が複数回発火しても二重 resume を防ぐ。
final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        block()
    }
}

enum TestSocketError: Error {
    case socketFailed
    case bindFailed
    case listenFailed
    case getsocknameFailed
    case badAddress
    case connectFailed
}

/// accept 同時数上限の回帰用: 127.0.0.1 のランダムポートで待ち受け、受理した接続を
/// **保持し続ける**(read も write も close もしない)スタブ上流サーバ。
/// これによりプロキシ側のリレースロットが解放されないまま占有され続けるので、上限の
/// 挙動(超過接続の即 close)を実ソケットで観測できる。`acceptedCount` で上流到達数を数える。
final class HoldingUpstreamServer: @unchecked Sendable {
    let port: UInt16
    private let listenFD: Int32
    private let lock = NSLock()
    private var heldFDs: [Int32] = []
    private var _acceptedCount = 0
    private var stopped = false

    /// これまでに上流(このサーバ)へ到達し accept された接続数。
    var acceptedCount: Int { lock.withLock { _acceptedCount } }

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestSocketError.socketFailed }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        guard "127.0.0.1".withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            close(fd)
            throw TestSocketError.badAddress
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw TestSocketError.bindFailed }
        guard listen(fd, 16) == 0 else { close(fd); throw TestSocketError.listenFailed }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard nameResult == 0 else { close(fd); throw TestSocketError.getsocknameFailed }

        self.listenFD = fd
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "HoldingUpstreamServer.accept"
        thread.start()
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                lock.lock()
                let s = stopped
                lock.unlock()
                if s { return }
                if errno == EINTR { continue }
                return
            }
            lock.lock()
            heldFDs.append(clientFD)     // 保持: read/write/close しない
            _acceptedCount += 1
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true
        let fds = heldFDs
        heldFDs.removeAll()
        lock.unlock()
        for fd in fds { close(fd) }
        close(listenFD)
    }
}

/// 生 POSIX ソケットで接続を張り、明示 close するまで**開いたまま保持する**テストクライアント。
/// 上限テストでスロットを占有し続けるために使う。
final class PersistentRawClient {
    let fd: Int32

    /// - recvBufferBytes: 非 nil なら connect 前に SO_RCVBUF をこの値へ固定する。受信バッファの
    ///   自動拡張を無効化し、相手(relay)の write を早期にブロックさせる用途(SIGPIPE wiring テスト)。
    init(port: UInt16, host: String = "127.0.0.1", recvBufferBytes: Int32? = nil) throws {
        let f = socket(AF_INET, SOCK_STREAM, 0)
        guard f >= 0 else { throw TestSocketError.socketFailed }

        if var rcv = recvBufferBytes {
            setsockopt(f, SOL_SOCKET, SO_RCVBUF, &rcv, socklen_t(MemoryLayout<Int32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            Darwin.close(f)
            throw TestSocketError.badAddress
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(f, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { Darwin.close(f); throw TestSocketError.connectFailed }
        // テストクライアント自身を守る。相手(プロキシ)がリレーを teardown した後に本クライアントが
        // write すると SIGPIPE でテストランナーが死ぬため、SO_NOSIGPIPE で EPIPE 化する。
        // これは production の被テスト対象(SocketRelay/POSIXSocketListener)の wiring とは独立。
        var on: Int32 = 1
        setsockopt(f, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        self.fd = f
    }

    /// 1 バイトを最大 `ms` ミリ秒待って読む。戻り値は read の戻り値そのもの
    /// (0=EOF/相手 close, 正数=データ, 負数=タイムアウト等のエラー)。
    func readOneWithTimeout(ms: Int) -> Int {
        var tv = timeval(tv_sec: ms / 1000, tv_usec: Int32((ms % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        return read(fd, &byte, 1)
    }

    /// data を可能な限り全量書き込む。相手 teardown による失敗(EPIPE 等)は無視する
    /// (SO_NOSIGPIPE 済みなのでランナーは死なない)。巨大 body を送って relay の upstream
    /// write-after-close を踏ませる用途。
    func sendAllIgnoringError(_ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    return  // 相手が消えた(EPIPE 等)。ここで打ち切る(ランナーは生存)。
                }
                offset += n
            }
        }
    }

    /// SO_LINGER {1,0} を設定して close することで、送信バッファを捨てて **RST** で即切断する。
    /// 相手(relay)の未完了 read/write を EPIPE/ECONNRESET で確実に失敗させる。
    func closeWithReset() {
        var lg = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &lg, socklen_t(MemoryLayout<linger>.size))
        Darwin.close(fd)
    }

    func close() {
        Darwin.close(fd)
    }
}

/// upstream fd 側(SocketRelay.connectLoopback)の SIGPIPE wiring を突くための上流スタブ。
/// relay の接続を accept した後、**読まずに** `closeAfterMs` 待ってから RST で切断する。
/// これで relay の `pumpClientToUpstream` は満杯の upstream 送信バッファで write にブロックし、
/// RST 到達時に write-after-peer-close(SIGPIPE or EPIPE)を踏む。
/// 受信バッファを小さく固定(`recvBufferBytes`)して自動拡張を止めることで、巨大 body を
/// 全部飲み込まれずに relay を早期ブロックさせられる。
final class AbortingUpstreamServer: @unchecked Sendable {
    let port: UInt16
    private let listenFD: Int32
    private let closeAfterMs: Int
    private let lock = NSLock()
    private var stopped = false

    init(closeAfterMs: Int, recvBufferBytes: Int32? = nil) throws {
        self.closeAfterMs = closeAfterMs
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestSocketError.socketFailed }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // 受信バッファを小さく固定(listen 前に設定 → accept 済みソケットが継承)。relay の
        // upstream write を早期にブロックさせ、RST 時に write-after-close を確実に踏ませる。
        if var rcv = recvBufferBytes {
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcv, socklen_t(MemoryLayout<Int32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        guard "127.0.0.1".withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            Darwin.close(fd)
            throw TestSocketError.badAddress
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { Darwin.close(fd); throw TestSocketError.bindFailed }
        guard listen(fd, 16) == 0 else { Darwin.close(fd); throw TestSocketError.listenFailed }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard nameResult == 0 else { Darwin.close(fd); throw TestSocketError.getsocknameFailed }

        self.listenFD = fd
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "AbortingUpstreamServer.accept"
        thread.start()
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                lock.lock(); let s = stopped; lock.unlock()
                if s { return }
                if errno == EINTR { continue }
                return
            }
            let delayUs = UInt32(closeAfterMs * 1000)
            // 読まずに待ってから RST(linger 0)で切断する。
            Thread.detachNewThread {
                usleep(delayUs)
                var linger = linger(l_onoff: 1, l_linger: 0)
                setsockopt(clientFD, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<linger>.size))
                Darwin.close(clientFD)
            }
        }
    }

    func stop() {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true
        lock.unlock()
        Darwin.close(listenFD)
    }
}
