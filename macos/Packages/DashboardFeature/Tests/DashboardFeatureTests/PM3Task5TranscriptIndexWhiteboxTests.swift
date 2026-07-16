import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-5 白箱テスト（tasks/task-5.md 契約）。
// 受け入れテスト（PM3Task5TranscriptIDIndexAcceptanceTests）が覆う send/delta/turn完了/revert/restore の
// 主経路に対し、ここでは transcript を変更する内部経路のうち受け入れテストが直接踏まない分岐を狙う:
//   - appendDelta の「同一 itemId への2回目以降のデルタ」in-place 更新分岐（ID 集合を変えない）
//   - appendCommandExecution の append 分岐 → in-place 更新分岐
//   - appendOrReplace の複数種別 append 分岐（fileChange / error / warning、いずれも都度新規 id）
//   - restore の resume 失敗かつ store が空のときの appendOrReplace(.error) 経路（setTranscript を経ない）
//   - markRestoreFailed の直接呼び出し（公開 API から appendOrReplace を叩く経路）
// いずれも「常に transcriptItemIDs == Set(transcript.map(\.id))」の不変条件を検査する。
// RecordingTranscriptStore / EventYieldingStructuredClient / FailingResumeStructuredClient / waitUntil は
// ChatSessionViewModelTests.swift / SessionViewModelTests.swift で定義済みの共有ヘルパーを再利用する。

@MainActor
private func pm3Task5WhiteboxVM(
    client: EventYieldingStructuredClient,
    store: RecordingTranscriptStore = RecordingTranscriptStore()
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/pm3task5-whitebox",
        transcriptStore: store
    )
}

@MainActor
private func pm3Task5WhiteboxAssertInvariant(_ vm: ChatSessionViewModel, _ context: String) {
    #expect(
        vm.transcriptItemIDs == Set(vm.transcript.map(\.id)),
        "\(context): transcriptItemIDs が transcript と乖離（index=\(vm.transcriptItemIDs.count)件 / transcript=\(vm.transcript.count)件）"
    )
}

@Suite(.serialized)
struct PM3Task5TranscriptIndexWhiteboxTests {

    // appendDelta: 同一 itemId への2回目のデルタは transcript[index] = ... の in-place 更新
    // （ID 集合の変化なし）。件数が増えないことと不変条件の両方を検査する。
    @Test @MainActor
    func appendDelta_sameItemIdInPlaceUpdate_keepsIndexSizeStable() async throws {
        let client = EventYieldingStructuredClient()
        let vm = pm3Task5WhiteboxVM(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.agentMessageDelta(itemId: "wb-a1", "最初の"))
        try await waitUntil { vm.transcript.contains { $0.id == "wb-a1" } }
        pm3Task5WhiteboxAssertInvariant(vm, "1回目デルタ後")
        #expect(vm.transcriptItemIDs.count == 1)

        client.yield(.agentMessageDelta(itemId: "wb-a1", "続き"))
        try await waitUntil {
            if case .agentMessage(_, let text, _) = vm.transcript.first(where: { $0.id == "wb-a1" }) {
                return text == "最初の続き"
            }
            return false
        }
        pm3Task5WhiteboxAssertInvariant(vm, "2回目デルタ（同一ID・in-place更新）後")
        #expect(vm.transcriptItemIDs.count == 1, "同一IDの上書きで件数が増えない")
    }

    // appendCommandExecution: command 付き新規イベントで append 分岐、同一 itemId の追撃で in-place 更新分岐。
    @Test @MainActor
    func appendCommandExecution_appendThenUpdate_keepsInvariant() async throws {
        let client = EventYieldingStructuredClient()
        let vm = pm3Task5WhiteboxVM(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.commandExecution(itemId: "wb-cmd1", command: "ls", outputDelta: "a.txt\n"))
        try await waitUntil { vm.transcript.contains { $0.id == "wb-cmd1" } }
        pm3Task5WhiteboxAssertInvariant(vm, "command 新規 append 後")
        #expect(vm.transcriptItemIDs.count == 1)

        client.yield(.commandExecution(itemId: "wb-cmd1", command: "ls", outputDelta: "b.txt\n"))
        try await waitUntil {
            if case .commandExecution(_, _, let output, _) = vm.transcript.first(where: { $0.id == "wb-cmd1" }) {
                return output.contains("b.txt")
            }
            return false
        }
        pm3Task5WhiteboxAssertInvariant(vm, "command 追撃更新後")
        #expect(vm.transcriptItemIDs.count == 1, "同一IDの追撃で件数が増えない")
    }

    // appendOrReplace: fileChange / error / warning という異なる種別の新規 id 項目が
    // それぞれ append 分岐を通っても索引が乖離しないことを確認する。
    @Test @MainActor
    func appendOrReplace_multipleItemKinds_keepsInvariant() async throws {
        let client = EventYieldingStructuredClient()
        let vm = pm3Task5WhiteboxVM(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.fileChange(itemId: "wb-file1", []))
        try await waitUntil { vm.transcript.contains { $0.id == "wb-file1" } }
        pm3Task5WhiteboxAssertInvariant(vm, "fileChange append 後")

        client.yield(.error(message: "boom"))
        try await waitUntil { vm.transcript.count >= 2 }
        pm3Task5WhiteboxAssertInvariant(vm, "error append 後")

        client.yield(.warning(message: "careful"))
        try await waitUntil { vm.transcript.count >= 3 }
        pm3Task5WhiteboxAssertInvariant(vm, "warning append 後")
        #expect(vm.transcriptItemIDs.count == vm.transcript.count, "ID 重複がないこと")
    }

    // restore: store が空かつ client.resume が失敗する経路。setTranscript を経由しない
    // appendOrReplace(.error) 単発 append で索引が同期することを確認する。
    @Test @MainActor
    func restore_resumeFailsWithEmptyStore_appendsErrorItemAndKeepsInvariant() async throws {
        let store = RecordingTranscriptStore()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: FailingResumeStructuredClient(),
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/pm3task5-whitebox-restore",
            transcriptStore: store
        )

        await vm.restore(
            threadId: "wb-thread",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )

        pm3Task5WhiteboxAssertInvariant(vm, "restore（resume失敗・store空）後")
        #expect(vm.transcript.count == 1, "エラー項目が1件だけ append される")
    }

    // markRestoreFailed: 公開 API 経由で appendOrReplace(.error) を直接叩く分岐。
    @Test @MainActor
    func markRestoreFailed_appendsErrorItemAndKeepsInvariant() async throws {
        let client = EventYieldingStructuredClient()
        let vm = pm3Task5WhiteboxVM(client: client)

        vm.markRestoreFailed("手動失敗")

        pm3Task5WhiteboxAssertInvariant(vm, "markRestoreFailed 後")
        #expect(vm.transcriptItemIDs.count == 1)
    }
}
