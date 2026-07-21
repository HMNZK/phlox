import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 完了したサブエージェントで「右ペインにツールしか出ず、途中のナレーションが消える」退行の固定。
/// ライブ transcript は各ツールが tool_use（inline assistant）と tool_result（inline user）の
/// 両方から `.subAgentActivity(.tool)` を生むため、ツール件数が実数の約2倍に水増しされる。
/// 一方 parsed（output_file）は tool_use+tool_result を1セルにマージし、さらに途中のナレーション
/// text を保持する。`subAgentTranscript(for:)` が「項目数の多い方」を機械選択すると、2重化で
/// 件数が膨れたライブ（ナレーション欠落）が、内容の richer な parsed に不当に勝ち、
/// ①ツールの2重表示 ②中間ナレーションの欠落 を招く。
///
/// 完了済み（status == .completed）かつ parsed が読める場合は、権威である parsed を優先することを固定する。
/// reasoning 優先（片方だけ reasoning を持つとき reasoning を失わない側を選ぶ）は不変で、本テストと両立する。
@Suite("SubAgent completed prefers persisted narration acceptance")
@MainActor
struct SubAgentCompletedPrefersPersistedNarrationAcceptanceTests {

    @Test
    func completedSubAgentPrefersPersistedNarrationOverDoubledLiveTools() async throws {
        // parsed（output_file）: tool×2（マージ）＋ 中間ナレーション ＋ 最終レポート = 4 項目。
        // ツールの合間に text ブロック（ナレーション）が挟まる実 sidechain 形状を模す。
        let parsedJSONL = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a","content":[{"type":"text","text":"OUT-A"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"MID-NARRATION-XYZ"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_b","name":"Bash","input":{"command":"pwd"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_b","content":[{"type":"text","text":"OUT-B"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"FINAL-ANALYSIS-XYZ"}]}}"#,
        ].joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-narration-\(UUID().uuidString).jsonl")
        try parsedJSONL.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        // ライブ: prompt + 2重化ツール4件（tool_use inline と tool_result inline の両方）。
        // 中間ナレーション（MID-NARRATION-XYZ）は含めない＝実運用でライブに来ないことを模す。
        // これにより live.count(6) > parsed.count(4) となり、旧「件数の多い方」規則では live が選ばれる。
        client.yield(.subAgentStarted(toolUseId: "toolu_S", subagentType: "Explore", description: "narration test"))
        client.yield(.subAgentActivity(toolUseId: "toolu_S", kind: .prompt, itemId: nil, text: "PROMPT"))
        client.yield(.subAgentActivity(toolUseId: "toolu_S", kind: .tool, itemId: nil, text: "call toolu_a"))
        client.yield(.subAgentActivity(toolUseId: "toolu_S", kind: .tool, itemId: nil, text: "OUT-A"))
        client.yield(.subAgentActivity(toolUseId: "toolu_S", kind: .tool, itemId: nil, text: "call toolu_b"))
        client.yield(.subAgentActivity(toolUseId: "toolu_S", kind: .tool, itemId: nil, text: "OUT-B"))
        client.yield(.subAgentCompleted(toolUseId: "toolu_S", status: "completed", summary: "FINAL-ANALYSIS-XYZ", outputFile: url.path))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_S" && $0.status == .completed }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_S")

        // (1) 中間ナレーションが表示に残る（parsed が選ばれる）。旧規則では live が選ばれ欠落する。
        #expect(transcript.contains {
            if case .agentMessage(_, let text, _) = $0 { return text.contains("MID-NARRATION-XYZ") }
            return false
        }, "completed 時は parsed を優先し、中間ナレーションを失わないこと（2重化で膨れた live に負けない）")

        // (2) ツールはマージ済みの2件（parsed）であって、ライブの2重化4件ではない。
        let commandCount = transcript.reduce(into: 0) { acc, item in
            if case .commandExecution = item { acc += 1 }
        }
        #expect(commandCount == 2, "parsed のマージ済みツール2件が選ばれること（live の2重化4件ではない）。実際=\(commandCount)")
    }
}
