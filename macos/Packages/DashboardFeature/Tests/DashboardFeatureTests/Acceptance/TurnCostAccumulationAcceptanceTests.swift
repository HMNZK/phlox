// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — `.turnUsage` 受信で lastTurnUsage / lastTurnCostUSD を更新し、
// sessionTotalCostUSD にターンコストを累積する。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class UsageFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func makeUsageVM(client: UsageFakeClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Test @MainActor
func turnCost_accumulatesPerTurnAndSessionTotal() async throws {
    let client = UsageFakeClient()
    let vm = makeUsageVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let firstUsage = TurnUsage(costUSD: 0.5, inputTokens: 10, outputTokens: 20)
    client.yield(.turnUsage(firstUsage))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 1 }

    #expect(vm.lastTurnUsage == firstUsage)
    #expect(vm.lastTurnCostUSD == 0.5)
    #expect(vm.sessionTotalCostUSD == 0.5)

    client.yield(.turnUsage(TurnUsage(costUSD: 0.25)))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 2 }

    #expect(vm.lastTurnCostUSD == 0.25)
    #expect(vm.sessionTotalCostUSD == 0.75)
}

@Test @MainActor
func turnCost_turnWithoutUsage_keepsSessionTotalAndClearsNothing() async throws {
    let client = UsageFakeClient()
    let vm = makeUsageVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.turnUsage(TurnUsage(costUSD: 0.5)))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.sessionTotalCostUSD == 0.5)

    // usage の無いターン: 累計は変わらない（nil コスト加算で 0 加算になっても NaN にならない）
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 2 }
    #expect(vm.sessionTotalCostUSD == 0.5)
}
