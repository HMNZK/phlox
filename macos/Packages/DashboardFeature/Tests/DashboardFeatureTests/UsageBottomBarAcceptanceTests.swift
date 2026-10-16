import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: 下部の使用量バー")
struct UsageBottomBarAcceptanceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let japanese = Locale(identifier: "ja")

    @Test("全ハーネスの全枠を定義順で保持する")
    func keepsAllHarnessBucketsInOrder() throws {
        let usages: [AgentKind: CLIUsage] = [
            .cursor: CLIUsage(kind: .cursor, state: .ok([
                UsageBucket(id: "auto", label: "Auto", usedPercent: 20),
                UsageBucket(id: "api", label: "API", usedPercent: 5),
            ]), updatedAt: now),
            .codex: CLIUsage(kind: .codex, state: .ok([
                UsageBucket(id: "5h", label: "5時間", usedPercent: 28),
                UsageBucket(id: "weekly", label: "週次", usedPercent: 60),
                UsageBucket(id: "extra", label: "追加", usedPercent: 8),
            ]), updatedAt: now),
        ]

        let groups = UsageDisplay.bottomBarGroups(usages: usages)
        #expect(groups.map(\.kind) == AgentKind.allCases)
        #expect(groups.first?.buckets == nil)
        #expect(try #require(groups.first(where: { $0.kind == .codex })?.buckets).map(\.id) == ["5h", "weekly", "extra"])
        #expect(try #require(groups.first(where: { $0.kind == .cursor })?.buckets).map(\.id) == ["auto", "api"])
    }

    @Test("「未取得の CLI も表示」がオフなら、取得できないハーネスを出さない（FR-36）")
    func hidesUnavailableHarnessWhenSettingIsOff() {
        let usages: [AgentKind: CLIUsage] = [
            .codex: CLIUsage(kind: .codex, state: .ok([
                UsageBucket(id: "5h", label: "5時間", usedPercent: 28),
            ]), updatedAt: now),
            .cursor: CLIUsage(kind: .cursor, state: .unavailable(reason: "Cursorアプリ未検出"), updatedAt: now),
        ]

        #expect(UsageDisplay.bottomBarGroups(usages: usages, showUnavailable: false).map(\.kind) == [.codex])
        #expect(UsageDisplay.bottomBarGroups(usages: usages, showUnavailable: true).map(\.kind) == AgentKind.allCases)
    }

    @Test("未取得のハーネスも表示し、理由の代わりに定型文を使う")
    func unavailableHarnessUsesFixedText() throws {
        let usages: [AgentKind: CLIUsage] = [
            .codex: CLIUsage(kind: .codex, state: .ok([
                UsageBucket(id: "5h", label: "5時間", usedPercent: 28),
            ]), updatedAt: now),
            .cursor: CLIUsage(kind: .cursor, state: .unavailable(reason: "Cursorアプリ未検出"), updatedAt: now),
        ]

        let groups = UsageDisplay.bottomBarGroups(usages: usages)
        #expect(groups.map(\.kind) == AgentKind.allCases)
        let unavailable = try #require(groups.first { $0.kind == .cursor })
        #expect(unavailable.buckets == nil)
        #expect(UsageDisplay.bottomBarUnavailableText(locale: japanese) == "取得できません")
    }

    @Test("幅に応じて枠名とリセット時刻だけを省き、残量の数値は残す")
    func omitsDetailsWithoutOmittingNumbers() {
        let bucket = UsageBucket(
            id: "5h", label: "5時間", usedPercent: 28,
            resetsAt: now.addingTimeInterval(7_200)
        )
        #expect(UsageDisplay.bottomBarBucketText(
            bucket, showsLabel: true, showsReset: true, now: now, locale: japanese
        ) == "5時間 72%（02:00）")
        #expect(UsageDisplay.bottomBarBucketText(
            bucket, showsLabel: true, showsReset: false, now: now, locale: japanese
        ) == "5時間 72%")
        #expect(UsageDisplay.bottomBarBucketText(
            bucket, showsLabel: false, showsReset: false, now: now, locale: japanese
        ) == "72%")
    }

    @Test("モックの使用量バーと同じ幅で表示段階を切り替える")
    func usesReferenceStages() {
        #expect(UsageDisplay.bottomBarStage(forWidth: 1_100) == .full)
        #expect(UsageDisplay.bottomBarStage(forWidth: 1_099) == .compact)
        #expect(UsageDisplay.bottomBarStage(forWidth: 600) == .compact)
        #expect(UsageDisplay.bottomBarStage(forWidth: 599) == .percentageOnly)
    }

    @Test("5時間枠は残り時間を HH:MM、週次はリセット日時を MM/DD HH:MM で示す")
    func formatsResetForBottomBar() throws {
        let fiveHour = UsageBucket(id: "5h", label: "5時間", usedPercent: 28,
                                   resetsAt: now.addingTimeInterval(4 * 3_600 + 5 * 60 + 59))
        #expect(UsageDisplay.bottomBarResetText(for: fiveHour, now: now) == "04:05")
        let reset = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 5)))
        let weekly = UsageBucket(id: "weekly", label: "週次", usedPercent: 60, resetsAt: reset)
        #expect(UsageDisplay.bottomBarResetText(for: weekly, now: reset.addingTimeInterval(-3 * 86_400)) == "10/20 09:05")
        #expect(UsageDisplay.bottomBarResetSuffix(for: weekly, now: now, locale: Locale(identifier: "en")) == " (10/20 09:05)")
    }

    @Test("残り20%未満は読み上げに残りわずかを含める")
    func lowRemainingIsAnnounced() throws {
        #expect(UsageDisplay.isLowRemaining(usedPercent: 80.1))
        #expect(!UsageDisplay.isLowRemaining(usedPercent: 80))
        let groups = UsageDisplay.bottomBarGroups(usages: [
            .claudeCode: CLIUsage(kind: .claudeCode, state: .ok([
                UsageBucket(id: "5h", label: "5時間", usedPercent: 88),
            ]), updatedAt: now),
        ])
        let label = UsageDisplay.bottomBarAccessibilityLabel(groups: groups, now: now, locale: japanese)
        #expect(label.contains("Claude"))
        #expect(label.contains("残り 12%"))
        #expect(label.contains("残りわずか"))
    }
}
