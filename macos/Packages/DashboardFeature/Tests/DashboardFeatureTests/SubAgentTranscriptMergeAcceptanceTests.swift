import Testing
import Foundation
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（Bug A/B/C）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 実データ（子 output_file）の構造を再現: 複数の assistant 行が同一 message.id を共有し、
/// tool_use（assistant）とその tool_result（後続 user）は同一 id（tool_use_id）を持つ。
/// 旧 parse はこれを **同一 id の別 ChatItem 2個** として生成していた（duplicate id → ForEach/
/// LazyVStack 破綻＝スクロール CPU 暴走、reasoning 脱落、呼び出しと結果が別セルで隙間）。
/// 本テストは (1) 全 ChatItem の id が一意、(2) reasoning が保持される、(3) tool_use と
/// tool_result が **1 つの commandExecution にマージ**され output を含む、を固定する。
@Suite("SubAgent transcript merge acceptance")
struct SubAgentTranscriptMergeAcceptanceTests {

    // 2 つの assistant 行が同一 message.id "msg_1" を共有（実データの再現）。
    // tool_use "toolu_A" とその tool_result（tool_use_id "toolu_A"）は同一 id。
    private static let jsonl = [
        #"{"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"thinking","thinking":"THINK-NEEDLE","signature":"sig"}]}}"#,
        #"{"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"tool_use","id":"toolu_A","name":"Bash","input":{"command":"ls /tmp"}}]}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":[{"type":"text","text":"OUTPUT-NEEDLE"}]}]}}"#,
        #"{"type":"assistant","message":{"id":"msg_2","role":"assistant","content":[{"type":"text","text":"FINAL-NEEDLE"}]}}"#,
    ].joined(separator: "\n")

    @Test
    func toolUseAndResultMergeWithoutDuplicateIds() {
        let items = SubAgentTranscriptLoader.parse(jsonl: Self.jsonl)

        // (1) 全 id が一意（duplicate id を作らない）。
        let ids = items.map(\.id)
        #expect(Set(ids).count == ids.count, "parsed items must have unique ids; got duplicates: \(ids)")

        // (2) reasoning が保持される（thinking → reasoning）。
        let reasonings = items.filter { if case .reasoning(_, let t, _) = $0 { return t.contains("THINK-NEEDLE") } else { return false } }
        #expect(reasonings.count == 1, "reasoning must be preserved exactly once")

        // (3) tool_use と tool_result が 1 つの commandExecution にマージされ、command と output を持つ。
        let commands = items.compactMap { item -> (String?, String)? in
            if case .commandExecution(let id, let command, let output, _) = item, id == "toolu_A" {
                return (command, output)
            }
            return nil
        }
        #expect(commands.count == 1, "tool_use and its tool_result must merge into a single commandExecution (got \(commands.count))")
        if let (command, output) = commands.first {
            #expect(command?.contains("ls /tmp") == true || command?.contains("Bash") == true,
                    "merged command must retain the tool_use invocation")
            #expect(output.contains("OUTPUT-NEEDLE"), "merged commandExecution must contain the tool_result output")
        }

        // 親メッセージ本文も保持。
        #expect(items.contains { if case .agentMessage(_, let t, _) = $0 { return t.contains("FINAL-NEEDLE") } else { return false } })
    }

    /// stage1 レビュー指摘（順序耐性）: 孤児 tool_result が先行し、後続で同一 tool_use_id の
    /// tool_use が来ても duplicate id を作らない（順序に依らず「1 ツールコール = 1 セル」）。
    @Test
    func orphanResultThenLateToolUseDoesNotDuplicateId() {
        let jsonl = [
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_X","content":[{"type":"text","text":"OUT-NEEDLE"}]}]}}"#,
            #"{"type":"assistant","message":{"id":"m","role":"assistant","content":[{"type":"tool_use","id":"toolu_X","name":"Bash","input":{"command":"ls"}}]}}"#,
        ].joined(separator: "\n")
        let items = SubAgentTranscriptLoader.parse(jsonl: jsonl)
        let ids = items.map(\.id)
        #expect(Set(ids).count == ids.count, "reversed tool order must not create duplicate ids: \(ids)")
        // 単一の commandExecution に command と output の両方が入る。
        let cmds = items.compactMap { item -> (String?, String)? in
            if case .commandExecution(let id, let c, let o, _) = item, id == "toolu_X" { return (c, o) }
            return nil
        }
        #expect(cmds.count == 1)
        #expect(cmds.first?.1.contains("OUT-NEEDLE") == true)
    }
}
