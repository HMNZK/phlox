import XCTest
import PhloxCore
@testable import PhloxNetworking

/// task-7 白箱テスト（実装役が追加可）。受け入れテストの補完。
final class APIExtensionsClientTests: XCTestCase {
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

    func testSubAgentMessagesPercentEncodesSlashInRequestPath() async throws {
        NetStubURLProtocol.outcomes = [
            .status(200, Data(#"{"sessionId":"s1","subAgentId":"a/b","messages":[]}"#.utf8), [:]),
        ]
        _ = try await makeClient().subAgentMessages(sessionID: "s1", subAgentID: "a/b")
        let url = try XCTUnwrap(NetStubURLProtocol.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedPath, "/sessions/s1/subagents/a%2Fb/messages")
        XCTAssertFalse(url.absoluteString.contains("%252F"), "二重エンコードされていないこと")
    }

    func testSubAgentMessagesPercentEncodesSpaceAndHashInRequestPath() async throws {
        NetStubURLProtocol.outcomes = [
            .status(200, Data(#"{"sessionId":"s1","subAgentId":"a b#c","messages":[]}"#.utf8), [:]),
        ]
        _ = try await makeClient().subAgentMessages(sessionID: "s1", subAgentID: "a b#c")
        let url = try XCTUnwrap(NetStubURLProtocol.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedPath, "/sessions/s1/subagents/a%20b%23c/messages")
        XCTAssertFalse(url.absoluteString.contains("%2520"), "二重エンコードされていないこと")
    }

    func testRespondPercentEncodesSpaceInApprovalID() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        try await makeClient().respond(approvalID: "ap 1", decision: .accept)
        XCTAssertEqual(percentEncodedPath(of: NetStubURLProtocol.lastRequest), "/approvals/ap%201")
    }

    func testOutputPercentEncodesSpaceInSessionID() async throws {
        NetStubURLProtocol.outcomes = [
            .status(200, Data(#"{"text":"out"}"#.utf8), [:]),
        ]
        _ = try await makeClient().output(sessionID: "ses 1")
        XCTAssertEqual(percentEncodedPath(of: NetStubURLProtocol.lastRequest), "/sessions/ses%201/output")
    }
}
