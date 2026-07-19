import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-25 受け入れテスト（PM 著・実装役は編集禁止）。
// 実測フィクスチャ（2026-07-03・claude 2.1.198・docs/agent-output/claude-bg-task-events-fixture.jsonl）:
//   system/task_started {task_id, tool_use_id, description, task_type: "local_bash"|"local_agent", subagent_type?}
//   system/task_updated {task_id, patch:{status,end_time}}   ← 正規化しない（notification が完了信号）
//   system/task_notification {task_id, tool_use_id, status, summary, output_file, usage}
// 契約: NormalizedChatEvent に backgroundTaskStarted / backgroundTaskCompleted を追加し、
// ClaudeChatClient が上記 system イベントを正規化する。task_updated と既知の無害 system
// subtype（init/thinking_tokens）は従来どおりイベントを出さない。

@Test func taskStartedEventsAreNormalizedForBashAndSubagent() async throws {
    let mock = BgMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(
        #"{"type":"system","subtype":"task_started","task_id":"bykplx1u6","tool_use_id":"toolu_01N","description":"Sleep 8 seconds then print BGDONE","task_type":"local_bash","uuid":"u1","session_id":"s1"}"#
    )
    mock.receive(
        #"{"type":"system","subtype":"task_started","task_id":"a6147d5fa6e66e7f2","tool_use_id":"toolu_01G","description":"hiとだけ返答","task_type":"local_agent","subagent_type":"general-purpose","prompt":"hi とだけ返答せよ。","uuid":"u2","session_id":"s1"}"#
    )

    #expect(await iterator.next() == .backgroundTaskStarted(
        taskId: "bykplx1u6",
        taskType: "local_bash",
        description: "Sleep 8 seconds then print BGDONE",
        toolUseId: "toolu_01N"
    ))
    // 実サブエージェント（local_agent かつ tool_use_id 有り）は subAgentStarted に正規化され、
    // バックグラウンドタスク・チップとしては出さない（task-3 でサブエージェント表現へ一本化）。
    #expect(await iterator.next() == .subAgentStarted(
        toolUseId: "toolu_01G",
        subagentType: "general-purpose",
        description: "hiとだけ返答"
    ))
    await client.close()
}

@Test func taskNotificationIsNormalizedAsCompletion() async throws {
    let mock = BgMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(
        #"{"type":"system","subtype":"task_notification","task_id":"bykplx1u6","tool_use_id":"toolu_01N","status":"completed","output_file":"/tmp/x","summary":"Background command \"Sleep\" completed (exit code 0)","uuid":"u3","session_id":"s1"}"#
    )

    #expect(await iterator.next() == .backgroundTaskCompleted(
        taskId: "bykplx1u6",
        status: "completed",
        summary: #"Background command "Sleep" completed (exit code 0)"#
    ))
    await client.close()
}

// status が未知でも silent drop せず completion として流す（安全側）。
@Test func unknownNotificationStatusStillCompletes() async throws {
    let mock = BgMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(
        #"{"type":"system","subtype":"task_notification","task_id":"t9","tool_use_id":"toolu_09","status":"failed","summary":"boom","uuid":"u4","session_id":"s1"}"#
    )

    #expect(await iterator.next() == .backgroundTaskCompleted(taskId: "t9", status: "failed", summary: "boom"))
    await client.close()
}

// task_updated と既知の無害 subtype はイベントを出さない（従来挙動維持）。
@Test func taskUpdatedAndBenignSystemSubtypesEmitNothing() async throws {
    let mock = BgMockTransport()
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(
        #"{"type":"system","subtype":"task_updated","task_id":"bykplx1u6","patch":{"status":"completed","end_time":1783019601521},"uuid":"u5","session_id":"s1"}"#
    )
    mock.receive(#"{"type":"system","subtype":"thinking_tokens","uuid":"u6","session_id":"s1"}"#)
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    // 上2行から何も yield されず、直接 turnCompleted が来る。
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

// MARK: - テストダブル

private final class BgMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        record(data)
    }

    private func record(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        sent.append(data)
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}
