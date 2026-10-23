import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeUpdateCompatibilityTests {
    @Test(arguments: [("1", "1", true), ("1", "2", true), ("2", "3", false),
                      ("0", "1", false), ("2", "1", false), ("bad", "1", false)])
    func verifiesIncomingGUICompatibility(minimum: String, maximum: String, expected: Bool) {
        #expect(SessionRuntimeUpdateCompatibility.allows(minimum: minimum, maximum: maximum, runtimeProtocol: 1) == expected)
    }

    @Test func missingMetadataDoesNotApproveAnUnknownGUI() {
        #expect(!SessionRuntimeUpdateCompatibility.allows(minimum: nil, maximum: "1", runtimeProtocol: 1))
        #expect(!SessionRuntimeUpdateCompatibility.allows(minimum: "1", maximum: nil, runtimeProtocol: 1))
    }
}
