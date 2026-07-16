import AgentDomain
import Foundation
import StructuredChatKit

// 供給順序: 生きているチャットセッション（UsageQuerying）へ順に問い合わせ、
// 最初に成功したスナップショットを CLIUsage(.ok) へ写像する。セッションが
// 0 本・全滅・バケット空のときは fallback（statusLine キャッシュの
// ClaudeUsageProvider）の結果をそのまま返す。
public final class ClaudeChatUsageSource: UsageProvider, Sendable {
    public let kind: AgentKind = .claudeCode

    private let sessions: @Sendable () async -> [any UsageQuerying]
    private let fallback: any UsageProvider

    public init(
        sessions: @escaping @Sendable () async -> [any UsageQuerying],
        fallback: any UsageProvider
    ) {
        self.sessions = sessions
        self.fallback = fallback
    }

    public func fetch() async -> CLIUsage {
        for session in await sessions() {
            do {
                let snapshot = try await session.fetchRateLimits()
                if let usage = Self.mapSnapshot(snapshot) {
                    return usage
                }
            } catch {
                continue
            }
        }
        return await fallback.fetch()
    }

    private static func mapSnapshot(_ snapshot: AgentRateLimitsSnapshot) -> CLIUsage? {
        var buckets: [UsageBucket] = []
        if let fiveHour = snapshot.fiveHour {
            buckets.append(UsageBucket(
                id: "5h",
                label: String(localized: "5時間"),
                usedPercent: fiveHour.usedPercentage,
                resetsAt: fiveHour.resetsAt
            ))
        }
        if let sevenDay = snapshot.sevenDay {
            buckets.append(UsageBucket(
                id: "weekly",
                label: String(localized: "週次"),
                usedPercent: sevenDay.usedPercentage,
                resetsAt: sevenDay.resetsAt
            ))
        }
        guard !buckets.isEmpty else { return nil }
        return CLIUsage(
            kind: .claudeCode,
            state: .ok(buckets),
            updatedAt: Date(),
            dataAsOf: snapshot.asOf
        )
    }
}
