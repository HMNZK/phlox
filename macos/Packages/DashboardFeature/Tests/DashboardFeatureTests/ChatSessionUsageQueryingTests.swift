// task-3 契約テスト: ChatSessionViewModel.usageQuerying のキャスト契約。
// UsageQuerying に適合するクライアントでは非 nil、適合しないクライアントでは nil。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Test doubles

private final class UsageQueryingStructuredClient: StructuredAgentClient, UsageQuerying, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    let snapshot: AgentRateLimitsSnapshot

    init(snapshot: AgentRateLimitsSnapshot = AgentRateLimitsSnapshot(
        fiveHour: AgentRateLimitsSnapshot.Bucket(usedPercentage: 12, resetsAt: nil),
        sevenDay: AgentRateLimitsSnapshot.Bucket(usedPercentage: 3, resetsAt: nil),
        asOf: Date(timeIntervalSince1970: 1_500)
    )) {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
        self.snapshot = snapshot
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }

    func fetchRateLimits() async throws -> AgentRateLimitsSnapshot {
        snapshot
    }
}

// MARK: - Tests

@Suite("ChatSessionViewModel usageQuerying")
@MainActor
struct ChatSessionUsageQueryingTests {

    private func makeVM(client: any StructuredAgentClient) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
    }

    @Test func usageQuerying_returnsNonNilWhenClientConforms() async throws {
        let snapshot = AgentRateLimitsSnapshot(
            fiveHour: AgentRateLimitsSnapshot.Bucket(usedPercentage: 42, resetsAt: nil),
            sevenDay: nil,
            asOf: Date(timeIntervalSince1970: 2_000)
        )
        let client = UsageQueryingStructuredClient(snapshot: snapshot)
        let vm = makeVM(client: client)

        let querying = vm.usageQuerying
        #expect(querying != nil)

        let fetched = try await querying?.fetchRateLimits()
        #expect(fetched == snapshot)
    }

    @Test func usageQuerying_returnsNilWhenClientDoesNotConform() {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client: client)

        #expect(vm.usageQuerying == nil)
    }
}
