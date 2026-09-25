import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// C1: 再起動して復元しても、返信の下のトークン内訳・「N分前に応答」・サブエージェント（出力ファイルの場所）が残る。

private final class DisplayStateFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func displayStateVM(id: SessionID, store: any TranscriptStore) -> (ChatSessionViewModel, DisplayStateFakeClient) {
    let client = DisplayStateFakeClient()
    let vm = ChatSessionViewModel(
        id: id,
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-display-state",
        transcriptStore: store
    )
    return (vm, client)
}

@Test @MainActor
func chatDisplayState_survivesRestore() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "display-state-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileTranscriptStore(directoryURL: dir)
    let sessionID = SessionID()
    let usage = TurnUsage(
        costUSD: 0.02,
        inputTokens: 1200,
        outputTokens: 300,
        cacheReadTokens: nil,
        cacheCreationTokens: nil,
        contextUsedTokens: 27_400,
        contextWindowTokens: 200_000
    )

    let (first, client) = displayStateVM(id: sessionID, store: store)
    await first.restore(threadId: "native", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
    client.yield(.turnStarted)
    client.yield(.agentMessageDelta(itemId: "a1", "調べました"))
    client.yield(.subAgentStarted(toolUseId: "t1", subagentType: "Explore", description: "探す"))
    client.yield(.subAgentCompleted(toolUseId: "t1", status: "completed", summary: "見つけた", outputFile: "/tmp/agent-t1.jsonl"))
    client.yield(.turnUsage(usage))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { first.lastTurnCompletedAt != nil && !first.turnUsageByItemID.isEmpty }
    await first.flushTranscriptNow()

    let (restored, _) = displayStateVM(id: sessionID, store: store)
    await restored.restore(threadId: "native", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))

    #expect(restored.turnUsageByItemID == first.turnUsageByItemID)
    #expect(restored.lastTurnCompletedAt == first.lastTurnCompletedAt)
    #expect(restored.subAgents.map(\.outputFile) == ["/tmp/agent-t1.jsonl"])
    #expect(restored.subAgents.map(\.status) == [.completed])
}

@Test @MainActor
func chatDisplayState_runningSubAgentIsRestoredAsFailed() async throws {
    let sessionID = SessionID()
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "display-state-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileTranscriptStore(directoryURL: dir)
    try await store.saveDisplayState(
        ChatDisplayState(
            turnUsageByItemID: [:],
            lastTurnCompletedAt: nil,
            subAgents: [SubAgentRef(id: "t1", subagentType: "Explore", description: "探す", status: .running, startedAt: .now)]
        ),
        for: sessionID
    )

    let (restored, _) = displayStateVM(id: sessionID, store: store)
    await restored.restore(threadId: "native", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))

    #expect(restored.subAgents.map(\.status) == [.failed])
}
