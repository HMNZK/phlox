import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// 受け入れテスト: 未回答の質問カードを「回答せずに閉じる」経路。
//
// 質問カードの閉じるボタンは `ChatSessionViewModel.turnInterrupt()` を呼ぶ（Esc・中断ボタンと同じ経路）。
// 目的は「回答せずに別の指示を出せる状態にする」ことなので、次の3つが揃って初めて意味を持つ:
//   ①CLI へ中断が届く（＝エージェントが質問待ちで固まったままにならない）
//   ②カードが期限切れになる（＝もう回答できないことが画面から判る）
//   ③セッションが running でなくなる（＝次の指示を送れる）

// MARK: - ハーネス

private final class InterruptRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var interruptCallCount = 0

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    var interruptCalls: Int {
        lock.withLock { interruptCallCount }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}

    /// 実クライアント（`ClaudeChatClient.interrupt()`）と同じく、中断を受けたら
    /// `.turnInterrupted` を流す。VM 側の失効処理はこのイベントで駆動される。
    func interrupt() async throws {
        lock.withLock { interruptCallCount += 1 }
        continuation.yield(.turnInterrupted(nativeSessionId: nil))
    }

    func close() async {
        continuation.finish()
    }

    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async {}
}

@MainActor
private func makeViewModel(client: InterruptRecordingClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

private let dismissQuestions = [
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

@MainActor
private func questionState(
    in vm: ChatSessionViewModel,
    requestId: String
) -> ChatUserQuestionState? {
    for item in vm.transcript {
        if case let .userQuestion(_, rid, _, _, state, _) = item, rid == requestId {
            return state
        }
    }
    return nil
}

private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    timeoutMs: Int = 2000
) async throws {
    for _ in 0..<(timeoutMs / 10) {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let final = await condition()
    #expect(final, "waitUntil timed out")
}

// MARK: - 受け入れ条件

@Test @MainActor
func dismissingPendingQuestionSendsInterruptAndExpiresCard() async throws {
    let client = InterruptRecordingClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: dismissQuestions))
    try await waitUntil { questionState(in: vm, requestId: "req-1") == .pending }
    #expect(vm.status == .awaitingUserQuestion, "回答待ちで止まっている")

    // 閉じるボタンが呼ぶ経路。
    await vm.turnInterrupt()

    try await waitUntil { questionState(in: vm, requestId: "req-1") == .expired }
    #expect(client.interruptCalls == 1, "CLI へ中断が1回だけ届く")
    #expect(questionState(in: vm, requestId: "req-1") == .expired, "カードは期限切れになる")
    #expect(!vm.status.isRunning, "次の指示を送れる状態に戻る")
}

@Test @MainActor
func dismissedQuestionNoLongerAcceptsAnswers() async throws {
    let client = InterruptRecordingClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: dismissQuestions))
    try await waitUntil { questionState(in: vm, requestId: "req-1") == .pending }

    await vm.turnInterrupt()
    try await waitUntil { questionState(in: vm, requestId: "req-1") == .expired }

    let accepted = await vm.respondToUserQuestion(
        requestId: "req-1",
        answers: ["デプロイ先は?": ["staging"]]
    )
    #expect(!accepted, "閉じたあとの回答は受理しない")
}
