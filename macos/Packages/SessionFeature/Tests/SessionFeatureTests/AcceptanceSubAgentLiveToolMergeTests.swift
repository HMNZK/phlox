import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// 受け入れテスト（不変）。
//
// 契約: ライブ（stdout 由来）のサブエージェント transcript も、永続 JSONL の parse と同じ
// 「1 ツールコール = 1 セル」で組み立てる。子の tool_use と tool_result は同一 tool_use_id を
// `itemId` に載せて届き、受け側は同 id の 1 つの `commandExecution` へ
// 「呼び出し → command 欄 / 結果 → output 欄」でマージする。
//
// これが無いと、tool_use と tool_result の両方が独立セルを作り、実行中のドロワーで
// ツールが実数の2倍に見える（完了して parsed に切り替わった瞬間に半減する）。
// itemId が nil の活動は従来どおり独立 item のまま（後方互換）。

// MARK: - Fake client

private final class LiveToolMergeFakeClient: StructuredAgentClient, @unchecked Sendable {
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

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

// MARK: - Helpers

@MainActor
private func waitUntilLiveToolMerge(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeLiveToolMergeVM() -> (ChatSessionViewModel, LiveToolMergeFakeClient) {
    let client = LiveToolMergeFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-live-tool-merge-test"
    )
    return (vm, client)
}

private func commandCells(_ items: [ChatItem]) -> [(command: String?, output: String)] {
    items.compactMap { item in
        if case .commandExecution(_, let command, let output, _) = item {
            return (command, output)
        }
        return nil
    }
}

// MARK: - Tests

@Test @MainActor
func liveSubAgentToolCallAndResultMergeIntoOneCell() async throws {
    let (vm, client) = makeLiveToolMergeVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: "toolu_a", text: #"Bash {"command":"ls"}"#))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .toolResult, itemId: "toolu_a", text: "OUT-A"))

    try await waitUntilLiveToolMerge {
        commandCells(vm.subAgentTranscript(for: "tu1")).first?.output.contains("OUT-A") == true
    }

    let cells = commandCells(vm.subAgentTranscript(for: "tu1"))
    #expect(cells.count == 1, "1 ツールコール = 1 セル。実際=\(cells.count)")
    #expect(cells.first?.command?.contains("Bash") == true, "コマンド説明は command 欄に入ること（output 欄ではない）")
    #expect(cells.first?.output == "OUT-A", "tool_result は同一セルの output へマージされること")
}

@Test @MainActor
func liveSubAgentToolsAreNotDoubledAcrossManyCalls() async throws {
    let (vm, client) = makeLiveToolMergeVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    for index in 0..<10 {
        client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: "toolu_\(index)", text: "Bash cmd\(index)"))
        client.yield(.subAgentActivity(toolUseId: "tu1", kind: .toolResult, itemId: "toolu_\(index)", text: "out\(index)"))
    }

    try await waitUntilLiveToolMerge {
        commandCells(vm.subAgentTranscript(for: "tu1")).last?.output == "out9"
    }

    let cells = commandCells(vm.subAgentTranscript(for: "tu1"))
    #expect(cells.count == 10, "10 ツールコールは 10 セル（2重化なら 20）。実際=\(cells.count)")
}

@Test @MainActor
func liveSubAgentOrphanToolResultIsCompletedByLateToolCall() async throws {
    let (vm, client) = makeLiveToolMergeVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    // tool_use を取り逃して tool_result が先行するケース（resume・途中接続）。
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .toolResult, itemId: "toolu_a", text: "OUT-A"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: "toolu_a", text: "Bash late"))

    try await waitUntilLiveToolMerge {
        commandCells(vm.subAgentTranscript(for: "tu1")).first?.command != nil
    }

    let cells = commandCells(vm.subAgentTranscript(for: "tu1"))
    #expect(cells.count == 1, "順序が逆でもセルは増えないこと。実際=\(cells.count)")
    #expect(cells.first?.command == "Bash late", "遅れて来た呼び出しが command 欄を補うこと")
    #expect(cells.first?.output == "OUT-A", "先行した結果は保持されること")
}

@Test @MainActor
func liveSubAgentNumericChildToolIdDoesNotCollideWithSequentialCells() async throws {
    // itemId nil 経路は `-tool-\(連番)` の id を使う。マージ経路が同じ接頭辞を使うと、
    // 子の tool_use_id が "0" のときに連番セルと衝突して別ツールが1セルに混ざる。
    let (vm, client) = makeLiveToolMergeVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: nil, text: "LEGACY-CELL"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: "0", text: "MERGED-CELL"))

    try await waitUntilLiveToolMerge { commandCells(vm.subAgentTranscript(for: "tu1")).count == 2 }

    let cells = commandCells(vm.subAgentTranscript(for: "tu1"))
    #expect(cells.count == 2, "連番セルとマージセルは別物として残ること。実際=\(cells.count)")
    #expect(cells.map(\.output).contains("LEGACY-CELL"), "itemId nil のセルが上書きされないこと")
    #expect(cells.compactMap(\.command).contains("MERGED-CELL"), "マージセルは command 欄に入ること")
}

@Test @MainActor
func liveSubAgentToolResultWithNilItemIdRemainsIndividualItem() async throws {
    // 後方互換: itemId を持たない活動は従来どおり独立 item として積む。
    let (vm, client) = makeLiveToolMergeVM()
    client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "probe"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .tool, itemId: nil, text: "Bash: ls"))
    client.yield(.subAgentActivity(toolUseId: "tu1", kind: .toolResult, itemId: nil, text: "OUT"))

    try await waitUntilLiveToolMerge { commandCells(vm.subAgentTranscript(for: "tu1")).count == 2 }
    #expect(commandCells(vm.subAgentTranscript(for: "tu1")).map(\.output) == ["Bash: ls", "OUT"])
}
