import XCTest
import PhloxCore
@testable import Features

// task-4 受け入れテスト（PM 著・凍結）。契約: tasks/task-4.md（VM 回答送信）。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

/// respondToQuestion を記録できる PhloxAPI モック（このファイル専用）。
private actor QuestionMockAPI: PhloxAPI {
    var messagesOutcome: Result<[ChatMessage], PhloxError>
    var respondToQuestionError: PhloxError?
    private(set) var respondToQuestionLog: [(sessionID: String, requestId: String, answers: [String: [String]])] = []

    init(
        messagesOutcome: Result<[ChatMessage], PhloxError> = .success([]),
        respondToQuestionError: PhloxError? = nil
    ) {
        self.messagesOutcome = messagesOutcome
        self.respondToQuestionError = respondToQuestionError
    }

    func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws {
        respondToQuestionLog.append((sessionID, requestId, answers))
        if let respondToQuestionError {
            throw respondToQuestionError
        }
    }

    func log() -> [(sessionID: String, requestId: String, answers: [String: [String]])] {
        respondToQuestionLog
    }

    // --- 既存プロトコル要件（ダミー） ---
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "new", name: "New", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { try messagesOutcome.get() }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}

@MainActor
final class UserQuestionAnswerAcceptanceTests: XCTestCase {
    private func session() -> Session {
        Session(id: "s1", name: "Rose", agent: .claudeCode, status: .running, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func pendingQuestionMessage(requestId: String = "req-1") -> ChatMessage {
        .userQuestion(
            id: "question-\(requestId)",
            requestId: requestId,
            questions: [
                UserQuestionItem(
                    question: "デプロイ先は?",
                    header: "Deploy",
                    options: [
                        UserQuestionOption(label: "staging", description: "検証環境"),
                        UserQuestionOption(label: "prod", description: nil),
                    ],
                    multiSelect: false
                ),
            ],
            answers: nil,
            state: .pending
        )
    }

    private func questionState(in vm: SessionDetailViewModel, requestId: String) -> (answers: [String: [String]]?, state: UserQuestionState)? {
        for message in vm.visibleMessages {
            if case let .userQuestion(_, rid, _, answers, state) = message, rid == requestId {
                return (answers, state)
            }
        }
        return nil
    }

    func testPendingQuestionCardIsVisibleAfterLoad() async {
        let api = QuestionMockAPI(messagesOutcome: .success([
            .agent(id: "a1", text: "考え中"),
            pendingQuestionMessage(),
        ]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let card = questionState(in: vm, requestId: "req-1")
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.state, .pending)
        XCTAssertNil(card?.answers)
    }

    func testAnswerQuestionPostsAndMarksAnswered() async {
        let api = QuestionMockAPI(messagesOutcome: .success([pendingQuestionMessage()]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])

        XCTAssertTrue(accepted)
        let log = await api.log()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.sessionID, "s1")
        XCTAssertEqual(log.first?.requestId, "req-1")
        XCTAssertEqual(log.first?.answers, ["デプロイ先は?": ["staging"]])
        let card = questionState(in: vm, requestId: "req-1")
        XCTAssertEqual(card?.state, .answered)
        XCTAssertEqual(card?.answers, ["デプロイ先は?": ["staging"]])
    }

    func testAnswerQuestionAPIFailureKeepsPendingAndReturnsFalse() async {
        let api = QuestionMockAPI(
            messagesOutcome: .success([pendingQuestionMessage()]),
            respondToQuestionError: .unreachable
        )
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])

        XCTAssertFalse(accepted)
        let card = questionState(in: vm, requestId: "req-1")
        XCTAssertEqual(card?.state, .pending)
        XCTAssertNil(card?.answers)
    }

    func testAnswerQuestionForUnknownRequestIdIsRejectedWithoutAPICall() async {
        let api = QuestionMockAPI(messagesOutcome: .success([pendingQuestionMessage()]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "no-such", answers: ["Q": ["A"]])

        XCTAssertFalse(accepted)
        let log = await api.log()
        XCTAssertTrue(log.isEmpty)
    }

    func testAnswerQuestionForExpiredCardIsRejected() async {
        let expired = ChatMessage.userQuestion(
            id: "question-req-9",
            requestId: "req-9",
            questions: [
                UserQuestionItem(
                    question: "Q",
                    header: "H",
                    options: [
                        UserQuestionOption(label: "A", description: nil),
                        UserQuestionOption(label: "B", description: nil),
                    ],
                    multiSelect: false
                ),
            ],
            answers: nil,
            state: .expired
        )
        let api = QuestionMockAPI(messagesOutcome: .success([expired]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "req-9", answers: ["Q": ["A"]])

        XCTAssertFalse(accepted)
        let log = await api.log()
        XCTAssertTrue(log.isEmpty)
    }
}
