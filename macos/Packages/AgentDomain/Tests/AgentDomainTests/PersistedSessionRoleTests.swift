import Foundation
import Testing
@testable import AgentDomain

@Suite struct PersistedSessionRoleTests {
    @Test func oldJSONWithoutRoleKey_decodesNil() throws {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let json = """
        {
          "id": { "rawValue": "\(id.uuidString)" },
          "kind": "claudeCode",
          "workingDirectory": "/tmp/work",
          "name": "Legacy",
          "projectID": null,
          "startedAt": 0,
          "command": "/usr/local/bin/claude",
          "args": [],
          "env": {}
        }
        """

        let descriptor = try JSONDecoder().decode(
            PersistedSessionDescriptor.self,
            from: Data(json.utf8)
        )

        #expect(descriptor.role == nil)
    }

    @Test func roleRoundTrip_preservesValue() throws {
        let original = PersistedSessionDescriptor(
            id: SessionID(),
            kind: .claudeCode,
            workingDirectory: "/tmp",
            name: "A",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1),
            command: "claude",
            args: [],
            env: [:],
            role: "推進者"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)
        #expect(decoded.role == "推進者")
    }
}
