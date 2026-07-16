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
