import Foundation
import Testing
@testable import DashboardFeature

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "phlox.test.agora.\(UUID().uuidString)")!
}

@Suite("AgoraDiscussionSettings whitebox (task-6)")
struct AgoraSettingsWhiteboxTests {

    @Test func 境界値_1_はそのまま採用される() {
        let defaults = freshDefaults()
        defaults.set(1, forKey: AgoraDiscussionSettings.maxUtterancesKey)
        defaults.set(1, forKey: AgoraDiscussionSettings.maxAgentsKey)
        defaults.set(1, forKey: AgoraDiscussionSettings.turnTimeoutSecondsKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.maxUtterances == 1)
        #expect(config.maxAgents == 1)
        #expect(config.turnTimeoutSeconds == 1)
    }

    @Test func 内部既定値は常に固定される() {
        let defaults = freshDefaults()
        defaults.set(12, forKey: AgoraDiscussionSettings.maxUtterancesKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.consecutiveSpeakLimit == 2)
        #expect(config.stallPassRounds == 2)
        #expect(config.warningRemaining == 5)
    }

    @Test func freeSpeech_文字列はそのまま解釈される() {
        let defaults = freshDefaults()
        defaults.set(AgoraSchedulerKind.freeSpeech.rawValue, forKey: AgoraDiscussionSettings.schedulerKey)
        let config = AgoraDiscussionSettings(defaults: defaults).config
        #expect(config.scheduler == .freeSpeech)
    }
}
