import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// MARK: - Test doubles

final class EventYieldingStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeViewModel(client: EventYieldingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

// MARK: - appendDelta empty-delta guard

@Test @MainActor
func chatSessionViewModel_emptyAgentMessageDelta_doesNotCreateItemUntilNonEmptyDelta() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "agent-1", ""))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(!vm.transcript.contains { $0.id == "agent-1" })

    client.yield(.agentMessageDelta(itemId: "agent-1", "Hello"))
    try await waitUntil {
        vm.transcript.contains { item in
            if case .agentMessage(let id, let text, _) = item {
                return id == "agent-1" && text == "Hello"
            }
            return false
        }
    }
    let agentItems = vm.transcript.compactMap { item -> (String, String)? in
        if case .agentMessage(let id, let text, _) = item { return (id, text) }
        return nil
    }
    #expect(agentItems.count == 1)
    #expect(agentItems[0].0 == "agent-1")
    #expect(agentItems[0].1 == "Hello")
}

@Test @MainActor
func chatSessionViewModel_emptyReasoningDelta_doesNotCreateItemUntilNonEmptyDelta() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.reasoningDelta(itemId: "reason-1", ""))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(!vm.transcript.contains { $0.id == "reason-1" })

    client.yield(.reasoningDelta(itemId: "reason-1", "Thinking"))
    try await waitUntil {
        vm.transcript.contains { item in
            if case .reasoning(let id, let text, _) = item {
                return id == "reason-1" && text == "Thinking"
            }
            return false
        }
    }
    let reasoningItems = vm.transcript.compactMap { item -> (String, String)? in
        if case .reasoning(let id, let text, _) = item { return (id, text) }
        return nil
    }
    #expect(reasoningItems.count == 1)
    #expect(reasoningItems[0].0 == "reason-1")
    #expect(reasoningItems[0].1 == "Thinking")
}
