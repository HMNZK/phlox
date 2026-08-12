import Foundation
import Observation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-6 の Dashboard → app-server ChatSessionView の実合成経路を固定する。
/// SwiftUI の View 本体を mock せず、DashboardViewModel が作った実セッションと
/// AppRouter の選択状態を通して、Codex surface が到達可能であることを検査する。
@Suite("AcceptanceCodexChatParityRouteTests")
@MainActor
struct AcceptanceCodexChatParityRouteTests {
    private final class RouteClient: StructuredAgentClient, @unchecked Sendable {
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

    private enum ObservationWaitError: Error {
        case timedOut
    }

    private func awaitObservation(
        timeout: Duration = .seconds(2),
        observing: @escaping () -> Void,
        trigger: () -> Void
    ) async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            observing()
        } onChange: {
            continuation.yield()
            continuation.finish()
        }
        trigger()
        defer { continuation.finish() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                guard await iterator.next() != nil else {
                    throw ObservationWaitError.timedOut
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ObservationWaitError.timedOut
            }
            defer { group.cancelAll() }
            guard try await group.next() != nil else {
                throw ObservationWaitError.timedOut
            }
        }
    }

    private func withRemovedSession<T>(
        _ dashboard: DashboardViewModel,
        id: SessionID,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            let result = try await operation()
            _ = await dashboard.removeSession(id)
            return result
        } catch {
            _ = await dashboard.removeSession(id)
            throw error
        }
    }

    @Test("Codex app-server セッションは Dashboard の single route から既存 Chat surface へ届く")
    func codexAppServerSessionIsReachableFromDashboardRoute() async throws {
        let client = RouteClient()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
            appServerClientFactory: { _, _, _, _, _ in client }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let sessionID = try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        try await withRemovedSession(dashboard, id: sessionID) {
            let node = try #require(dashboard.sessionNode(id: sessionID))
            guard case .appServer(let chat) = node else {
                Issue.record("Codex app-server spawn が ChatSessionView の node になっていない")
                return
            }

            let router = AppRouter(viewMode: .team)
            router.openSingle(sessionID: sessionID)
            #expect(router.viewMode == .single)
            #expect(router.selectedSession == sessionID)
            #expect(chat.agentRef == .builtin(.codex))

            // 実セッションの event stream を通して、route 先で task/background/sub-agent
            // の surface が更新されることを確認する。View の存在だけは検査しない。
            try await awaitObservation(
                observing: { _ = chat.subAgents },
                trigger: {
                    client.yield(.taskListUpdated(tasks: [
                        AgentTaskItem(id: "route-plan", title: "route", status: .inProgress),
                    ]))
                    client.yield(.backgroundTaskStarted(
                        taskId: "route-process",
                        taskType: "backgroundTerminal",
                        description: "route command",
                        toolUseId: "route-item"
                    ))
                    client.yield(.subAgentStarted(
                        toolUseId: "route-child",
                        subagentType: "worker",
                        description: "route child"
                    ))
                }
            )

            #expect(chat.transcript.contains { item in
                if case .taskList(_, let tasks, _) = item {
                    return tasks.map(\.id) == ["route-plan"]
                }
                return false
            })
            #expect(chat.runningBackgroundTasks.contains { $0.taskId == "route-process" },
                    "Dashboard route から Codex background terminal を一覧 surface へ届けること")
            #expect(chat.subAgents.contains { $0.id == "route-child" })
        }
    }
}
