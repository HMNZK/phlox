import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@MainActor
struct CompletionRuntimeParityAcceptanceTests {
    @Test("受け付け後に次のターンが完了した確認要求をruntime適用時に拒否する")
    func queuedAcknowledgementCannotClearANewerCompletion() async throws {
        let client = RuntimeCompletionClient()
        let owned = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
                                         approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
        await owned.restore(threadId: "runtime-parity-thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        var gate: CheckedContinuation<Void, Never>?
        do {
            try await completeTurn(1, model: owned, client: client)
            let firstToken = try #require(SessionNode.appServer(owned).completionToken)
            let projection = ChatSessionViewModel(projection: owned.makeRuntimeSnapshot()) { executionID, command in
                await withCheckedContinuation { gate = $0 }
                return try await owned.performRuntimeCommand(command, expectedExecutionID: executionID)
            }
            let acknowledging = Task { try await projection.markCompletionSeen(ifCurrent: firstToken) }
            try await waitUntil { gate != nil }

            try await completeTurn(2, model: owned, client: client)
            let secondToken = try #require(SessionNode.appServer(owned).completionToken)
            #expect(secondToken != firstToken)
            gate?.resume()
            gate = nil

            #expect(try await acknowledging.value == false)
            #expect(owned.hasUnseenCompletion)
            #expect(owned.completedTurnSeq == 2)

            let result = try await owned.performRuntimeCommand(.markCompletionSeenIfCurrent(secondToken),
                                                               expectedExecutionID: owned.executionID)
            guard case .bool(let accepted) = result else {
                Issue.record("確認要求のbool応答がありません")
                await owned.terminate()
                return
            }
            #expect(accepted)
            #expect(!owned.hasUnseenCompletion)
            await owned.terminate()
        } catch {
            gate?.resume()
            gate = nil
            await owned.terminate()
            throw error
        }
    }

    private func completeTurn(_ sequence: Int, model: ChatSessionViewModel, client: RuntimeCompletionClient) async throws {
        try await model.sendText("依頼\(sequence)", submit: true)
        client.continuation.yield(.turnStarted)
        client.continuation.yield(.turnCompleted(nativeSessionId: "runtime-parity-thread"))
        try await waitUntil { model.completedTurnSeq == sequence }
        try #require(model.hasUnseenCompletion)
    }

    private enum WaitError: Error { case timedOut }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor RuntimeCompletionClient: StructuredAgentClient {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async throws {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}
