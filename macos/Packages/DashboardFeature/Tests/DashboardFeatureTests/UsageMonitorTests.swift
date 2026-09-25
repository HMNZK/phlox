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

@Test func usageMonitor_keepsTwoHourOldOKByDefault() {
    let ok = CLIUsage(
        kind: .codex,
        state: .ok([UsageBucket(id: "weekly", label: "Weekly", usedPercent: 38)]),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    let unavailable = CLIUsage(
        kind: .codex,
        state: .unavailable(reason: "offline"),
        updatedAt: Date(timeIntervalSince1970: 7_200)
    )

    let resolved = UsageMonitor.resolvedUsage(
        incoming: unavailable,
        previousOK: ok,
        now: Date(timeIntervalSince1970: 7_200),
        stalenessInterval: UsageMonitor.defaultStalenessInterval
    )

    guard case .ok = resolved.state else {
        Issue.record("Expected the 2-hour-old value to stay on screen")
        return
    }
    #expect(resolved.updatedAt == ok.updatedAt)
}

@Test func usageMonitor_dropsTheKeptValueOnceAResetHasPassed() {
    let ok = CLIUsage(
        kind: .claudeCode,
        state: .ok([UsageBucket(id: "5h", label: "5h", usedPercent: 80, resetsAt: Date(timeIntervalSince1970: 3_600))]),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    let unavailable = CLIUsage(kind: .claudeCode, state: .unavailable(reason: "offline"), updatedAt: Date(timeIntervalSince1970: 3_600))

    let resolved = UsageMonitor.resolvedUsage(
        incoming: unavailable,
        previousOK: ok,
        now: Date(timeIntervalSince1970: 3_600),
        stalenessInterval: UsageMonitor.defaultStalenessInterval
    )

    guard case .unavailable = resolved.state else {
        Issue.record("A value from before the reset must not be shown as current")
        return
    }
}

@MainActor
@Test func usageMonitor_syncsKeptValuesAsUnavailable() async {
    let monitor = UsageMonitor(providers: [.codex: FlakyUsageProvider()], now: { Date(timeIntervalSince1970: 60) })
    await monitor.refresh()
    await monitor.refresh()

    guard case .ok = monitor.usages[.codex]?.state else {
        Issue.record("The Mac keeps showing the previous value")
        return
    }
    guard case .unavailable(let reason) = monitor.syncedUsages[.codex]?.state else {
        Issue.record("The phone must not get the kept value as current")
        return
    }
    #expect(reason == "offline")
}

private actor CallCounter {
    private var count = 0
    func next() -> Int {
        defer { count += 1 }
        return count
    }
}

/// 1 回目は成功、2 回目からは失敗する。
private struct FlakyUsageProvider: UsageProvider {
    let kind: AgentKind = .codex
    let calls = CallCounter()

    func fetch() async -> CLIUsage {
        await calls.next() == 0
            ? CLIUsage(kind: kind, state: .ok([UsageBucket(id: "weekly", label: "Weekly", usedPercent: 38)]), updatedAt: Date(timeIntervalSince1970: 0))
            : CLIUsage(kind: kind, state: .unavailable(reason: "offline"), updatedAt: Date(timeIntervalSince1970: 60))
    }
}

@MainActor
@Test func usageMonitor_doesNotKeepAValueNormalizedAfterItsReset() async {
    let monitor = UsageMonitor(providers: [.codex: PastResetThenFailingProvider()], now: { Date(timeIntervalSince1970: 7_200) })
    await monitor.refresh()
    await monitor.refresh()

    guard case .unavailable = monitor.usages[.codex]?.state else {
        Issue.record("A value from before the reset must not stay on screen as 100% left")
        return
    }
}

/// 1 回目はリセット時刻を過ぎた値で成功、2 回目からは失敗する。
private struct PastResetThenFailingProvider: UsageProvider {
    let kind: AgentKind = .codex
    let calls = CallCounter()

    func fetch() async -> CLIUsage {
        await calls.next() == 0
            ? CLIUsage(kind: kind, state: .ok([UsageBucket(id: "5h", label: "5h", usedPercent: 80, resetsAt: Date(timeIntervalSince1970: 3_600))]), updatedAt: Date(timeIntervalSince1970: 0))
            : CLIUsage(kind: kind, state: .unavailable(reason: "offline"), updatedAt: Date(timeIntervalSince1970: 7_200))
    }
}
