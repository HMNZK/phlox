import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-1 白箱: performChatEscape 経由で非フォーカス ESC フォールバックと同一の中止経路に乗ること。

private final class EscapeHandlingFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var _interruptCount = 0

    var interruptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _interruptCount
    }

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {
        recordInterrupt()
    }

    private nonisolated func recordInterrupt() {
        lock.lock()
        _interruptCount += 1
        lock.unlock()
    }
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

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
private func makeEscapeHandlingVM() -> (ChatSessionViewModel, EscapeHandlingFakeClient) {
    let client = EscapeHandlingFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-chat-escape-whitebox-test"
    )
    return (vm, client)
}

@Test @MainActor
func performChatEscapeDuringRunningTurnFiresInterrupt() async throws {
    let (vm, client) = makeEscapeHandlingVM()
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    #expect(vm.selectedSubAgentId == nil)
    #expect(vm.isHistoryPickerPresented == false)

    performChatEscape(vm)

    try await waitUntil { client.interruptCount == 1 }
    #expect(client.interruptCount == 1)
}

@Test @MainActor
func performChatEscapeClosesDrawerWithoutInterrupt() async throws {
    let (vm, client) = makeEscapeHandlingVM()
    client.yield(.turnStarted)
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "bg work"))
    try await waitUntil { vm.subAgents.count == 1 }
    vm.selectSubAgent(vm.subAgents[0].id)

    performChatEscape(vm)

    #expect(vm.selectedSubAgentId == nil)
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(client.interruptCount == 0)
}
