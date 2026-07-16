// task-8 受け入れテスト（PM 著・実装役は編集禁止）

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class RevertRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnTexts: [String] = []
    private var resetCount = 0

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        let text = input.compactMap { item in
            if case .text(let value) = item { value } else { nil }
        }.joined()
        lock.withLock { turnTexts.append(text) }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {
        lock.withLock { resetCount += 1 }
    }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func recordedTurnTexts() -> [String] { lock.withLock { turnTexts } }
    func resetConversationCalls() -> Int { lock.withLock { resetCount } }
}

@MainActor
private func makeVM(client: RevertRecordingClient, store: RecordingTranscriptStore) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )
}

/// user→agent 応答 1 ターンを進めるヘルパ（送信 → 応答 delta → turnCompleted → idle 待ち）。
@MainActor
private func completeTurn(
    _ vm: ChatSessionViewModel, client: RevertRecordingClient,
    userText: String, agentItemID: String, agentReply: String
) async throws {
    try await vm.sendText(userText, submit: true)
    client.yield(.agentMessageDelta(itemId: agentItemID, agentReply))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
}

@Test @MainActor
func revert_truncatesTranscriptAndStore_resetsConversation_andReplaysContextOnNextSend() async throws {
    let client = RevertRecordingClient()
    let store = RecordingTranscriptStore()
    let vm = makeVM(client: client, store: store)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await completeTurn(vm, client: client, userText: "最初の依頼", agentItemID: "a1", agentReply: "応答1")
    try await completeTurn(vm, client: client, userText: "二番目の依頼", agentItemID: "a2", agentReply: "応答2")

    let userIDs = vm.transcript.compactMap { item in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }
    try #require(userIDs.count == 2)

    // 契約: 二番目の userMessage の直前まで巻き戻す。
    let restored = await vm.revert(toUserMessageID: userIDs[1])
    #expect(restored == "二番目の依頼")

    let remainingTexts = vm.transcript.map(\.plainText)
    #expect(remainingTexts.contains { $0.contains("最初の依頼") })
    #expect(remainingTexts.contains { $0.contains("応答1") })
    #expect(!remainingTexts.joined().contains("二番目の依頼"))
    #expect(!remainingTexts.joined().contains("応答2"))

    // store も同内容に replace される（追記キューとの順序保証込み）。
    try await waitUntil {
        let stored = (try? await store.loadTranscript(for: vm.id)) ?? []
        let joined = stored.map(\.plainText).joined()
        return joined.contains("最初の依頼") && !joined.contains("二番目の依頼") && !joined.contains("応答2")
    }

    // 会話リセットがちょうど 1 回。
    #expect(client.resetConversationCalls() == 1)

    // 次の送信: client へはリプレイプリアンブル + 新規入力、transcript へは新規入力のみ。
    try await vm.sendText("編集後の依頼", submit: true)
    let lastTurn = try #require(client.recordedTurnTexts().last)
    #expect(lastTurn.contains("編集後の依頼"))
    #expect(lastTurn.contains("最初の依頼"), "保持分の文脈リプレイが含まれていない")
    let newUserTexts = vm.transcript.compactMap { item in
        if case .userMessage(_, let text, _, _) = item { text } else { nil }
    }
    #expect(newUserTexts.contains("編集後の依頼"))
    #expect(!newUserTexts.contains { $0.contains("最初の依頼") && $0.contains("編集後の依頼") }, "プリアンブルが transcript に混入している")

    // リプレイは 1 回きり: さらに次の送信では素の入力のみ。
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await vm.sendText("その次の依頼", submit: true)
    #expect(client.recordedTurnTexts().last == "その次の依頼")
}

@Test @MainActor
func revert_toFirstMessage_startsPlainNewConversationWithoutPreamble() async throws {
    let client = RevertRecordingClient()
    let store = RecordingTranscriptStore()
    let vm = makeVM(client: client, store: store)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await completeTurn(vm, client: client, userText: "唯一の依頼", agentItemID: "a1", agentReply: "応答")

    let firstUserID = try #require(vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }.first)

    let restored = await vm.revert(toUserMessageID: firstUserID)
    #expect(restored == "唯一の依頼")
    #expect(vm.transcript.isEmpty)

    try await vm.sendText("仕切り直しの依頼", submit: true)
    #expect(client.recordedTurnTexts().last == "仕切り直しの依頼", "保持分が空ならプリアンブルなしの素の入力を送る")
}

@Test @MainActor
func revert_whileRunning_isRefusedAndChangesNothing() async throws {
    let client = RevertRecordingClient()
    let store = RecordingTranscriptStore()
    let vm = makeVM(client: client, store: store)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await completeTurn(vm, client: client, userText: "先行ターン", agentItemID: "a1", agentReply: "応答")
    try await vm.sendText("実行中ターン", submit: true) // turnCompleted を流さない = running のまま

    let firstUserID = try #require(vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }.first)
    let countBefore = vm.transcript.count

    let restored = await vm.revert(toUserMessageID: firstUserID)
    #expect(restored == nil)
    #expect(vm.transcript.count == countBefore)
    #expect(client.resetConversationCalls() == 0)
}
