import Testing
import Foundation
@testable import DashboardFeature
@testable import SessionFeature

/// task-3（バグ3コア）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// サブエージェントの output_file（子 JSONL）を turn-by-turn の [ChatItem] にパースする
/// 純関数 `SubAgentTranscriptLoader.parse(jsonl:)` の契約を固定する。
/// 実データ（docs/agent-output/claude-subagent-output-file-fixture.jsonl）の構造に忠実な
/// 最小 JSONL を用いる: user → userMessage / assistant thinking → reasoning /
/// assistant text → agentMessage。attachment 等の未知行は無視。空入力は []。
@Suite("SubAgent transcript loader acceptance")
struct SubAgentTranscriptLoaderAcceptanceTests {

    private static let childJSONL = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Output three lines"}]}}
    {"type":"attachment","subtype":"context","note":"should be ignored"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Let me think about the three lines"}]}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"LINE-A\\nLINE-B\\nLINE-C"}]}}
    """

    @Test
    func parsesTurnByTurnFromChildJSONL() {
        let items = SubAgentTranscriptLoader.parse(jsonl: Self.childJSONL)
        #expect(!items.isEmpty)

        // 子のプロンプト（user）が userMessage として出る。
        #expect(items.contains {
            if case .userMessage(_, let text, _, _) = $0 { return text.contains("Output three lines") }
            return false
        })
        // thinking が reasoning として出る。
        #expect(items.contains {
            if case .reasoning(_, let text, _) = $0 { return text.contains("Let me think") }
            return false
        })
        // 最終出力（text）が agentMessage として出る。
        #expect(items.contains {
            if case .agentMessage(_, let text, _) = $0 { return text.contains("LINE-A") && text.contains("LINE-C") }
            return false
        })
    }

    /// 実 Claude 形式のツール結果は user メッセージに tool_result としてネストされる。
    /// これを commandExecution として拾えること（ツール使用サブエージェントの turn-by-turn 保全）。
    @Test
    func userNestedToolResultBecomesCommandExecution() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":[{"type":"text","text":"file.txt"}]}]}}
        """
        let items = SubAgentTranscriptLoader.parse(jsonl: jsonl)
        #expect(items.contains {
            if case .commandExecution(_, _, let out, _) = $0 { return out.contains("file.txt") }
            return false
        })
    }

    @Test
    func emptyInputYieldsEmpty() {
        #expect(SubAgentTranscriptLoader.parse(jsonl: "").isEmpty)
    }

    @Test
    func malformedLinesAreSkippedNotCrashing() {
        let jsonl = """
        not-json-at-all
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OK-TEXT"}]}}
        {broken json
        """
        let items = SubAgentTranscriptLoader.parse(jsonl: jsonl)
        // 不正行はスキップし、有効な assistant text は拾う（クラッシュしない）。
        #expect(items.contains {
            if case .agentMessage(_, let text, _) = $0 { return text.contains("OK-TEXT") }
            return false
        })
    }
}
