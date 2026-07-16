import XCTest
import PhloxCore
@testable import PhloxNetworking

// E5-3 ヘッドレス E2E（モック）。spawn → send → approve → remove を URLProtocol スタブで一気通貫検証する。
// 実機 E2E は未実施（理由は doc/E2ETestReport.md に明記）。実サーバには接続しない。
final class E2EFlowTests: XCTestCase {

    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    override func setUp() { super.setUp(); E2EStubURLProtocol.reset() }
    override func tearDown() { E2EStubURLProtocol.reset(); super.tearDown() }

    private func makeClient() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [E2EStubURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "e2e-token"),
            session: URLSession(configuration: configuration),
            retryBaseDelayNanos: 1
        )
    }

    func testSpawnSendApproveRemoveFlow() async throws {
        // ルーティング: パスとメソッドでレスポンスを出し分ける。
        E2EStubURLProtocol.router = { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            switch (method, path) {
            case ("POST", "/sessions"):
                return (200, Data(#"{"id":"sess-1","name":"Rose","kind":"claudeCode","status":"running","workspace":"proj"}"#.utf8))
            case ("POST", "/send"):
                return (200, Data())
            case ("GET", "/approvals"):
                return (200, Data(#"{"approvals":[{"id":"appr-1","sessionID":"sess-1","kind":"claudeCode","prompt":"続行しますか？"}]}"#.utf8))
            case ("POST", "/approvals/appr-1"):
                return (200, Data())
            case ("DELETE", "/sessions/sess-1"):
                return (200, Data())
            default:
                return (404, Data())
            }
        }

        let client = makeClient()

        // 1. spawn（Mac は {id} のみ返す。新規セッションは .starting で合成される）
        let session = try await client.spawn(SpawnRequest(agent: .claudeCode, workspace: "proj"))
        XCTAssertEqual(session.id, "sess-1")
        XCTAssertEqual(session.status, .starting)

        // 2. send
        let sendResult = try await client.send(SendRequest(sessionID: "sess-1", text: "テストを実行して"))
        XCTAssertTrue(sendResult.accepted)

        // 3. approve（GET /approvals → POST /approvals/{id}）
        let approvals = try await client.approvals()
        XCTAssertEqual(approvals.first?.id, "appr-1")
        try await client.respond(approvalID: "appr-1", decision: .accept)

        // 4. remove
        try await client.remove(sessionID: "sess-1")

        XCTAssertGreaterThanOrEqual(E2EStubURLProtocol.requestCount, 5, "全 5 リクエストが発行される")
    }

    // UC-03: 一覧で承認待ちが needsAttention として復元される
    func testListSessionsWithAttention() async throws {
        E2EStubURLProtocol.router = { request in
            guard request.httpMethod == "GET", request.url?.path == "/sessions" else {
                return (404, Data())
            }
            let json = """
            {"sessions":[
              {"id":"s1","name":"Rose","kind":"claudeCode","status":"awaitingApproval","workspace":"proj"},
              {"id":"s2","name":"Idle","kind":"codex","status":"idle","workspace":""}
            ]}
            """
            return (200, Data(json.utf8))
        }

        let sessions = try await makeClient().listSessions()
        XCTAssertEqual(sessions.count, 2)
        let attention = sessions.first { $0.id == "s1" }
        XCTAssertTrue(attention?.needsAttention == true)
        XCTAssertEqual(attention?.status, .awaitingApproval(prompt: ""))
    }

    // UC-05: 質問への回答（send）
    func testAnswerQuestionSendFlow() async throws {
        // 正規契約: POST /send（200 空 body）→ accepted=true
        E2EStubURLProtocol.router = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path == "/send" {
                let auth = request.value(forHTTPHeaderField: "Authorization")
                XCTAssertEqual(auth, "Bearer e2e-token")
                return (200, Data())
            }
            return (404, Data())
        }

        let result = try await makeClient().send(SendRequest(sessionID: "q1", text: "feature/foo でお願い"))
        XCTAssertTrue(result.accepted)
    }

    // UC-04: 詳細画面の出力取得
    func testOutputFetchForDetail() async throws {
        E2EStubURLProtocol.router = { request in
            guard request.httpMethod == "GET", request.url?.path == "/sessions/s1/output" else {
                return (404, Data())
            }
            // Mac の output 応答は wire キー `text`（実機 wire で確認）。
            return (200, Data(#"{"text":"> running tests...\nOK"}"#.utf8))
        }

        let text = try await makeClient().output(sessionID: "s1")
        XCTAssertTrue(text.contains("running tests"))
    }

    // UC-02: トークン失効時は unauthorized
    func testUnauthorizedListSessions() async throws {
        E2EStubURLProtocol.router = { _ in (401, Data()) }

        do {
            _ = try await makeClient().listSessions()
            XCTFail("401 は unauthorized を throw する")
        } catch let error as PhloxError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    // UC-06: spawn レート制限
    func testRateLimitedSpawn() async throws {
        E2EStubURLProtocol.router = { request in
            guard request.httpMethod == "POST", request.url?.path == "/sessions" else {
                return (404, Data())
            }
            return (429, Data())
        }

        do {
            _ = try await makeClient().spawn(SpawnRequest(agent: .claudeCode, workspace: "proj"))
            XCTFail("429 は rateLimited を throw する")
        } catch let error as PhloxError {
            if case .rateLimited = error { } else {
                XCTFail("expected rateLimited, got \(error)")
            }
        }
    }
}

final class E2EStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var router: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() { router = nil; requestCount = 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        E2EStubURLProtocol.requestCount += 1
        let (code, data) = E2EStubURLProtocol.router?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
