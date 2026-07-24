import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
import StructuredChatKit
import TerminalUI
@testable import SessionFeature

private final class DisplayStatusStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        let stream = AsyncStream<NormalizedChatEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
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

private final class DisplayStatusPTYManager: PTYManagerProtocol, Sendable {
    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        id ?? SessionID()
    }

    func write(_ data: Data, to id: SessionID) async throws {}
    func kill(_ id: SessionID) async {}
    func outputStream(for id: SessionID) -> AsyncStream<Data> { AsyncStream { $0.finish() } }
    func exitStream(for id: SessionID) -> AsyncStream<Int32> { AsyncStream { $0.finish() } }
}

@MainActor
private func waitForDisplayStatusCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

@Test @MainActor
func chatDisplayStatusPromotesIdleWhileSubAgentRuns() async throws {
    let client = DisplayStatusStructuredClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-display-status-test"
    )

    client.yield(.turnStarted)
    client.yield(.subAgentStarted(toolUseId: "subagent-1", subagentType: "general-purpose", description: "background work"))
    client.yield(.turnCompleted(nativeSessionId: nil))

    try await waitForDisplayStatusCondition {
        viewModel.status == .idle && viewModel.subAgents.contains { $0.status == .running }
    }
    #expect(viewModel.displayStatus == .running)
}

@Test @MainActor
func chatDisplayStatusRemainsIdleWithoutBackgroundWork() async throws {
    let client = DisplayStatusStructuredClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-display-status-test"
    )

    client.yield(.turnStarted)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitForDisplayStatusCondition { viewModel.status == .idle }

    #expect(viewModel.displayStatus == .idle)
}

@Test @MainActor
func ptyDisplayStatusMatchesIdleStatus() async throws {
    let sessionID = SessionID()
    let stream = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let viewModel = SessionViewModel(
        id: sessionID,
        ptyManager: DisplayStatusPTYManager(),
        hookEvents: stream.stream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: .init(
            command: "/usr/bin/true",
            args: [],
            env: [:],
            workingDirectory: nil,
            kind: .claudeCode
        )
    )

    await viewModel.start()
    stream.continuation.yield((sessionID, .sessionStart))
    try await waitForDisplayStatusCondition { viewModel.status == .idle }

    #expect(viewModel.displayStatus == viewModel.status)
    #expect(viewModel.displayStatus == .idle)
}
