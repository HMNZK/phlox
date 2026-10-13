import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: 使用量バーの残量と読み上げ")
struct AcceptanceUsageRemainingSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let japanese = Locale(identifier: "ja")

    @Test("残り20%未満の値は注意の読み上げを含む")
    func lowRemainingIsIncludedInAccessibility() {
        let bucket = UsageBucket(id: "5h", label: "5時間", usedPercent: 81)
        let group = UsageDisplay.BottomBarGroup(kind: .codex, buckets: [bucket])
        let label = UsageDisplay.bottomBarAccessibilityLabel(groups: [group], now: now, locale: japanese)
        #expect(label.contains("残り 19%"))
        #expect(label.contains("残りわずか"))
    }

    @Test("未取得は固定文言で読み上げ、残量0%と区別する")
    func unavailableIsNotAnnouncedAsZero() {
        let group = UsageDisplay.BottomBarGroup(kind: .cursor, buckets: nil)
        let label = UsageDisplay.bottomBarAccessibilityLabel(groups: [group], now: now, locale: japanese)
        #expect(label.contains("取得できません"))
        #expect(!label.contains("%"))
    }
}
