// task-29（UX-09）の受け入れテスト。
//
// ベースラインでの red 理由: `UsageDisplay.remainingPercentText(usedPercent:)` と
// `UsageDisplay.topBarHelpText(chip:now:)` は本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 使用量（usedPercent）と残量を取り違えないよう、残量の文字列は 1 箇所の関数で作り、要約（トップバー）と
// 詳細（サイドバー）が同じ関数を使う。未取得・取得失敗（`.unavailable`）は「残り0%」と区別され、ヘルプには
// 提供元名と理由だけが出る。ヘルプには提供元名・各バケットの残量・リセット表示（`sidebarResetDisplay` と同じ文字列）を含める。

import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("task-29: usage remaining summary")
struct AcceptanceUsageRemainingSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("残量文字列は 100 − 使用率を四捨五入し「残りN%」で返す")
    func remainingPercentTextRoundsAndLabels() {
        #expect(UsageDisplay.remainingPercentText(usedPercent: 30) == "残り70%")
        #expect(UsageDisplay.remainingPercentText(usedPercent: 0) == "残り100%")
        #expect(UsageDisplay.remainingPercentText(usedPercent: 100) == "残り0%")
        #expect(UsageDisplay.remainingPercentText(usedPercent: 33.4) == "残り67%")
        #expect(UsageDisplay.remainingPercentText(usedPercent: 66.5) == "残り34%") // round(33.5) = 34
        #expect(UsageDisplay.remainingPercentText(usedPercent: 67.5) == "残り33%") // round(32.5) = 33（%.0f の偶数丸めなら 32 になる＝区別）
    }

    @Test("使用率が範囲外でも残量は 0〜100 に収まる")
    func remainingPercentTextClamps() {
        #expect(UsageDisplay.remainingPercentText(usedPercent: 120) == "残り0%")
        #expect(UsageDisplay.remainingPercentText(usedPercent: -5) == "残り100%")
    }

    @Test("取得成功チップのヘルプは提供元名・各バケットの残量・リセットを含む")
    func helpTextForOkChip() {
        let fiveHour = UsageBucket(id: "5h", label: "5時間", usedPercent: 30, resetsAt: now.addingTimeInterval(1800))
        let weekly = UsageBucket(id: "weekly", label: "週次", usedPercent: 80, resetsAt: now.addingTimeInterval(3 * 86_400))
        let chip = UsageDisplay.TopBarChip(kind: .codex, allBuckets: [fiveHour, weekly], shownBuckets: [fiveHour, weekly], unavailableReason: nil, staleNote: nil)
        let help = UsageDisplay.topBarHelpText(chip: chip, now: now)
        let lines = help.components(separatedBy: "\n")
        #expect(lines.first == AgentKind.codex.displayName)
        #expect(lines.contains("5時間 残り70%（リセット \(UsageDisplay.sidebarResetDisplay(for: fiveHour, now: now)!.text)）"))
        #expect(lines.contains("週次 残り20%（リセット \(UsageDisplay.sidebarResetDisplay(for: weekly, now: now)!.text)）"))
        #expect(lines.count == 3)
    }

    @Test("リセット不明のバケットはリセット部分を省き、古い値の注記は末尾に付く")
    func helpTextWithoutResetAndWithStaleNote() {
        let bucket = UsageBucket(id: "monthly", label: "月次", usedPercent: 50)
        let chip = UsageDisplay.TopBarChip(kind: .cursor, allBuckets: [bucket], shownBuckets: [bucket], unavailableReason: nil, staleNote: "12分前の値")
        let lines = UsageDisplay.topBarHelpText(chip: chip, now: now).components(separatedBy: "\n")
        #expect(lines == [AgentKind.cursor.displayName, "月次 残り50%", "12分前の値"])
    }

    @Test("未取得・取得失敗のヘルプは提供元名と理由だけで、残量 0% と区別される")
    func helpTextForUnavailableChip() {
        let chip = UsageDisplay.TopBarChip(kind: .claudeCode, allBuckets: [], shownBuckets: [], unavailableReason: "取得失敗", staleNote: nil)
        let help = UsageDisplay.topBarHelpText(chip: chip, now: now)
        #expect(help == "\(AgentKind.claudeCode.displayName): 取得失敗")
        #expect(!help.contains("%"))
        #expect(!help.contains("残り"))
    }

    @Test("残り 0% の取得成功は表示対象のまま（未取得と混同しない）")
    func exhaustedButAvailableIsStillVisible() {
        let exhausted = CLIUsage(kind: .codex, state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 100)]), updatedAt: now)
        let failed = CLIUsage(kind: .cursor, state: .unavailable(reason: "取得失敗"), updatedAt: now)
        #expect(UsageDisplay.visibleKinds(usages: [.codex: exhausted, .cursor: failed], showUnavailable: false) == [.codex])
        let chips = UsageDisplay.topBarChips(usages: [.codex: exhausted, .cursor: failed], showUnavailable: true, now: now)
        #expect(chips.map(\.kind) == [.codex, .cursor])
        #expect(UsageDisplay.topBarHelpText(chip: chips[0], now: now).contains("残り0%"))
        #expect(!UsageDisplay.topBarHelpText(chip: chips[1], now: now).contains("%"))
    }
}
