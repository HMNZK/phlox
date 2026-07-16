import AgentDomain
import Foundation
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

@Test func topBarBuckets_returnsFiveHourThenWeeklyRegardlessOfInputOrder() {
    let buckets = [
        UsageBucket(id: "weekly", label: "週次", usedPercent: 72),
        UsageBucket(id: "5h", label: "5時間", usedPercent: 30),
    ]

    let result = UsageDisplay.topBarBuckets(buckets)

    #expect(result.map(\.id) == ["5h", "weekly"])
}

@Test func topBarBuckets_weeklyOnlyReturnsWeekly() {
    let buckets = [
        UsageBucket(id: "weekly", label: "週次", usedPercent: 41),
    ]

    let result = UsageDisplay.topBarBuckets(buckets)

    #expect(result.map(\.id) == ["weekly"])
}

@Test func topBarBuckets_withoutFiveHourAndWeeklyReturnsAll() {
    let buckets = [
        UsageBucket(id: "auto", label: "Auto+Composer", usedPercent: 21),
        UsageBucket(id: "api", label: "API", usedPercent: 6),
    ]

    let result = UsageDisplay.topBarBuckets(buckets)

    #expect(result.map(\.id) == ["auto", "api"])
}

@Test func topBarBuckets_emptyReturnsEmpty() {
    let result = UsageDisplay.topBarBuckets([])

    #expect(result.isEmpty)
}

@Test func topBarShortLabel_mapsFiveHourAndWeeklyAndKeepsOthers() {
    let fiveHour = UsageBucket(id: "5h", label: "5時間", usedPercent: 30)
    let weekly = UsageBucket(id: "weekly", label: "週次", usedPercent: 72)
    let total = UsageBucket(id: "total", label: "Total", usedPercent: 19)

    #expect(UsageDisplay.topBarShortLabel(for: fiveHour) == "5h")
    #expect(UsageDisplay.topBarShortLabel(for: weekly) == "7d")
    #expect(UsageDisplay.topBarShortLabel(for: total) == "Total")
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
