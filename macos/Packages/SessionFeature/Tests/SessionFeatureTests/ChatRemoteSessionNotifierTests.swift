import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// MARK: - Fake StructuredAgentClient（イベントを任意に yield する）

private final class FakeStructuredAgentClient: StructuredAgentClient, @unchecked Sendable {
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
    timeoutNanoseconds: UInt64 = 1_500_000_000,
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
private func makeChatSessionViewModel(
    sessionID: SessionID = SessionID(),
    remoteSessionNotifier: (any RemoteSessionNotifier)? = nil
) -> (ChatSessionViewModel, FakeStructuredAgentClient) {
    let client = FakeStructuredAgentClient()
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-chat-notify-test"
    )
    vm.remoteSessionNotifier = remoteSessionNotifier
    return (vm, client)
}

// MARK: - Tests

@Test @MainActor
func chatRemoteNotifier_turnCompletedWhileRunning_firesSessionCompletedOnce() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeChatSessionViewModel(
        sessionID: sessionID,
        remoteSessionNotifier: notifier
    )
    vm.name = "Chat Session"

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
    #expect(notifier.sessionCompletedCalls[0].sessionId == sessionID.description)
    #expect(notifier.sessionCompletedCalls[0].sessionName == "Chat Session")
    #expect(notifier.approvalPendingCalls.isEmpty)
}

@Test @MainActor
func chatRemoteNotifier_turnInterrupted_doesNotFireSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeChatSessionViewModel(remoteSessionNotifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func chatRemoteNotifier_turnCompletedWithoutRunning_doesNotFireSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeChatSessionViewModel(remoteSessionNotifier: notifier)

    // 復元リプレイ等で running を経ずに turnCompleted が届いた場合は通知しない。
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func chatRemoteNotifier_enterAwaitingApproval_firesApprovalPendingOnceWhileAwaiting() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeChatSessionViewModel(
        sessionID: sessionID,
        remoteSessionNotifier: notifier
    )
    vm.name = "Chat Session"

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve command?")
    #expect(notifier.approvalPendingCalls.count == 1)
    #expect(notifier.approvalPendingCalls[0].sessionId == sessionID.description)
    #expect(notifier.approvalPendingCalls[0].sessionName == "Chat Session")

    // 既に承認待ちの間に届いた追加の承認要求では再通知しない。
    vm.enterAwaitingApproval(prompt: "another approval?")
    #expect(notifier.approvalPendingCalls.count == 1)
    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func chatRemoteNotifier_completionAfterApprovalResumed_firesSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeChatSessionViewModel(remoteSessionNotifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve?")
    #expect(notifier.approvalPendingCalls.count == 1)

    // 承認後にターンが再開して完了した場合は完了通知が出る。
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}
