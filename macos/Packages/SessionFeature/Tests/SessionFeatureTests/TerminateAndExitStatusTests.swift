import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// ADR 0222: 閉じた後・終了表示の後に、遅れて戻った停止や送信失敗が status を書き換えない。

private struct TurnStartFailed: Error {}

/// turnStart と interrupt を途中で止められるクライアント。
private final class GatedClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var pendingTurnStart: CheckedContinuation<Void, Error>?
    private var pendingInterrupt: CheckedContinuation<Void, Never>?
    private var gatesTurnStart = false

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    var turnStartEntered: Bool { lock.withLock { pendingTurnStart != nil } }
    var interruptEntered: Bool { lock.withLock { pendingInterrupt != nil } }
    func gateNextTurnStart() { lock.withLock { gatesTurnStart = true } }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        guard lock.withLock({ gatesTurnStart }) else { return }
        try await withCheckedThrowingContinuation { c in
            lock.withLock { gatesTurnStart = false; pendingTurnStart = c }
        }
    }
    func failTurnStart() {
        lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { pendingTurnStart = nil }
            return pendingTurnStart
        }?.resume(throwing: TurnStartFailed())
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {
        await withCheckedContinuation { c in lock.withLock { pendingInterrupt = c } }
    }
    func releaseInterrupt() {
        lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { pendingInterrupt = nil }
            return pendingInterrupt
        }?.resume()
    }
    func close() async { continuation.finish() }
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func makeVM(_ client: GatedClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-terminate-exit-status-test"
    )
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    #expect(condition())
}

@Test @MainActor
func interruptReturningAfterTerminateKeepsCompleted() async throws {
    let client = GatedClient()
    let vm = makeVM(client)
    try await vm.sendText("hello", submit: true)
    #expect(vm.status == .running)

    let interrupt = Task { await vm.turnInterrupt() }
    try await waitUntil { client.interruptEntered }
    await vm.terminate()
    #expect(vm.status == .completed(exitCode: 0))

    client.releaseInterrupt()
    await interrupt.value
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func sendFailingAfterTerminateKeepsCompleted() async throws {
    let client = GatedClient()
    let vm = makeVM(client)
    client.gateNextTurnStart()
    let send = Task { try await vm.sendText("hello", submit: true) }
    try await waitUntil { client.turnStartEntered }
    await vm.terminate()
    #expect(vm.status == .completed(exitCode: 0))

    client.failTurnStart()
    _ = try? await send.value
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func sendFailingAfterProcessExitKeepsTheExitError() async throws {
    let client = GatedClient()
    let vm = makeVM(client)
    client.gateNextTurnStart()
    let send = Task { try await vm.sendText("hello", submit: true) }
    try await waitUntil { client.turnStartEntered }

    client.yield(.processExited(exitCode: 1))
    try await waitUntil { vm.processExit != nil && vm.status != .running }
    let exitStatus = vm.status

    client.failTurnStart()
    _ = try? await send.value
    #expect(vm.status == exitStatus)
    #expect(vm.status != .idle)
}

@Test @MainActor
func turnCompletedHandledWhileClosingKeepsTheSessionIdAndEndsCompleted() async throws {
    let client = GatedClient()
    let vm = makeVM(client)
    try await vm.sendText("hello", submit: true)

    // 閉じ始めた時点で受信ループへ渡っていた完了通知。状態は動かさず、会話 ID は残す。
    client.yield(.turnCompleted(nativeSessionId: "closing-session"))
    await vm.terminate()

    #expect(vm.status == .completed(exitCode: 0))
    #expect(vm.chatNativeSessionId == "closing-session")
}
