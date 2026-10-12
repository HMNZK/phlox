import AgentDomain
import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import DashboardFeature

@Test func visibleKinds_excludesUnavailableAndMissing() {
    let usages: [AgentKind: CLIUsage] = [
        .codex: CLIUsage(
            kind: .codex,
            state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 50)]),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        .cursor: CLIUsage(
            kind: .cursor,
            state: .unavailable(reason: "未取得"),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
    ]

    let result = UsageDisplay.visibleKinds(usages: usages, showUnavailable: false)

    #expect(result == [.codex])
}

@Test func visibleKinds_showUnavailableReturnsAllCasesInOrder() {
    let usages: [AgentKind: CLIUsage] = [
        .codex: CLIUsage(
            kind: .codex,
            state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 50)]),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        .cursor: CLIUsage(
            kind: .cursor,
            state: .unavailable(reason: "未取得"),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
    ]

    let result = UsageDisplay.visibleKinds(usages: usages, showUnavailable: true)

    #expect(result == AgentKind.allCases)
}

@Test func visibleKinds_orderMatchesAllCasesRegardlessOfDictionaryOrder() {
    let usages: [AgentKind: CLIUsage] = [
        .cursor: CLIUsage(
            kind: .cursor,
            state: .ok([UsageBucket(id: "total", label: "Total", usedPercent: 10)]),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        .codex: CLIUsage(
            kind: .codex,
            state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 20)]),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        .claudeCode: CLIUsage(
            kind: .claudeCode,
            state: .ok([UsageBucket(id: "week", label: "週次", usedPercent: 30)]),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
    ]

    let result = UsageDisplay.visibleKinds(usages: usages, showUnavailable: false)

    #expect(result == [.claudeCode, .codex, .cursor])
}

@Test func bottomBarGroups_keepsEveryBucketInProviderOrder() throws {
    let now = Date(timeIntervalSince1970: 100)
    let usages: [AgentKind: CLIUsage] = [
        .cursor: CLIUsage(kind: .cursor, state: .ok([
            UsageBucket(id: "auto", label: "Auto", usedPercent: 10),
            UsageBucket(id: "api", label: "API", usedPercent: 20),
        ]), updatedAt: now),
        .codex: CLIUsage(kind: .codex, state: .ok([
            UsageBucket(id: "weekly", label: "週次", usedPercent: 30),
            UsageBucket(id: "5h", label: "5時間", usedPercent: 40),
        ]), updatedAt: now),
    ]

    let groups = UsageDisplay.bottomBarGroups(usages: usages)

    #expect(groups.map(\.kind) == AgentKind.allCases)
    #expect(groups.first?.buckets == nil)
    #expect(try #require(groups.first(where: { $0.kind == .codex })?.buckets).map(\.id) == ["weekly", "5h"])
    #expect(try #require(groups.first(where: { $0.kind == .cursor })?.buckets).map(\.id) == ["auto", "api"])
}

@Test func bottomBarBucketText_usesAllDetailsThenDropsResetAndLabel() {
    let now = Date(timeIntervalSince1970: 100)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 28, resetsAt: now.addingTimeInterval(7200))

    #expect(UsageDisplay.bottomBarBucketText(bucket, showsLabel: true, showsReset: true, now: now, locale: Locale(identifier: "ja")) == "5時間 72%（2時間後）")
    #expect(UsageDisplay.bottomBarBucketText(bucket, showsLabel: true, showsReset: false, now: now, locale: Locale(identifier: "ja")) == "5時間 72%")
    #expect(UsageDisplay.bottomBarBucketText(bucket, showsLabel: false, showsReset: false, now: now, locale: Locale(identifier: "ja")) == "72%")
}

// MARK: - リセット残り時間

@Test func remainingTimeText_formatsHoursAndMinutes() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(3 * 3600 + 50 * 60)

    #expect(UsageDisplay.remainingTimeText(until: resetsAt, now: now) == "3h50m")
}

@Test func remainingTimeText_formatsMinutesOnlyUnderOneHour() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(45 * 60)

    #expect(UsageDisplay.remainingTimeText(until: resetsAt, now: now) == "45m")
}

@Test func remainingTimeText_formatsDaysAndHoursOverOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(5 * 86_400 + 3 * 3600)

    #expect(UsageDisplay.remainingTimeText(until: resetsAt, now: now) == "5d3h")
}

@Test func remainingTimeText_clampsPastResetToZeroMinutes() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(-100)

    #expect(UsageDisplay.remainingTimeText(until: resetsAt, now: now) == "0m")
}

@Test func absoluteResetText_formatsAsMonthDayHourMinute() {
    let date = Date(timeIntervalSince1970: 1_000_000)

    let text = UsageDisplay.absoluteResetText(date)

    #expect(text.range(of: #"^\d{2}/\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil)
}

@Test func isResetUrgent_fiveHourTrueAtExactlyOneHour() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 90, resetsAt: now.addingTimeInterval(3600))

    #expect(UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func isResetUrgent_fiveHourFalseJustOverOneHour() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 90, resetsAt: now.addingTimeInterval(3601))

    #expect(!UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func isResetUrgent_weeklyTrueAtExactlyOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "weekly", label: "週次", usedPercent: 90, resetsAt: now.addingTimeInterval(86_400))

    #expect(UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func isResetUrgent_weeklyFalseJustOverOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "weekly", label: "週次", usedPercent: 90, resetsAt: now.addingTimeInterval(86_401))

    #expect(!UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func isResetUrgent_falseWhenNoResetDate() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 90)

    #expect(!UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func isResetUrgent_falseForUnknownBucketId() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "total", label: "Total", usedPercent: 99, resetsAt: now.addingTimeInterval(60))

    #expect(!UsageDisplay.isResetUrgent(for: bucket, now: now))
}

@Test func sidebarResetDisplay_fiveHourShowsRemainingTimeAndUrgentWhenLow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 95, resetsAt: now.addingTimeInterval(30 * 60))

    let display = UsageDisplay.sidebarResetDisplay(for: bucket, now: now)

    #expect(display == UsageDisplay.ResetDisplay(text: "30m", isUrgent: true))
}

@Test func sidebarResetDisplay_fiveHourRemainingTimeNotUrgentWhenAmple() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 20, resetsAt: now.addingTimeInterval(4 * 3600))

    let display = UsageDisplay.sidebarResetDisplay(for: bucket, now: now)

    #expect(display == UsageDisplay.ResetDisplay(text: "4h0m", isUrgent: false))
}

@Test func sidebarResetDisplay_weeklyShowsRemainingTimeAndUrgentWithinOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "weekly", label: "週次", usedPercent: 80, resetsAt: now.addingTimeInterval(20 * 3600 + 30 * 60))

    let display = UsageDisplay.sidebarResetDisplay(for: bucket, now: now)

    #expect(display == UsageDisplay.ResetDisplay(text: "20h30m", isUrgent: true))
}

@Test func sidebarResetDisplay_weeklyShowsAbsoluteTimeNotUrgentBeyondOneDay() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "weekly", label: "週次", usedPercent: 40, resetsAt: now.addingTimeInterval(3 * 86_400))

    let display = try #require(UsageDisplay.sidebarResetDisplay(for: bucket, now: now))

    #expect(!display.isUrgent)
    #expect(display.text.range(of: #"^\d{2}/\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil)
}

@Test func sidebarResetDisplay_nilWhenNoResetDate() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 50)

    #expect(UsageDisplay.sidebarResetDisplay(for: bucket, now: now) == nil)
}

// MARK: - 残量色・ブランドアイコン

@Test(arguments: [AgentKind.claudeCode, .codex, .cursor]) @MainActor
func agentBrandIconFromKind_usesRegistryDescriptor(kind: AgentKind) {
    let icon = AgentBrandIcon(kind: kind, size: 12)
    #expect(icon.descriptor.ref.builtinKind == kind)
    #expect(icon.descriptor.displayName == kind.displayName)
}
