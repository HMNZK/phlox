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

    func testRespondPercentEncodesSpaceInApprovalID() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        try await makeClient().respond(approvalID: "ap 1", decision: .accept)
        XCTAssertEqual(percentEncodedPath(of: NetStubURLProtocol.lastRequest), "/approvals/ap%201")
    }

}
