import XCTest
import PhloxCore
@testable import Features

// DP-4-7 検証。質問文導出・楽観的ユーザーバブル・POST /send・失敗ロールバックを検証する。
@MainActor
final class ChatAnswerViewModelTests: XCTestCase {

    private func questionSession(
        prompt: String = "v2 契約で進めますか？",
        subtitle: String = "回答待ち: 「v2 契約で進めますか？」"
    ) -> Session {
        Session(
            id: "sess-tulip",
            name: "Tulip",
            agent: .codex,
            status: .awaitingApproval(prompt: prompt),
            subtitle: subtitle,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - 質問文導出

    func testAgentQuestionUsesApprovalPromptWhenPresent() {
        let session = questionSession(prompt: "API 契約は v2 で進めますか？")
        XCTAssertEqual(
            ChatAnswerViewModel.agentQuestionText(for: session),
            "API 契約は v2 で進めますか？"
        )
    }

    func testAgentQuestionParsesSubtitleWhenPromptEmpty() {
        let session = Session(
            id: "q1",
            name: "Task",
            agent: .codex,
            status: .running,
            subtitle: "回答待ち: 「サブタイトルから取得」",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(
            ChatAnswerViewModel.agentQuestionText(for: session),
            "サブタイトルから取得"
        )
    }

    func testAgentQuestionFallsBackToSubtitle() {
        let session = Session(
            id: "q1",
            name: "Task",
            agent: .codex,
            status: .running,
            subtitle: "実行中",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(ChatAnswerViewModel.agentQuestionText(for: session), "実行中")
    }

    // MARK: - 送信（楽観更新）

    func testSendAnswerSuccessAddsUserBubbleAndClearsInput() async {
        let mock = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = ChatAnswerViewModel(session: questionSession(), api: mock)
        vm.inputText = "v2 契約で進めてください"

        await vm.sendAnswer()

        XCTAssertEqual(vm.inputText, "")
        XCTAssertEqual(vm.userMessages.count, 1)
        XCTAssertEqual(vm.userMessages[0].text, "v2 契約で進めてください")
        XCTAssertFalse(vm.userMessages[0].isPending)
        XCTAssertEqual(vm.sendState, .idle, "送信完了ステータスは表示しない（バナー廃止）")
        let count = await mock.sendCount
        XCTAssertEqual(count, 1)
    }

    func testSendAnswerFailureRollsBackBubbleAndRestoresInput() async {
        let mock = MockAPI(sendOutcome: .failure(.notFound))
        let vm = ChatAnswerViewModel(session: questionSession(), api: mock)
        vm.inputText = "復元される回答"

        await vm.sendAnswer()

        XCTAssertTrue(vm.userMessages.isEmpty, "失敗時は楽観バブルを除去")
        XCTAssertEqual(vm.inputText, "復元される回答")
        if case .failed = vm.sendState {} else { XCTFail("expected .failed") }
    }

    func testSendAnswerRateLimitedSetsFailedState() async {
        let vm = ChatAnswerViewModel(
            session: questionSession(),
            api: MockAPI(sendOutcome: .failure(.rateLimited(retryAfter: 48)))
        )
        vm.inputText = "送信"
        await vm.sendAnswer()
        if case .failed(let message) = vm.sendState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed")
        }
    }

    func testSendAnswerIgnoresEmptyInput() async {
        let mock = MockAPI()
        let vm = ChatAnswerViewModel(session: questionSession(), api: mock)
        vm.inputText = "  \n"
        await vm.sendAnswer()
        let count = await mock.sendCount
        XCTAssertEqual(count, 0)
        XCTAssertTrue(vm.userMessages.isEmpty)
    }

    func testIsSendingReflectsSendState() async {
        let mock = SlowSendMockAPI()
        let vm = ChatAnswerViewModel(session: questionSession(), api: mock)
        vm.inputText = "first"
        let sendTask = Task { await vm.sendAnswer() }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(vm.isSending)
        await mock.release()
        await sendTask.value
        XCTAssertFalse(vm.isSending)
    }
}

/// 送信完了を遅延させ、送信中状態を観測するためのモック。
private actor SlowSendMockAPI: PhloxAPI {
    private var continuation: CheckedContinuation<Void, Never>?

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { MockAPI.defaultSession }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult {
        await withCheckedContinuation { continuation = $0 }
        return SendResult(accepted: true)
    }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
