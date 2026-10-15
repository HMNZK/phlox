import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@MainActor
struct ClaudeUsageNotificationViewModelTests {
    @Test func notificationDoesNotChangeConversation() async throws {
        let client = NotificationClient()
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
                                      approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp")
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        let status = vm.status
        let transcript = vm.transcript
        let sequence = vm.completedTurnSeq
        let cost = vm.lastTurnCostUSD
        var received: AgentRateLimitsSnapshot?
        vm.rateLimitsDidChange = { received = $0 }
        let snapshot = AgentRateLimitsSnapshot(fiveHour: .init(usedPercentage: 9, resetsAt: .distantFuture),
                                               sevenDay: .init(usedPercentage: 39, resetsAt: .distantFuture), asOf: .now)
        client.continuation.yield(.rateLimitsUpdated(snapshot))
        for _ in 0..<200 where received == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(received == snapshot)
        #expect(vm.status == status)
        #expect(vm.transcript == transcript)
        #expect(vm.completedTurnSeq == sequence)
        #expect(vm.lastTurnCostUSD == cost)
        await vm.terminate()
    }
}

private final class NotificationClient: StructuredAgentClient, Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async throws {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}
