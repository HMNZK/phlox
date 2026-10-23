import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
@testable import SessionFeature

// control API の userQuestion 配線（ControlQuestionWireContract）: messages の出力形と respondQuestion の転送。

@MainActor
@Suite struct UserQuestionWireTests {
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
            workingDirectory: String?, projectID: ProjectID?, initialSettings: CodexAppServerSessionSettings?
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
        #expect(message["text"] == nil)
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

    @Test func messagesPreserveDistinctQuestionIDsForIdenticalTitles() async throws {
        let dashboard = QuestionDashboardStub()
        let questions = ["first", "second"].map {
            ChatUserQuestion(question: "同じ質問", header: "", options: [], multiSelect: false, id: $0)
        }
        dashboard.deltaResponse = TranscriptDelta(items: [.userQuestion(
            id: "q", requestId: "request", questions: questions, answers: ["first": ["A"], "second": ["B"]],
            state: .answered, timestamp: Self.ts
        )], cursor: "cursor", isSnapshot: false)
        let response = await makeHandler(dashboard).handle(
            ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
        )
        let message = try #require((try bodyJSON(response)["messages"] as? [[String: Any]])?.first)
        let wireQuestions = try #require(message["questions"] as? [[String: Any]])
        #expect(wireQuestions.compactMap { $0["id"] as? String } == ["first", "second"])
        #expect(message["answers"] as? [String: [String]] == ["first": ["A"], "second": ["B"]])
    }

    @Test func messagesDeltaEmitsExpiredUserQuestionWithWireStateKey() async throws {
        let dashboard = QuestionDashboardStub()
        dashboard.deltaResponse = TranscriptDelta(
            items: [.userQuestion(
                id: "q-expired",
                requestId: "req-exp",
                questions: Self.wireQuestions,
                answers: nil,
                state: .expired,
                timestamp: Self.ts
            )],
            cursor: "c-exp",
            isSnapshot: false
        )
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
        )

        #expect(response.statusCode == 200)
        let message = try #require((try bodyJSON(response)["messages"] as? [[String: Any]])?.first)
        #expect(message["state"] as? String == ControlQuestionWireContract.stateExpired)
        #expect(message["answers"] == nil)
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

    @Test(arguments: [true, false, nil] as [Bool?])
    func permissionQuestionEmitsOptionalSessionScope(allowsSessionScope: Bool?) async throws {
        let dashboard = QuestionDashboardStub()
        let options = [ChatUserQuestionOption(label: "Allow"), ChatUserQuestionOption(label: "Deny")]
        let questions = [
            ChatUserQuestion(question: "Bash?", header: "Permission", options: options, multiSelect: false,
                permission: ChatToolPermission(toolName: "Bash", detail: "pwd", allowsSessionScope: allowsSessionScope)),
            ChatUserQuestion(question: "Normal?", header: "Question", options: options, multiSelect: false),
            ChatUserQuestion(question: "Legacy?", header: "Question", options: options, multiSelect: false, permission: nil),
        ]
        dashboard.deltaResponse = TranscriptDelta(
            items: [.userQuestion(id: "q", requestId: "req", questions: questions, answers: nil, state: .pending, timestamp: Self.ts)],
            cursor: "c", isSnapshot: false
        )
        let response = await makeHandler(dashboard).handle(
            ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
        )
        #expect(response.statusCode == 200)
        let message = try #require((try bodyJSON(response)["messages"] as? [[String: Any]])?.first)
        let wireQuestions = try #require(message["questions"] as? [[String: Any]])
        #expect(wireQuestions.count == 3)
        #expect(wireQuestions[0]["allowsSessionScope"] as? Bool == allowsSessionScope)
        if allowsSessionScope == nil { #expect(wireQuestions[0]["allowsSessionScope"] == nil) }
        #expect(wireQuestions[1]["allowsSessionScope"] == nil)
        #expect(wireQuestions[2]["allowsSessionScope"] == nil)
        #expect(ControlQuestionWireContract.toolNameKey == "toolName")
        #expect(ControlQuestionWireContract.toolDetailKey == "toolDetail")
        #expect(wireQuestions[0]["toolName"] as? String == "Bash")
        #expect(wireQuestions[0]["toolDetail"] as? String == "pwd")
        for question in wireQuestions.dropFirst() {
            #expect(question["toolName"] == nil)
            #expect(question["toolDetail"] == nil)
        }
        for question in wireQuestions {
            let wireOptions = try #require(question["options"] as? [[String: Any]])
            #expect(wireOptions.compactMap { $0["label"] as? String } == ["Allow", "Deny"])
        }
    }

    @Test func sessionPermissionAnswerForwardsUnchanged() async throws {
        #expect(ControlQuestionWireContract.allowForSessionAnswer == ChatSessionViewModel.allowForSessionAnswer)
        let dashboard = QuestionDashboardStub()
        let id = SessionID()
        let answers = ["Bash?": ["AllowForSession"]]
        let response = await makeHandler(dashboard).handle(ControlRequest(
            requester: nil, action: .respondQuestion(id: id, requestId: "req", answers: answers)
        ))
        #expect(response.statusCode == 200)
        #expect(dashboard.respondQuestionCalls.count == 1)
        #expect(dashboard.respondQuestionCalls.first?.id == id)
        #expect(dashboard.respondQuestionCalls.first?.requestId == "req")
        #expect(dashboard.respondQuestionCalls.first?.answers == answers)
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
