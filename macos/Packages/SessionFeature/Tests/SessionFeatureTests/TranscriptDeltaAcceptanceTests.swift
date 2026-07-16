import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-3 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 6 の
// 差分エンジン（ChatSessionViewModel.transcriptDelta(since:)）のセマンティクス:
//   - since=nil → 全量（isSnapshot=false）＋cursor
//   - since 有効かつ以降 append のみ → 差分のみ（新規なしは空・isSnapshot=false）
//   - 既存項目の編集/置換が起きた・不正/期限切れ cursor → 全量＋isSnapshot=true（エラーにしない）
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。
// ハーネスは ChatSessionViewModelAppendDeltaTests と同流儀（EventYieldingStructuredClient）。

@MainActor
private func makeDeltaViewModel(client: EventYieldingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func waitUntilCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

@Test @MainActor
func transcriptDelta_sinceNil_returnsFullTranscriptWithCursor() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    client.yield(.agentMessageDelta(itemId: "a2", "two"))
    try await waitUntilCondition { vm.transcript.count >= 2 }

    let delta = vm.transcriptDelta(since: nil)
    #expect(delta.items.count == vm.transcript.count)
    #expect(delta.isSnapshot == false)
    #expect(!delta.cursor.isEmpty)
}

@Test @MainActor
func transcriptDelta_appendOnly_returnsOnlyNewItems() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    try await waitUntilCondition { vm.transcript.count >= 1 }
    let first = vm.transcriptDelta(since: nil)

    client.yield(.agentMessageDelta(itemId: "a2", "two"))
    try await waitUntilCondition { vm.transcript.count >= 2 }

    let delta = vm.transcriptDelta(since: first.cursor)
    #expect(delta.isSnapshot == false)
    #expect(delta.items.count == 1)
    if case .agentMessage(let id, let text, _)? = delta.items.first {
        #expect(id == "a2")
        #expect(text == "two")
    } else {
        Issue.record("expected agentMessage a2, got \(String(describing: delta.items.first))")
    }
}

@Test @MainActor
func transcriptDelta_noChange_returnsEmptyDelta() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    try await waitUntilCondition { vm.transcript.count >= 1 }
    let first = vm.transcriptDelta(since: nil)

    let delta = vm.transcriptDelta(since: first.cursor)
    #expect(delta.items.isEmpty)
    #expect(delta.isSnapshot == false)
}

@Test @MainActor
func transcriptDelta_editOfEarlierItem_fallsBackToSnapshot() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    try await waitUntilCondition { vm.transcript.count >= 1 }
    client.yield(.agentMessageDelta(itemId: "a2", "two"))
    try await waitUntilCondition { vm.transcript.count >= 2 }
    let cursorBeforeEdit = vm.transcriptDelta(since: nil).cursor

    // 既存項目 a1（末尾でない）への追記＝既存 ChatItem の置換（appendOrReplace の replace 経路）
    client.yield(.agentMessageDelta(itemId: "a1", " more"))
    try await waitUntilCondition {
        vm.transcript.contains { item in
            if case .agentMessage(let id, let text, _) = item {
                return id == "a1" && text.contains("more")
            }
            return false
        }
    }

    let delta = vm.transcriptDelta(since: cursorBeforeEdit)
    // 編集を「新規なし」と黙殺してはならない。契約どおり全量スナップショットへ倒す
    #expect(delta.isSnapshot == true)
    #expect(delta.items.count == vm.transcript.count)
}

@Test @MainActor
func transcriptDelta_invalidCursor_fallsBackToSnapshotWithoutError() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    try await waitUntilCondition { vm.transcript.count >= 1 }

    let delta = vm.transcriptDelta(since: "totally-bogus-cursor")
    #expect(delta.isSnapshot == true)
    #expect(delta.items.count == vm.transcript.count)
    #expect(!delta.cursor.isEmpty)
}

@Test @MainActor
func transcriptDelta_cursorAdvancesAcrossAppends() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeDeltaViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "a1", "one"))
    try await waitUntilCondition { vm.transcript.count >= 1 }
    let c1 = vm.transcriptDelta(since: nil).cursor

    client.yield(.agentMessageDelta(itemId: "a2", "two"))
    try await waitUntilCondition { vm.transcript.count >= 2 }
    let c2 = vm.transcriptDelta(since: nil).cursor

    // cursor は不透明だが、変化が起きたら前と同値ではない（前進する）
    #expect(c1 != c2)

    // 古い cursor(c1) は新しい状態でも有効に差分を返す（a2 のみ）
    let delta = vm.transcriptDelta(since: c1)
    #expect(delta.isSnapshot == false)
    #expect(delta.items.count == 1)
}
