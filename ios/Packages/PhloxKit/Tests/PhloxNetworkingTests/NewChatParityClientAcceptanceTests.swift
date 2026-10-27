import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

@Suite(.serialized)
struct NewChatParityClientAcceptanceTests {
    private let projectID = "6C2F0E2A-1111-4222-8333-444455556666"

    @Test("従来の起動はworktree・起点・履歴キーを送らない")
    func ordinarySpawnKeepsLegacyBody() async throws {
        ParityURLProtocol.configure(response: #"{"id":"created"}"#)
        _ = try await client().spawn(SpawnRequest(agent: .codex, workspace: "Phlox", projectID: projectID))
        let body = try capturedBody()
        #expect(body["usesWorktree"] == nil)
        #expect(body["startPoint"] == nil)
        #expect(body["resumeHistoryID"] == nil)
        #expect(body["projectId"] as? String == projectID)
    }

    @Test("worktreeの起点を表示名ではなく種別と値で送信する")
    func spawnCarriesWorktreeStartPoint() async throws {
        ParityURLProtocol.configure(response: #"{"id":"created"}"#)
        let point = NewChatStartPoint(kind: .tag, value: "release/1.0", title: "Release", summary: nil)
        _ = try await client().spawn(SpawnRequest(agent: .codex, workspace: "Phlox", projectID: projectID,
                                                usesWorktree: true, startPoint: point))
        let body = try capturedBody()
        #expect(body["usesWorktree"] as? Bool == true)
        let encodedPoint = try #require(body["startPoint"] as? [String: Any])
        #expect(encodedPoint["kind"] as? String == "tag")
        #expect(encodedPoint["value"] as? String == "release/1.0")
        #expect(ParityURLProtocol.request?.httpMethod == "POST")
        #expect(ParityURLProtocol.request?.url?.path == "/sessions")
    }

    @Test("履歴再開は安定したIDを送り内部ファイルパスを送らない")
    func resumeCarriesHistoryIDOnly() async throws {
        ParityURLProtocol.configure(response: #"{"id":"resumed"}"#)
        _ = try await client().spawn(SpawnRequest(agent: .claudeCode, workspace: "Phlox", projectID: projectID,
                                                resumeHistoryID: "history-session"))
        let body = try capturedBody()
        #expect(body["resumeHistoryID"] as? String == "history-session")
        #expect(body["fileURL"] == nil)
        #expect(body["historyPath"] == nil)
    }

    @Test("開始地点一覧はprojectIDとコミット検索値を正しくエンコードする")
    func startPointsRequestEncodesCommit() async throws {
        ParityURLProtocol.configure(response: #"{"startPoints":[{"kind":"commit","value":"abc1234","title":"abc1234","summary":"Fix"}]}"#)
        let result = try await client().projectStartPoints(projectID: projectID, commit: "feature/a+b")
        let request = try #require(ParityURLProtocol.request)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/projects/\(projectID)/start-points")
        #expect(components.queryItems?.first(where: { $0.name == "commit" })?.value == "feature/a+b")
        #expect(result.count == 1)
        #expect(result.first?.kind == .commit)
        #expect(result.first?.value == "abc1234")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test("再開候補は選択したプロジェクトとエージェントで取得し日付を解釈する")
    func historyRequestDecodesDatesAndFiltersAgentAtServer() async throws {
        ParityURLProtocol.configure(response: #"{"entries":[{"id":"h1","title":"Earlier task","updatedAt":"2026-10-25T01:02:03Z","branch":"dev","workingDirectory":"/repo"}]}"#)
        let result = try await client().projectHistory(projectID: projectID, kind: .codex)
        let request = try #require(ParityURLProtocol.request)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/projects/\(projectID)/history")
        #expect(components.queryItems?.first(where: { $0.name == "kind" })?.value == "codex")
        #expect(result.first?.id == "h1")
        #expect(result.first?.branch == "dev")
        #expect(result.first?.updatedAt == ISO8601DateFormatter().date(from: "2026-10-25T01:02:03Z"))
    }

    private func capturedBody() throws -> [String: Any] {
        let data = try #require(ParityURLProtocol.requestBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func client() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ParityURLProtocol.self]
        return PhloxAPIClient(config: ConnectionConfig(host: "100.64.0.1", port: 8765),
                              tokenStore: InMemoryTokenStore(token: "token"),
                              session: URLSession(configuration: configuration),
                              maxRetries: 1, retryBaseDelayNanos: 1)
    }
    @Test("確認済み更新は読んだ完了のtokenを送る")
    func acknowledgementCarriesObservedCompletionToken() async throws {
        ParityURLProtocol.configure(response: "", status: 204)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ParityURLProtocol.self]
        let client = PhloxAPIClient(config: ConnectionConfig(host: "100.64.0.1", port: 8765),
                                    tokenStore: InMemoryTokenStore(token: "token"),
                                    session: URLSession(configuration: configuration), maxRetries: 1)

        try await client.markCompletionSeen(sessionID: "session-1", completionToken: "execution-a:3")

        #expect(ParityURLProtocol.request?.httpMethod == "POST")
        #expect(ParityURLProtocol.request?.url?.path == "/sessions/session-1/completion-seen")
        let body = try #require(ParityURLProtocol.requestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["completionToken": "execution-a:3"])
    }

    @Test("token競合を成功扱いにしない")
    func conflictRemainsAnError() async throws {
        ParityURLProtocol.configure(response: #"{"error":"completion changed"}"#, status: 409)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ParityURLProtocol.self]
        let client = PhloxAPIClient(config: ConnectionConfig(host: "100.64.0.1", port: 8765),
                                    tokenStore: InMemoryTokenStore(token: "token"),
                                    session: URLSession(configuration: configuration), maxRetries: 1)
        do {
            try await client.markCompletionSeen(sessionID: "session-1", completionToken: "execution-a:3")
            Issue.record("競合を確認済みとして受理しました")
        } catch PhloxError.server(let status, _) {
            #expect(status == 409)
        } catch {
            Issue.record("競合とは異なるエラー: \(error)")
        }
    }

    @Test("一覧の完了tokenを保持し、旧サーバーの省略も許容する")
    func sessionDTOCarriesOptionalCompletionToken() throws {
        let prefix = #"{"id":"s1","name":"Task","kind":"codex","status":"completed","workspace":"repo","hasUnseenCompletion":true"#
        let current = try JSONDecoder().decode(SessionDTO.self, from: Data((prefix + #", "completionToken":"exec:2"}"#).utf8))
        let legacy = try JSONDecoder().decode(SessionDTO.self, from: Data((prefix + "}").utf8))
        #expect(current.toDomain(now: Date())?.completionToken == "exec:2")
        #expect(legacy.toDomain(now: Date())?.completionToken == nil)
    }
}

private final class ParityURLProtocol: URLProtocol {
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var requestBody: Data?
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var responseStatus: Int?

    static func configure(response: String, status: Int? = nil) {
        request = nil
        requestBody = nil
        responseBody = Data(response.utf8)
        responseStatus = status
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.request = request
        Self.requestBody = request.readBodyForTesting()
        let status = Self.responseStatus ?? (request.httpMethod == "POST" ? 201 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
