import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// taskListUpdated イベントを transcript のタスクリストのスナップショット（ChatItem.taskList）へ反映する。
// 更新のたびに一意の id（task-list-<UUID>）で追記し、経過を残す（ADR 0226・設計 §3.3）。
// 同じ入力の中で同じ内容を続けて追記しない件は AgentStatusEventTests が持つ。

// MARK: - ハーネス

private final class TaskListFakeAgentClient: StructuredAgentClient, @unchecked Sendable {
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

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
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
private func makeViewModel() -> (ChatSessionViewModel, TaskListFakeAgentClient) {
    let client = TaskListFakeAgentClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-task-list-test"
    )
    return (vm, client)
}

@MainActor
private func taskListItems(_ vm: ChatSessionViewModel) -> [(id: String, tasks: [AgentTaskItem])] {
    vm.transcript.compactMap {
        if case .taskList(let id, let tasks, _) = $0 { return (id, tasks) }
        return nil
    }
}

// MARK: - Tests

@Test @MainActor
func taskListUpdated_appendsFirstSnapshot() async throws {
    let (vm, client) = makeViewModel()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "t1", title: "調査する", status: .inProgress),
        AgentTaskItem(id: "t2", title: "実装する", status: .pending),
    ]))
    try await waitUntil { !taskListItems(vm).isEmpty }

    let cards = taskListItems(vm)
    #expect(cards.count == 1, "taskListUpdated → transcript にタスクリストのスナップショットが 1 件現れること")
    #expect(cards.first?.tasks.map(\.title) == ["調査する", "実装する"])
    #expect(cards.first?.tasks.map(\.status) == [.inProgress, .pending])
}

@Test @MainActor
func taskListUpdated_appendsNewSnapshotInsteadOfReplacing() async throws {
    let (vm, client) = makeViewModel()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "t1", title: "調査する", status: .inProgress),
        AgentTaskItem(id: "t2", title: "実装する", status: .pending),
    ]))
    try await waitUntil { !taskListItems(vm).isEmpty }

    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "t1", title: "調査する", status: .completed),
        AgentTaskItem(id: "t2", title: "実装する", status: .inProgress),
        AgentTaskItem(id: "t3", title: "検証する", status: .pending),
    ]))
    try await waitUntil { taskListItems(vm).count == 2 }

    let cards = taskListItems(vm)
    #expect(cards.count == 2, "更新のたびに置換せず、スナップショットを追記すること")
    #expect(cards.first?.tasks.map(\.status) == [.inProgress, .pending], "最初のスナップショットは書き換わらない")
    #expect(cards.last?.tasks.map(\.status) == [.completed, .inProgress, .pending])
    #expect(cards.first?.id != cards.last?.id, "スナップショットごとに一意の id")
}

@Test
func taskListChatItem_roundTripsThroughCodable() throws {
    let item = ChatItem.taskList(
        id: "task-list",
        tasks: [
            AgentTaskItem(id: "t1", title: "調査する", status: .completed),
            AgentTaskItem(id: "t2", title: "実装する", status: .inProgress),
        ],
        timestamp: Date(timeIntervalSince1970: 1_753_000_000)
    )
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(ChatItem.self, from: data)
    #expect(decoded == item, "タスクリストカードは transcript 永続化（Codable）を往復できること")
}

@Test @MainActor
func taskListUpdates_appendSnapshotsForEmptyAndDuplicateTitles() async throws {
    let (vm, client) = makeViewModel()

    client.yield(.taskListUpdated(tasks: []))
    try await waitUntil { taskListItems(vm).count == 1 }
    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "first", title: "同じ項目", status: .pending),
        AgentTaskItem(id: "second", title: "同じ項目", status: .completed),
    ]))
    try await waitUntil { taskListItems(vm).count == 2 }

    let cards = taskListItems(vm)
    #expect(cards.count == 2)
    #expect(cards.allSatisfy { $0.id.hasPrefix("task-list-") })
    #expect(cards.first?.tasks.isEmpty == true)
    #expect(cards.last?.tasks.map(\.id) == ["first", "second"])
    #expect(cards.last?.tasks.map(\.status) == [.pending, .completed])
}
