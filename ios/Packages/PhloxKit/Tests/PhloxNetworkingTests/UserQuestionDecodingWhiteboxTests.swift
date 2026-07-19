import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// task-4 白箱: デコード分岐・respondToQuestion ワイヤ・implemented 反転。
@Suite("AskUserQuestion デコード / API 白箱", .serialized)
struct UserQuestionDecodingWhiteboxTests {
    @Test("questions キー欠落は nil（DTO はデコード成功）")
    func missingQuestionsKeyDropsMessage() throws {
        let fixture = """
        {"sessionId":"S1","messages":[
          {"id":"q1","type":"userQuestion","requestId":"req-1","state":"pending"}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(fixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        #expect(messages.isEmpty)
    }

    @Test("空 questions 配列は isVisible 除外前提でデコード自体は成功")
    func emptyQuestionsArrayDecodes() throws {
        let fixture = """
        {"sessionId":"S1","messages":[
          {"id":"q1","type":"userQuestion","requestId":"req-1","state":"pending","questions":[]}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(fixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        guard case let .userQuestion(_, _, questions, _, state)? = messages.first else {
            Issue.record("expected userQuestion")
            return
        }
        #expect(questions.isEmpty)
        #expect(state == .pending)
    }

    @Test("respondToQuestion は POST sessions/{id}/question に requestId/answers を載せる")
    func respondToQuestionPostsExpectedBody() async throws {
        QuestionAPIStubURLProtocol.reset()
        QuestionAPIStubURLProtocol.outcomes = [.status(200, Data(), [:])]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuestionAPIStubURLProtocol.self]
        let client = PhloxAPIClient(
            config: ConnectionConfig(host: "100.64.0.1", port: 8765),
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )

        try await client.respondToQuestion(
            sessionID: "s1",
            requestId: "req-1",
            answers: ["Q": ["A", "B"]]
        )

        #expect(QuestionAPIStubURLProtocol.requestCount == 1)
        #expect(QuestionAPIStubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(QuestionAPIStubURLProtocol.lastRequest?.url?.path == "/sessions/s1/\(PhloxQuestionWireContract.questionPathSuffix)")
        let body = try #require(QuestionAPIStubURLProtocol.lastRequestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object[PhloxQuestionWireContract.requestIdKey] as? String == "req-1")
        let answers = try #require(object[PhloxQuestionWireContract.answersKey] as? [String: [String]])
        #expect(answers == ["Q": ["A", "B"]])
    }

    @Test("実装完了後は PhloxQuestionWireContract.implemented が true")
    func wireContractImplementedIsTrue() {
        #expect(PhloxQuestionWireContract.implemented)
        #expect(PhloxQuestionWireContract.messageType == "userQuestion")
        #expect(PhloxQuestionWireContract.questionPathSuffix == "question")
    }
}

// MARK: - URLProtocol スタブ（本ファイル専用）

private final class QuestionAPIStubURLProtocol: URLProtocol {
    enum Outcome {
        case status(Int, Data, [String: String])
    }

    nonisolated(unsafe) static var outcomes: [Outcome] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
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
        let index = min(Self.requestCount, Self.outcomes.count - 1)
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastRequestBody = request.readBodyForTesting()

        guard index >= 0, Self.outcomes.indices.contains(index) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch Self.outcomes[index] {
        case let .status(code, data, headers):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
