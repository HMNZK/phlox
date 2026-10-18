import DesignSystemIOS
import Foundation
import Observation
import PhloxCore

@MainActor
@Observable
public final class UnreachableViewModel {
    public let reachability: Reachability
    public let endpoint: String?
    public let lastUpdated: Date?
    private let onRetry: () async -> Void
    public var isRetrying = false

    public init(
        reachability: Reachability,
        host: String? = nil,
        endpoint: String? = nil,
        lastUpdated: Date? = nil,
        onRetry: @escaping () async -> Void = {}
    ) {
        self.reachability = reachability
        self.endpoint = endpoint ?? host.map { "\($0):8765" }
        self.lastUpdated = lastUpdated
        self.onRetry = onRetry
    }

    public var cardTitle: String {
        switch reachability {
        case .offlineNetwork: "インターネットにつながっていません"
        case .unreachableHost: "Mac に届きません"
        default: "接続を確かめています"
        }
    }

    public var cardMessage: String {
        switch reachability {
        case .offlineNetwork:
            "iPhone が圏外か、機内モードになっています。"
        case .unreachableHost:
            "Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。"
        default:
            "Mac からの応答を待っています。最大 20 秒ほどかかります。"
        }
    }

    public var nextStep: String {
        switch reachability {
        case .offlineNetwork:
            "通信が戻ると自動でつなぎ直します。"
        case .unreachableHost:
            "Mac を起こすと自動でつなぎ直します。すぐ試すときはボタンを押してください。"
        default:
            "このままお待ちください。"
        }
    }

    public func technicalDetail(now: Date = Date()) -> String? {
        guard reachability == .unreachableHost, let endpoint else { return nil }
        return "\(endpoint) · \(lastUpdatedText(now: now) ?? "最終取得なし")"
    }

    public func lastUpdatedText(now: Date = Date()) -> String? {
        guard let lastUpdated else { return nil }
        let relative = DSRelativeTime.compact(from: lastUpdated, now: now)
        let unit = ["秒", "分", "時間", "日"].first { relative.contains($0) }
        let spacedRelative: String
        if let unit, let unitRange = relative.range(of: unit), unitRange.lowerBound > relative.startIndex {
            var spaced = relative
            spaced.insert(" ", at: unitRange.lowerBound)
            spacedRelative = spaced
        } else {
            spacedRelative = relative
        }
        return "最終取得 " + spacedRelative
    }

    public func footerText(now: Date = Date()) -> String {
        "\(lastUpdatedText(now: now) ?? "最終取得なし") · 下の「再接続を試す」で今すぐ確認"
    }

    public func retry() async {
        isRetrying = true
        await onRetry()
        isRetrying = false
    }
}
