// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — 下書きの単一の正本を ChatSessionViewModel.draft に移譲する
// （F バグ: シングル⇄グリッド切替のビュー再生成で View ローカル @State の下書きが消える）。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class DraftFakeClient: StructuredAgentClient, @unchecked Sendable {
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
}

@MainActor
private func makeDraftVM() -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: DraftFakeClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Test @MainActor
func composerDraft_persistsOnViewModel() {
    let vm = makeDraftVM()
    vm.draft = "書きかけのメッセージ"
    #expect(vm.draft == "書きかけのメッセージ")
}

@Test @MainActor
func composerDraft_consumeTrimsAndClearsDraft() {
    let vm = makeDraftVM()
    vm.draft = "  hello world \n"
    #expect(vm.consumeDraftForSend() == "hello world")
    #expect(vm.draft == "")
}

@Test @MainActor
func composerDraft_consumeWhitespaceOnlyReturnsNilAndKeepsDraft() {
    let vm = makeDraftVM()
    vm.draft = "   \n  "
    #expect(vm.consumeDraftForSend() == nil)
    #expect(vm.draft == "   \n  ")
}
