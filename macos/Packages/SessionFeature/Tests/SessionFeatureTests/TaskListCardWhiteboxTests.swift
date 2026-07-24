import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

@Test @MainActor
func taskListUpdatesKeepOneFixedCardForEmptyAndDuplicateTitles() async throws {
    let client = TaskListCardWhiteboxClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-task-list-whitebox"
    )

    client.yield(.taskListUpdated(tasks: []))
    try await waitForTaskListCard { taskListCards(in: viewModel).count == 1 }
    client.yield(.taskListUpdated(tasks: [
        AgentTaskItem(id: "first", title: "同じ項目", status: .pending),
        AgentTaskItem(id: "second", title: "同じ項目", status: .completed),
    ]))
    try await waitForTaskListCard { taskListCards(in: viewModel).first?.tasks.count == 2 }

    let cards = taskListCards(in: viewModel)
    #expect(cards.count == 1)
    #expect(cards.first?.id == "task-list")
    #expect(cards.first?.tasks.map(\.id) == ["first", "second"])
    #expect(cards.first?.tasks.map(\.status) == [.pending, .completed])
}

@MainActor
private func taskListCards(in viewModel: ChatSessionViewModel) -> [(id: String, tasks: [AgentTaskItem])] {
    viewModel.transcript.compactMap {
        guard case .taskList(let id, let tasks, _) = $0 else { return nil }
        return (id, tasks)
    }
}

@MainActor
private func waitForTaskListCard(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for task-list card")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

private final class TaskListCardWhiteboxClient: StructuredAgentClient, @unchecked Sendable {
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
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}
