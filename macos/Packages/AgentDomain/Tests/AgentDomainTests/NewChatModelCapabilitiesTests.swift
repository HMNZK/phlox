import Foundation
import Testing
@testable import AgentDomain

@Test func newChatModelCapabilitiesRoundTripAndDecodeLegacyOptions() throws {
    let model = ControlModelOption(id: "m", displayName: "M", reasoningEfforts: ["low", "high"],
                                  defaultReasoningEffort: "high", acceptsImages: true)
    #expect(try JSONDecoder().decode(ControlModelOption.self, from: JSONEncoder().encode(model)) == model)
    let legacy = try JSONDecoder().decode(ControlModelOption.self, from: Data(#"{"id":"m","displayName":"M"}"#.utf8))
    #expect(legacy.reasoningEfforts == nil)
    #expect(legacy.defaultReasoningEffort == nil)
    #expect(legacy.acceptsImages == nil)
}
