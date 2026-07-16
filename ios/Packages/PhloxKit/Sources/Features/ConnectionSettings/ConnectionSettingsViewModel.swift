import SwiftUI
import PhloxCore

/// QR 専用の接続設定画面で使う文言。
enum ConnectionSettingsCopy {
    static let title = "接続設定"
    static let subtitle = "Mac の Phlox に QR コードで接続"
    static let connectionSection = "接続"
    static let currentConnectionLabel = "現在の接続先"
    static let notConnectedValue = "未接続"
    static let connectButtonTitle = "QR で接続"
    static let reconnectButtonTitle = "QR で再接続"
    static let testConnectionButtonTitle = "疎通テスト"
    static let testConnectionIcon = "arrow.clockwise"
    static let testSuccessMessage = "接続成功 · GET /sessions → 200"
    static let testFailureMessage = "到達不可 · Mac がスリープ中の可能性"
    static let noConnectionMessage = "QR コードを読み取って接続してください"
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
        banner = .success(ConnectionSettingsCopy.testSuccessMessage)
    }

    public var currentConnection: String {
        guard let connectionConfig else { return ConnectionSettingsCopy.notConnectedValue }
        return "\(connectionConfig.host):\(connectionConfig.port)"
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
        banner = reachable
            ? .success(ConnectionSettingsCopy.testSuccessMessage)
            : .failure(ConnectionSettingsCopy.testFailureMessage)
    }
}
