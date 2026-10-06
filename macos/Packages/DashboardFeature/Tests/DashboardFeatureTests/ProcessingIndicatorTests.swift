// showsProcessingIndicator は「主ターン running またはバックグラウンド
// タスク/サブエージェント継続中」で true。turnCompleted で status が .idle に落ちても、
// 継続中の処理があるあいだは true を保つ。interrupt / error では消える。

import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@MainActor
private func indicatorVM() -> (ChatSessionViewModel, EventYieldingStructuredClient) {
    let client = EventYieldingStructuredClient()
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

@MainActor
private func processingIndicatorCodexVM(
    transport: ScriptedAppServerTransport = ScriptedAppServerTransport()
) -> (ChatSessionViewModel, ScriptedAppServerTransport) {
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-processing-indicator-work"
    )
    return (vm, transport)
}

@Test @MainActor
func processingIndicator_codexIgnoresIdleThreadStatusWhileTurnIsRunning() async throws {
    let (vm, transport) = processingIndicatorCodexVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    try await waitUntil { vm.status == .running }

    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-1","status":{"type":"idle"}}}
    """)
    try await Task.sleep(for: .milliseconds(50))

    #expect(vm.status == .running)
}
