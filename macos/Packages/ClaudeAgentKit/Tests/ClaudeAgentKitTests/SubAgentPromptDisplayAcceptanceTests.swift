import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

/// task-1（Bug1）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// バックグラウンド起動（run_in_background:true）のサブエージェントでは、launcher tool_result は
/// 「Async agent launched successfully …」という**起動確認メタデータ**であって出力ではない。
/// これを `.subAgentOutput` として表示してはならず、代わりに `input["prompt"]` を
/// `.subAgentActivity(.prompt)` として運ぶことを固定する。
///
/// 併せて、フォアグラウンド（run_in_background:false）の launcher tool_result は従来どおり
/// 正当な最終出力として `.subAgentOutput` に残ること（＝抑制がフォアグラウンドを巻き添えにしない）を固定する。
@Suite("SubAgent prompt display acceptance")
struct SubAgentPromptDisplayAcceptanceTests {

    private static let bgToolUseId = "toolu_BG1"
    private static let promptNeedle = "PROMPT-NEEDLE-loopflow-調査"

    /// バックグラウンド起動 + 起動確認メタデータ tool_result（実測 Image5 に忠実）。
    private static let backgroundLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S1","tools":["Task","Bash","Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_BG1","name":"Agent","input":{"subagent_type":"general-purpose","description":"loopflow を調査","prompt":"このリポジトリの loopflow を調査して PROMPT-NEEDLE-loopflow-調査 を返せ。","run_in_background":true}}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_BG1","task_type":"local_agent","subagent_type":"general-purpose","description":"loopflow を調査"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_BG1","type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully. (This tool result is internal metadata — never quote or paste any part of it, including the agentId below, into a user-facing reply.) agentId: a6e94146882961e7e (internal ID - do not mention to user.) output_file: /private/tmp/x.output"}]}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_notification","task_id":"t1","tool_use_id":"toolu_BG1","status":"completed","summary":"done","output_file":"/tmp/does-not-exist-sub.jsonl"}"#,
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"MAIN-DONE"}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"result","subtype":"success","session_id":"S1","result":"MAIN-DONE"}"#,
    ]

    @Test
    func backgroundLauncherMetadataIsSuppressedAndPromptIsShown() async throws {
        let events = try await collect(Self.backgroundLines)

        // (a) プロンプトが subAgentActivity(.prompt) として現れる。
        #expect(events.contains {
            if case .subAgentActivity(let id, .prompt, _, let text) = $0 {
                return id == Self.bgToolUseId && text.contains(Self.promptNeedle)
            }
            return false
        }, "sub-agent prompt was not surfaced as .subAgentActivity(.prompt)")

        // (b) 起動確認メタデータはどのイベントにも現れない（メイン・subAgent 双方）。
        for needle in ["Async agent launched successfully", "internal metadata", "agentId"] {
            #expect(!events.contains { Self.anyText($0).contains(needle) },
                    "launch metadata leaked into an event: \(needle)")
        }

        // (c) バックグラウンド launcher tool_result は subAgentOutput として放出されない。
        #expect(!events.contains {
            if case .subAgentOutput(let id, _) = $0 { return id == Self.bgToolUseId }
            return false
        }, "background launcher metadata must not be emitted as .subAgentOutput")

        // (d) 親の発言はメインへ（隔離維持）。
        #expect(events.contains {
            if case .agentMessageDelta(_, let text) = $0 { return text.contains("MAIN-DONE") }
            return false
        })
    }

    /// フォアグラウンド（run_in_background:false）の launcher tool_result は正当な最終出力として維持。
    private static let foregroundLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S2","tools":["Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_FG1","name":"Agent","input":{"subagent_type":"general-purpose","description":"3行出力","prompt":"FG-PROMPT を返せ。","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S2"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t2","tool_use_id":"toolu_FG1","task_type":"local_agent","subagent_type":"general-purpose","description":"3行出力"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_FG1","type":"tool_result","content":[{"type":"text","text":"FG-REAL-OUTPUT-XYZ"}]}]},"parent_tool_use_id":null,"session_id":"S2"}"#,
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"FG-MAIN-DONE"}]},"parent_tool_use_id":null,"session_id":"S2"}"#,
        #"{"type":"result","subtype":"success","session_id":"S2","result":"FG-MAIN-DONE"}"#,
    ]

    @Test
    func foregroundLauncherOutputIsPreserved() async throws {
        let events = try await collect(Self.foregroundLines)

        // フォアグラウンドの正当出力は subAgentOutput として残る（抑制の巻き添えにしない）。
        #expect(events.contains {
            if case .subAgentOutput(let id, let text) = $0 {
                return id == "toolu_FG1" && text.contains("FG-REAL-OUTPUT-XYZ")
            }
            return false
        }, "foreground sub-agent real output must be preserved as .subAgentOutput")

        // プロンプトも表示される。
        #expect(events.contains {
            if case .subAgentActivity(let id, .prompt, _, let text) = $0 {
                return id == "toolu_FG1" && text.contains("FG-PROMPT")
            }
            return false
        })

        // フォアグラウンドの正当出力は隔離される（メインへ漏れない）。
        for ev in events {
            #expect(!Self.mainBoundText(ev).contains("FG-REAL-OUTPUT-XYZ"),
                    "foreground sub-agent output leaked into a main-bound event: \(ev)")
        }
    }

    /// stage2 レビュー指摘（状態寿命）: 同一 tool_use_id が bg の後に fg で再利用されても、
    /// 抑制フラグは現在の tool_use に束縛され、fg の正当出力は抑制されない。
    private static let reusedIdLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S3","tools":["Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_REUSE","name":"Agent","input":{"subagent_type":"general-purpose","description":"bg","prompt":"BG","run_in_background":true}}]},"parent_tool_use_id":null,"session_id":"S3"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_REUSE","type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully. agentId: x internal metadata"}]}]},"parent_tool_use_id":null,"session_id":"S3"}"#,
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"toolu_REUSE","name":"Agent","input":{"subagent_type":"general-purpose","description":"fg","prompt":"FG","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S3"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_REUSE","type":"tool_result","content":[{"type":"text","text":"FG-REAL-OUTPUT"}]}]},"parent_tool_use_id":null,"session_id":"S3"}"#,
        #"{"type":"result","subtype":"success","session_id":"S3","result":"done"}"#,
    ]

    @Test
    func foregroundWithReusedToolUseIdAfterBackgroundIsNotSuppressed() async throws {
        let events = try await collect(Self.reusedIdLines)
        // 再利用された id が fg（run_in_background:false）へ切り替わったら、その launcher 出力は
        // 抑制されず .subAgentOutput として残る。
        #expect(events.contains {
            if case .subAgentOutput("toolu_REUSE", let text) = $0 { return text.contains("FG-REAL-OUTPUT") }
            return false
        }, "reused-id foreground output must not be suppressed by sticky background state")
        // bg 側のメタデータは依然として漏れない。
        for needle in ["Async agent launched successfully", "internal metadata", "agentId"] {
            #expect(!events.contains { Self.anyText($0).contains(needle) })
        }
    }

    /// 実データ忠実（runtime で判明）: 非同期 Agent ツールは run_in_background フラグを持たず、
    /// launcher tool_result に "This tool result is internal metadata" 署名付きの起動確認メタデータを返す。
    /// フラグ判定では捕捉できないため署名で抑制することを固定する。
    private static let asyncAgentNoFlagLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S4","tools":["Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_ASYNC","name":"Agent","input":{"subagent_type":"Explore","description":"loopflow を調査","prompt":"このリポジトリの loopflow について ASYNC-PROMPT-NEEDLE を返せ。"}}]},"parent_tool_use_id":null,"session_id":"S4"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t4","tool_use_id":"toolu_ASYNC","task_type":"local_agent","subagent_type":"Explore","description":"loopflow を調査"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_ASYNC","type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully. (This tool result is internal metadata — never quote or paste any part of it, including the agentId below, into a user-facing reply.)\nagentId: a2420c818a860c555 (internal ID - do not mention to user.) output_file: /private/tmp/x.output"}]}]},"parent_tool_use_id":null,"session_id":"S4"}"#,
        #"{"type":"system","subtype":"task_notification","task_id":"t4","tool_use_id":"toolu_ASYNC","status":"completed","summary":"done","output_file":"/tmp/does-not-exist-async.jsonl"}"#,
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"MAIN-DONE"}]},"parent_tool_use_id":null,"session_id":"S4"}"#,
        #"{"type":"result","subtype":"success","session_id":"S4","result":"MAIN-DONE"}"#,
    ]

    @Test
    func asyncAgentLaunchMetadataSuppressedWithoutRunInBackgroundFlag() async throws {
        let events = try await collect(Self.asyncAgentNoFlagLines)

        // (a) run_in_background フラグ無しでも起動確認メタデータは抑制される（署名判定）。
        #expect(!events.contains {
            if case .subAgentOutput(let id, _) = $0 { return id == "toolu_ASYNC" }
            return false
        }, "async launch metadata must be suppressed even without run_in_background flag")
        for needle in ["Async agent launched successfully", "internal metadata", "agentId"] {
            #expect(!events.contains { Self.anyText($0).contains(needle) },
                    "launch metadata leaked: \(needle)")
        }
        // (b) プロンプトは表示される。
        #expect(events.contains {
            if case .subAgentActivity(let id, .prompt, _, let text) = $0 {
                return id == "toolu_ASYNC" && text.contains("ASYNC-PROMPT-NEEDLE")
            }
            return false
        }, "prompt must be surfaced for async Agent launch")
    }

    /// stage2 レビュー指摘（false-positive/silent-loss）: フォアグラウンドの正当出力が本文の
    /// 途中で起動メタデータの2フレーズを「引用」しても、それは起動 ack ではないので抑制しない。
    /// （本文が "Async agent launched successfully" で始まらない＝hasPrefix で救われる）
    private static let foregroundQuotingMetadataLines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S5","tools":["Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_FG5","name":"Agent","input":{"subagent_type":"Explore","description":"chat正規化調査","prompt":"FG5-NEEDLE","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S5"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_FG5","type":"tool_result","content":[{"type":"text","text":"調査結果 FG5-REAL-OUTPUT: 抑制は 'Async agent launched successfully' かつ 'This tool result is internal metadata' を含むかで判定している。"}]}]},"parent_tool_use_id":null,"session_id":"S5"}"#,
        #"{"type":"result","subtype":"success","session_id":"S5","result":"done"}"#,
    ]

    @Test
    func foregroundOutputQuotingMetadataPhrasesIsNotSuppressed() async throws {
        let events = try await collect(Self.foregroundQuotingMetadataLines)
        // 本文途中で2フレーズを引用した正当出力は抑制されず .subAgentOutput として残る。
        #expect(events.contains {
            if case .subAgentOutput("toolu_FG5", let text) = $0 { return text.contains("FG5-REAL-OUTPUT") }
            return false
        }, "foreground output that merely quotes metadata phrases must not be silently suppressed")
    }

    // MARK: - helpers

    private func collect(_ lines: [String]) async throws -> [NormalizedChatEvent] {
        let mock = PromptMockLineTransport()
        let recorder = PromptMockTransportRecorder(mock)
        let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in lines { mock.receive(line) }
        await mock.close()

        var events: [NormalizedChatEvent] = []
        for _ in 0..<200 {
            guard let ev = await iterator.next() else { break }
            events.append(ev)
            if case .turnCompleted = ev { break }
        }
        return events
    }

    /// 全イベント種からテキストを抽出（メタデータ非出現の全数検査用）。
    private static func anyText(_ event: NormalizedChatEvent) -> String {
        switch event {
        case .subAgentActivity(_, _, _, let text), .subAgentOutput(_, let text):
            return text
        case .subAgentStarted(_, let type, let desc):
            return type + " " + desc
        case .subAgentCompleted(_, _, let summary, let outputFile):
            return summary + " " + (outputFile ?? "")
        default:
            return mainBoundText(event)
        }
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

// MARK: - 最小 transport（他テストの private 版は不可視のため自前定義）

private final class PromptMockLineTransport: LineDelimitedTransport, @unchecked Sendable {
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

private final class PromptMockTransportRecorder: @unchecked Sendable {
    private let transport: PromptMockLineTransport
    init(_ transport: PromptMockLineTransport) { self.transport = transport }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        transport
    }
}
