import SwiftUI
import PhloxCore

/// パース済みペイロードを既存の保存経路へ適用する。保存は常に実行（QR が正）。
/// 疎通プローブは結果表示のためだけに使い、失敗でも保存は巻き戻さない。
@MainActor
@Observable
public final class PairingApplyViewModel {
    public enum Phase: Equatable {
        case idle
        case applying
        case success(name: String?)
        case unreachable(guidance: String)
    }

    public private(set) var phase: Phase

    private let tokenStore: TokenStore
    private let configStore: ConnectionConfigStoring
    private let probe: ConnectionSettingsViewModel.Probe

    public init(
        tokenStore: TokenStore,
        configStore: ConnectionConfigStoring,
        probe: @escaping ConnectionSettingsViewModel.Probe
    ) {
        self.tokenStore = tokenStore
        self.configStore = configStore
        self.probe = probe
        self.phase = .idle
    }

    /// ConnectionConfig(host:port:) を configStore.save、token を tokenStore.save したうえで
    /// probe(config, token) を1回実行し、phase を .success / .unreachable にする。
    public func apply(_ payload: PairingPayload) async {
        phase = .applying
        let config = ConnectionConfig(host: payload.host, port: payload.port)
        configStore.save(config)
        try? await tokenStore.save(payload.token)

        let reachable = await probe(config, payload.token)
        phase = reachable
            ? .success(name: payload.name)
            : .unreachable(guidance: PairingCopy.unreachableGuidance)
    }
}

/// 文言（テスト可能なコピー層。ConnectionSettingsCopy と同じ流儀）。
public enum PairingCopy {
    public static let unreachableGuidance =
        "Mac に接続できませんでした。Tailscale の接続を確認し、Mac 側で QR を再表示して、もう一度スキャンしてください。"
}
