import AgentDomain
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
    }
}
