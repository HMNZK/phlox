// 契約の正本: tasks/task-1.md — AskUserQuestion 到着時の attention（赤枠ラッチ＋通知）。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約:
//   - running 中に .userQuestionRequested を受けたら hasUnseenCompletion をラッチする
//     （SessionGridView の赤枠は hasUnseenCompletion が駆動するため、これが赤枠の契約）
//   - 同時に remoteSessionNotifier.approvalPending を 1 回だけ発火する（ローカル通知
//     SessionCompletionNotifier.notifyAwaitingInput と同経路。多重通知しない）
//   - markCompletionSeen() でラッチが解除される
//   - 質問の解決（.userQuestionResolved）は新たな通知・ラッチを発火しない

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class QuestionAttentionFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeViewModel(
    notifier: MockRemoteSessionNotifier? = nil
) -> (ChatSessionViewModel, QuestionAttentionFakeClient) {
    let client = QuestionAttentionFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-question-attention-test"
    )
    vm.remoteSessionNotifier = notifier
    return (vm, client)
}

private func question(_ text: String = "どの方式にしますか？") -> ChatUserQuestion {
    ChatUserQuestion(
        question: text,
        header: "方式",
        options: [ChatUserQuestionOption(label: "A案"), ChatUserQuestionOption(label: "B案")],
        multiSelect: false
    )
}

@Suite("Acceptance: AskUserQuestion の attention（task-1）")
struct AcceptanceUserQuestionAttentionTests {
    @Test @MainActor
    func running中の質問到着で未確認停止をラッチする() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        #expect(vm.hasUnseenCompletion == false)

        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.hasUnseenCompletion }

        #expect(vm.hasUnseenCompletion)
    }

    @Test @MainActor
    func 質問到着でリモート通知をちょうど1回発火する() async throws {
        let notifier = MockRemoteSessionNotifier()
        let (vm, client) = makeViewModel(notifier: notifier)
        vm.name = "Question Session"

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { notifier.approvalPendingCalls.count >= 1 }

        #expect(notifier.approvalPendingCalls.count == 1)
        #expect(notifier.approvalPendingCalls.first?.sessionName == "Question Session")
    }

    @Test @MainActor
    func markCompletionSeenでラッチが解除される() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.hasUnseenCompletion }

        vm.markCompletionSeen()

        #expect(vm.hasUnseenCompletion == false)
    }

    @Test @MainActor
    func 質問の解決は追加の通知もラッチもしない() async throws {
        let notifier = MockRemoteSessionNotifier()
        let (vm, client) = makeViewModel(notifier: notifier)

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { notifier.approvalPendingCalls.count >= 1 }
        vm.markCompletionSeen()

        client.yield(.userQuestionResolved(
            requestId: "q-1",
            outcome: .answered(answers: ["どの方式にしますか？": ["A案"]])
        ))
        try await waitUntil { vm.transcript.contains { item in
            if case .userQuestion(_, _, _, _, let state, _) = item { return state == .answered }
            return false
        } }

        #expect(notifier.approvalPendingCalls.count == 1)
        #expect(vm.hasUnseenCompletion == false)
    }
}
