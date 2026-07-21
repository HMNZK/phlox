import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

/// task-3（バグ3コア）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 実 ClaudeChatClient に、実データ構造に忠実な親 stream-json（サブエージェント=Agent ツール）を
/// MockTransport 経由で流し、放出される NormalizedChatEvent を検証する。
/// サブエージェントの出力全体が、メイン transcript へ流れる既存ケース
/// （commandExecution/agentMessageDelta/reasoningDelta/fileChange）に**現れない**こと、
/// 代わりに subAgent* イベントで運ばれること、親の発言はメインへ流れることを固定する。
@Suite("SubAgent isolation acceptance")
struct SubAgentIsolationAcceptanceTests {

    private static let subToolUseId = "toolu_01QCyoxs2rMLaBJYg3FRGfFo"

    /// 実測フィクスチャ（docs/agent-output/claude-subagent-fixture.jsonl）の要点を再現した親ストリーム。
    private static let parentLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S1","tools":["Task","Bash","Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_01QCyoxs2rMLaBJYg3FRGfFo","name":"Agent","input":{"subagent_type":"general-purpose","description":"Output three lines","prompt":"Output three short lines: LINE-A, then LINE-B, then LINE-C.","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_01QCyoxs2rMLaBJYg3FRGfFo","task_type":"local_agent","subagent_type":"general-purpose","description":"Output three lines"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Output three short lines: LINE-A, then LINE-B, then LINE-C."}]},"parent_tool_use_id":"toolu_01QCyoxs2rMLaBJYg3FRGfFo","session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_notification","task_id":"t1","tool_use_id":"toolu_01QCyoxs2rMLaBJYg3FRGfFo","status":"completed","summary":"LINE-A\nLINE-B\nLINE-C","output_file":"/tmp/sub.jsonl"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01QCyoxs2rMLaBJYg3FRGfFo","type":"tool_result","content":[{"type":"text","text":"LINE-A\nLINE-B\nLINE-C"}]}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"DONE"}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"result","subtype":"success","session_id":"S1","result":"DONE"}"#,
    ]

    @Test
    func subAgentOutputDoesNotLeakIntoMainBoundEvents() async throws {
        let mock = MockLineTransport()
        let recorder = MockTransportRecorder(mock)
        let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in Self.parentLines { mock.receive(line) }
        await mock.close()

        // イベントを turnCompleted（result 由来）まで、または上限まで収集。
        var events: [NormalizedChatEvent] = []
        for _ in 0..<200 {
            guard let ev = await iterator.next() else { break }
            events.append(ev)
            if case .turnCompleted = ev { break }
        }

        // サブエージェントの識別・出力・完了が subAgent* イベントで運ばれる。
        #expect(events.contains {
            if case .subAgentStarted(let id, let type, let desc) = $0 {
                return id == Self.subToolUseId && type == "general-purpose" && desc == "Output three lines"
            }
            return false
        })
        #expect(events.contains {
            if case .subAgentOutput(let id, let text) = $0 {
                return id == Self.subToolUseId
                    && text.contains("LINE-A") && text.contains("LINE-B") && text.contains("LINE-C")
            }
            return false
        })
        #expect(events.contains {
            if case .subAgentCompleted(let id, _, _, _) = $0 { return id == Self.subToolUseId }
            return false
        })

        // 隔離: 出力全体はメイン向けの既存ケースに一切現れない。
        for ev in events {
            #expect(!Self.mainBoundText(ev).contains("LINE-A"),
                    "sub-agent output leaked into a main-bound event: \(ev)")
        }

        // 親の発言はメインへ（agentMessageDelta で "DONE"）。
        #expect(events.contains {
            if case .agentMessageDelta(_, let text) = $0 { return text.contains("DONE") }
            return false
        })
    }

    @Test
    func subAgentDoesNotAlsoEmitBackgroundTaskEvents() async throws {
        let mock = MockLineTransport()
        let recorder = MockTransportRecorder(mock)
        let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in Self.parentLines { mock.receive(line) }
        await mock.close()

        var events: [NormalizedChatEvent] = []
        for _ in 0..<200 {
            guard let ev = await iterator.next() else { break }
            events.append(ev)
            if case .turnCompleted = ev { break }
        }

        // 実サブエージェント（tool_use_id 有り local_agent）は background chip を出さない（マーカーと二重表現しない）。
        #expect(!events.contains {
            if case .backgroundTaskStarted(_, "local_agent", _, let tid) = $0 { return tid != nil }
            return false
        })
        #expect(!events.contains {
            if case .backgroundTaskCompleted(let t, _, _) = $0 { return t == "t1" }
            return false
        })
    }

    /// バックグラウンドサブエージェントは子のターン（thinking/tool_use/text/tool_result）を
    /// parent_tool_use_id 付きでインライン流入させる（実測 docs/agent-output/claude-subagent-inline-fixture.jsonl）。
    private static let inlineBackgroundLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S2"}"#,
        #"{"type":"assistant","message":{"id":"pm1","role":"assistant","content":[{"type":"tool_use","id":"toolu_BG","name":"Agent","input":{"subagent_type":"general-purpose","description":"bg task","run_in_background":true}}]},"parent_tool_use_id":null,"session_id":"S2"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"tbg","tool_use_id":"toolu_BG","task_type":"local_agent","subagent_type":"general-purpose","description":"bg task"}"#,
        #"{"type":"assistant","message":{"id":"c1","role":"assistant","content":[{"type":"thinking","thinking":"CHILD-THINKING"}]},"parent_tool_use_id":"toolu_BG","session_id":"S2"}"#,
        #"{"type":"assistant","message":{"id":"c2","role":"assistant","content":[{"type":"tool_use","id":"toolu_child_ls","name":"Bash","input":{"command":"ls /tmp"}}]},"parent_tool_use_id":"toolu_BG","session_id":"S2"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_child_ls","type":"tool_result","content":[{"type":"text","text":"CHILD-TOOL-OUTPUT"}]}]},"parent_tool_use_id":"toolu_BG","session_id":"S2"}"#,
        #"{"type":"assistant","message":{"id":"c3","role":"assistant","content":[{"type":"text","text":"CHILD-MESSAGE"}]},"parent_tool_use_id":"toolu_BG","session_id":"S2"}"#,
        #"{"type":"assistant","message":{"id":"pm2","role":"assistant","content":[{"type":"text","text":"PARENT-DONE"}]},"parent_tool_use_id":null,"session_id":"S2"}"#,
        #"{"type":"result","subtype":"success","session_id":"S2","result":"PARENT-DONE"}"#,
    ]

    @Test
    func backgroundSubAgentInlineTurnsAreIsolatedFromMain() async throws {
        let mock = MockLineTransport()
        let recorder = MockTransportRecorder(mock)
        let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in Self.inlineBackgroundLines { mock.receive(line) }
        await mock.close()

        var events: [NormalizedChatEvent] = []
        for _ in 0..<200 {
            guard let ev = await iterator.next() else { break }
            events.append(ev)
            if case .turnCompleted = ev { break }
        }

        // 子のインライン内容（thinking/tool/tool_result/text）はメイン向けイベントに一切現れない。
        for needle in ["CHILD-THINKING", "CHILD-TOOL-OUTPUT", "CHILD-MESSAGE", "ls /tmp"] {
            #expect(!events.contains { Self.mainBoundText($0).contains(needle) },
                    "sub-agent inline content leaked into main: \(needle)")
        }
        // 子の内容は subAgentActivity(toolUseId: toolu_BG) として運ばれる。
        for needle in ["CHILD-THINKING", "CHILD-MESSAGE"] {
            #expect(events.contains {
                if case .subAgentActivity(let id, _, _, let text) = $0 { return id == "toolu_BG" && text.contains(needle) }
                return false
            }, "sub-agent inline content missing from subAgentActivity: \(needle)")
        }
        // 子の tool_use は .tool、tool_result は .toolResult として運ばれる（4種の positive 到達を固定）。
        // 〔ADR 0113〕呼び出しと結果を受け側が 1 セルへマージできるよう種別を分離したため、
        // 「どちらも .tool」から「種別まで固定」へ検証を強めている。
        for (needle, expectedKind) in [("ls /tmp", SubAgentActivityKind.tool), ("CHILD-TOOL-OUTPUT", SubAgentActivityKind.toolResult)] {
            #expect(events.contains {
                if case .subAgentActivity(let id, let kind, _, let text) = $0 {
                    return id == "toolu_BG" && kind == expectedKind && text.contains(needle)
                }
                return false
            }, "sub-agent tool activity missing from subAgentActivity(\(expectedKind)): \(needle)")
        }
        // 親の発言はメインへ。
        #expect(events.contains {
            if case .agentMessageDelta(_, let text) = $0 { return text.contains("PARENT-DONE") }
            return false
        })
    }

    /// メイン transcript へ append される既存ケースのテキストを連結（他は空）。
    private static func mainBoundText(_ event: NormalizedChatEvent) -> String {
        switch event {
        case .agentMessageDelta(_, let text), .reasoningDelta(_, let text):
            return text
        case .commandExecution(_, let command, let output):
            return (command ?? "") + "\n" + output
        case .fileChange(_, let changes):
            return changes.map { $0.diff }.joined(separator: "\n")
        default:
            return ""
        }
    }
}

// MARK: - 最小 transport（ClaudeChatClientTests の private 版は不可視のため自前定義）

private final class MockLineTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
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

private final class MockTransportRecorder: @unchecked Sendable {
    private let transport: MockLineTransport
    init(_ transport: MockLineTransport) { self.transport = transport }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        transport
    }
}
