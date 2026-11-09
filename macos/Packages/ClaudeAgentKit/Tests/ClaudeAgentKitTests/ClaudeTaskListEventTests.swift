import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// Claude Code のタスクリスト（TodoWrite: todos 全量スナップショット、status ∈ {pending,in_progress,completed}、
// および TaskCreate / TaskUpdate）を NormalizedChatEvent.taskListUpdated へ正規化する。
// TodoWrite を汎用「ツール実行」カードへ埋没させない。

/// turnCompleted（result 行）まで受信したイベントを集める。ハングを避けるため上限つき。
private func collectEventsUntilTurnCompleted(
    _ client: ClaudeChatClient,
    maxEvents: Int = 20
) async -> [NormalizedChatEvent] {
    var events: [NormalizedChatEvent] = []
    var iterator = client.events.makeAsyncIterator()
    for _ in 0..<maxEvents {
        guard let event = await iterator.next() else { break }
        events.append(event)
        if case .turnCompleted = event { break }
    }
    return events
}

private func taskListEvents(_ events: [NormalizedChatEvent]) -> [[AgentTaskItem]] {
    events.compactMap {
        if case .taskListUpdated(let tasks) = $0 { return tasks }
        return nil
    }
}

@Test func todoWriteSnapshotIsNormalizedAsTaskListUpdated() async throws {
    let mock = TaskListMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    try await client.start()

    mock.receive(
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_T1","name":"TodoWrite","input":{"todos":[{"content":"調査する","activeForm":"調査中","status":"completed"},{"content":"実装する","activeForm":"実装中","status":"in_progress"},{"content":"検証する","activeForm":"検証中","status":"pending"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    )
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let events = await collectEventsUntilTurnCompleted(client)
    let snapshots = taskListEvents(events)
    #expect(snapshots.count == 1, "TodoWrite 1回 → taskListUpdated 1回。events=\(events)")
    let tasks = try #require(snapshots.first)
    #expect(tasks.map(\.title) == ["調査する", "実装する", "検証する"], "順序・タイトル（content）を保持すること")
    #expect(tasks.map(\.status) == [.completed, .inProgress, .pending], "status の対応: completed/in_progress/pending")

    // TodoWrite を汎用「ツール実行」（commandExecution）へ埋没させない。
    let commandEvents = events.filter {
        if case .commandExecution = $0 { return true }
        return false
    }
    #expect(commandEvents.isEmpty, "TodoWrite は commandExecution として流さないこと。events=\(events)")
    await client.close()
}

@Test func todoWriteResendKeepsStableIdsAndReflectsStatusChange() async throws {
    let mock = TaskListMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    try await client.start()

    mock.receive(
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_T1","name":"TodoWrite","input":{"todos":[{"content":"調査する","activeForm":"調査中","status":"in_progress"},{"content":"実装する","activeForm":"実装中","status":"pending"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    )
    mock.receive(
        #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"toolu_T2","name":"TodoWrite","input":{"todos":[{"content":"調査する","activeForm":"調査中","status":"completed"},{"content":"実装する","activeForm":"実装中","status":"in_progress"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    )
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let snapshots = taskListEvents(await collectEventsUntilTurnCompleted(client))
    #expect(snapshots.count == 2, "TodoWrite 2回 → taskListUpdated 2回")
    let first = try #require(snapshots.first)
    let second = try #require(snapshots.last)
    #expect(
        first.map(\.id) == second.map(\.id),
        "同一タスク（同じ content・同じ位置）の id はスナップショット間で安定していること（UI の置換・アニメの同一性のため）"
    )
    #expect(second.map(\.status) == [.completed, .inProgress], "2回目のスナップショットの status が反映されること")
    await client.close()
}

@Test func todoWriteHandlesEmptyUnknownAndDuplicateTasksSafely() async throws {
    let mock = TaskListMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    try await client.start()

    mock.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_empty","name":"TodoWrite","input":{"todos":[]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"toolu_duplicates","name":"TodoWrite","input":{"todos":[{"content":"同じ項目","status":"unknown"},{"content":"同じ項目","status":"pending"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let snapshots = taskListEvents(await collectEventsUntilTurnCompleted(client))

    #expect(snapshots.count == 2)
    let emptySnapshot = try #require(snapshots.first)
    let duplicateSnapshot = try #require(snapshots.last)
    #expect(emptySnapshot.isEmpty)
    #expect(duplicateSnapshot.map(\.title) == ["同じ項目", "同じ項目"])
    #expect(duplicateSnapshot.map(\.status) == [.pending, .pending])
    #expect(duplicateSnapshot[0].id != duplicateSnapshot[1].id)
    await client.close()
}

// 実 CLI（Claude Code 2.1.319）の stream-json の形。`cli-taskcreate-probe.jsonl` から、確認に要る行の形だけを抜いた。
// 以前の旧い形（`toolUseResult` のキャメルケース）は実 CLI が送らない形で、テストの誤りだった（ADR 0228）。
// 作成結果は `tool_use_result.task.id`、assistant 行・user 行とも session_id・uuid などの付属フィールドを持つ。
@Test func taskCreateAndUpdateUseTaskIdentifierFromRealToolResultShape() async throws {
    let mock = TaskListMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    try await client.start()

    mock.receive(#"{"type":"assistant","message":{"model":"claude-haiku-5-5","id":"msg_1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_create","name":"TaskCreate","input":{"subject":"実装する","description":"実装する作業"},"caller":{"type":"direct"}}]},"parent_tool_use_id":null,"session_id":"S1","uuid":"u1"}"#)
    mock.receive(#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_create","type":"tool_result","content":"Task #1 created successfully: 実装する"}]},"parent_tool_use_id":null,"session_id":"S1","uuid":"u2","timestamp":"2026-11-07T11:59:39.740Z","tool_use_result":{"task":{"id":"1","subject":"実装する","description":"実装する作業"}},"tool_result_meta":[{"id":"toolu_create","permission_decision":{"decision":"accept","source":"config"}}]}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_start","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"},"caller":{"type":"direct"}}]},"parent_tool_use_id":null,"session_id":"S1","uuid":"u3"}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"msg_3","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_done","name":"TaskUpdate","input":{"taskId":"1","status":"completed"},"caller":{"type":"direct"}}]},"parent_tool_use_id":null,"session_id":"S1","uuid":"u4"}"#)
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let snapshots = taskListEvents(await collectEventsUntilTurnCompleted(client))

    #expect(snapshots.count == 3, "作成 1 回・更新 2 回。snapshots=\(snapshots)")
    #expect(snapshots.map { $0.map(\.id) } == [["1"], ["1"], ["1"]])
    #expect(snapshots.map { $0.map(\.title) } == [["実装する"], ["実装する"], ["実装する"]])
    #expect(snapshots.map { $0.map(\.status) } == [[.pending], [.inProgress], [.completed]])
    await client.close()
}

@Test func todoWriteWithRealEnvelopeIsNormalizedAsTaskListUpdated() async throws {
    let mock = TaskListMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    try await client.start()

    mock.receive(#"{"type":"assistant","message":{"model":"claude-haiku-5-5","id":"msg_1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_todo","name":"TodoWrite","input":{"todos":[{"content":"調査する","activeForm":"調査中","status":"in_progress"},{"content":"実装する","activeForm":"実装中","status":"pending"}]},"caller":{"type":"direct"}}],"stop_reason":null},"parent_tool_use_id":null,"session_id":"S1","uuid":"u1","timestamp":"2026-11-07T11:59:39.735Z"}"#)
    mock.receive(#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_todo","type":"tool_result","content":"Todos have been modified successfully"}]},"parent_tool_use_id":null,"session_id":"S1","uuid":"u2","tool_use_result":{"oldTodos":[],"newTodos":[]}}"#)
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let snapshots = taskListEvents(await collectEventsUntilTurnCompleted(client))

    #expect(snapshots.count == 1, "snapshots=\(snapshots)")
    #expect(snapshots.first?.map(\.title) == ["調査する", "実装する"])
    #expect(snapshots.first?.map(\.status) == [.inProgress, .pending])
    await client.close()
}

// Phlox が起動する Claude（チャットの経路）には、タスクの道具を使えるようにする環境変数を渡す（ADR 0228）。
// 道具を使うようには指示しない。呼び出し側が同じ変数を指定していれば、そちらが優先する。
@Test func spawnedClaudeGetsTodoToolsEnvironmentVariable() async throws {
    let mock = TaskListMockTransport()
    let captured = EnvironmentBox()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "S1"],
        transportFactory: { _, _, environment, _ in
            captured.set(environment)
            return mock
        }
    )
    try await client.start()

    let environment = try #require(captured.value)
    #expect(environment["CLAUDE_CODE_ENABLE_TODO_TOOLS"] == "1")
    #expect(environment["PHLOX_SESSION_ID"] == "S1", "呼び出し側の環境変数は残す")
    await client.close()
}

@Test func callerCanOverrideTodoToolsEnvironmentVariable() async throws {
    let mock = TaskListMockTransport()
    let captured = EnvironmentBox()
    let client = ClaudeChatClient(
        environment: ["CLAUDE_CODE_ENABLE_TODO_TOOLS": "0"],
        transportFactory: { _, _, environment, _ in
            captured.set(environment)
            return mock
        }
    )
    try await client.start()

    #expect(captured.value?["CLAUDE_CODE_ENABLE_TODO_TOOLS"] == "0")
    await client.close()
}

private final class EnvironmentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]?
    var value: [String: String]? { lock.withLock { stored } }
    func set(_ environment: [String: String]) { lock.withLock { stored = environment } }
}

// MARK: - テストダブル

private final class TaskListMockTransport: LineDelimitedTransport, @unchecked Sendable {
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
