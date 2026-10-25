import XCTest
import PhloxCore
@testable import PhloxNetworking

/// task-7 白箱テスト（実装役が追加可）。受け入れテストの補完。
final class APIExtensionsClientTests: XCTestCase {
    func testSkillEndpointsAndLegacy404() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(#"{"skills":[{"name":"poteto-mode","description":"説明","path":"/skills/poteto/SKILL.md","runtimeFingerprint":"f1"}]}"#.utf8), [:])]
        let skills = try await makeClient().agentSkills(kind: .codex, projectID: "a&b", workspace: "日本語 repo")
        XCTAssertEqual(skills?.first?.name, "poteto-mode")
        let url = try XCTUnwrap(NetStubURLProtocol.lastRequest?.url)
        XCTAssertEqual(url.path, "/agents/codex/skills")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "projectID" })?.value, "a&b")
        XCTAssertEqual(query?.first(where: { $0.name == "workspace" })?.value, "日本語 repo")
        NetStubURLProtocol.outcomes = [.status(404, Data(), [:])]
        let unsupported = try await makeClient().sessionSkills(sessionID: "s/1")
        XCTAssertNil(unsupported)
        XCTAssertEqual(percentEncodedPath(of: NetStubURLProtocol.lastRequest), "/sessions/s%2F1/skills")
    }

    func testSkillSendWireAndOmission() throws {
        let skill = AgentSkillSelection(name: "poteto-mode", path: "/skills/poteto/SKILL.md", runtimeFingerprint: "f1")
        let data = try JSONEncoder().encode(SendRequestDTO(to: "s1", text: "$poteto-mode", skill: skill))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = try XCTUnwrap(json["skill"] as? [String: String])
        XCTAssertEqual(value["runtimeFingerprint"], "f1")
        XCTAssertEqual(value["path"], skill.path)
        let plain = try JSONEncoder().encode(SendRequestDTO(to: "s1", text: "hello"))
        let plainJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        XCTAssertNil(plainJSON["skill"])
    }
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    override func setUp() {
        super.setUp()
        NetStubURLProtocol.reset()
    }

    override func tearDown() {
        NetStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetStubURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }

    private func percentEncodedPath(of request: URLRequest?) -> String? {
        guard let url = request?.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
    }

    func testPercentEncodedPathSegmentEscapesSlash() {
        XCTAssertEqual(
            PhloxAPIClient.percentEncodedPathSegment("sa/with/slash"),
            "sa%2Fwith%2Fslash"
        )
    }

    func testPercentEncodedPathSegmentEscapesSpace() {
        XCTAssertEqual(
            PhloxAPIClient.percentEncodedPathSegment("sa with space"),
            "sa%20with%20space"
        )
    }

    func testPercentEncodedPathSegmentLeavesSimpleID() {
        XCTAssertEqual(PhloxAPIClient.percentEncodedPathSegment("sa-1"), "sa-1")
    }

    func testRespondPercentEncodesSpaceInApprovalID() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        try await makeClient().respond(approvalID: "ap 1", decision: .accept)
        XCTAssertEqual(percentEncodedPath(of: NetStubURLProtocol.lastRequest), "/approvals/ap%201")
    }

}
