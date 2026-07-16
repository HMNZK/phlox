import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// subagent-session-cpu run / task-1 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
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
