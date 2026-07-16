// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-5.md — 実行中の Thinking 表示に現在ターンの推論テキスト末尾（最大3行）を出す。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class ReasoningFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func makeReasoningVM(client: ReasoningFakeClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

// MARK: - 純関数 tail

@Test func reasoningPreview_tail_returnsLastLinesSkippingBlanks() {
    #expect(ReasoningPreview.tail("l1\nl2\nl3\nl4", maxLines: 3) == "l2\nl3\nl4")
    #expect(ReasoningPreview.tail("l1\n\n   \nl2\nl3\nl4", maxLines: 3) == "l2\nl3\nl4")
    #expect(ReasoningPreview.tail("only", maxLines: 3) == "only")
}

@Test func reasoningPreview_tail_emptyOrBlankReturnsEmpty() {
    #expect(ReasoningPreview.tail("", maxLines: 3) == "")
    #expect(ReasoningPreview.tail("  \n \n", maxLines: 3) == "")
}

// MARK: - ViewModel 統合

@Test @MainActor
func reasoningPreview_showsTailOfCurrentTurnReasoning_whileRunning_andClearsOnCompletion() async throws {
    let client = ReasoningFakeClient()
    let vm = makeReasoningVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await vm.sendText("質問です", submit: true)
    client.yield(.turnStarted)
    client.yield(.reasoningDelta(itemId: "r1", "alpha\nbeta\ngamma\ndelta"))

    try await waitUntil { vm.runningReasoningPreview != nil }
    #expect(vm.runningReasoningPreview == "beta\ngamma\ndelta")

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    #expect(vm.runningReasoningPreview == nil)
}

@Test @MainActor
func reasoningPreview_doesNotLeakPreviousTurnReasoning() async throws {
    let client = ReasoningFakeClient()
    let vm = makeReasoningVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    // ターン1: reasoning あり → 完了
    try await vm.sendText("最初の質問", submit: true)
    client.yield(.turnStarted)
    client.yield(.reasoningDelta(itemId: "r1", "old reasoning"))
    try await waitUntil { vm.runningReasoningPreview != nil }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    // ターン2: まだ reasoning が無い → 前ターンの内容を漏らさない
    try await vm.sendText("次の質問", submit: true)
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    #expect(vm.runningReasoningPreview == nil)
}
