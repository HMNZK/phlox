import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

// task-3 受け入れテスト（PM 著・凍結）。契約: tasks/task-3.md / ControlQuestionWireContract。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

@MainActor
@Suite struct AcceptanceUserQuestionWireTests {
    @MainActor
    private final class QuestionDashboardStub: ControlActionDashboard {
        var deltaResponse: TranscriptDelta?
        var respondQuestionResult = true
        private(set) var respondQuestionCalls: [(id: SessionID, requestId: String, answers: [String: [String]])] = []

        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
            deltaResponse
        }

        func respondToUserQuestion(
            id: SessionID,
            requestId: String,
            answers: [String: [String]]
        ) async -> Bool {
            respondQuestionCalls.append((id, requestId, answers))
            return respondQuestionResult
        }

        // --- 既存プロトコル要件（ダミー） ---
        var controlSessionSummaries: [ControlSessionSummary] = []
        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome { .sent }
        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID { SessionID() }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessages(for id: SessionID) -> [ChatItem]? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ dashboard: QuestionDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func bodyJSON(_ response: ControlResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private static let ts = Date(timeIntervalSince1970: 1_700_000_000)

    private static let wireQuestions = [
        ChatUserQuestion(
            question: "デプロイ先は?",
            header: "Deploy",
            options: [
                ChatUserQuestionOption(label: "staging", description: "検証環境"),
                ChatUserQuestionOption(label: "prod", description: nil),
            ],
            multiSelect: false
        ),
    ]

    @Test func messagesDeltaEmitsPendingUserQuestionPayload() async throws {
        let dashboard = QuestionDashboardStub()
        dashboard.deltaResponse = TranscriptDelta(
            items: [.userQuestion(
                id: "question-req-1",
                requestId: "req-1",
                questions: Self.wireQuestions,
                answers: nil,
                state: .pending,
                timestamp: Self.ts
            )],
            cursor: "c-1",
            isSnapshot: false
        )
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
        )

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        let message = try #require(messages.first)
        #expect(message["id"] as? String == "question-req-1")
        #expect(message["type"] as? String == "userQuestion")
        #expect(message["requestId"] as? String == "req-1")
        #expect(message["state"] as? String == "pending")
        // 未回答の answers キーは省略する（不要キー省略の既存規約）。
        #expect(message["answers"] == nil)
        let questions = try #require(message["questions"] as? [[String: Any]])
        #expect(questions.count == 1)
        let question = try #require(questions.first)
        #expect(question["question"] as? String == "デプロイ先は?")
        #expect(question["header"] as? String == "Deploy")
        #expect(question["multiSelect"] as? Bool == false)
        let options = try #require(question["options"] as? [[String: Any]])
        guard options.count == 2 else {
            Issue.record("expected 2 options, got \(options)")
            return
        }
        #expect(options[0]["label"] as? String == "staging")
        #expect(options[0]["description"] as? String == "検証環境")
        #expect(options[1]["label"] as? String == "prod")
        #expect(options[1]["description"] == nil)
    }

    @Test func messagesDeltaEmitsAnsweredAnswersAndState() async throws {
        let dashboard = QuestionDashboardStub()
        dashboard.deltaResponse = TranscriptDelta(
            items: [.userQuestion(
                id: "question-req-2",
                requestId: "req-2",
                questions: Self.wireQuestions,
                answers: ["デプロイ先は?": ["staging"]],
                state: .answered,
                timestamp: Self.ts
            )],
            cursor: "c-2",
            isSnapshot: false
        )
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
        )

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let message = try #require((body["messages"] as? [[String: Any]])?.first)
        #expect(message["state"] as? String == "answered")
        let answers = try #require(message["answers"] as? [String: Any])
        #expect(answers["デプロイ先は?"] as? [String] == ["staging"])
    }

    @Test func respondQuestionForwardsToDashboardAndReturns200() async throws {
        let dashboard = QuestionDashboardStub()
        dashboard.respondQuestionResult = true
        let handler = makeHandler(dashboard)
        let sessionID = SessionID()

        let response = await handler.handle(ControlRequest(
            requester: nil,
            action: .respondQuestion(
                id: sessionID,
                requestId: "req-1",
                answers: ["デプロイ先は?": ["staging"]]
            )
        ))

        #expect(response.statusCode == 200)
        #expect(dashboard.respondQuestionCalls.count == 1)
        #expect(dashboard.respondQuestionCalls.first?.id == sessionID)
        #expect(dashboard.respondQuestionCalls.first?.requestId == "req-1")
        #expect(dashboard.respondQuestionCalls.first?.answers == ["デプロイ先は?": ["staging"]])
    }

    @Test func respondQuestionRejectedByDashboardReturns404() async throws {
        let dashboard = QuestionDashboardStub()
        dashboard.respondQuestionResult = false
        let handler = makeHandler(dashboard)

        let response = await handler.handle(ControlRequest(
            requester: nil,
            action: .respondQuestion(id: SessionID(), requestId: "gone", answers: ["Q": ["A"]])
        ))

        #expect(response.statusCode == 404)
        #expect(dashboard.respondQuestionCalls.count == 1)
    }
}
