import Foundation
import PhloxCore
import PhloxSecurity
import PhloxNetworking
import PhloxReachability
import Features

// App ターゲットの live Composition Root（Phase 4 統合）。
// 各依存の本番実装を組み立てる。接続設定（host/port）は UserDefaults、トークンは Keychain から読む。
//
// api/reachability は接続先を**都度** UserDefaults から解決する（`liveProvider`）。
// これにより「保存して接続」後にアプリ再起動なしで新しい host/port が反映される。
@MainActor
extension AppEnvironment {
    static let live: AppEnvironment = makeLive()

    /// 接続設定・QR ペアリング適用で共有する疎通プローブ。
    static let pairingProbe: ConnectionSettingsViewModel.Probe = { config, token in
        guard let url = URL(string: "http://\(config.host):\(config.port)") else { return false }
        return await HostHealthChecker().isHostReachable(baseURL: url, token: token)
    }

    private static func makeLive() -> AppEnvironment {
        let tokenStore = KeychainStore()
        let configProvider = UserDefaultsConnectionConfigStore.liveProvider

        let apiClient = PhloxAPIClient(configProvider: configProvider, tokenStore: tokenStore)
        let healthChecker = HostHealthChecker()
        let reachability = ReachabilityMonitor(healthCheck: {
            let config = configProvider()
            guard !config.host.isEmpty,
                  let url = URL(string: "http://\(config.host):\(config.port)") else { return false }
            let token = (try? await tokenStore.load()) ?? nil
            return await healthChecker.isHostReachable(baseURL: url, token: token)
        })
        let repository = SessionRepository(api: apiClient, reachability: reachability)

        return AppEnvironment(
            tokenStore: tokenStore,
            authenticator: BiometricGate(),
            apiClient: apiClient,
            reachability: reachability,
            sessionRepository: repository,
            auditLog: FileAuditLog()
        )
    }

    /// live の `PhloxAPIClient` を `DeviceTokenRegistering` として取り出す（Push 配線専用）。
    static var liveDeviceTokenRegistrar: any DeviceTokenRegistering {
        guard let client = live.apiClient as? PhloxAPIClient else {
            preconditionFailure("live apiClient must be PhloxAPIClient")
        }
        return client
    }
}
