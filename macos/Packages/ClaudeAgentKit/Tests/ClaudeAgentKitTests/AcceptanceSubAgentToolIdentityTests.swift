import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

// 受け入れテスト（不変）。
//
// 契約: サブエージェントの子ターンに現れるツールは、**呼び出し（tool_use）と結果（tool_result）を
// 区別できる形**で隔離される:
// - 呼び出し → `kind == .tool`、`itemId == 子の tool_use.id`、text はコマンド説明
// - 結果     → `kind == .toolResult`、`itemId == 子の tool_result.tool_use_id`、text は出力
//
// この2つが同じ `itemId` を共有することで、受け側（ChatSubAgentModel）が永続 JSONL の parse と
// 同じ「1 ツールコール = 1 セル」へマージできる。id を捨てて両方 `.tool`/`itemId: nil` で流すと、
// 受け側は呼び出しと結果を区別できず独立セル2個を作り、実行中のツール件数が2倍に見える。

private final class ToolIdentityMockLineTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }

    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }
}

@Suite("SubAgent tool identity acceptance")
struct AcceptanceSubAgentToolIdentityTests {

    private static let subToolUseId = "toolu_SA_TOOLID"
    private static let childToolUseId = "toolu_child_a"

    private static let lines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S1","tools":["Task","Bash","Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_SA_TOOLID","name":"Agent","input":{"subagent_type":"general-purpose","description":"tool identity probe","prompt":"do work","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_SA_TOOLID","task_type":"local_agent","subagent_type":"general-purpose","description":"tool identity probe"}"#,
        #"{"type":"assistant","message":{"id":"mS1","role":"assistant","content":[{"type":"tool_use","id":"toolu_child_a","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":"toolu_SA_TOOLID","session_id":"S1"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_child_a","content":[{"type":"text","text":"OUT-A"}]}]},"parent_tool_use_id":"toolu_SA_TOOLID","session_id":"S1"}"#,
    ]

    @Test
    func childToolCallAndResultShareToolUseIdAndAreDistinguishable() async throws {
        let mock = ToolIdentityMockLineTransport()
        let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in Self.lines { mock.receive(line) }
        await mock.close()

        var call: (itemId: String?, text: String)?
        var result: (itemId: String?, text: String)?
        for _ in 0..<100 {
            guard let event = await iterator.next() else { break }
            guard case .subAgentActivity(let toolUseId, let kind, let itemId, let text) = event,
                  toolUseId == Self.subToolUseId
            else { continue }
            switch kind {
            case .tool where call == nil:
                call = (itemId, text)
            case .toolResult where result == nil:
                result = (itemId, text)
            default:
                break
            }
            if call != nil && result != nil { break }
        }

        let callActivity = try #require(call, "子の tool_use が .tool として隔離されること")
        let resultActivity = try #require(result, "子の tool_result が .toolResult として隔離されること")

        #expect(callActivity.itemId == Self.childToolUseId, "呼び出しは子の tool_use.id を itemId に運ぶこと")
        #expect(resultActivity.itemId == Self.childToolUseId, "結果は同じ tool_use_id を itemId に運ぶこと")
        #expect(callActivity.text == "ls", "呼び出しの text は commandDescription（Bash なら command 本体）であること")
        #expect(resultActivity.text.contains("OUT-A"), "結果の text はツール出力であること")
    }
}
