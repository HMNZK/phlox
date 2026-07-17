import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

/// プロキシ起動時の失敗。
public enum MobileProxyError: Error, Sendable {
    case listenerFailed(Error)
    case alreadyStarted
    case noPort
    case socketFailed(String)
}

/// プロキシが実際にどの範囲へバインドしたか(露出状態)。secure-by-default の可観測化に使う。
///
/// - tailscale: Tailscale の特定 IPv4 にのみバインド(モバイル到達可・最小権限)。
/// - loopbackOnly: Tailscale 未検出時の fail-closed フォールバック。127.0.0.1 限定で
///   外部露出ゼロ(モバイルからは到達不可)。**全 IF(0.0.0.0)には決して暗黙バインドしない**。
/// - explicitHost: 呼び出し側が listenHost を明示指定したときのみ。利用者の意図的選択として
///   そのホスト(特定 IP 推奨。"0.0.0.0" を指定したときだけ全 IF)にバインドする。
public enum BindMode: Equatable, Sendable {
    case tailscale(String)
    case loopbackOnly
    case explicitHost(String)

    /// 実際にバインドするホスト文字列。loopbackOnly は常に 127.0.0.1。
    public var bindHost: String {
        switch self {
        case .tailscale(let ip):
            return ip
        case .loopbackOnly:
            return "127.0.0.1"
        case .explicitHost(let host):
            return host
        }
    }

    /// fail-closed のバインド範囲決定(純関数・テスト可能)。
    /// - listenHost 明示 → explicitHost(利用者の意図。"0.0.0.0" 明示時のみ全 IF を許す)。
    /// - 未指定 + Tailscale 解決成功 → tailscale(特定 IP)。
    /// - 未指定 + Tailscale 未解決 → loopbackOnly(127.0.0.1 限定。全 IF へは開かない)。
    static func resolve(listenHost: String?, resolveTailscaleIPv4: () -> String?) -> BindMode {
        if let listenHost {
            return .explicitHost(listenHost)
        }
        if let tailscaleIP = resolveTailscaleIPv4() {
            return .tailscale(tailscaleIP)
        }
        return .loopbackOnly
    }
}

/// Tailscale インターフェース(既定)で固定ポートを待ち受け、受けた TCP 接続を
/// `127.0.0.1:<targetPort>`(ControlServer)へ生バイトのまま双方向中継する薄いリバースプロキシ。
///
/// listener は **BSD/POSIX ソケット**で実装する。NWListener は requiredLocalEndpoint /
/// requiredInterface のどちらでも Tailscale の utun(point-to-point/VPN)アドレスで accept
/// できない(LISTEN 表示のみ)実機バグがあるため。素のソケットを特定アドレスへ bind すれば
/// utun でも accept が成立する(Python の素ソケットで実証済み)。
///
/// 透過性: HTTP を一切パースしない生 TCP リレー。method / path / query / ヘッダ
/// (Authorization・Content-Length 含む)/ body / status をバイト等価で通す。
/// 認証判断はしない(透過)。Bearer 検証は転送先の ControlServer が行う。
public actor MobileProxy {
    /// 同時リレー数の既定上限(CWE-400 対策)。1 リレー = スレッド 2 本 + 上流ソケット 1 本を消費するため
    /// 無制限だとスレッド/ソケット枯渇でプロキシ(ひいては Phlox)が不安定化する。実運用のモバイル
    /// 同時接続数(端末 1〜数台の keep-alive)を大きく上回る 128 を上限に、超過は accept 直後に close する。
    public static let defaultMaxConcurrentRelays = 128

    /// nil のとき start 時に Tailscale IPv4 を解決する。
    private let configuredHost: String?
    private let listenPort: UInt16
    private let targetPort: UInt16
    private let maxConcurrentRelays: Int
    private let resolver: TailscaleIPResolver
    private let logger = Logger(subsystem: "com.phlox.MobileProxy", category: "proxy")

    private var listener: POSIXSocketListener?

    /// 起動後に確定する露出状態。未起動は nil。
    public private(set) var bindMode: BindMode?

    /// 現在の listener が実際に束縛しているポート。未起動または起動失敗時は nil。
    public private(set) var boundPort: UInt16?

    /// - Parameters:
    ///   - listenHost: 待ち受けアドレス。nil なら Tailscale IPv4 を解決し、不可なら loopback 限定。
    ///   - listenPort: 待ち受けポート(既定 8765)。0 を渡すとランダム(テスト用)。
    ///   - targetPort: 転送先 ControlServer のポート(127.0.0.1)。
    ///   - maxConcurrentRelays: 同時リレー数の上限(既定 128)。超過接続は accept 直後に close される。
    ///   - resolver: Tailscale IP 解決器(DI シーム)。
    public init(
        listenHost: String? = nil,
        listenPort: UInt16 = 8765,
        targetPort: UInt16,
        maxConcurrentRelays: Int = MobileProxy.defaultMaxConcurrentRelays,
        resolver: TailscaleIPResolver = TailscaleIPResolver()
    ) {
        self.configuredHost = listenHost
        self.listenPort = listenPort
        self.targetPort = targetPort
        self.maxConcurrentRelays = maxConcurrentRelays
        self.resolver = resolver
    }

    /// プロキシを起動し、束縛された待ち受けポートを返す。
    /// 露出範囲(BindMode)は start 後に `bindMode` から参照できる。
    @discardableResult
    public func start() async throws -> UInt16 {
        try startListener()
    }

    /// listener の構築と状態更新を、actor の中断点を挟まずに完了する。
    private func startListener() throws -> UInt16 {
        if listener != nil {
            throw MobileProxyError.alreadyStarted
        }

        // fail-closed: バインド範囲を決定する。未解決時も loopback 限定で、全 IF へは開かない。
        let resolver = self.resolver
        let mode = BindMode.resolve(listenHost: configuredHost) { resolver.resolveIPv4() }
        logBindMode(mode)

        let (bindAddress, allowedRemoteCIDRs) = Self.bindPlan(for: mode)

        let targetPort = self.targetPort
        let listener: POSIXSocketListener
        do {
            listener = try POSIXSocketListener(
                bindAddress: bindAddress,
                port: listenPort,
                allowedRemoteCIDRs: allowedRemoteCIDRs,
                maxConcurrentRelays: maxConcurrentRelays
            ) { clientFD, onRelayFinished in
                SocketRelay.start(clientFD: clientFD, targetPort: targetPort, onFinished: onRelayFinished)
            }
        } catch let error as MobileProxyError {
            throw error
        } catch {
            throw MobileProxyError.listenerFailed(error)
        }

        self.listener = listener
        self.bindMode = mode
        self.boundPort = listener.boundPort
        listener.startAccepting()
        return listener.boundPort
    }

    /// Tailscale の状態を再評価し、必要なら listener を停止して再構築する。
    /// tailscale または明示ホストで起動済みの場合は現在の状態を維持する。
    @discardableResult
    public func refresh() async -> BindMode? {
        switch bindMode {
        case .tailscale, .explicitHost:
            return bindMode
        case nil, .loopbackOnly:
            stop()
            do {
                _ = try startListener()
                return bindMode
            } catch {
                logger.error("Mobile proxy refresh failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// Tailscale 到達可能になるまで、有限回だけ再解決・再バインドを試す。
    /// 試行間の待機は注入可能で、テストでは実時間待ちを避けられる。
    @discardableResult
    public func recoverUntilReachable(
        maxAttempts: Int,
        delay: Duration,
        sleep: @Sendable (Duration) async -> Void = { duration in
            try? await Task<Never, Never>.sleep(for: duration)
        }
    ) async -> BindMode? {
        guard maxAttempts > 0 else { return bindMode }

        for attempt in 0..<maxAttempts {
            let mode = await refresh()
            if case .tailscale = mode {
                return mode
            }
            if case .explicitHost = mode {
                return mode
            }
            if attempt < maxAttempts - 1 {
                await sleep(delay)
            }
        }
        return bindMode
    }

    /// loopback の許可 CIDR(127.0.0.0/8。hairpin/ヘルスチェック/結合テストの 127.0.0.1 用)。
    static let loopbackCIDR = "127.0.0.0/8"
    /// Tailscale ピアの CGNAT 範囲。Tailscale ノードの IP は必ずこの範囲。
    static let tailscaleCGNATCIDR = "100.64.0.0/10"

    /// BindMode から「実 bind アドレス」と「accept を許可する接続元 CIDR」を決める(純関数)。
    ///
    /// - tailscale / 非 loopback explicitHost: macOS は utun の特定 IP bind へトンネル着信を
    ///   配送しないため `0.0.0.0` に bind する。接続元の許可 CIDR は Tailscale 範囲 + loopback。
    ///   LAN(172.16/12・192.168/16・10/8)やグローバルの接続元はこれに入らず遮断される。
    /// - loopbackOnly / loopback explicitHost: `127.0.0.1` に bind し、許可も loopback のみ(隔離維持)。
    static func bindPlan(for mode: BindMode) -> (bindAddress: String, allowedRemoteCIDRs: [String]) {
        let host = mode.bindHost
        if isLoopback(host) {
            return ("127.0.0.1", [loopbackCIDR])
        }
        // 非 loopback: 0.0.0.0 で listen しつつ、接続元は Tailscale 範囲 + loopback に限定する。
        return ("0.0.0.0", [tailscaleCGNATCIDR, loopbackCIDR])
    }

    /// プロキシを停止する。
    public func stop() {
        listener?.stop()
        listener = nil
        bindMode = nil
        boundPort = nil
    }

    /// 127.0.0.1 系(ループバック)か。
    static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1" || host.hasPrefix("127.")
    }

    /// バインド範囲に応じてログを出す。loopbackOnly は「モバイル接続不可」と分かる形で記録する。
    private func logBindMode(_ mode: BindMode) {
        switch mode {
        case .tailscale(let ip):
            logger.info("Mobile proxy binding to Tailscale interface \(ip, privacy: .public):\(self.listenPort, privacy: .public)")
        case .explicitHost(let host):
            logger.info("Mobile proxy binding to explicit host \(host, privacy: .public):\(self.listenPort, privacy: .public)")
        case .loopbackOnly:
            logger.warning(
                "Tailscale not detected; mobile proxy bound to loopback only (127.0.0.1:\(self.listenPort, privacy: .public)) — mobile connection unavailable, no external exposure (fail-closed)"
            )
        }
    }
}
