import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// accept デバッグログがファイルへ書き込むか（release では常に false）。
enum AcceptDebugLogPolicy {
    static var writesToFile: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// 設定画面のモバイル接続案内・トークン導線の表示可否。
/// iPhone コンパニオンが配布物に同梱されるまで非表示にする。
public enum MobileConnectionGuidePolicy {
    /// 現行配布物に iPhone クライアントアプリが同梱されているか。
    public static let isCompanionClientBundled = true

    /// 設定のモバイル接続セクション（トークン表示・接続案内）を出すか。
    public static var showsSettingsConnectionSection: Bool { isCompanionClientBundled }
}

/// BSD/POSIX ソケット listener。NWListener が utun で accept できない問題を回避するために
/// 素のソケットで実装する。
///
/// bind と最小権限の二段構え(macOS の VPN 配送制約への対応):
/// - macOS は VPN(utun)の特定 IP に bind したソケットへトンネル着信を配送しない。tailscale
///   モードでは機能のため `bindAddress = "0.0.0.0"`(INADDR_ANY)で bind せざるを得ない。
/// - 露出は accept 時の**接続元(remote peer)IP の CIDR フィルタ**(`allowedRemoteCIDRs`)で絞る。
///   Tailscale ピア(100.64.0.0/10)/ loopback(127.0.0.0/8)以外の接続元(LAN=en0 等)は
///   accept 直後に close し、ControlServer へ一切中継しない。
/// - loopbackOnly では `bindAddress = "127.0.0.1"` のまま(隔離維持)。
final class POSIXSocketListener: @unchecked Sendable {
    /// 受理したクライアント fd を受け取るハンドラ(所有権は受け手へ移る)。
    /// - clientFD: 受理済みクライアント fd。
    /// - onRelayFinished: リレー完全終了時に呼ぶ返却コールバック。同時リレー数セマフォの
    ///   スロットを 1 つ解放する。受け手(SocketRelay)は全終了経路で必ず一度だけ呼ぶ責務を負う。
    typealias AcceptHandler = @Sendable (_ clientFD: Int32, _ onRelayFinished: @escaping @Sendable () -> Void) -> Void

    #if DEBUG
    /// 検証用デバッグログのパス(os_log は log show で拾えないためファイル追記)。
    static let debugLogPath = "/tmp/mobileproxy-accept.log"
    #endif

    private let listenFD: Int32
    /// 実際に束縛されたポート(port 0 指定時はランダム割当て後の値)。
    let boundPort: UInt16
    private let handler: AcceptHandler
    /// accept を許可する接続元 CIDR。これ以外の接続元は即 close。
    private let allowedRemoteCIDRs: [String]
    /// 同時リレー数の上限セマフォ(CWE-400 対策)。accept ごとに 1 取得し、リレー終了で 1 返却。
    /// 取得できない(=上限超過)接続は accept 直後に close して枯渇を防ぐ。
    private let relaySemaphore: DispatchSemaphore

    private let lock = NSLock()
    private var stopped = false
    private var acceptThread: Thread?

    /// socket → SO_REUSEADDR → bind(bindAddress) → listen まで行う。失敗は MobileProxyError で投げる。
    /// - bindAddress: 実際に bind するアドレス(tailscale=0.0.0.0, loopbackOnly=127.0.0.1, 等)。
    /// - allowedRemoteCIDRs: accept を許可する接続元 CIDR(最小権限フィルタ)。
    /// - maxConcurrentRelays: 同時に中継するリレー数の上限。超過接続は accept 直後に close する。
    init(
        bindAddress: String,
        port: UInt16,
        allowedRemoteCIDRs: [String],
        maxConcurrentRelays: Int,
        handler: @escaping AcceptHandler
    ) throws {
        self.handler = handler
        self.allowedRemoteCIDRs = allowedRemoteCIDRs
        self.relaySemaphore = DispatchSemaphore(value: max(1, maxConcurrentRelays))

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw MobileProxyError.socketFailed("socket() failed: errno=\(errno)")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard bindAddress.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            close(fd)
            throw MobileProxyError.socketFailed("inet_pton failed for host \(bindAddress)")
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let e = errno
            close(fd)
            throw MobileProxyError.socketFailed("bind(\(bindAddress):\(port)) failed: errno=\(e)")
        }

        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            throw MobileProxyError.socketFailed("listen failed: errno=\(e)")
        }

        // port 0 指定時は getsockname で実ポートを取得する。
        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard nameResult == 0 else {
            let e = errno
            close(fd)
            throw MobileProxyError.socketFailed("getsockname failed: errno=\(e)")
        }

        self.listenFD = fd
        self.boundPort = UInt16(bigEndian: boundAddr.sin_port)
    }

    /// 専用スレッドで accept ループを開始する。受理した fd は handler へ渡す。
    func startAccepting() {
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "MobileProxy.accept"
        lock.lock()
        acceptThread = thread
        lock.unlock()
        thread.start()
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let isStopped = stopped
            lock.unlock()
            if isStopped { return }

            // 接続元アドレスを取得しながら accept する。
            var remoteAddr = sockaddr_storage()
            var remoteLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &remoteAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(listenFD, sa, &remoteLen)
                }
            }
            if clientFD < 0 {
                if errno == EINTR { continue }
                // listen fd がクローズされた(stop)等。停止状態なら正常終了。
                lock.lock()
                let s = stopped
                lock.unlock()
                if s { return }
                // それ以外の accept エラーは短い間隔を置いて継続(暴走防止)。
                usleep(10_000)
                continue
            }

            // accept 済み client fd の生成直後に SIGPIPE を抑止する。相手(iPhone)切断中の
            // 応答 write が SIGPIPE でプロセスを落とさず EPIPE を返すよう、上流 fd と両方に必須。
            setNoSIGPIPE(clientFD)

            // 最小権限フィルタ: 接続元(remote peer)IP が許可 CIDR に無ければ即 close。
            // 0.0.0.0 bind で全 IF に listen していても、Tailscale ピア(100.64.0.0/10)/
            // loopback(127.0.0.0/8)以外の接続元(LAN=en0 等)は ControlServer へ中継しない。
            let remoteIP = AcceptFilter.ipv4String(from: &remoteAddr)
            let allowed = AcceptFilter.shouldAccept(remoteIP: remoteIP, allowedCIDRs: allowedRemoteCIDRs)
            Self.appendDebugLog(remoteIP: remoteIP, accepted: allowed)
            guard allowed else {
                close(clientFD)
                continue
            }

            // 同時リレー数の上限(CWE-400 対策)。スロットを取れなければ超過接続として即 close する
            // (既存接続は継続)。取得成功時のみ handler へ渡し、リレー終了で 1 スロット返却する。
            // release はリレーの全終了経路(正常/早期 close/例外)で必ず一度だけ発火する(SocketRelay 側)。
            if relaySemaphore.wait(timeout: .now()) == .timedOut {
                close(clientFD)
                continue
            }
            let semaphore = relaySemaphore
            handler(clientFD) { semaphore.signal() }
        }
    }

    /// 検証用: accept ごとに接続元 IP と判定をファイルへ 1 行追記する(DEBUG のみ)。
    /// os_log は `log show` で拾えないためファイル追記。失敗は無視(検証補助のため)。
    private static func appendDebugLog(remoteIP: String?, accepted: Bool) {
        guard AcceptDebugLogPolicy.writesToFile else { return }
        #if DEBUG
        appendAcceptDebugLog(remoteIP: remoteIP, accepted: accepted, to: debugLogPath)
        #endif
    }

    #if DEBUG
    /// テスト用: 任意パスへ 1 行追記する。
    static func appendAcceptDebugLogForTesting(remoteIP: String?, accepted: Bool, to path: String) {
        appendAcceptDebugLog(remoteIP: remoteIP, accepted: accepted, to: path)
    }

    private static func appendAcceptDebugLog(remoteIP: String?, accepted: Bool, to path: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let decision = accepted ? "accept" : "reject"
        let line = "\(timestamp) remoteIP=\(remoteIP ?? "unknown") decision=\(decision)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
    #endif

    /// listener を停止する(listen fd を閉じて accept ループを終わらせる)。
    func stop() {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()
        // listen fd を閉じると accept がエラーで返り、ループが終了する。
        close(listenFD)
    }
}
