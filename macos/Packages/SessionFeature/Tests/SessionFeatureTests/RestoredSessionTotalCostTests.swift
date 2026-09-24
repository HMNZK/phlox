import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

// 07 I1: 会話を復元したセッションでも、インスペクタの総コストが出る
// （ライブで受け取った使用量だけを足していたため「—」になっていた）。
// 総コストは保存した値を使う。保存が無い以前の会話は、ターンのコストに Claude の累計が入っているので最後の値が総額。

private final class IdleClient: StructuredAgentClient, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent> { _ in }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}

private struct StoredTranscript: TranscriptStore {
    let items: [ChatItem]
    var saved: SessionTotalCost?
    func loadSessionTotalCost(for sessionID: SessionID) async throws -> SessionTotalCost? { saved }
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { items }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {}
}

private let at = Date(timeIntervalSince1970: 1_700_000_000)
private let legacyItems: [ChatItem] = [
    .userMessage(id: "u1", text: "一つ目", timestamp: at, attachments: []),
    .agentMessage(id: "a1", text: "はい", timestamp: at),
    .turnCost(id: "c1", costUSD: 0.5, timestamp: at),
    .userMessage(id: "u2", text: "二つ目", timestamp: at, attachments: []),
    .agentMessage(id: "a2", text: "はい", timestamp: at),
    .turnCost(id: "c2", costUSD: 1.25, timestamp: at),
    .agentMessage(id: "a3", text: "費用なしの応答", timestamp: at),
]

@MainActor
private func restoredTotal(_ store: StoredTranscript) async -> Double {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: IdleClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-restored-cost",
        transcriptStore: store
    )
    await vm.restore(threadId: "thread-1", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    return vm.sessionTotalCostUSD
}

@MainActor
@Test func restoredSessionUsesSavedTotalCost() async {
    let total = await restoredTotal(StoredTranscript(items: legacyItems, saved: SessionTotalCost(totalUSD: 3.5, lastReportedUSD: 3.5)))

    #expect(total == 3.5)
}

@MainActor
@Test func restoredSessionWithoutSavedTotalUsesLastCumulativeTurnCost() async {
    let total = await restoredTotal(StoredTranscript(items: legacyItems, saved: nil))

    #expect(total == 1.25)
}

// Claude の total_cost_usd はセッションの累計（再開前の分も含む）。ターンのコストは直前の累計との差にする。

private final class YieldingClient: StructuredAgentClient, @unchecked Sendable {
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
    func finishTurn(reportedTotal: Double) {
        continuation.yield(.turnUsage(TurnUsage(costUSD: reportedTotal)))
        continuation.yield(.turnCompleted(nativeSessionId: nil))
    }
}

@MainActor
private func claudeViewModel(_ client: YieldingClient, store: StoredTranscript) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-restored-cost",
        transcriptStore: store
    )
}

@MainActor
private func waitForTurns(_ vm: ChatSessionViewModel, _ count: Int) async {
    for _ in 0..<200 where vm.completedTurnSeq < count {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
@Test func claudeCumulativeCostBecomesPerTurnCost() async throws {
    let client = YieldingClient()
    let vm = claudeViewModel(client, store: StoredTranscript(items: [], saved: nil))
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.finishTurn(reportedTotal: 0.5)
    client.finishTurn(reportedTotal: 0.75)
    await waitForTurns(vm, 2)

    #expect(vm.lastTurnCostUSD == 0.25)
    #expect(vm.sessionTotalCostUSD == 0.75)
}

@MainActor
@Test func resumedClaudeSessionCountsOnlyTheNewTurn() async {
    let client = YieldingClient()
    let vm = claudeViewModel(client, store: StoredTranscript(items: legacyItems, saved: SessionTotalCost(totalUSD: 2.5, lastReportedUSD: 2.5)))
    await vm.restore(threadId: "thread-1", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    // 再開した CLI は再開前の 2.5 を含めた累計を送る。
    client.finishTurn(reportedTotal: 3.25)
    await waitForTurns(vm, 1)

    #expect(vm.lastTurnCostUSD == 0.75)
    #expect(vm.sessionTotalCostUSD == 3.25)
}

// 取り消しで会話がリセットされると累計は 0 から数え直すので、総コストと最後の累計は別に保存して復元する。

@MainActor
@Test func restoredBaselineIsTheLastReportedCumulativeNotTheTotal() async {
    let client = YieldingClient()
    let vm = claudeViewModel(client, store: StoredTranscript(items: legacyItems, saved: SessionTotalCost(totalUSD: 2.7, lastReportedUSD: 0.2)))
    await vm.restore(threadId: "thread-1", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.finishTurn(reportedTotal: 0.25)
    await waitForTurns(vm, 1)

    #expect(abs((vm.lastTurnCostUSD ?? -1) - 0.05) < 1e-9)
    #expect(abs(vm.sessionTotalCostUSD - 2.75) < 1e-9)
}

@MainActor
@Test func revertStartsTheCumulativeFromZero() async {
    let client = YieldingClient()
    let vm = claudeViewModel(client, store: StoredTranscript(items: legacyItems, saved: SessionTotalCost(totalUSD: 0.1, lastReportedUSD: 0.1)))
    await vm.restore(threadId: "thread-1", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    _ = await vm.revert(toUserMessageID: "u2")
    // 新しい会話の最初の累計 0.2 は、取り消し前の 0.1 より大きくてもまるごと 1 ターン分。
    client.finishTurn(reportedTotal: 0.2)
    await waitForTurns(vm, 1)

    #expect(vm.lastTurnCostUSD == 0.2)
    #expect(abs(vm.sessionTotalCostUSD - 0.3) < 1e-9)
}

// 履歴（CLI の JSONL）から再開したときはコストの記録が無く、再開前の累計がわからない。
// 最初に届いた累計をそのまま総コストにし、そのターンのコストは出さない（累計をターンのコストと見せない）。

@MainActor
@Test func resumingFromHistoryUsesTheFirstCumulativeAsTheTotal() async {
    let client = YieldingClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-restored-cost",
        historyTranscriptLoader: { _ in [.userMessage(id: "h1", text: "前の会話", timestamp: at, attachments: [])] }
    )
    await vm.startFromHistory(ClaudeSessionHistoryEntry(
        sessionID: "history-1",
        preview: "前の会話",
        firstUserAt: at,
        lastModified: at,
        gitBranch: "main",
        fileURL: URL(fileURLWithPath: "/tmp/history-1.jsonl")
    ))

    client.finishTurn(reportedTotal: 2.94)
    client.finishTurn(reportedTotal: 2.96)
    await waitForTurns(vm, 2)

    #expect(abs((vm.lastTurnCostUSD ?? -1) - 0.02) < 1e-9)
    #expect(vm.sessionTotalCostUSD == 2.96)
    #expect(vm.transcript.filter { if case .turnCost = $0 { true } else { false } }.count == 1)
}

// 総コストと最後の累計がファイルに保存され、次に開いたときに読み戻される。

@MainActor
@Test func totalCostAndLastCumulativeSurviveReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "phlox-cost-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileTranscriptStore(directoryURL: directory)
    let id = SessionID()

    let client = YieldingClient()
    let first = ChatSessionViewModel(id: id, agentRef: .builtin(.claudeCode), client: client, approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-restored-cost", transcriptStore: store)
    try await first.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.finishTurn(reportedTotal: 0.5)
    await waitForTurns(first, 1)
    await first.flushTranscriptNow()

    #expect(try await store.loadSessionTotalCost(for: id) == SessionTotalCost(totalUSD: 0.5, lastReportedUSD: 0.5))
}
