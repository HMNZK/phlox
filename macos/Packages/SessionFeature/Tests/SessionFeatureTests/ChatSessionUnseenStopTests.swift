import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// チャット（app-server）型セッションの「未確認の停止」ラッチ挙動。
// PTY 型は SessionViewModelTests が network、ここでは chat 側の status.didSet 経由の
// ラッチ・解除・SessionNode 委譲を検証する。

private final class UnseenStopFakeClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeChatViewModel() -> (ChatSessionViewModel, UnseenStopFakeClient) {
    let client = UnseenStopFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-chat-unseen-test"
    )
    return (vm, client)
}

@Test @MainActor
func chatSession_turnCompletedWhileRunning_latchesUnseenStop() async throws {
    let (vm, client) = makeChatViewModel()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    #expect(vm.hasUnseenCompletion == false)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(vm.hasUnseenCompletion)
}

@Test @MainActor
func chatSession_markCompletionSeen_clearsUnseenStop() async throws {
    let (vm, client) = makeChatViewModel()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.hasUnseenCompletion }

    vm.markCompletionSeen()

    #expect(vm.hasUnseenCompletion == false)
}

@Test @MainActor
func chatSession_enteringAwaitingApproval_latchesUnseenStop() {
    let (vm, _) = makeChatViewModel()
    #expect(vm.hasUnseenCompletion == false)

    vm.enterAwaitingApproval(prompt: "Approve tool use?")

    #expect(vm.status == .awaitingApproval(prompt: "Approve tool use?"))
    #expect(vm.hasUnseenCompletion)
}

@Test @MainActor
func sessionNode_appServer_exposesUnseenStopAndClearsOnMarkSeen() {
    let (vm, _) = makeChatViewModel()
    vm.enterAwaitingApproval(prompt: "Approve?")
    let node = SessionNode.appServer(vm)

    #expect(node.hasUnseenCompletion)

    node.markCompletionSeen()

    #expect(node.hasUnseenCompletion == false)
}
