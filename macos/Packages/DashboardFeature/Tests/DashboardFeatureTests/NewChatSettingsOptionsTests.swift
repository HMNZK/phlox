import AgentDomain
import Foundation
import SessionFeature
import Testing
@testable import DashboardFeature

@Suite struct NewChatSettingsOptionsTests {
    @Test(arguments: ["haiku", "haiku[1m]"])
    func haikuHasNoNewChatEfforts(model: String) {
        #expect(newChatEffortOptions(for: .claudeCode, modelID: model, languageCode: "ja").isEmpty)
    }

    @Test func claudeMissingOrStaleModelKeepsTheNewChatEfforts() {
        for model: String? in [nil, "unavailable"] {
            let options = newChatEffortOptions(for: .claudeCode, modelID: model, languageCode: "ja")
            #expect(options.map(\.value) == ["low", "medium", "high", "xhigh", "max"])
            #expect(options.map(\.displayName) == ["低", "中", "高", "非常に高", "最大"])
        }
    }

    @Test func cursorKeepsTheNewChatDefaultLabel() {
        let options = newChatSettingsOptions(for: .cursor, languageCode: "ja")
        #expect(options.availablePermissions.first?.value == nil)
        #expect(options.availablePermissions.first?.displayName == "既定")
        #expect(options.planModeAvailable)
        #expect(options.defaultPermission == nil)
    }

    @MainActor
    @Test func reportedDefaultsMatchMacNewChatAndFollowBothBypassStates() throws {
        for fullAccess in [false, true] {
            let suite = "phlox-new-chat-settings-defaults-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LastUsedChatSettingsStore(defaults: defaults)
            let draft = NewChatDraft(lastUsedChatSettingsStore: store, isFullAccessEnabled: { _ in fullAccess })
            let model = try #require(draft.settings.selectedModel)
            let options = newChatSettingsOptions(
                for: .claudeCode,
                languageCode: "ja",
                fullAccessEnabled: fullAccess
            )

            #expect(options.defaultEfforts?[model] == draft.settings.selectedEffort)
            #expect(options.defaultPermission == draft.settings.selectedPermissionProfile)
            #expect(options.defaultPermission == (fullAccess ? "bypassPermissions" : "auto"))
        }
    }
}
