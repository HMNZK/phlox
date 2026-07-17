// 契約の正本: tasks/task-5.md — 「アゴラ」→「チームビュー」改名＋ベータ表記。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止（ハーネス欠陥は PM 承認の上でのみ修理可）。
//
// 凍結 API（表記の一元管理）:
//   enum TeamViewBranding { static let title / betaSuffix / displayTitle }

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: チームビュー改名とベータ表記（task-5）")
struct AcceptanceTeamViewRenameTests {
    @Test func brandingの正本はチームビューとベータ表記を持つ() {
        #expect(TeamViewBranding.title == "チームビュー")
        #expect(TeamViewBranding.betaSuffix == "Beta")
        #expect(TeamViewBranding.displayTitle == "チームビュー (Beta)")
    }

    @Test func 役割プロンプトはチームビュー表記でアゴラを含まない() {
        let config = AgoraDiscussionConfig(maxUtterances: 24, maxAgents: 4)
        for isFacilitator in [true, false] {
            let prompt = AgoraRolePromptTemplate.prompt(
                role: "批判者",
                agenda: "議題X",
                isFacilitator: isFacilitator,
                config: config
            )
            #expect(!prompt.contains("アゴラ"))
            #expect(prompt.contains("チームビュー討論"))
            // 既存契約（AcceptanceAgoraRoleTests）の骨子は不変
            #expect(prompt.contains("議題X"))
            #expect(prompt.contains("PASS"))
        }
    }
}
