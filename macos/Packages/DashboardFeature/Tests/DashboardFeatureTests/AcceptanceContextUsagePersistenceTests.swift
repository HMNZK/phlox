// task-7 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-7.md — lastTurnUsage をセッション単位で永続化し、restore 直後から
// コンテキストドーナツが表示できる。
// - TranscriptStore に loadTurnUsageSnapshot/saveTurnUsageSnapshot を要件追加（デフォルト実装あり）
// - FileTranscriptStore はサイドカーへ保存・復元
// - ChatSessionViewModel は .turnUsage 受信時に保存（costUSD nil でも）、restore で復元
// アサーションは変更禁止。ハーネス欠陥を発見した場合は PM に報告し承認を得たうえで
// ハーネス部分に限り修理してよい。

import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private let sampleUsage = TurnUsage(
    costUSD: nil,
    inputTokens: nil,
    outputTokens: nil,
    cacheReadTokens: nil,
    cacheCreationTokens: nil,
    contextUsedTokens: 27_400,
    contextWindowTokens: 353_000
)

private final class UsageFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

/// snapshot の保存/読込を記録・供給する fake store（新要件のみ実装。転写系はデフォルト動作）。
private actor RecordingUsageStore: TranscriptStore {
    private(set) var savedSnapshots: [TurnUsage] = []
    private let stubbedSnapshot: TurnUsage?

    init(stubbedSnapshot: TurnUsage? = nil) {
        self.stubbedSnapshot = stubbedSnapshot
    }

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { [] }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}

    func loadTurnUsageSnapshot(for sessionID: SessionID) async throws -> TurnUsage? {
        stubbedSnapshot
    }

    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {
        savedSnapshots.append(usage)
    }

    func savedCount() -> Int { savedSnapshots.count }
    func lastSaved() -> TurnUsage? { savedSnapshots.last }
}

@MainActor
private func usageVM(store: any TranscriptStore) -> (ChatSessionViewModel, UsageFakeClient) {
    let client = UsageFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-usage-persistence-work",
        transcriptStore: store
    )
    return (vm, client)
}

// MARK: - FileTranscriptStore ラウンドトリップ

@Test
func fileStore_loadWithoutSaveReturnsNil() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "usage-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileTranscriptStore(directoryURL: dir)

    let loaded = try await store.loadTurnUsageSnapshot(for: SessionID())
    #expect(loaded == nil)
}

@Test
func fileStore_savesAndLoadsTurnUsageSnapshot() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "usage-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileTranscriptStore(directoryURL: dir)
    let sessionID = SessionID()

    try await store.saveTurnUsageSnapshot(sampleUsage, for: sessionID)
    let loaded = try await store.loadTurnUsageSnapshot(for: sessionID)

    #expect(loaded == sampleUsage)
    // 別セッションの snapshot は混ざらない。
    let other = try await store.loadTurnUsageSnapshot(for: SessionID())
    #expect(other == nil)
}

// MARK: - .turnUsage イベントで保存（costUSD nil の Codex 経路を含む）

@Test @MainActor
func viewModel_savesSnapshotOnTurnUsageEventEvenWithoutCost() async throws {
    let store = RecordingUsageStore()
    let (vm, client) = usageVM(store: store)
    _ = vm

    client.yield(.turnStarted)
    client.yield(.turnUsage(sampleUsage))  // costUSD == nil でも保存される

    try await waitUntil { await store.savedCount() >= 1 }
    let last = await store.lastSaved()
    #expect(last == sampleUsage)
}

// MARK: - restore で復元（claude 系 = codexClient nil の経路）

@Test @MainActor
func viewModel_restoresLastTurnUsageFromSnapshot() async throws {
    let store = RecordingUsageStore(stubbedSnapshot: sampleUsage)
    let (vm, _) = usageVM(store: store)
    #expect(vm.lastTurnUsage == nil)

    await vm.restore(
        threadId: "restored-thread",
        approvalPolicy: .named("never"),
        sandbox: .named("workspace-write")
    )

    try await waitUntil { vm.lastTurnUsage == sampleUsage }
    #expect(vm.lastTurnUsage == sampleUsage)
    // ドーナツの供給条件（fraction が計算できる）まで満たすこと。
    #expect(ComposerContextGauge.fraction(for: vm.lastTurnUsage) != nil)
}
