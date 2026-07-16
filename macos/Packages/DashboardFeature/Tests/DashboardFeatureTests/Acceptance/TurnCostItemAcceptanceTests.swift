// task-6 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-6.md — ターン完了時に .turnCost アイテムを transcript 末尾へ追加する。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class CostFakeClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeCostVM(client: CostFakeClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Test @MainActor
func turnCostItem_appendedAtTurnEndWhenUsageHasCost() async throws {
    let client = CostFakeClient()
    let vm = makeCostVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await vm.sendText("質問です", submit: true)
    client.yield(.agentMessageDelta(itemId: "a1", "応答"))
    client.yield(.turnUsage(TurnUsage(costUSD: 0.0123)))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 1 }

    guard case .turnCost(_, let costUSD, _) = vm.transcript.last else {
        Issue.record("transcript 末尾が .turnCost でない: \(String(describing: vm.transcript.last))")
        return
    }
    #expect(costUSD == 0.0123)
}

@Test @MainActor
func turnCostItem_notAppendedWhenTurnHasNoUsage() async throws {
    let client = CostFakeClient()
    let vm = makeCostVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await vm.sendText("質問です", submit: true)
    client.yield(.agentMessageDelta(itemId: "a1", "応答"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 1 }

    let hasTurnCost = vm.transcript.contains { item in
        if case .turnCost = item { return true }
        return false
    }
    #expect(!hasTurnCost)
}

@Test @MainActor
func turnCostItem_notAppendedTwiceAcrossTurns_usesEachTurnsOwnCost() async throws {
    let client = CostFakeClient()
    let vm = makeCostVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    // ターン1: コストあり
    try await vm.sendText("最初", submit: true)
    client.yield(.turnUsage(TurnUsage(costUSD: 0.5)))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 1 }

    // ターン2: コストなし → 前ターンのコストを再利用して追加してはならない
    try await vm.sendText("次", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.completedTurnSeq == 2 }

    let turnCostCount = vm.transcript.filter { item in
        if case .turnCost = item { return true }
        return false
    }.count
    #expect(turnCostCount == 1)
}

@Test func turnCostItem_codableRoundTrip_andLegacyDecodeStillWorks() throws {
    let item = ChatItem.turnCost(id: "cost-1", costUSD: 1.25, timestamp: Date(timeIntervalSince1970: 1_000))
    let data = try JSONEncoder().encode([item])
    let decoded = try JSONDecoder().decode([ChatItem].self, from: data)
    #expect(decoded == [item])

    // 旧形式（turnCost を知らないデータ）の decode が壊れない
    let legacy = #"[{"userMessage":{"id":"u1","text":"こんにちは","timestamp":0}}]"#
    let legacyDecoded = try JSONDecoder().decode([ChatItem].self, from: Data(legacy.utf8))
    #expect(legacyDecoded.count == 1)
}
