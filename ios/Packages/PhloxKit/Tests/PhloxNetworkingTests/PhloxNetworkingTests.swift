import XCTest
import PhloxCore
@testable import PhloxNetworking

// E3-1 検証。URLProtocol スタブで全 7 エンドポイントの成功/エラー（401/429/timeout/422）と
// GET 再試行・破壊的操作の非再試行・Bearer 注入を検証する。実ネットワークには接続しない。
final class PhloxNetworkingTests: XCTestCase {

    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    override func setUp() {
        super.setUp()
        NetStubURLProtocol.reset()
    }

    override func tearDown() {
        NetStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(token: String? = "tok", maxRetries: Int = 3) -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: token),
            session: session,
            maxRetries: maxRetries,
            retryBaseDelayNanos: 1
        )
    }

    private func json(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - 成功系

    func testListSessionsDecodesAndMapsStatus() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json("""
        {"sessions":[
          {"id":"s1","name":"Rose","kind":"claudeCode","status":"awaitingApproval","workspace":"proj"},
          {"id":"s2","name":"Tulip","kind":"codex","status":"running","workspace":null}
        ]}
        """), [:])]
        let sessions = try await makeClient().listSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].agent, .claudeCode)
        XCTAssertEqual(sessions[0].status, .awaitingApproval(prompt: ""))
        XCTAssertEqual(sessions[0].subtitle, "proj")
        XCTAssertEqual(sessions[1].status, .running)
    }

    func testListSessionsSkipsUnknownAgentKind() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json("""
        {"sessions":[
          {"id":"s1","name":"A","kind":"claudeCode","status":"idle","workspace":null},
          {"id":"s2","name":"B","kind":"customCLI","status":"idle","workspace":null}
        ]}
        """), [:])]
        let sessions = try await makeClient().listSessions()
        XCTAssertEqual(sessions.map(\.id), ["s1"])
    }

    func testApprovalsDecodes() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json("""
        {"approvals":[{"id":"a1","sessionID":"s1","kind":"claudeCode","prompt":"削除しますか？"}]}
        """), [:])]
        let approvals = try await makeClient().approvals()
        XCTAssertEqual(approvals.first?.prompt, "削除しますか？")
    }

    func testSpawnSendsKindAndDecodesIDOnlyResponse() async throws {
        // 実 wire: Mac は POST /sessions に {id} のみ返し、body は `kind` キーを期待する（agent ではない）。
        // Session はレスポンス id とリクエストのエージェントから合成する。
        NetStubURLProtocol.outcomes = [.status(201, json(#"{"id":"s9"}"#), [:])]
        let session = try await makeClient().spawn(SpawnRequest(agent: .cursor, workspace: "w"))
        XCTAssertEqual(session.id, "s9")
        XCTAssertEqual(session.agent, .cursor, "Session はリクエストのエージェントから合成する")
        XCTAssertEqual(session.status, .starting)

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(NetStubURLProtocol.lastRequestBody)) as? [String: Any]
        )
        XCTAssertEqual(body["kind"] as? String, "cursor", "Mac は kind キーを期待する")
        XCTAssertNil(body["agent"], "agent キーは送らない")
        XCTAssertEqual(body["backend"] as? String, "appServer", "構造化(.appServer)で起動しチャット表示にする")
    }

    func testWaitUntilReadyDecodesReadyFlag() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json(#"{"ready":true}"#), [:])]
        let ready = try await makeClient().waitUntilReady(sessionID: "s1")
        XCTAssertTrue(ready)
        XCTAssertEqual(NetStubURLProtocol.lastRequest?.url?.path, "/sessions/s1/ready", "ready エンドポイントを叩く")
    }

    func testSendPostsToSendEndpoint() async throws {
        // 正規契約: POST /send に対してリクエストを送ること
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        _ = try await makeClient().send(SendRequest(sessionID: "s1", text: "hello"))
        let req = try XCTUnwrap(NetStubURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.path, "/send", "エンドポイントは /send でなければならない")
        XCTAssertEqual(req.httpMethod, "POST")
    }

    func testSendBodyContainsToAndText() async throws {
        // 正規契約: body は { "to": sessionID, "text": text }
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        _ = try await makeClient().send(SendRequest(sessionID: "ses42", text: "ping"))
        let bodyData = try XCTUnwrap(NetStubURLProtocol.lastRequestBody, "リクエスト body が nil")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        XCTAssertEqual(json["to"], "ses42")
        XCTAssertEqual(json["text"], "ping")
        XCTAssertNil(json["submit"], "submit フィールドは送らない（YAGNI）")
    }

    func testSendReturnsAcceptedTrueOn200EmptyBody() async throws {
        // 正規契約: 200（空 body）→ SendResult(accepted: true, message: nil)
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        let result = try await makeClient().send(SendRequest(sessionID: "s1", text: "hi"))
        XCTAssertTrue(result.accepted)
        XCTAssertNil(result.message)
    }

    func testSendDoesNotRetryOnTransientFailure() async {
        // 破壊的操作（send）は再試行しない
        NetStubURLProtocol.outcomes = [.error(URLError(.timedOut))]
        await assertThrows(.unreachable) {
            _ = try await self.makeClient(maxRetries: 3).send(SendRequest(sessionID: "s1", text: "x"))
        }
        XCTAssertEqual(NetStubURLProtocol.requestCount, 1, "send は破壊的操作なので再試行しない")
    }

    func testSend422MapsToSpawnRejected() async {
        // エラー正規化: 422 → spawnRejected
        NetStubURLProtocol.outcomes = [.status(422, json(#"{"reason":"不正なリクエスト"}"#), [:])]
        await assertThrows(.spawnRejected(reason: "不正なリクエスト")) {
            _ = try await self.makeClient().send(SendRequest(sessionID: "s1", text: "x"))
        }
    }

    func testSend429MapsToRateLimited() async {
        // エラー正規化: 429 → rateLimited
        NetStubURLProtocol.outcomes = [.status(429, Data(), ["Retry-After": "5"])]
        await assertThrows(.rateLimited(retryAfter: 5)) {
            _ = try await self.makeClient().send(SendRequest(sessionID: "s1", text: "x"))
        }
    }

    func testOutputDecodes() async throws {
        // Mac の GET /sessions/{id}/output は本文を wire キー `text` で返す（実機 wire で確認）。
        NetStubURLProtocol.outcomes = [.status(200, json(#"{"text":"line1\nline2"}"#), [:])]
        let output = try await makeClient().output(sessionID: "s1")
        XCTAssertEqual(output, "line1\nline2")
    }

    func testMessagesDecodesAllKindsAndSkipsUnknownType() async throws {
        // 全 6 種 + 未知 type を含む wire（CH-1 の実 wire 形に一致。未知 type は前方互換で除外される）。
        NetStubURLProtocol.outcomes = [.status(200, json("""
        {"sessionId":"S1","messages":[
          {"id":"u1","type":"user","text":"hi"},
          {"id":"a1","type":"agent","text":"hello"},
          {"id":"r1","type":"reasoning","text":"thinking"},
          {"id":"c1","type":"command","command":"ls","output":"file.txt"},
          {"id":"f1","type":"fileChange","changes":[{"path":"A.swift","diff":"@@","kind":"modified"}]},
          {"id":"e1","type":"error","message":"boom"},
          {"id":"x1","type":"futureType","text":"ignored"}
        ]}
        """), [:])]

        let messages = try await makeClient().messages(sessionID: "s1")

        XCTAssertEqual(messages, [
            .user(id: "u1", text: "hi"),
            .agent(id: "a1", text: "hello"),
            .reasoning(id: "r1", text: "thinking"),
            .command(id: "c1", command: "ls", output: "file.txt"),
            .fileChange(id: "f1", changes: [ChatFileChange(path: "A.swift", diff: "@@", kind: "modified")]),
            .error(id: "e1", message: "boom"),
        ])
    }

    func testMessagesNotFoundThrowsNotFound() async {
        // 非構造化/不在セッションは Mac が 404 を返す → 呼び出し側はターミナル output にフォールバックする。
        NetStubURLProtocol.outcomes = [.status(404, json(#"{"error":"session not found"}"#), [:])]
        do {
            _ = try await makeClient().messages(sessionID: "pty1")
            XCTFail("404 では notFound を投げるべき")
        } catch {
            XCTAssertEqual(error as? PhloxError, .notFound)
        }
    }

    func testConfigProviderResolvesHostPerRequest() async throws {
        // 動的 config: 同一クライアントでも provider が返す host を都度反映する
        // （保存して接続→再起動なしで新接続先に切り替わる挙動の根拠）。
        let box = ConfigBox(ConnectionConfig(host: "host-a", port: 8765))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = PhloxAPIClient(
            configProvider: { box.get() },
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: session,
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )

        NetStubURLProtocol.outcomes = [.status(200, json(#"{"sessions":[]}"#), [:])]
        _ = try await client.listSessions()
        XCTAssertEqual(NetStubURLProtocol.lastRequest?.url?.host, "host-a")

        box.set(ConnectionConfig(host: "host-b", port: 9000))
        NetStubURLProtocol.outcomes = [.status(200, json(#"{"sessions":[]}"#), [:])]
        _ = try await client.listSessions()
        XCTAssertEqual(NetStubURLProtocol.lastRequest?.url?.host, "host-b")
        XCTAssertEqual(NetStubURLProtocol.lastRequest?.url?.port, 9000)
    }

    func testRemoveSucceedsOn200() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        try await makeClient().remove(sessionID: "s1")
        XCTAssertEqual(NetStubURLProtocol.requestCount, 1)
    }

    func testRespondSucceeds() async throws {
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]
        try await makeClient().respond(approvalID: "a1", decision: .accept)
        XCTAssertEqual(NetStubURLProtocol.requestCount, 1)
    }

    // MARK: - エラー正規化

    func testUnauthorizedMapsTo401() async {
        NetStubURLProtocol.outcomes = [.status(401, Data(), [:])]
        await assertThrows(.unauthorized) { _ = try await self.makeClient().listSessions() }
    }

    func testRateLimitedReadsRetryAfter() async {
        NetStubURLProtocol.outcomes = [.status(429, Data(), ["Retry-After": "7"])]
        await assertThrows(.rateLimited(retryAfter: 7)) { _ = try await self.makeClient().listSessions() }
    }

    func testTimeoutMapsToUnreachable() async {
        NetStubURLProtocol.outcomes = [.error(URLError(.timedOut))]
        await assertThrows(.unreachable) { _ = try await self.makeClient(maxRetries: 1).listSessions() }
    }

    func testSpawnDepthRejectionMapsTo422() async {
        NetStubURLProtocol.outcomes = [.status(422, json(#"{"reason":"最大深度を超えています"}"#), [:])]
        await assertThrows(.spawnRejected(reason: "最大深度を超えています")) {
            _ = try await self.makeClient().spawn(SpawnRequest(agent: .codex, workspace: "w"))
        }
    }

    func testServer400ErrorFieldSurfacedInMessage() async {
        // Mac の ErrorDTO は理由を `error` キーで返す（ControlServer 全エンドポイント共通の wire 形）。
        // iOS が旧実装で message/reason だけ見て理由を nil に潰し、モバイルが「Mac側で問題が
        // 発生しました」という汎用文言になっていた回帰の凍結テスト。`error` を人間向け message に写す。
        NetStubURLProtocol.outcomes = [.status(400, json(#"{"error":"control-characters"}"#), [:])]
        await assertThrows(.server(status: 400, message: "control-characters")) {
            _ = try await self.makeClient().send(SendRequest(sessionID: "s1", text: "x"))
        }
    }

    func testSpawn422ErrorFieldSurfacedAsReason() async {
        // 422(spawnRejected)経路でも `error` キーから理由を採れることを凍結する。
        NetStubURLProtocol.outcomes = [.status(422, json(#"{"error":"invalid role"}"#), [:])]
        await assertThrows(.spawnRejected(reason: "invalid role")) {
            _ = try await self.makeClient().spawn(SpawnRequest(agent: .codex, workspace: "w"))
        }
    }

    // MARK: - 再試行ポリシー

    func testGetRetriesOnTransientFailureThenSucceeds() async throws {
        NetStubURLProtocol.outcomes = [
            .error(URLError(.timedOut)),
            .error(URLError(.timedOut)),
            .status(200, json(#"{"sessions":[]}"#), [:]),
        ]
        let sessions = try await makeClient(maxRetries: 3).listSessions()
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(NetStubURLProtocol.requestCount, 3, "GET は最大 3 回試行する")
    }

    func testMutatingOperationDoesNotRetry() async {
        NetStubURLProtocol.outcomes = [.error(URLError(.timedOut))]
        await assertThrows(.unreachable) {
            _ = try await self.makeClient(maxRetries: 3).spawn(SpawnRequest(agent: .codex, workspace: "w"))
        }
        XCTAssertEqual(NetStubURLProtocol.requestCount, 1, "破壊的操作は再試行しない")
    }

    // MARK: - Bearer 注入

    func testBearerHeaderInjectedFromTokenStore() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json(#"{"sessions":[]}"#), [:])]
        _ = try await makeClient(token: "secret-123").listSessions()
        XCTAssertEqual(NetStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-123")
    }

    func testNoBearerHeaderWhenTokenMissing() async throws {
        NetStubURLProtocol.outcomes = [.status(200, json(#"{"sessions":[]}"#), [:])]
        _ = try await makeClient(token: nil).listSessions()
        XCTAssertNil(NetStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - helper

    private func assertThrows(_ expected: PhloxError, _ block: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await block()
            XCTFail("expected \(expected) to be thrown", file: file, line: line)
        } catch let error as PhloxError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}

// MARK: - テスト用ヘルパ

/// 可変 ConnectionConfig を @Sendable provider 越しに差し替えるためのスレッドセーフ箱。
final class ConfigBox: @unchecked Sendable {
    private var config: ConnectionConfig
    private let lock = NSLock()
    init(_ config: ConnectionConfig) { self.config = config }
    func get() -> ConnectionConfig { lock.lock(); defer { lock.unlock() }; return config }
    func set(_ newValue: ConnectionConfig) { lock.lock(); config = newValue; lock.unlock() }
}

// MARK: - URLProtocol スタブ

enum StubOutcome {
    case status(Int, Data, [String: String])
    case error(URLError)
}

final class NetStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var outcomes: [StubOutcome] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    /// httpBody は URLSession 経由で送られると httpBodyStream に変換される。
    /// startLoading() でストリームから読み出してここに保存する。
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        outcomes = []
        requestCount = 0
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = min(NetStubURLProtocol.requestCount, NetStubURLProtocol.outcomes.count - 1)
        NetStubURLProtocol.requestCount += 1
        NetStubURLProtocol.lastRequest = request
        NetStubURLProtocol.lastRequestBody = request.readBodyForTesting()

        guard index >= 0, NetStubURLProtocol.outcomes.indices.contains(index) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch NetStubURLProtocol.outcomes[index] {
        case let .status(code, data, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .error(urlError):
            client?.urlProtocol(self, didFailWithError: urlError)
        }
    }

    override func stopLoading() {}
}
