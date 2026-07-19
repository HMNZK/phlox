import XCTest
import PhloxCore
@testable import Features

/// task-4 白箱: answerQuestion の分岐（answered 再送拒否・可視メッセージ前提）。
private actor WhiteboxQuestionMockAPI: PhloxAPI {
    var messagesOutcome: Result<[ChatMessage], PhloxError>
    private(set) var respondToQuestionLog: [(sessionID: String, requestId: String, answers: [String: [String]])] = []

    init(messagesOutcome: Result<[ChatMessage], PhloxError> = .success([])) {
        self.messagesOutcome = messagesOutcome
    }

    func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws {
        respondToQuestionLog.append((sessionID, requestId, answers))
    }

    func log() -> [(sessionID: String, requestId: String, answers: [String: [String]])] {
        respondToQuestionLog
    }

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
final class UserQuestionWhiteboxTests: XCTestCase {
    private func session() -> Session {
        Session(id: "s1", name: "Rose", agent: .claudeCode, status: .running, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func questionItem(multiSelect: Bool = false) -> UserQuestionItem {
        UserQuestionItem(
            question: "Q",
            header: "H",
            options: [
                UserQuestionOption(label: "A", description: nil),
                UserQuestionOption(label: "B", description: "desc"),
            ],
            multiSelect: multiSelect
        )
    }

    func testAnswerQuestionRejectsAlreadyAnsweredWithoutAPICall() async {
        let answered = ChatMessage.userQuestion(
            id: "question-req-1",
            requestId: "req-1",
            questions: [questionItem()],
            answers: ["Q": ["A"]],
            state: .answered
        )
        let api = WhiteboxQuestionMockAPI(messagesOutcome: .success([answered]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "req-1", answers: ["Q": ["B"]])

        XCTAssertFalse(accepted)
        let log = await api.log()
        XCTAssertTrue(log.isEmpty)
    }

    func testAnswerQuestionReplacesLocalCardOnlyAfterSuccess() async {
        let pending = ChatMessage.userQuestion(
            id: "question-req-2",
            requestId: "req-2",
            questions: [questionItem(multiSelect: true)],
            answers: nil,
            state: .pending
        )
        let api = WhiteboxQuestionMockAPI(messagesOutcome: .success([pending]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        let accepted = await vm.answerQuestion(requestId: "req-2", answers: ["Q": ["A", "B"]])

        XCTAssertTrue(accepted)
        guard case let .userQuestion(_, _, _, answers, state)? = vm.visibleMessages.first else {
            XCTFail("expected userQuestion")
            return
        }
        XCTAssertEqual(state, .answered)
        XCTAssertEqual(answers, ["Q": ["A", "B"]])
    }

    func testEmptyQuestionsUserQuestionIsNotVisible() async {
        let empty = ChatMessage.userQuestion(
            id: "question-req-3",
            requestId: "req-3",
            questions: [],
            answers: nil,
            state: .pending
        )
        let api = WhiteboxQuestionMockAPI(messagesOutcome: .success([empty]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()

        XCTAssertTrue(vm.visibleMessages.isEmpty)
        let accepted = await vm.answerQuestion(requestId: "req-3", answers: ["Q": ["A"]])
        XCTAssertFalse(accepted)
        let log = await api.log()
        XCTAssertTrue(log.isEmpty)
    }
}
