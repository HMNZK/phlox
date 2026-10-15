import AgentDomain
import ClaudeAgentKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature

@MainActor
struct ClaudeUsageRefreshTests {
    @MainActor final class Clock {
        var date = Date(timeIntervalSince1970: 2000000000)
        func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }
    final class Output {
        var usage: CLIUsage?
        var failure: String?
    }
    actor CloseCounter {
        var count = 0
        func increment() { count += 1 }
    }
    struct Cache: UsageProvider {
        let kind: AgentKind = .claudeCode
        let usage: CLIUsage?
        func fetch() async -> CLIUsage { usage ?? CLIUsage(kind: kind, state: .unavailable(reason: "no cache"), updatedAt: .now) }
    }
    actor Query: UsageQuerying {
        var calls = 0
        var fail = false
        var suspended = false
        var retryAfter: TimeInterval?
        var pending: CheckedContinuation<AgentRateLimitsSnapshot, Error>?
        let snapshot: AgentRateLimitsSnapshot
        init(_ snapshot: AgentRateLimitsSnapshot) { self.snapshot = snapshot }
        func configure(fail: Bool = false, suspended: Bool = false, retryAfter: TimeInterval? = nil) {
            self.fail = fail; self.suspended = suspended; self.retryAfter = retryAfter
        }
        func fetchRateLimits() async throws -> AgentRateLimitsSnapshot {
            calls += 1
            if let retryAfter { throw ClaudeChatClientError.usageRequestThrottled(retryAfter: retryAfter) }
            if fail { throw CocoaError(.fileReadUnknown) }
            if suspended { return try await withCheckedThrowingContinuation { pending = $0 } }
            return snapshot
        }
        func complete() { pending?.resume(returning: snapshot); pending = nil }
    }
    func snapshot(_ clock: Clock, five: Double? = 9, weekly: Double? = 39) -> AgentRateLimitsSnapshot {
        .init(fiveHour: five.map { .init(usedPercentage: $0, resetsAt: clock.date.addingTimeInterval(3600)) },
              sevenDay: weekly.map { .init(usedPercentage: $0, resetsAt: clock.date.addingTimeInterval(86400)) }, asOf: clock.date)
    }
    func make(_ clock: Clock, query: Query, output: Output, id: UUID,
              cache: CLIUsage? = nil) -> ClaudeUsageRefresh {
        ClaudeUsageRefresh(connections: { [.init(id: id, query: query)] }, dedicated: query,
                           closeDedicated: {}, cache: Cache(usage: cache), now: { clock.date },
                           sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { output.usage = $0; output.failure = $1 }
    }

    @Test func notificationDefersBothWindowsUntilSixtySeconds() async throws {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        refresh.receive(snapshot(clock), from: id)
        clock.advance(59)
        await refresh.refreshIfDue()
        #expect(await query.calls == 1)
        clock.advance(1)
        await refresh.refreshIfDue()
        #expect(await query.calls == 2)
        let usage = try #require(output.usage)
        guard case .ok(let buckets) = usage.state else { Issue.record("missing usage"); return }
        #expect(buckets.map { UsageDisplay.remainingPercent(usedPercent: $0.usedPercent) } == [91, 61])
        #expect(output.failure == nil)
    }

    @Test func oneWindowCannotKeepOtherWindowFresh() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        clock.advance(59)
        refresh.receive(snapshot(clock, weekly: nil), from: id)
        clock.advance(1)
        await refresh.refreshIfDue()
        #expect(await query.calls == 2)
    }

    @Test func delayedQueryCannotOverwriteNotificationAndOnlyOneQueryRuns() async throws {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock, five: 5, weekly: 30))
        await query.configure(suspended: true)
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        let request = Task { await refresh.refreshIfDue() }
        while await query.calls == 0 { await Task.yield() }
        await refresh.refreshIfDue()
        refresh.receive(snapshot(clock, five: 20, weekly: nil), from: id)
        await query.complete()
        await request.value
        #expect(await query.calls == 1)
        guard case .ok(let buckets) = output.usage?.state else { Issue.record("missing usage"); return }
        #expect(buckets.first { $0.id == "5h" }?.usedPercent == 20)
        #expect(buckets.first { $0.id == "weekly" }?.usedPercent == 30)
    }

    @Test func failuresBackOffAndCacheDoesNotPostponeRetry() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        await query.configure(fail: true)
        let cached = CLIUsage(kind: .claudeCode, state: .ok([
            .init(id: "5h", label: "5時間", usedPercent: 8, resetsAt: clock.date.addingTimeInterval(5000))
        ]), updatedAt: clock.date.addingTimeInterval(-300), dataAsOf: clock.date.addingTimeInterval(-300))
        let refresh = make(clock, query: query, output: output, id: id, cache: cached)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        for delay in [120.0, 240, 480, 900, 900] {
            await refresh.refreshIfDue()
            #expect(refresh.nextFetchAt == clock.date.addingTimeInterval(delay))
            #expect(output.failure != nil)
            clock.advance(delay - 1)
            let before = await query.calls
            await refresh.refreshIfDue()
            #expect(await query.calls == before)
            clock.advance(1)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func settingsCombinations(enabled: Bool, automatic: Bool) async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: enabled, automatic: automatic)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        clock.advance(60)
        await refresh.refreshIfDue()
        #expect(await query.calls == (enabled ? (automatic ? 2 : 1) : 0))
        refresh.receive(snapshot(clock, five: 21), from: id)
        if enabled {
            guard case .ok(let buckets) = output.usage?.state else { Issue.record("notification missing"); return }
            #expect(buckets.first?.usedPercent == 21)
        } else {
            guard case .unavailable = output.usage?.state else { Issue.record("disabled must be unavailable"); return }
        }
    }

    @Test func disabledDuringRequestRejectsLateResponseAndUnknownSourceIsIgnored() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        await query.configure(suspended: true)
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        let request = Task { await refresh.refreshIfDue() }
        while await query.calls == 0 { await Task.yield() }
        refresh.updateSettings(enabled: false, automatic: true)
        await query.complete()
        await request.value
        guard case .unavailable = output.usage?.state else { Issue.record("late response accepted"); return }
        refresh.updateSettings(enabled: true, automatic: false)
        refresh.receive(snapshot(clock), from: UUID())
        guard case .unavailable = output.usage?.state else { Issue.record("unknown source accepted"); return }
    }

    @Test func freshNotificationsRecoverFailureWithoutPolling() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        await query.configure(fail: true)
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: false)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        #expect(output.failure != nil)
        refresh.receive(snapshot(clock), from: id)
        #expect(output.failure == nil)
        #expect(refresh.nextFetchAt == nil)
        #expect(await query.calls == 1)
    }

    @Test func switchingAwayFromDedicatedRequestDoesNotCreateFailureOrBackoff() async {
        let clock = Clock(), output = Output(), id = UUID()
        let dedicated = Query(snapshot(clock)), chat = Query(snapshot(clock))
        await dedicated.configure(suspended: true)
        var available: [ClaudeUsageConnection] = []
        let refresh = ClaudeUsageRefresh(connections: { available }, dedicated: dedicated,
            closeDedicated: {}, cache: Cache(usage: nil), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { output.usage = $0; output.failure = $1 }
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        let request = Task { await refresh.refreshIfDue() }
        while await dedicated.calls == 0 { await Task.yield() }
        available = [.init(id: id, query: chat)]
        refresh.connectionsChanged()
        await dedicated.complete()
        await request.value
        #expect(output.failure == nil)
        #expect(refresh.nextFetchAt == clock.date.addingTimeInterval(60))
        clock.advance(60)
        await refresh.refreshIfDue()
        #expect(await chat.calls == 1)
    }

    @Test func expiredWindowIsUnknownWhileRealZeroRemainsOneHundredPercent() throws {
        let clock = Clock()
        let invalid = AgentRateLimitsSnapshot(fiveHour: .init(usedPercentage: 99, resetsAt: clock.date),
            sevenDay: .init(usedPercentage: 0, resetsAt: clock.date.addingTimeInterval(60)), asOf: clock.date)
        let buckets = ClaudeUsageRefresh.buckets(invalid, now: clock.date)
        #expect(buckets.map(\.id) == ["weekly"])
        #expect(UsageDisplay.remainingPercent(usedPercent: try #require(buckets.first).usedPercent) == 100)
        let aboveLimit = snapshot(clock, five: 130)
        #expect(ClaudeUsageRefresh.buckets(aboveLimit, now: clock.date).first?.usedPercent == 130)
        #expect(UsageDisplay.remainingPercent(usedPercent: 130) == 0)
    }

    @Test func delayWhilePreparingSourceDoesNotShortenNextQueryInterval() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        let refresh = ClaudeUsageRefresh(connections: { [.init(id: id, query: query)] }, dedicated: query,
            closeDedicated: { await MainActor.run { clock.advance(10) } }, cache: Cache(usage: nil), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { output.usage = $0; output.failure = $1 }
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        #expect(refresh.nextFetchAt == clock.date.addingTimeInterval(60))
        clock.advance(59)
        await refresh.refreshIfDue()
        #expect(await query.calls == 1)
    }

    @Test func serverWaitSurvivesSuccessfulNotification() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        await query.configure(retryAfter: 600)
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: true)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        let deadline = clock.date.addingTimeInterval(600)
        clock.advance(10)
        refresh.receive(snapshot(clock), from: id)
        #expect(output.failure == nil)
        #expect(refresh.nextFetchAt == deadline)
        clock.advance(589)
        await refresh.refreshIfDue()
        #expect(await query.calls == 1)
        clock.advance(1)
        await refresh.refreshIfDue()
        #expect(await query.calls == 2)
    }

    @Test func unrelatedSettingsNotificationDoesNotCloseInitialOneShotRequest() async {
        let clock = Clock(), output = Output()
        let query = Query(snapshot(clock))
        await query.configure(suspended: true)
        let closes = CloseCounter()
        let refresh = ClaudeUsageRefresh(connections: { [] }, dedicated: query,
            closeDedicated: { await closes.increment() }, cache: Cache(usage: nil), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { output.usage = $0; output.failure = $1 }
        refresh.start(enabled: true, automatic: false)
        defer { refresh.stop() }
        let request = Task { await refresh.refreshIfDue() }
        while await query.calls == 0 { await Task.yield() }
        refresh.updateSettings(enabled: true, automatic: false)
        #expect(await closes.count == 0)
        await query.complete()
        await request.value
        #expect(await closes.count == 1)
        #expect(output.failure == nil)
    }

    @Test func expiredStaleWindowDoesNotHideFreshWeeklyWindowFromSync() async throws {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(snapshot(clock))
        await query.configure(fail: true)
        let cached = CLIUsage(kind: .claudeCode, state: .ok([
            .init(id: "5h", label: "5時間", usedPercent: 8, resetsAt: clock.date.addingTimeInterval(10)),
            .init(id: "weekly", label: "週次", usedPercent: 30, resetsAt: clock.date.addingTimeInterval(3600))
        ]), updatedAt: clock.date.addingTimeInterval(-300), dataAsOf: clock.date.addingTimeInterval(-300))
        let refresh = ClaudeUsageRefresh(connections: { [.init(id: id, query: query)] }, dedicated: query,
            closeDedicated: {}, cache: Cache(usage: cached), now: { clock.date }, sleep: { delay in
                if delay < 100 {
                    try await Task.sleep(for: .milliseconds(1))
                    await MainActor.run { clock.advance(delay) }
                } else { try await Task.sleep(for: .seconds(3600)) }
            }) { output.usage = $0; output.failure = $1 }
        refresh.start(enabled: true, automatic: false)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        refresh.receive(snapshot(clock, five: nil), from: id)
        #expect(output.failure != nil)
        for _ in 0..<200 where output.failure != nil { try await Task.sleep(for: .milliseconds(1)) }
        #expect(output.failure == nil)
        guard case .ok(let buckets) = output.usage?.state else { Issue.record("fresh weekly missing"); return }
        #expect(buckets.map(\.id) == ["weekly"])
    }

    @Test func integerSecondNotificationCanUpdateFractionalSecondQueryWindow() async {
        let clock = Clock(), output = Output(), id = UUID()
        let query = Query(.init(
            fiveHour: .init(usedPercentage: 9, resetsAt: clock.date.addingTimeInterval(3600.163)),
            sevenDay: .init(usedPercentage: 39, resetsAt: clock.date.addingTimeInterval(86400.163)), asOf: clock.date))
        let refresh = make(clock, query: query, output: output, id: id)
        refresh.start(enabled: true, automatic: false)
        defer { refresh.stop() }
        await refresh.refreshIfDue()
        refresh.receive(snapshot(clock, five: 20, weekly: 41), from: id)
        guard case .ok(let updated) = output.usage?.state else { Issue.record("notification lost"); return }
        #expect(updated.map(\.usedPercent) == [20, 41])
        let older = AgentRateLimitsSnapshot(fiveHour: .init(usedPercentage: 1, resetsAt: clock.date.addingTimeInterval(3599)),
                                           sevenDay: nil, asOf: clock.date)
        refresh.receive(older, from: id)
        guard case .ok(let preserved) = output.usage?.state else { Issue.record("current window lost"); return }
        #expect(preserved.map(\.usedPercent) == [20, 41])
    }
}
