// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — showsProcessingIndicator は「主ターン running またはバックグラウンド
// タスク/サブエージェント継続中」で true。turnCompleted で status が .idle に落ちても、
// 継続中の処理があるあいだは true を保つ。interrupt / error では消える。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class IndicatorFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

@MainActor
private func indicatorVM() -> (ChatSessionViewModel, IndicatorFakeClient) {
    let client = IndicatorFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-indicator-work"
    )
    return (vm, client)
}

@Test @MainActor
func processingIndicator_runningTurn_showsIndicator() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    #expect(vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_staysVisibleWhileBackgroundTaskContinuesAfterTurnCompleted() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.backgroundTaskStarted(
        taskId: "bg-1", taskType: "local_agent", description: "subtask", toolUseId: nil
    ))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    // 主ターンは完了したが background task が継続中 → インジケータは出続ける。
    #expect(vm.showsProcessingIndicator)

    client.yield(.backgroundTaskCompleted(taskId: "bg-1", status: "completed", summary: "done"))
    try await waitUntil { !vm.showsProcessingIndicator }
    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_staysVisibleWhileSubAgentRunsAfterTurnCompleted() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.subAgentStarted(toolUseId: "tool-1", subagentType: "explore", description: "scan"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(vm.showsProcessingIndicator)

    client.yield(.subAgentCompleted(toolUseId: "tool-1", status: "completed", summary: "ok", outputFile: nil))
    try await waitUntil { !vm.showsProcessingIndicator }
    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_clearsOnInterruptEvenWithBackgroundTask() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.backgroundTaskStarted(
        taskId: "bg-2", taskType: "local_agent", description: "subtask", toolUseId: nil
    ))
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_clearsOnErrorEvenWithBackgroundTask() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.backgroundTaskStarted(
        taskId: "bg-3", taskType: "local_agent", description: "subtask", toolUseId: nil
    ))
    client.yield(.error(message: "boom"))
    try await waitUntil { vm.status == .error(message: "boom") }

    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_clearsOnInterruptEvenWithRunningSubAgent() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.subAgentStarted(toolUseId: "tool-i1", subagentType: "explore", description: "scan"))
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_clearsOnErrorEvenWithRunningSubAgent() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.subAgentStarted(toolUseId: "tool-e1", subagentType: "explore", description: "scan"))
    client.yield(.error(message: "boom"))
    try await waitUntil { vm.status == .error(message: "boom") }

    #expect(!vm.showsProcessingIndicator)
}

@Test @MainActor
func processingIndicator_idleWithoutWork_isHidden() async throws {
    let (vm, client) = indicatorVM()

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(!vm.showsProcessingIndicator)
}
