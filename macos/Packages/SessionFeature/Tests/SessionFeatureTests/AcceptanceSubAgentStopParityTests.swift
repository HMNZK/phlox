import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// subagent-view-parity run / task-1 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: 「処理中」の正本は showsProcessingIndicator（status.running / backgroundTasks /
// サブエージェント running のいずれか）。
// 1. ターン完了後もサブエージェントが running の間、esc（handleEscapeKey の単発押下）は
//    turnInterrupt() を発火し client.interrupt() を呼ぶ（status == .idle でも不発にしない）。
// 2. turnInterrupt() はターン間（status == .idle）でも running サブエージェントを
//    非 running（failed）へ収束させ、showsProcessingIndicator を false に落とす
//    （turnInterrupted イベントが来ない経路でもローカル状態が収束する）。
// 3. 完全 idle（サブエージェントなし）の単発 esc は interrupt を発火しない（従来挙動の維持）。

// MARK: - Fake client

private final class StopFakeClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeChatVM() -> (ChatSessionViewModel, StopFakeClient) {
    let client = StopFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-stop-parity-test"
    )
    return (vm, client)
}

@MainActor
private func startBackgroundSubAgentTurn(_ client: StopFakeClient, _ vm: ChatSessionViewModel) async throws {
    client.yield(.turnStarted)
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "bg work"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil {
        vm.status == .idle && vm.subAgents.contains { $0.status == .running }
    }
}

// MARK: - Tests

@Test @MainActor
func turnCompletedWithRunningSubAgentKeepsProcessingIndicator() async throws {
    let (vm, client) = makeChatVM()
    try await startBackgroundSubAgentTurn(client, vm)
    #expect(vm.status == .idle)
    #expect(vm.showsProcessingIndicator)
}

@Test @MainActor
func escWhileSubAgentRunningAfterTurnCompletedFiresInterrupt() async throws {
    let (vm, client) = makeChatVM()
    try await startBackgroundSubAgentTurn(client, vm)

    vm.handleEscapeKey()

    try await waitUntil { client.interruptCount == 1 }
    #expect(client.interruptCount == 1)
    try await waitUntil { !vm.subAgents.contains { $0.status == .running } }
    #expect(!vm.subAgents.contains { $0.status == .running })
    #expect(vm.showsProcessingIndicator == false)
}

@Test @MainActor
func turnInterruptBetweenTurnsStopsRunningSubAgents() async throws {
    let (vm, client) = makeChatVM()
    try await startBackgroundSubAgentTurn(client, vm)

    await vm.turnInterrupt()

    #expect(client.interruptCount == 1)
    #expect(!vm.subAgents.contains { $0.status == .running })
    #expect(vm.showsProcessingIndicator == false)
    #expect(vm.status == .idle)
}

@Test @MainActor
func escWhenFullyIdleDoesNotInterrupt() async throws {
    let (vm, client) = makeChatVM()
    client.yield(.turnStarted)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    vm.handleEscapeKey()
    try await Task.sleep(nanoseconds: 150_000_000)

    #expect(client.interruptCount == 0)
}

@Test @MainActor
func subAgentCompletionDropsProcessingIndicator() async throws {
    let (vm, client) = makeChatVM()
    try await startBackgroundSubAgentTurn(client, vm)

    client.yield(.subAgentCompleted(toolUseId: "tu1", status: "completed", summary: "done", outputFile: nil))

    try await waitUntil { vm.showsProcessingIndicator == false }
    #expect(vm.showsProcessingIndicator == false)
    #expect(vm.subAgents.first?.status == .completed)
}
