import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class SuspendingInterruptClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var _interruptCount = 0
    private var interruptContinuations: [CheckedContinuation<Void, Never>] = []

    var interruptCount: Int {
        lock.withLock { _interruptCount }
    }

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        eventContinuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func close() async { eventContinuation.finish() }

    func interrupt() async throws {
        await withCheckedContinuation { continuation in
            lock.withLock {
                _interruptCount += 1
                interruptContinuations.append(continuation)
            }
        }
    }

    func yield(_ event: NormalizedChatEvent) {
        eventContinuation.yield(event)
    }

    func resumeAllInterrupts() {
        let continuations = lock.withLock {
            let pending = interruptContinuations
            interruptContinuations.removeAll()
            return pending
        }
        continuations.forEach { $0.resume() }
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
private func makeVM(client: SuspendingInterruptClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-stop-whitebox-test"
    )
}

@MainActor
private func seedRunningSubAgentAfterCompletedTurn(
    _ vm: ChatSessionViewModel,
    _ client: SuspendingInterruptClient
) async throws {
    client.yield(.turnStarted)
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "bg work"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil {
        vm.status == .idle && vm.subAgents.contains { $0.status == .running }
    }
}

@Test @MainActor
func repeatedSingleEscWhileInterruptPendingSendsOnlyOnce() async throws {
    let client = SuspendingInterruptClient()
    let vm = makeVM(client: client)
    try await seedRunningSubAgentAfterCompletedTurn(vm, client)

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    vm.handleEscapeKey(now: t0)
    try await waitUntil { client.interruptCount == 1 }

    vm.handleEscapeKey(now: t0.addingTimeInterval(2))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(client.interruptCount == 1)
    client.resumeAllInterrupts()
}

@Test @MainActor
func pendingInterruptCompletionDoesNotOverwriteNewTurnStatus() async throws {
    let client = SuspendingInterruptClient()
    let vm = makeVM(client: client)
    try await seedRunningSubAgentAfterCompletedTurn(vm, client)

    let interruptTask = Task { await vm.turnInterrupt() }
    try await waitUntil { client.interruptCount == 1 }

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.resumeAllInterrupts()
    await interruptTask.value

    #expect(vm.status == .running)
}

@Test @MainActor
func pendingInterruptDoesNotOverwriteLocallyStartedNewTurn() async throws {
    let client = SuspendingInterruptClient()
    let vm = makeVM(client: client)
    try await seedRunningSubAgentAfterCompletedTurn(vm, client)

    let interruptTask = Task { await vm.turnInterrupt() }
    try await waitUntil { client.interruptCount == 1 }

    try await vm.sendText("new turn", submit: true)
    #expect(vm.status == .running)

    client.resumeAllInterrupts()
    await interruptTask.value

    #expect(vm.status == .running)
}

@Test @MainActor
func interruptStartedAfterLocalSendStillConvergesWhenTurnStartedArrives() async throws {
    let client = SuspendingInterruptClient()
    let vm = makeVM(client: client)

    try await vm.sendText("new turn", submit: true)

    let interruptTask = Task { await vm.turnInterrupt() }
    try await waitUntil { client.interruptCount == 1 }

    // sendText 直後から status == .running のため、status では .turnStarted の
    // 処理完了を検知できない。rawEventLog への記録で処理済みを待つ（レビュー r4 指摘）。
    let previousEventCount = vm.rawEventLog.count
    client.yield(.turnStarted)
    try await waitUntil {
        vm.rawEventLog.dropFirst(previousEventCount).contains { $0.contains("turnStarted") }
    }

    client.resumeAllInterrupts()
    await interruptTask.value

    #expect(vm.status == .idle)
    #expect(!vm.subAgents.contains { $0.status == .running })
}
