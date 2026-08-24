import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class WhiteboxMergeClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeWhiteboxChatVM() -> (ChatSessionViewModel, WhiteboxMergeClient) {
    let client = WhiteboxMergeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-merge-whitebox"
    )
    return (vm, client)
}

@MainActor
private func waitForWhiteboxMerge(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
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

private func whiteboxAgentTexts(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .agentMessage(_, let text, _) = $0 { text } else { nil } }
}

private func whiteboxReasoningTexts(_ items: [ChatItem]) -> [String] {
    items.compactMap { if case .reasoning(_, let text, _) = $0 { text } else { nil } }
}

@Test @MainActor
func whiteboxSameSubAgentItemIdAndKindMergesRawFragments() async throws {
    let (vm, client) = makeWhiteboxChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu-whitebox", subagentType: "general-purpose", description: "merge"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox", kind: .message, itemId: "msg-1:text", text: "Hello,"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox", kind: .message, itemId: "msg-1:text", text: " "))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox", kind: .message, itemId: "msg-1:text", text: "world"))

    try await waitForWhiteboxMerge {
        whiteboxAgentTexts(vm.subAgentTranscript(for: "tu-whitebox")) == ["Hello, world"]
    }

    let transcript = vm.subAgentTranscript(for: "tu-whitebox")
    #expect(whiteboxAgentTexts(transcript) == ["Hello, world"])
    #expect(transcript.count == 1)
}

@Test @MainActor
func whiteboxSameItemIdButDifferentKindStaysSeparate() async throws {
    let (vm, client) = makeWhiteboxChatVM()
    client.yield(.subAgentStarted(toolUseId: "tu-whitebox-kind", subagentType: "general-purpose", description: "kind"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox-kind", kind: .reasoning, itemId: "msg-1", text: "think"))
    client.yield(.subAgentActivity(toolUseId: "tu-whitebox-kind", kind: .message, itemId: "msg-1", text: "say"))

    try await waitForWhiteboxMerge {
        whiteboxReasoningTexts(vm.subAgentTranscript(for: "tu-whitebox-kind")) == ["think"]
            && whiteboxAgentTexts(vm.subAgentTranscript(for: "tu-whitebox-kind")) == ["say"]
    }

    let transcript = vm.subAgentTranscript(for: "tu-whitebox-kind")
    #expect(whiteboxReasoningTexts(transcript) == ["think"])
    #expect(whiteboxAgentTexts(transcript) == ["say"])
    #expect(transcript.count == 2)
}

@Test @MainActor
func transcriptReplacementPreservesPendingSubAgentDelta() async throws {
    let client = WhiteboxMergeClient()
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
    try await waitForWhiteboxMerge { vm.hasPendingTranscriptStreamDeltasForTesting }
    await vm.startFromHistory(entry)

    try await waitForWhiteboxMerge {
        whiteboxAgentTexts(vm.subAgentTranscript(for: "tu-preserve")) == ["preserved"]
    }
    #expect(whiteboxAgentTexts(vm.subAgentTranscript(for: "tu-preserve")) == ["preserved"])
    await client.close()
}

@Test @MainActor
func subAgentDeltaRefreshesRunningActivityTimestamp() async throws {
    let (vm, client) = makeWhiteboxChatVM()
    client.yield(.turnStarted)
    try await waitForWhiteboxMerge { vm.status == .running }

    client.yield(.subAgentActivity(
        toolUseId: "tu-live",
        kind: .message,
        itemId: "msg-live:text",
        text: "live"
    ))
    try await waitForWhiteboxMerge { vm.lastOutputAt != nil }

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

    #expect(whiteboxAgentTexts(model.transcript(for: "tu-performance")) == [String(repeating: "x", count: deltaCount)])
    #expect(model.dedupScanMetricsForTesting.callCount == deltaCount)
    #expect(model.dedupScanMetricsForTesting.characterCount == deltaCount)
}

@Test @MainActor
func repeatedWarningMessageReplacesItsExistingTranscriptItem() async throws {
    let (vm, client) = makeWhiteboxChatVM()
    client.yield(.warning(message: "MCPサーバー「github」: connection refused"))
    client.yield(.warning(message: "MCPサーバー「github」: connection refused"))

    try await waitForWhiteboxMerge {
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
