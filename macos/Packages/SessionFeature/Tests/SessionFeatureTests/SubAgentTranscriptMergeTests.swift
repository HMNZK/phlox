import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// 契約: `NormalizedChatEvent.subAgentActivity` は `itemId: String?` を運び、
// ChatSessionViewModel はサブエージェントの `.message`/`.reasoning` 断片を
// itemId 単位で 1 つの ChatItem にマージする（メイン transcript の appendDelta と同じ結合則）。
// itemId が nil の活動（tool 等）は従来どおり独立 item として積む。
// これが「断片ごとに新規 item が無限に積み増され、実行中ドロワーを開くと CPU 暴走する」
// 欠陥（docs/phase0.md 欠陥1）の修正契約である。

// MARK: - Fake client

private final class MergeFakeClient: StructuredAgentClient, @unchecked Sendable {
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

// MARK: - Helpers

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
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
private func makeChatVM() -> (ChatSessionViewModel, MergeFakeClient) {
    let client = MergeFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-merge-test"
    )
    return (vm, client)
}

private func agentMessageTexts(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .agentMessage(_, let text, _) = $0 { text } else { nil } }
}

private func reasoningTexts(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .reasoning(_, let text, _) = $0 { text } else { nil } }
}

private func commandOutputs(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .commandExecution(_, _, let output, _) = $0 { output } else { nil } }
}

// MARK: - Tests

@Test @MainActor
func subAgentMessageFragmentsWithSameItemIdMergeIntoOneItem() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: "Hello,"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: " "))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: "world"))

    try await waitUntil { agentMessageTexts(vm.subAgentTranscript(for: "tu1")) == ["Hello, world"] }
    #expect(agentMessageTexts(vm.subAgentTranscript(for: "tu1")) == ["Hello, world"])
    #expect(vm.subAgentTranscript(for: "tu1").count == 1)
}

@Test @MainActor
func subAgentFragmentsWithDifferentItemIdsStaySeparateItems() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: "first message"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m2:text", text: "second message"))

    try await waitUntil { agentMessageTexts(vm.subAgentTranscript(for: "tu1")).count == 2 }
    #expect(agentMessageTexts(vm.subAgentTranscript(for: "tu1")) == ["first message", "second message"])
}

@Test @MainActor
func subAgentReasoningFragmentsMergeSeparatelyFromMessages() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .reasoning, itemId: "m1:thinking", text: "think "))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .reasoning, itemId: "m1:thinking", text: "hard"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: "answer"))

    try await waitUntil {
        reasoningTexts(vm.subAgentTranscript(for: "tu1")) == ["think hard"]
            && agentMessageTexts(vm.subAgentTranscript(for: "tu1")) == ["answer"]
    }
    let transcript = vm.subAgentTranscript(for: "tu1")
    #expect(reasoningTexts(transcript) == ["think hard"])
    #expect(agentMessageTexts(transcript) == ["answer"])
    #expect(transcript.count == 2)
}

@Test @MainActor
func subAgentNilItemIdActivitiesRemainIndividualItems() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: nil, text: "Bash: ls"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: nil, text: "Read: foo.txt"))

    try await waitUntil { commandOutputs(vm.subAgentTranscript(for: "tu1")).count == 2 }
    #expect(commandOutputs(vm.subAgentTranscript(for: "tu1")) == ["Bash: ls", "Read: foo.txt"])
}

@Test @MainActor
func subAgentFragmentStreamDoesNotGrowItemCountUnbounded() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    for i in 0..<50 {
        client.yield(.subAgentActivity(toolUseId: "tu1", kind: .message, itemId: "m1:text", text: "chunk\(i) "))
    }

    try await waitUntil {
        agentMessageTexts(vm.subAgentTranscript(for: "tu1")).first?.contains("chunk49") == true
    }
    let transcript = vm.subAgentTranscript(for: "tu1")
    #expect(transcript.count == 1)
    let merged = try #require(agentMessageTexts(transcript).first)
    #expect(merged.hasPrefix("chunk0 chunk1 "))
    #expect(merged.contains("chunk49"))
}

@Test @MainActor
func subAgentSameItemIdButDifferentKindStaysSeparate() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu-whitebox-kind", subagentType: "general-purpose", description: "kind"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox-kind", kind: .reasoning, itemId: "msg-1", text: "think"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox-kind", kind: .message, itemId: "msg-1", text: "say"))

    try await waitUntil {
        reasoningTexts(vm.subAgentTranscript(for: "tu-whitebox-kind")) == ["think"]
            && agentMessageTexts(vm.subAgentTranscript(for: "tu-whitebox-kind")) == ["say"]
    }

    let transcript = vm.subAgentTranscript(for: "tu-whitebox-kind")
    #expect(reasoningTexts(transcript) == ["think"])
    #expect(agentMessageTexts(transcript) == ["say"])
    #expect(transcript.count == 2)
}

@Test @MainActor
func transcriptReplacementPreservesPendingSubAgentDelta() async throws {
    let client = MergeFakeClient()
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "history-subagent",
        preview: "history",
        firstUserAt: nil,
        lastModified: Date(),
        gitBranch: nil,
        fileURL: URL(fileURLWithPath: "/tmp/history-subagent.jsonl")
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-restore-whitebox",
        historyTranscriptLoader: { _ in [] }
    )

    client.yield(.subAgentActivity(
        toolUseId: "tu-preserve",
        kind: .message,
        itemId: "msg-preserve:text",
        text: "preserved"
    ))
    try await waitUntil { vm.hasPendingTranscriptStreamDeltasForTesting }
    await vm.startFromHistory(entry)

    try await waitUntil {
        agentMessageTexts(vm.subAgentTranscript(for: "tu-preserve")) == ["preserved"]
    }
    #expect(agentMessageTexts(vm.subAgentTranscript(for: "tu-preserve")) == ["preserved"])
    await client.close()
}

@Test @MainActor
func subAgentDeltaRefreshesRunningActivityTimestamp() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.subAgentActivity(
        toolUseId: "tu-live",
        kind: .message,
        itemId: "msg-live:text",
        text: "live"
    ))
    try await waitUntil { vm.lastOutputAt != nil }

    #expect(vm.lastOutputAt != nil)
    #expect(vm.lastRunningEventAtForTesting != nil)
    await client.close()
}

@Test @MainActor
func completedSubAgentClearsDedupTextCache() {
    let model = ChatSubAgentModel()
    model.appendSubAgentActivity(
        toolUseId: "tu-cache",
        kind: .message,
        itemId: "msg-cache:text",
        text: "本文"
    )
    #expect(model.dedupTextCacheCountForTesting == 1)

    model.completeSubAgent(
        toolUseId: "tu-cache",
        status: "completed",
        summary: "本文",
        outputFile: nil
    )

    #expect(model.dedupTextCacheCountForTesting == 0)
}

@Test @MainActor
func subAgentStreamDedupScansEachDirectDeltaOnce() {
    let model = ChatSubAgentModel()
    model.resetDedupScanMetricsForTesting()
    model.upsertSubAgent(
        toolUseId: "tu-performance",
        subagentType: "general-purpose",
        description: "scan",
        status: .running,
        summary: nil,
        outputFile: nil
    )

    let deltaCount = 5_000
    for _ in 0..<deltaCount {
        model.appendSubAgentActivities([ChatSubAgentModel.StreamActivity(
            toolUseId: "tu-performance",
            kind: .message,
            itemId: "m1:text",
            text: "x"
        )])
    }

    #expect(agentMessageTexts(model.transcript(for: "tu-performance")) == [String(repeating: "x", count: deltaCount)])
    #expect(model.dedupScanMetricsForTesting.callCount == deltaCount)
    #expect(model.dedupScanMetricsForTesting.characterCount == deltaCount)
}

@Test @MainActor
func repeatedWarningMessageReplacesItsExistingTranscriptItem() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.warning(message: "MCPサーバー「github」: connection refused"))
    client.yield(.warning(message: "MCPサーバー「github」: connection refused"))

    try await waitUntil {
        vm.transcript.contains { item in
            if case .error(_, let message, _) = item {
                return message.contains("connection refused")
            }
            return false
        }
    }

    let warnings = vm.transcript.compactMap { item -> String? in
        guard case .error(_, let message, _) = item,
              message.contains("connection refused") else { return nil }
        return message
    }
    #expect(warnings == ["MCPサーバー「github」: connection refused"])
}
