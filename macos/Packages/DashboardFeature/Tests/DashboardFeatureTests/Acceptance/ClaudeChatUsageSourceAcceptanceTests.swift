import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature

// task-3 受け入れテスト（PM 著・実装役編集禁止）。
// 契約: ClaudeChatUsageSource は生きているチャットセッション（UsageQuerying）へ
// 順に問い合わせ、最初に成功したスナップショットを CLIUsage(.ok) に写像する。
// セッション 0 本・全滅・バケット空のときは fallback の結果をそのまま返す。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

// MARK: - ハーネス

private struct FakeUsageQuerying: UsageQuerying {
    var snapshot: AgentRateLimitsSnapshot?

    func fetchRateLimits() async throws -> AgentRateLimitsSnapshot {
        guard let snapshot else { throw FakeUsageError() }
        return snapshot
    }
}

private struct FakeUsageError: Error {}

private struct FakeFallbackProvider: UsageProvider {
    let kind: AgentKind = .claudeCode
    let result: CLIUsage

    func fetch() async -> CLIUsage {
        result
    }
}

private let fallbackSentinel = CLIUsage(
    kind: .claudeCode,
    state: .unavailable(reason: "fallback-sentinel"),
    updatedAt: Date(timeIntervalSince1970: 1_000)
)

private func snapshot(
    fiveHour: Double? = 12,
    fiveHourResetsAt: Date? = Date(timeIntervalSince1970: 2_000),
    sevenDay: Double? = 3,
    sevenDayResetsAt: Date? = Date(timeIntervalSince1970: 3_000),
    asOf: Date = Date(timeIntervalSince1970: 1_500)
) -> AgentRateLimitsSnapshot {
    AgentRateLimitsSnapshot(
        fiveHour: fiveHour.map { AgentRateLimitsSnapshot.Bucket(usedPercentage: $0, resetsAt: fiveHourResetsAt) },
        sevenDay: sevenDay.map { AgentRateLimitsSnapshot.Bucket(usedPercentage: $0, resetsAt: sevenDayResetsAt) },
        asOf: asOf
    )
}

private func expectFallbackSentinel(_ usage: CLIUsage) {
    #expect(usage.kind == .claudeCode)
    guard case .unavailable(let reason) = usage.state else {
        Issue.record("expected fallback sentinel(.unavailable), got: \(usage.state)")
        return
    }
    #expect(reason == "fallback-sentinel")
    #expect(usage.updatedAt == fallbackSentinel.updatedAt)
}

// MARK: - 受け入れテスト

@Test func chatUsageSourceMapsSessionSnapshotToOKBuckets() async throws {
    let source = ClaudeChatUsageSource(
        sessions: { [FakeUsageQuerying(snapshot: snapshot())] },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    let usage = await source.fetch()

    #expect(usage.kind == .claudeCode)
    guard case .ok(let buckets) = usage.state else {
        Issue.record("expected .ok, got: \(usage.state)")
        return
    }
    // 既存 ClaudeUsageProvider と同じバケット語彙（id: "5h"/"weekly"）で UI 互換を保つ。
    #expect(buckets.count == 2)
    let fiveHour = try #require(buckets.first { $0.id == "5h" })
    let weekly = try #require(buckets.first { $0.id == "weekly" })
    #expect(fiveHour.usedPercent == 12)
    #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 2_000))
    #expect(weekly.usedPercent == 3)
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 3_000))
    #expect(usage.dataAsOf == Date(timeIntervalSince1970: 1_500))
}

@Test func chatUsageSourceOmitsMissingBucketInsteadOfFailing() async throws {
    let source = ClaudeChatUsageSource(
        sessions: { [FakeUsageQuerying(snapshot: snapshot(fiveHour: nil, fiveHourResetsAt: nil))] },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    let usage = await source.fetch()

    guard case .ok(let buckets) = usage.state else {
        Issue.record("expected .ok, got: \(usage.state)")
        return
    }
    #expect(buckets.count == 1)
    #expect(buckets.first?.id == "weekly")
    #expect(buckets.first?.usedPercent == 3)
}

@Test func chatUsageSourceFallsBackWhenNoSessions() async {
    let source = ClaudeChatUsageSource(
        sessions: { [] },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    expectFallbackSentinel(await source.fetch())
}

@Test func chatUsageSourceTriesNextSessionWhenFirstThrows() async throws {
    let source = ClaudeChatUsageSource(
        sessions: {
            [
                FakeUsageQuerying(snapshot: nil),
                FakeUsageQuerying(snapshot: snapshot(fiveHour: 77)),
            ]
        },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    let usage = await source.fetch()

    guard case .ok(let buckets) = usage.state else {
        Issue.record("expected .ok, got: \(usage.state)")
        return
    }
    #expect(buckets.first { $0.id == "5h" }?.usedPercent == 77)
}

@Test func chatUsageSourceFallsBackWhenAllSessionsThrow() async {
    let source = ClaudeChatUsageSource(
        sessions: { [FakeUsageQuerying(snapshot: nil), FakeUsageQuerying(snapshot: nil)] },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    expectFallbackSentinel(await source.fetch())
}

@Test func chatUsageSourceFallsBackWhenSnapshotHasNoBuckets() async {
    let source = ClaudeChatUsageSource(
        sessions: {
            [FakeUsageQuerying(snapshot: snapshot(
                fiveHour: nil, fiveHourResetsAt: nil,
                sevenDay: nil, sevenDayResetsAt: nil
            ))]
        },
        fallback: FakeFallbackProvider(result: fallbackSentinel)
    )

    expectFallbackSentinel(await source.fetch())
}
