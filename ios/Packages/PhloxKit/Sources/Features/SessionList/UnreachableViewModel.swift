import SwiftUI
import PhloxCore
import DesignSystemIOS

/// 到達不可（カンプ⑩ / E4-4 / DP-4-10）。圏外と Mac 応答なしを出しわけ、一覧オーバーレイ下部カード用。
@MainActor
@Observable
public final class UnreachableViewModel {
    public let reachability: Reachability
    public let host: String?
    public let lastUpdated: Date?
    private let onRetry: () async -> Void
    public var isRetrying = false

    public init(
        reachability: Reachability,
        host: String? = nil,
        lastUpdated: Date? = nil,
        onRetry: @escaping () async -> Void
    ) {
        self.reachability = reachability
        self.host = host
        self.lastUpdated = lastUpdated
        self.onRetry = onRetry
    }

    public var cardTitle: String {
        switch reachability {
        case .offlineNetwork: return "オフライン"
        case .unreachableHost: return "Mac に到達できません"
        default: return "接続を確認しています"
        }
    }

    public var cardMessage: String {
        switch reachability {
        case .offlineNetwork:
            return "圏外です。Wi-Fi またはモバイル通信を確認してください。"
        case .unreachableHost:
            return "Mac がスリープ中か Tailscale が切断されている可能性があります。スリープ解除後に自動で再接続します。"
        default:
            return "接続状態を確認しています。"
        }
    }

    public var technicalDetail: String? {
        guard reachability == .unreachableHost, let host else { return nil }
        return "ping \(host) → timeout"
    }

    public func bannerText(now: Date = Date()) -> String {
        if let last = lastUpdatedText(now: now) {
            return "オフライン · \(last)"
        }
        return "オフライン"
    }

    public func lastUpdatedText(now: Date = Date()) -> String? {
        guard let lastUpdated else { return nil }
        return "最終取得 " + DSRelativeTime.compact(from: lastUpdated, now: now)
    }

    public func retry() async {
        isRetrying = true
        await onRetry()
        isRetrying = false
    }
}
