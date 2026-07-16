// task-6 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-6.md — 討論設定（UserDefaults 読み出し・クランプ・スケジューラ）。
// テストは共有 UserDefaults に触れない（L-34: 固有 suite 注入）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import DashboardFeature

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "phlox.test.agora.\(UUID().uuidString)")!
}

@Suite("AgoraDiscussionSettings acceptance (task-6)")
struct AcceptanceAgoraSettingsTests {

    @Test func 未設定なら既定値の_config_を返す() {
        let settings = AgoraDiscussionSettings(defaults: freshDefaults())
        let config = settings.config
        #expect(config.maxUtterances == 30)
        #expect(config.maxAgents == 5)
        #expect(config.turnTimeoutSeconds == 180)
        #expect(config.scheduler == .freeSpeech)
        #expect(config.consecutiveSpeakLimit == 2)
        #expect(config.stallPassRounds == 2)
        #expect(config.warningRemaining == 5)
    }

    @Test func 保存値が_config_に反映される() {
        let defaults = freshDefaults()
        defaults.set(12, forKey: AgoraDiscussionSettings.maxUtterancesKey)
        defaults.set(3, forKey: AgoraDiscussionSettings.maxAgentsKey)
        defaults.set(60, forKey: AgoraDiscussionSettings.turnTimeoutSecondsKey)
        defaults.set(AgoraSchedulerKind.roundRobin.rawValue, forKey: AgoraDiscussionSettings.schedulerKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.maxUtterances == 12)
        #expect(config.maxAgents == 3)
        #expect(config.turnTimeoutSeconds == 60)
        #expect(config.scheduler == .roundRobin)
    }

    @Test func 不正値_0以下_は既定値へクランプされる() {
        let defaults = freshDefaults()
        defaults.set(0, forKey: AgoraDiscussionSettings.maxUtterancesKey)
        defaults.set(-1, forKey: AgoraDiscussionSettings.maxAgentsKey)
        defaults.set(-5, forKey: AgoraDiscussionSettings.turnTimeoutSecondsKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.maxUtterances == 30)
        #expect(config.maxAgents == 5)
        #expect(config.turnTimeoutSeconds == 180)
    }

    @Test func 不明なスケジューラ文字列は既定の_freeSpeech_にフォールバックする() {
        let defaults = freshDefaults()
        defaults.set("hand-raise", forKey: AgoraDiscussionSettings.schedulerKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.scheduler == .freeSpeech)
    }

    @Test func 別suiteの設定は互いに影響しない() {
        let a = freshDefaults()
        let b = freshDefaults()
        a.set(7, forKey: AgoraDiscussionSettings.maxUtterancesKey)
        #expect(AgoraDiscussionSettings(defaults: a).config.maxUtterances == 7)
        #expect(AgoraDiscussionSettings(defaults: b).config.maxUtterances == 30)
    }
}
