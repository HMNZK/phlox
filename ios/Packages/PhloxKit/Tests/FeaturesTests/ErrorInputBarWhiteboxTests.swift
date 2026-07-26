import XCTest
import PhloxCore
@testable import Features

@MainActor
final class ErrorInputBarWhiteboxTests: XCTestCase {
    private func session(_ status: SessionStatus) -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: status,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testInputEnabledStatusSwitchDisablesOnlyStarting() {
        let statuses: [(SessionStatus, Bool)] = [
            (.starting, false),
            (.idle, true),
            (.running, true),
            (.awaitingApproval(prompt: "p"), true),
            (.awaitingUserQuestion, true),
            (.completed(exitCode: 0), true),
            (.error(message: "boom"), true)
        ]

        for (status, expected) in statuses {
            let viewModel = SessionDetailViewModel(session: session(status), api: MockAPI())
            XCTAssertEqual(viewModel.inputEnabled, expected, "status: \(status)")
        }
    }

    /// 終了済みセッションでも、送信失敗をバナー表示用の状態で可視化し、入力を復元する。
    func testSendFailureOnErrorSessionSurfacesFailureAndRestoresInput() async {
        let viewModel = SessionDetailViewModel(
            session: session(.error(message: "boom")),
            api: MockAPI(sendOutcome: .failure(.unreachable))
        )
        viewModel.inputText = "再開したい"

        await viewModel.sendMessage()

        guard case .failed(let message) = viewModel.sendState else {
            return XCTFail("送信失敗は DSResultBanner の表示条件である .failed として可視化されること")
        }
        XCTAssertFalse(message.isEmpty, "バナーに表示する失敗メッセージを持つこと")
        XCTAssertEqual(viewModel.inputText, "再開したい", "失敗時は入力を復元して再送可能にすること")
        XCTAssertTrue(viewModel.isInputBarEnabled, "失敗後も復帰手段として入力欄を残すこと")
    }

    /// .error からの送信成功後に失敗バナーが残らないことを固定する。
    func testSendSuccessOnErrorSessionEndsInIdle() async {
        let viewModel = SessionDetailViewModel(
            session: session(.error(message: "boom")),
            api: MockAPI()
        )
        viewModel.inputText = "再開したい"

        await viewModel.sendMessage()

        XCTAssertEqual(viewModel.sendState, .idle)
    }

    /// .completed からの送信失敗も、.error と同じく可視化して入力を復元する。
    func testSendFailureOnCompletedSessionSurfacesFailureAndRestoresInput() async {
        let viewModel = SessionDetailViewModel(
            session: session(.completed(exitCode: 0)),
            api: MockAPI(sendOutcome: .failure(.unreachable))
        )
        viewModel.inputText = "続けたい"

        await viewModel.sendMessage()

        guard case .failed(let message) = viewModel.sendState else {
            return XCTFail("終了済みセッションの送信失敗も .failed として可視化されること")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(viewModel.inputText, "続けたい")
        XCTAssertTrue(viewModel.isInputBarEnabled)
    }

    /// 送信中は終了状態でも入力欄を無効化し、完了後に再び有効化する。
    func testInputBarDisabledWhileSendingOnErrorSession() async {
        let api = SlowSendAPI()
        let viewModel = SessionDetailViewModel(session: session(.error(message: "boom")), api: api)
        viewModel.inputText = "再開したい"

        let sendTask = Task { await viewModel.sendMessage() }
        await api.waitUntilSendStarts()

        XCTAssertTrue(viewModel.isSending)
        XCTAssertFalse(viewModel.isInputBarEnabled, "送信中は入力欄を無効化する既存の性質を保つこと")

        await api.release()
        await sendTask.value

        XCTAssertTrue(viewModel.isInputBarEnabled, "送信完了後は入力欄を再び有効化すること")
    }
}

/// 送信開始と完了を明示的に同期し、送信中の状態を決定的に観測するための API。
private actor SlowSendAPI: PhloxAPI {
    private var sendStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { MockAPI.defaultSession }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult {
        sendStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        return SendResult(accepted: true)
    }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func waitUntilSendStarts() async {
        guard !sendStarted else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
