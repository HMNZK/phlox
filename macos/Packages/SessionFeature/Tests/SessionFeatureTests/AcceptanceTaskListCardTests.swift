import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-2 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-2.md
// 目的: taskListUpdated イベントを transcript の「タスクリストカード」（ChatItem.taskList）へ
//       反映する。カードは 1 セッションの transcript に 1 枚だけ置かれ、更新のたびに
//       最新スナップショットへ置換される（更新ごとの新カード追加でチャットを埋めない）。

// MARK: - ハーネス（ChatRemoteSessionNotifierTests と同型）

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
func taskListUpdated_appendsSingleTaskListCard() async throws {
    let (vm, client) = makeViewModel()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "t1", title: "調査する", status: .inProgress),
        AgentTaskItem(id: "t2", title: "実装する", status: .pending),
    ]))
    try await waitUntil { !taskListItems(vm).isEmpty }

    let cards = taskListItems(vm)
    #expect(cards.count == 1, "taskListUpdated → transcript にタスクリストカードが 1 枚現れること")
    #expect(cards.first?.tasks.map(\.title) == ["調査する", "実装する"])
    #expect(cards.first?.tasks.map(\.status) == [.inProgress, .pending])
}

@Test @MainActor
func taskListUpdated_replacesExistingCardInsteadOfAppending() async throws {
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
    try await waitUntil { taskListItems(vm).first?.tasks.count == 3 }

    let cards = taskListItems(vm)
    #expect(cards.count == 1, "更新のたびに新カードを追加せず、既存カードを最新スナップショットへ置換すること")
    #expect(cards.first?.tasks.map(\.status) == [.completed, .inProgress, .pending])
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
