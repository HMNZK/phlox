import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func usageMonitor_keepsRecentOKWhenIncomingUnavailable() {
    let ok = CLIUsage(
        kind: .cursor,
        state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 15)]),
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let unavailable = CLIUsage(
        kind: .cursor,
        state: .unavailable(reason: "Cursorの使用量を一時的に取得できません"),
        updatedAt: Date(timeIntervalSince1970: 120)
    )

    let resolved = UsageMonitor.resolvedUsage(
        incoming: unavailable,
        previousOK: ok,
        now: Date(timeIntervalSince1970: 200),
        stalenessInterval: 300
    )

    guard case let .ok(buckets) = resolved.state else {
        Issue.record("Expected recent ok usage to be retained")
        return
    }
    #expect(buckets.first { $0.id == "total" }?.usedPercent == 15)
    #expect(resolved.updatedAt == ok.updatedAt)
}

@Test func usageMonitor_appliesUnavailableWhenPreviousOKIsStale() {
    let ok = CLIUsage(
        kind: .cursor,
        state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 15)]),
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let unavailable = CLIUsage(
        kind: .cursor,
        state: .unavailable(reason: "Cursorの使用量を一時的に取得できません"),
        updatedAt: Date(timeIntervalSince1970: 500)
    )

    let resolved = UsageMonitor.resolvedUsage(
        incoming: unavailable,
        previousOK: ok,
        now: Date(timeIntervalSince1970: 500),
        stalenessInterval: 300
    )

    guard case let .unavailable(reason) = resolved.state else {
        Issue.record("Expected stale ok usage to be replaced by unavailable")
        return
    }
    #expect(reason == "Cursorの使用量を一時的に取得できません")
    #expect(resolved.updatedAt == unavailable.updatedAt)
}

@Test func usageMonitor_alwaysAppliesIncomingOK() {
    let previous = CLIUsage(
        kind: .cursor,
        state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 15)]),
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let incoming = CLIUsage(
        kind: .cursor,
        state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 25)]),
        updatedAt: Date(timeIntervalSince1970: 120)
    )

    let resolved = UsageMonitor.resolvedUsage(
        incoming: incoming,
        previousOK: previous,
        now: Date(timeIntervalSince1970: 120),
        stalenessInterval: 300
    )

    guard case let .ok(buckets) = resolved.state else {
        Issue.record("Expected incoming ok usage")
        return
    }
    #expect(buckets.first { $0.id == "total" }?.usedPercent == 25)
    #expect(resolved.updatedAt == incoming.updatedAt)
}

@Test func usageMonitor_resetsBucketWhoseResetTimeHasPassed() throws {
    let usage = CLIUsage(
        kind: .claudeCode,
        state: .ok([
            UsageBucket(id: "5h", label: "5時間", usedPercent: 99, resetsAt: Date(timeIntervalSince1970: 1_000)),
            UsageBucket(id: "weekly", label: "週次", usedPercent: 66, resetsAt: Date(timeIntervalSince1970: 9_000)),
        ]),
        updatedAt: Date(timeIntervalSince1970: 900)
    )

    let normalized = UsageMonitor.expiringPassedResets(in: usage, now: Date(timeIntervalSince1970: 5_000))

    guard case let .ok(buckets) = normalized.state else {
        Issue.record("Expected ok usage")
        return
    }
    let fiveHour = try #require(buckets.first { $0.id == "5h" })
    #expect(fiveHour.usedPercent == 0)
    #expect(fiveHour.resetsAt == nil)
    let weekly = try #require(buckets.first { $0.id == "weekly" })
    #expect(weekly.usedPercent == 66)
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 9_000))
}

@Test func usageMonitor_keepsBucketWithoutResetTime() throws {
    let usage = CLIUsage(
        kind: .cursor,
        state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 19)]),
        updatedAt: Date(timeIntervalSince1970: 900)
    )

    let normalized = UsageMonitor.expiringPassedResets(in: usage, now: Date(timeIntervalSince1970: 5_000))

    guard case let .ok(buckets) = normalized.state else {
        Issue.record("Expected ok usage")
        return
    }
    let total = try #require(buckets.first { $0.id == "total" })
    #expect(total.usedPercent == 19)
    #expect(total.resetsAt == nil)
}

@MainActor
@Test func usageMonitor_refreshNormalizesPassedResetFromProvider() async throws {
    let stale = CLIUsage(
        kind: .claudeCode,
        state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 99, resetsAt: Date(timeIntervalSince1970: 1_000))]),
        updatedAt: Date(timeIntervalSince1970: 900)
    )
    let monitor = UsageMonitor(
        providers: [.claudeCode: StubUsageProvider(usage: stale)],
        now: { Date(timeIntervalSince1970: 5_000) }
    )

    await monitor.refresh(kinds: [.claudeCode])

    let resolved = try #require(monitor.usages[.claudeCode])
    guard case let .ok(buckets) = resolved.state else {
        Issue.record("Expected ok usage")
        return
    }
    let fiveHour = try #require(buckets.first { $0.id == "5h" })
    #expect(fiveHour.usedPercent == 0)
    #expect(fiveHour.resetsAt == nil)
}

private struct StubUsageProvider: UsageProvider {
    let usage: CLIUsage
    var kind: AgentKind { usage.kind }

    func fetch() async -> CLIUsage {
        usage
    }
}
