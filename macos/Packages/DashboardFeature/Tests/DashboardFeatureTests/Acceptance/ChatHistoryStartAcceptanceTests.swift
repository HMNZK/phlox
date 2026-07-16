// task-9 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-9.md — 新規 Claude チャットの中央に履歴一覧を出し、選択で --resume 再開する。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class HistoryFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var resumedRefs: [String] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {
        lock.withLock { resumedRefs.append(sessionRef) }
    }
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func recordedResumes() -> [String] { lock.withLock { resumedRefs } }
}

private func makeEntry(_ sessionID: String, preview: String = "過去の依頼") -> ClaudeSessionHistoryEntry {
    ClaudeSessionHistoryEntry(
        sessionID: sessionID,
        preview: preview,
        firstUserAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModified: Date(timeIntervalSince1970: 1_700_000_100),
        gitBranch: "dev",
        fileURL: URL(fileURLWithPath: "/tmp/\(sessionID).jsonl")
    )
}

@MainActor
private func makeHistoryVM(
    agentRef: AgentRef = .builtin(.claudeCode),
    client: HistoryFakeClient = HistoryFakeClient(),
    entries: [ClaudeSessionHistoryEntry],
    loaded: [ChatItem] = []
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: agentRef,
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        historyProvider: { entries },
        historyTranscriptLoader: { _ in loaded }
    )
}

@Test @MainActor
func chatHistoryStart_offeredOnlyForEmptyClaudeChatWithEntries() async throws {
    let entries = [makeEntry("11111111-1111-4111-8111-111111111111")]

    // 履歴ロードは off-main 非同期（fix round 2 で契約改訂: init を約1秒ブロックしないため）。
    // 表示可否はロード完了後に反応的に true になる。
    let claudeVM = makeHistoryVM(entries: entries)
    try await waitUntil { claudeVM.shouldOfferHistoryStart }
    #expect(claudeVM.historyEntries.map(\.sessionID) == entries.map(\.sessionID))

    // Claude 以外のエージェントでは出さない
    let cursorVM = makeHistoryVM(agentRef: .builtin(.cursor), entries: entries)
    #expect(!cursorVM.shouldOfferHistoryStart)

    // 履歴ゼロ件では出さない
    let emptyVM = makeHistoryVM(entries: [])
    #expect(!emptyVM.shouldOfferHistoryStart)

    // provider 未注入（既存呼び出し互換）では出さない
    let noProviderVM = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: HistoryFakeClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    #expect(!noProviderVM.shouldOfferHistoryStart)
}

@Test @MainActor
func chatHistoryStart_capsEntriesAtTwenty() async throws {
    let many = (0..<30).map { makeEntry(String(format: "%08d-0000-4000-8000-000000000000", $0)) }
    let vm = makeHistoryVM(entries: many)
    try await waitUntil { !vm.historyEntries.isEmpty }
    #expect(vm.historyEntries.count == 20)
}

@Test @MainActor
func chatHistoryStart_startFromHistoryResumesClientAndPopulatesTranscript() async throws {
    let client = HistoryFakeClient()
    let sessionID = "22222222-2222-4222-8222-222222222222"
    let loaded: [ChatItem] = [
        .userMessage(id: "u1", text: "過去の質問", timestamp: Date(timeIntervalSince1970: 1_000)),
        .agentMessage(id: "a1", text: "過去の回答", timestamp: Date(timeIntervalSince1970: 1_001)),
    ]
    let vm = makeHistoryVM(client: client, entries: [makeEntry(sessionID)], loaded: loaded)

    await vm.startFromHistory(makeEntry(sessionID))

    #expect(client.recordedResumes() == [sessionID])
    #expect(vm.transcript == loaded)
    #expect(!vm.shouldOfferHistoryStart)
}

@Test @MainActor
func chatHistoryStart_hiddenAfterFirstSend() async throws {
    let vm = makeHistoryVM(entries: [makeEntry("33333333-3333-4333-8333-333333333333")])
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await waitUntil { vm.shouldOfferHistoryStart }

    try await vm.sendText("新しい質問", submit: true)
    #expect(!vm.shouldOfferHistoryStart)
}
