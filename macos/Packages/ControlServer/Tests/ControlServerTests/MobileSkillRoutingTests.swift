import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor MobileSkillRoutingRecorder {
    var action: ControlRequest.Action?
    func handle(_ request: ControlRequest) -> ControlResponse {
        action = request.action
        return .status(200)
    }
}

@Suite struct MobileSkillRoutingTests {
    private func request(_ path: String, body: String? = nil) async throws -> (Int, ControlRequest.Action?) {
        let store = SessionTokenStore()
        await store.register("mobile-skills", for: SessionID())
        let recorder = MobileSkillRoutingRecorder()
        let server = ControlServer(tokenStore: store) { await recorder.handle($0) }
        let port = try await server.start()
        defer { withExtendedLifetime(server) {} }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer mobile-skills", forHTTPHeaderField: "Authorization")
        request.httpBody = body.map { Data($0.utf8) }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (try #require(response as? HTTPURLResponse).statusCode, await recorder.action)
    }

    @Test func sessionAndProjectRoutesPreserveIdentity() async throws {
        let id = SessionID()
        let (status, action) = try await request("/sessions/\(id)/skills")
        #expect(status == 200)
        guard case .sessionSkills(let received) = action else { Issue.record("missing session skills"); return }
        #expect(received == id)
        let project = ProjectID()
        let (projectStatus, projectAction) = try await request("/agents/codex/skills?projectID=\(project)&workspace=demo")
        #expect(projectStatus == 200)
        guard case .agentSkills(let kind, let projectID, let workspace) = projectAction else { Issue.record("missing agent skills"); return }
        #expect(kind == .codex && projectID == project && workspace == "demo")
    }

    @Test func invalidProjectAndUnknownQueryAreRejected() async throws {
        #expect(try await request("/agents/codex/skills?projectID=invalid").0 == 400)
        #expect(try await request("/agents/codex/skills?workingDirectory=/private").0 == 404)
    }

    @Test func sendCarriesSkillAndRejectsMalformedIdentity() async throws {
        let body = #"{"to":"test","text":"$review check","skill":{"name":"review","path":"/skills/review/SKILL.md","runtimeFingerprint":"digest"}}"#
        let (status, action) = try await request("/send", body: body)
        #expect(status == 200)
        guard case .sendTextWithSkill(_, let text, let submit, _, let images, let skill) = action else { Issue.record("missing skill send"); return }
        #expect(text == "$review check" && submit && images.isEmpty)
        #expect(skill == AgentSkillSelection(name: "review", path: "/skills/review/SKILL.md", runtimeFingerprint: "digest"))
        let malformed = #"{"to":"test","text":"check","skill":{"name":"","path":"/skills/review"}}"#
        #expect(try await request("/send", body: malformed).0 == 400)
    }
}
