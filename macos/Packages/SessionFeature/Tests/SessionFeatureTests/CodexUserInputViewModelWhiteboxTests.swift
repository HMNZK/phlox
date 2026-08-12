import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private actor CodexUserInputWireResult {
    private var value: JSONValue?

    func set(_ value: JSONValue) {
        self.value = value
    }

    var current: JSONValue? { value }
}

private final class CodexUserInputViewModelClient: StructuredAgentClient, @unchecked Sendable {
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
}

@MainActor
private func waitForCodexUserInputViewModel(
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

@Test("Codex 質問だけを broker へ返し、未知の requestId は wire を決着させない")
@MainActor
func codexUserInputResponseRoutesOnlyKnownRequestIDsToBroker() async throws {
    let client = CodexUserInputViewModelClient()
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
            let appeared = await waitForCodexUserInputViewModel {
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
    let client = CodexUserInputViewModelClient()
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
            #expect(await waitForCodexUserInputViewModel {
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
    let client = CodexUserInputViewModelClient()
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
            #expect(await waitForCodexUserInputViewModel {
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
