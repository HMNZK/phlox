// 契約の正本: tasks/task-1.md — AskUserQuestion 中は「入力待ち」状態（.awaitingUserQuestion）にする。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約（ADR 0107 を supersede する新挙動）:
//   - running 中に .userQuestionRequested → status == .awaitingUserQuestion（「実行中」をやめ停止状態にする）
//   - 遷移により hasUnseenCompletion がラッチされる（latchesUnseenAttentionOnEntry 経由）
//   - .userQuestionResolved(.answered) → status == .running（ターン継続）
//   - .turnInterrupted（質問保留中）→ status == .idle（既存の失効経路を壊さない）
//   - 通知（remoteSessionNotifier.approvalPending）は従来どおりちょうど1回

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class StatusFakeClient: StructuredAgentClient, @unchecked Sendable {
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
) -> (ChatSessionViewModel, StatusFakeClient) {
    let client = StatusFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-question-status-test"
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

@Suite("Acceptance: AskUserQuestion 中の入力待ち状態（ask-question-ux task-1）")
struct AcceptanceUserQuestionStatusTests {
    @Test @MainActor
    func 質問到着でawaitingUserQuestionへ遷移しラッチされる() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.status == .awaitingUserQuestion }

        #expect(vm.status == .awaitingUserQuestion)
        #expect(vm.hasUnseenCompletion)
    }

    @Test @MainActor
    func 回答決着でrunningへ復帰する() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.status == .awaitingUserQuestion }

        client.yield(.userQuestionResolved(
            requestId: "q-1",
            outcome: .answered(answers: ["どの方式にしますか？": ["A案"]])
        ))
        try await waitUntil { vm.status == .running }

        #expect(vm.status == .running)
    }

    @Test @MainActor
    func 質問保留中のturnInterruptedはidleへ戻す() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.status == .awaitingUserQuestion }

        client.yield(.turnInterrupted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }

        #expect(vm.status == .idle)
    }

    @Test @MainActor
    func 通知は従来どおりちょうど1回() async throws {
        let notifier = MockRemoteSessionNotifier()
        let (vm, client) = makeViewModel(notifier: notifier)
        vm.name = "Question Session"

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { notifier.approvalPendingCalls.count >= 1 }

        #expect(notifier.approvalPendingCalls.count == 1)
    }
}

@Suite("Acceptance: SessionStatus.awaitingUserQuestion の属性（ask-question-ux task-1）")
struct AcceptanceAwaitingUserQuestionAttributeTests {
    @Test func 入場でattentionをラッチする() {
        #expect(SessionStatus.awaitingUserQuestion.latchesUnseenAttentionOnEntry)
    }
}
