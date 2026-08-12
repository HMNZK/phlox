// 契約の正本: tasks/task-4.md — Codex の質問を既存の質問カード経路へ配線する。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。

import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private final class InterruptRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var interruptCount = 0
    private(set) var respondCount = 0

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws { interruptCount += 1 }
    func close() async { continuation.finish() }

    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async {
        respondCount += 1
    }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @escaping () -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
    return true
}

@MainActor
private func makeViewModel() -> (ChatSessionViewModel, InterruptRecordingClient, ChatApprovalBroker) {
    let client = InterruptRecordingClient()
    let broker = ChatApprovalBroker()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-codex-userinput-test"
    )
    return (vm, client, broker)
}

@MainActor
private func withTerminatedViewModel<T>(
    _ viewModel: ChatSessionViewModel,
    operation: () async throws -> T
) async throws -> T {
    do {
        let result = try await operation()
        await viewModel.terminate()
        return result
    } catch {
        await viewModel.terminate()
        throw error
    }
}

private func codexRequest(ids: [String] = ["q1"]) -> ToolRequestUserInputRequest {
    ToolRequestUserInputRequest(
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: ids.map { id in
            ToolRequestUserInputQuestion(
                id: id,
                header: "ヘッダ-\(id)",
                question: "質問-\(id)",
                options: [ToolRequestUserInputOption(label: "A案", description: "説明A")]
            )
        }
    )
}

/// transcript から質問カードを1件取り出す。
@MainActor
private func questionCard(
    _ vm: ChatSessionViewModel
) -> (requestId: String, questions: [ChatUserQuestion], state: ChatUserQuestionState)? {
    for item in vm.transcript {
        if case .userQuestion(_, let requestId, let questions, _, let state, _) = item {
            return (requestId, questions, state)
        }
    }
    return nil
}

@Suite("Acceptance: Codex 質問の ViewModel 配線（task-4）")
struct AcceptanceCodexUserInputViewModelTests {
    @Test @MainActor
    func 質問が届くと質問カードが出て入力待ちになる() async throws {
        let (vm, client, broker) = makeViewModel()
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let handler = broker.serverRequestHandler
            let requestTask = Task { _ = try? await handler(.userInputRequest(codexRequest())) }
            do {
                let appeared = await waitUntil { questionCard(vm) != nil }
                #expect(appeared, "Codex の質問が質問カードとして transcript に出ること")

                let card = try #require(questionCard(vm))
                #expect(card.state == .pending)
                #expect(card.questions.count == 1)
                #expect(card.questions.first?.id == "q1")
                #expect(card.questions.first?.question == "質問-q1")
                #expect(card.questions.first?.options.first?.label == "A案")

                #expect(vm.status == .awaitingUserQuestion, "質問中は入力待ち状態にすること")
                #expect(vm.pendingApprovals.isEmpty, "承認バナーとして出してはならない")
                await vm.terminate()
                _ = await requestTask.value
            } catch {
                await vm.terminate()
                requestTask.cancel()
                _ = await requestTask.value
                throw error
            }
        }
    }

    @Test @MainActor
    func 回答するとカードがansweredになりrunningへ戻る() async throws {
        let (vm, client, broker) = makeViewModel()
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let handler = broker.serverRequestHandler
            let requestTask = Task { _ = try? await handler(.userInputRequest(codexRequest())) }
            do {
                _ = await waitUntil { questionCard(vm) != nil }

                let card = try #require(questionCard(vm))
                let accepted = await vm.respondToUserQuestion(requestId: card.requestId, answers: ["q1": ["A案"]])
                #expect(accepted)

                let answered = await waitUntil { questionCard(vm)?.state == .answered }
                #expect(answered)
                #expect(vm.status == .running)
                _ = await requestTask.value
            } catch {
                await vm.terminate()
                requestTask.cancel()
                _ = await requestTask.value
                throw error
            }
        }
    }

    @Test @MainActor
    func 拒否するとターンを中断する() async throws {
        let (vm, client, broker) = makeViewModel()
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let handler = broker.serverRequestHandler
            let requestTask = Task { _ = try? await handler(.userInputRequest(codexRequest())) }
            do {
                _ = await waitUntil { questionCard(vm) != nil }

                let card = try #require(questionCard(vm))
                let declined = await vm.declineUserQuestion(requestId: card.requestId)
                #expect(declined, "拒否は受理されること")

                let interrupted = await waitUntil { client.interruptCount >= 1 }
                #expect(interrupted, "拒否はターンを中断すること（ゲート①の決定 D4）")
                _ = await requestTask.value
            } catch {
                await vm.terminate()
                requestTask.cancel()
                _ = await requestTask.value
                throw error
            }
        }
    }

    @Test @MainActor
    func Claude経路の質問は従来どおり動く_非回帰() async throws {
        let (vm, client, _) = makeViewModel()
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let claudeQuestion = ChatUserQuestion(
                question: "どの方式にしますか？",
                header: "方式",
                options: [ChatUserQuestionOption(label: "A案")],
                multiSelect: false
            )
            client.yield(.userQuestionRequested(requestId: "q-claude", questions: [claudeQuestion]))
            _ = await waitUntil { vm.status == .awaitingUserQuestion }

            let card = try #require(questionCard(vm))
            #expect(card.requestId == "q-claude")
            #expect(card.questions.first?.id == nil, "Claude 経路は id を持たない（挙動不変）")

            let accepted = await vm.respondToUserQuestion(
                requestId: "q-claude",
                answers: ["どの方式にしますか？": ["A案"]]
            )
            #expect(accepted)
            #expect(client.respondCount == 1, "Claude の質問は従来どおり client へ返送すること")
        }
    }
}
