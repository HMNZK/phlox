// task-5: チームビュー改名 — branding 定数とプロンプト表記の白箱テスト。
import Foundation
import Testing
@testable import DashboardFeature

@Suite struct TeamViewRenameWhiteboxTests {
    @Test func displayTitleはtitleとbetaSuffixを含む() {
        #expect(TeamViewBranding.displayTitle.contains(TeamViewBranding.title))
        #expect(TeamViewBranding.displayTitle.contains(TeamViewBranding.betaSuffix))
    }

    @Test func 役割プロンプトの冒頭はチームビュー討論参加者である() {
        let prompt = AgoraRolePromptTemplate.prompt(
            role: nil,
            agenda: "議題",
            isFacilitator: false,
            config: AgoraDiscussionConfig(maxUtterances: 1, maxAgents: 2)
        )
        #expect(prompt.hasPrefix("あなたはチームビュー討論の参加者です。"))
    }
}
