import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-2 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-2.md
// 目的: Claude Code のタスクリスト（TodoWrite。実測: todos 全量スナップショット、
//       status ∈ {pending,in_progress,completed}）を NormalizedChatEvent.taskListUpdated へ
//       正規化する。TodoWrite を汎用「ツール実行」カードへ埋没させない。

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
    await client.start()

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
    await client.start()

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

// MARK: - テストダブル（AcceptanceBackgroundTaskEventsTests と同型）

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
