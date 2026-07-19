import AgentDomain
import Foundation
import Testing
@testable import ControlServer

// task-3 受け入れテスト（PM 著・凍結）。契約: tasks/task-3.md / ControlQuestionWireContract。
// POST /sessions/{id}/question → Action.respondQuestion のルーティングを検証する。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

private actor QuestionRoutingHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct UserQuestionRoutingAcceptanceTests {
    private let requester = SessionID()
    private let bearer = "question-bearer"

    @Test func postQuestionRoutesRespondQuestion() async throws {
        let stub = QuestionRoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlQuestionWireContract.questionPathSuffix)",
            body: #"{"requestId":"req-1","answers":{"デプロイ先は?":["staging"],"含める機能は?":["A","B"]}}"#
        )

        #expect(response.statusCode == 200)
        let last = await stub.lastRequest
        guard case .respondQuestion(let id, let requestId, let answers)? = last?.action else {
            Issue.record("expected respondQuestion, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
        #expect(requestId == "req-1")
        #expect(answers == ["デプロイ先は?": ["staging"], "含める機能は?": ["A", "B"]])
    }

    @Test(arguments: [
        "{}",
        #"{"requestId":"req-1"}"#,
        #"{"answers":{"Q":["A"]}}"#,
        #"{"requestId":"","answers":{"Q":["A"]}}"#,
        "not-json",
    ])
    func invalidQuestionBodyReturns400WithoutCallingHandler(body: String) async throws {
        let stub = QuestionRoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlQuestionWireContract.questionPathSuffix)",
            body: body
        )

        #expect(response.statusCode == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getQuestionPathReturns404() async throws {
        let stub = QuestionRoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlQuestionWireContract.questionPathSuffix)"
        )

        #expect(response.statusCode == 404)
        #expect(await stub.callCount == 0)
    }

    private func startServer(_ stub: QuestionRoutingHandlerStub) async throws -> (Int, ControlServer) {
        let store = SessionTokenStore()
        await store.register(bearer, for: requester)
        let server = ControlServer(tokenStore: store) { request in
            await stub.handle(request)
        }
        return (try await server.start(), server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        body: String? = nil
    ) async throws -> HTTPURLResponse {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return try #require(response as? HTTPURLResponse)
    }
}
