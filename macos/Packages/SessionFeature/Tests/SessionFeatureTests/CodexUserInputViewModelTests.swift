// Codex の質問（tool/requestUserInput）を既存の質問カード経路へ配線する ViewModel の振る舞い。

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

@Suite("Codex user input: ViewModel")
struct CodexUserInputViewModelTests {
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

// MARK: - wire への決着（broker 経由）

private actor CodexUserInputWireResult {
    private var value: JSONValue?

    func set(_ value: JSONValue) {
        self.value = value
    }

    var current: JSONValue? { value }
}

private func waitForCodexUserInputWireResult(
    _ result: CodexUserInputWireResult,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async -> JSONValue? {
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanoseconds {
        if let value = await result.current { return value }
        try? await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
    return await result.current
}

@Test("Codex 質問だけを broker へ返し、未知の requestId は wire を決着させない")
@MainActor
func codexUserInputResponseRoutesOnlyKnownRequestIDsToBroker() async throws {
    let client = InterruptRecordingClient()
    let broker = ChatApprovalBroker()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-codex-userinput-whitebox"
    )
    try await withTerminatedViewModel(viewModel) {
        let request = ToolRequestUserInputRequest(
            threadId: "thread",
            turnId: "turn",
            itemId: "item",
            questions: [
                ToolRequestUserInputQuestion(
                    id: "choice",
                    header: "選択",
                    question: "どちらですか？",
                    options: nil
                )
            ]
        )
        let wireResult = CodexUserInputWireResult()
        let requestTask = Task {
            if let result = try? await broker.serverRequestHandler(.userInputRequest(request)) {
                await wireResult.set(result)
            }
        }
        do {
            let appeared = await waitUntil {
                viewModel.transcript.contains { item in
                    if case .userQuestion = item { return true }
                    return false
                }
            }
            #expect(appeared)

            #expect(await viewModel.respondToUserQuestion(requestId: "unknown", answers: [:]) == false)
            #expect(await waitForCodexUserInputWireResult(wireResult, timeoutNanoseconds: 100_000_000) == nil)

            let requestID = try #require(viewModel.transcript.compactMap { item -> String? in
                if case .userQuestion(_, let requestID, _, _, _, _) = item { return requestID }
                return nil
            }.first)

            #expect(await viewModel.respondToUserQuestion(requestId: requestID, answers: ["choice": ["A"]]))
            let result = try #require(await waitForCodexUserInputWireResult(wireResult))
            if let encodedAnswers = result["answers"]?["choice"]?["answers"],
               case .array(let values) = encodedAnswers
            {
                #expect(values.compactMap(\.stringValue) == ["A"])
            } else {
                Issue.record("Codex の回答が wire 形式で返っていない")
            }
            _ = await requestTask.value
        } catch {
            await viewModel.terminate()
            requestTask.cancel()
            _ = await requestTask.value
            throw error
        }
    }
}

@Test("terminate は保留中の Codex 質問を expired にして wire を空回答で決着させる")
@MainActor
func terminateExpiresPendingCodexUserInput() async throws {
    let client = InterruptRecordingClient()
    let broker = ChatApprovalBroker()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-codex-userinput-terminate"
    )
    try await withTerminatedViewModel(viewModel) {
        let request = ToolRequestUserInputRequest(
            threadId: "thread",
            turnId: "turn",
            itemId: "item",
            questions: [
                ToolRequestUserInputQuestion(
                    id: "choice",
                    header: "選択",
                    question: "どちらですか？",
                    options: nil
                )
            ]
        )
        let wireResult = CodexUserInputWireResult()
        let requestTask = Task {
            if let result = try? await broker.serverRequestHandler(.userInputRequest(request)) {
                await wireResult.set(result)
            }
        }
        do {
            #expect(await waitUntil {
                viewModel.transcript.contains { item in
                    if case .userQuestion = item { return true }
                    return false
                }
            })

            await viewModel.terminate()

            if case .userQuestion(_, _, _, _, let state, _) = viewModel.transcript.first {
                #expect(state == .expired)
            } else {
                Issue.record("Codex question card is missing")
            }

            let result = try #require(await waitForCodexUserInputWireResult(wireResult))
            if let answers = result["answers"], case .object(let entries) = answers {
                #expect(entries.isEmpty)
            } else {
                Issue.record("Codex の空回答が wire 形式で返っていない")
            }
            _ = await requestTask.value
        } catch {
            await viewModel.terminate()
            requestTask.cancel()
            _ = await requestTask.value
            throw error
        }
    }
}

@Test("ターン中断は保留中の Codex 質問を expired にして wire を空回答で決着させる")
@MainActor
func turnInterruptExpiresPendingCodexUserInput() async throws {
    let client = InterruptRecordingClient()
    let broker = ChatApprovalBroker()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-codex-userinput-interrupt"
    )
    try await withTerminatedViewModel(viewModel) {
        let request = ToolRequestUserInputRequest(
            threadId: "thread",
            turnId: "turn",
            itemId: "item",
            questions: [
                ToolRequestUserInputQuestion(
                    id: "choice",
                    header: "選択",
                    question: "どちらですか？",
                    options: nil
                )
            ]
        )
        let wireResult = CodexUserInputWireResult()
        let requestTask = Task {
            if let result = try? await broker.serverRequestHandler(.userInputRequest(request)) {
                await wireResult.set(result)
            }
        }
        do {
            #expect(await waitUntil {
                viewModel.transcript.contains { item in
                    if case .userQuestion = item { return true }
                    return false
                }
            })

            await viewModel.turnInterrupt()

            let result = await waitForCodexUserInputWireResult(wireResult, timeoutNanoseconds: 200_000_000)
            #expect(result != nil)
            if let result,
               let answers = result["answers"],
               case .object(let entries) = answers
            {
                #expect(entries.isEmpty)
            } else if result != nil {
                Issue.record("Codex の空回答が wire 形式で返っていない")
            }

            if case .userQuestion(_, _, _, _, let state, _) = viewModel.transcript.first {
                #expect(state == .expired)
            } else {
                Issue.record("Codex question card is missing")
            }
            _ = await requestTask.value
        }
    }
}
