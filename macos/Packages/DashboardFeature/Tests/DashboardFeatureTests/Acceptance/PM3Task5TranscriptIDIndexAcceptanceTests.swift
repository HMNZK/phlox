import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-5 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-5.md — 不変条件「常に transcriptItemIDs == Set(transcript.map(\.id))」を
// transcript の全変更経路（append / delta / revert 切詰め / restore 再構築）で固定する。

private final class PM3Task5Client: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func pm3Task5VM(
    id: SessionID = SessionID(),
    client: PM3Task5Client,
    store: RecordingTranscriptStore
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: id,
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/pm3task5",
        transcriptStore: store
    )
}

@MainActor
private func pm3Task5AssertInvariant(_ vm: ChatSessionViewModel, _ context: String) {
    #expect(
        vm.transcriptItemIDs == Set(vm.transcript.map(\.id)),
        "\(context): transcriptItemIDs が transcript と乖離（index=\(vm.transcriptItemIDs.count)件 / transcript=\(vm.transcript.count)件）"
    )
}

@Suite(.serialized)
struct PM3Task5TranscriptIDIndexAcceptanceTests {

    // append（userMessage / agent delta）・turn 完了・revert 切詰めの全経路で不変条件が保たれる。
    @Test @MainActor
    func transcriptItemIDs_staysConsistentThroughSendDeltaAndRevert() async throws {
        let client = PM3Task5Client()
        let vm = pm3Task5VM(client: client, store: RecordingTranscriptStore())
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        pm3Task5AssertInvariant(vm, "startNew 直後")

        try await vm.sendText("最初の依頼", submit: true)
        pm3Task5AssertInvariant(vm, "userMessage append 後")

        client.yield(.agentMessageDelta(itemId: "pm3t5-a1", "応答1"))
        try await waitUntil { vm.transcript.count >= 2 }
        pm3Task5AssertInvariant(vm, "agent delta 後")

        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }
        pm3Task5AssertInvariant(vm, "turn 完了後")

        try await vm.sendText("二番目の依頼", submit: true)
        client.yield(.agentMessageDelta(itemId: "pm3t5-a2", "応答2"))
        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }
        pm3Task5AssertInvariant(vm, "2ターン後")
        #expect(vm.transcriptItemIDs.count == vm.transcript.count, "ID 重複がないこと")

        // revert（切詰め）: 2番目の userMessage 以降が消える。
        let userIDs = vm.transcript.compactMap { item -> String? in
            if case .userMessage(let id, _, _, _) = item { id } else { nil }
        }
        #expect(userIDs.count == 2)
        _ = await vm.revert(toUserMessageID: userIDs[1])
        pm3Task5AssertInvariant(vm, "revert 切詰め後")
        #expect(!vm.transcript.isEmpty, "revert で全消えしない（前半ターンは残る）")
    }

    // restore（store からの一括再構築）でも不変条件が保たれる。
    @Test @MainActor
    func transcriptItemIDs_matchesAfterRestoreFromStore() async throws {
        let sessionID = SessionID()
        let store = RecordingTranscriptStore()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsertTranscriptItems([
            .userMessage(id: "pm3t5-u1", text: "復元前の依頼", timestamp: timestamp),
            .agentMessage(id: "pm3t5-r1", text: "復元前の応答", timestamp: timestamp),
        ], for: sessionID)

        let client = PM3Task5Client()
        let vm = pm3Task5VM(id: sessionID, client: client, store: store)
        await vm.restore(
            threadId: "pm3t5-thread",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { !vm.transcript.isEmpty }
        pm3Task5AssertInvariant(vm, "restore 後")
        #expect(vm.transcriptItemIDs.contains("pm3t5-u1"))
        #expect(vm.transcriptItemIDs.contains("pm3t5-r1"))
    }
}
