import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite struct MobileSkillRuntimeTests {
    @Test func runtimeMessagePreservesSkillAndDecodesOlderRequests() throws {
        let skill = AgentSkillSelection(name: "review", path: "/skills/review/SKILL.md", runtimeFingerprint: "hash")
        let request = DashboardRuntimeMessageRequest(recipient: .id(SessionID()), text: "$review inspect",
            submit: true, from: nil, inReplyTo: nil, images: [], skill: skill)
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(DashboardRuntimeMessageRequest.self, from: data).skill == skill)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "skill")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(DashboardRuntimeMessageRequest.self, from: oldData).skill == nil)
    }
}
