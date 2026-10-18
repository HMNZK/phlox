import SwiftUI
import PhloxCore

/// QR 専用の接続設定画面で使う文言。
enum ConnectionSettingsCopy {
    static let title = "Mac とつなぐ"
    static let subtitle = "Mac で動いている Claude Code・Codex・Cursor のセッションを、この iPhone から見て、応答できるようにします。"
    static let connectionSection = "接続"
    static let currentConnectionLabel = "現在の接続先"
    static let notConnectedValue = "未接続"
    static let connectButtonTitle = "QR を読み取る"
    static let reconnectButtonTitle = "QR で再接続"
    static let testConnectionButtonTitle = "疎通テスト"
    static let testConnectionIcon = "waveform.path.ecg"
    static let testSuccessMessage = "GET /sessions → 200 · 16:42 に確認"
    static let testFailureMessage = "Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。確かめてから、もう一度テストしてください。"
    static let noConnectionMessage = "QR コードを読み取って、接続先を保存してください。"

    static func successMessage(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return "GET /sessions → 200 · \(formatter.string(from: date)) に確認"
    }
}

/// 保存済みの接続先を読み取り専用で表示し、疎通を確認する。
/// 接続設定とトークンの更新は PairingApplyViewModel の QR 適用だけが担う。
@MainActor
@Observable
public final class ConnectionSettingsViewModel {
    public enum Banner: Equatable {
        case none
        case success(String)
        case failure(String)
    }

    /// 疎通プローブ。本番は HostHealthChecker、テストは closure を注入する。
    public typealias Probe = @Sendable (ConnectionConfig, String?) async -> Bool

    public private(set) var connectionConfig: ConnectionConfig?
    public var banner: Banner = .none
    public var isTesting = false
    public private(set) var lastTestWasReachable: Bool?

    private let tokenStore: TokenStore
    private let configStore: ConnectionConfigStoring
    private let probe: Probe

    public init(
        tokenStore: TokenStore,
        configStore: ConnectionConfigStoring,
        probe: @escaping Probe
    ) {
        self.tokenStore = tokenStore
        self.configStore = configStore
        self.probe = probe
        self.connectionConfig = configStore.load()
        seedForScreenshotIfNeeded()
    }

    private func seedForScreenshotIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-UIScreen=connectionSettings") else { return }
        connectionConfig = ConnectionConfig(host: "100.64.0.1", port: 8765)
        banner = .none
        lastTestWasReachable = true
    }

    public var currentConnection: String {
        guard let connectionConfig else { return ConnectionSettingsCopy.notConnectedValue }
        return "\(connectionConfig.host):\(connectionConfig.port)"
    }

    public var connectionStatus: String {
        switch lastTestWasReachable {
        case .none: "保存済み"
        case .some(true): "接続中"
        case .some(false): "Mac に届きません"
        }
    }

    public var hasConnectionConfig: Bool {
        connectionConfig != nil
    }

    public var qrButtonTitle: String {
        hasConnectionConfig
            ? ConnectionSettingsCopy.reconnectButtonTitle
            : ConnectionSettingsCopy.connectButtonTitle
    }

    /// QR 適用後に戻った場合を含め、永続化済みの接続先を表示へ反映する。
    public func refresh() {
        connectionConfig = configStore.load()
    }

    public func testConnection() async {
        guard let connectionConfig else {
            banner = .failure(ConnectionSettingsCopy.noConnectionMessage)
            return
        }
        isTesting = true
        let token = try? await tokenStore.load()
        let reachable = await probe(connectionConfig, token)
        isTesting = false
        lastTestWasReachable = reachable
        banner = reachable
            ? .success(ConnectionSettingsCopy.successMessage(at: Date()))
            : .failure(ConnectionSettingsCopy.testFailureMessage)
    }

    #if DEBUG
    public func seedReachabilityForSnapshot(_ isReachable: Bool?) {
        lastTestWasReachable = isReachable
    }
    #endif
}
