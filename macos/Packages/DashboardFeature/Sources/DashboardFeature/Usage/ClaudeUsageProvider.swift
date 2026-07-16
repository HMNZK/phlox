import AgentDomain
import Foundation

public final class ClaudeUsageProvider: UsageProvider {
    public let kind: AgentKind = .claudeCode

    private static let unavailableReason =
        "Claude使用量は未取得です（ターミナルの Claude セッション実行時に更新されます）"

    private let rateLimitsURL: URL
    // UserDefaults は非 Sendable のため suite 名で保持し fetch 時に解決する
    // （nil = 共有 phloxDefaults。テストが固有 suite を注入して並列汚染を防ぐ）。
    private let defaultsSuiteName: String?

    public init(
        rateLimitsURL: URL = AppSupportLocator.appSupportDirectoryURL(
            home: FileManager.default.homeDirectoryForCurrentUser
        ).appending(path: "claude-usage-rate-limits.json")
    ) {
        self.rateLimitsURL = rateLimitsURL
        self.defaultsSuiteName = nil
    }

    init(rateLimitsURL: URL, defaultsSuiteName: String? = nil) {
        self.rateLimitsURL = rateLimitsURL
        self.defaultsSuiteName = defaultsSuiteName
    }

    public func fetch() async -> CLIUsage {
        let now = Date()
        let defaults = defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.phloxDefaults()
        if defaults.object(forKey: "phlox.usage.claudeScrape") as? Bool == false {
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "取得無効")), updatedAt: now)
        }

        guard let data = try? Data(contentsOf: rateLimitsURL) else {
            return CLIUsage(kind: kind, state: .unavailable(reason: Self.unavailableReason), updatedAt: now)
        }

        let dataAsOf = Self.dataAsOf(fromCacheData: data)

        guard let buckets = Self.buckets(fromCacheData: data), !buckets.isEmpty else {
            return CLIUsage(kind: kind, state: .unavailable(reason: Self.unavailableReason), updatedAt: now)
        }

        return CLIUsage(kind: kind, state: .ok(buckets), updatedAt: now, dataAsOf: dataAsOf)
    }

    static func dataAsOf(fromCacheData data: Data) -> Date? {
        guard let cache = try? JSONDecoder().decode(ClaudeRateLimitsCache.self, from: data),
              let ts = cache.ts else {
            return nil
        }
        return Date(timeIntervalSince1970: ts)
    }

    static func buckets(fromCacheData data: Data) -> [UsageBucket]? {
        guard let cache = try? JSONDecoder().decode(ClaudeRateLimitsCache.self, from: data) else {
            return nil
        }

        var buckets: [UsageBucket] = []
        if let fiveHour = cache.rateLimits.fiveHour?.usedPercentage {
            buckets.append(UsageBucket(
                id: "5h",
                label: String(localized: "5時間"),
                usedPercent: fiveHour,
                resetsAt: cache.rateLimits.fiveHour?.resetsAt.map { Date(timeIntervalSince1970: $0) }
            ))
        }
        if let sevenDay = cache.rateLimits.sevenDay?.usedPercentage {
            buckets.append(UsageBucket(
                id: "weekly",
                label: String(localized: "週次"),
                usedPercent: sevenDay,
                resetsAt: cache.rateLimits.sevenDay?.resetsAt.map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return buckets.isEmpty ? nil : buckets
    }
}

private struct ClaudeRateLimitsCache: Decodable {
    let ts: Double?
    let rateLimits: ClaudeRateLimits

    enum CodingKeys: String, CodingKey {
        case ts
        case rateLimits = "rate_limits"
    }
}

private struct ClaudeRateLimits: Decodable {
    let fiveHour: ClaudeRateLimit?
    let sevenDay: ClaudeRateLimit?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeRateLimit: Decodable {
    let usedPercentage: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
