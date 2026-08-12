import Foundation
import Observation
import AppKit
import ApplicationServices
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-6 の Dashboard → app-server ChatSessionView の実合成経路を固定する。
/// SwiftUI の View 本体を mock せず、DashboardViewModel が作った実セッションと
/// AppRouter の選択状態を通して、Codex surface が到達可能であることを検査する。
@Suite("AcceptanceCodexChatParityRouteTests")
@MainActor
struct AcceptanceCodexChatParityRouteTests {
    private final class RouteClient: StructuredAgentClient, CodexSkillSelectionClient, @unchecked Sendable {
        let events: AsyncStream<NormalizedChatEvent>
        private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
        let skillEvents: AsyncStream<ThreadEvent>
        private let skillContinuation: AsyncStream<ThreadEvent>.Continuation

        init() {
            var captured: AsyncStream<NormalizedChatEvent>.Continuation?
            events = AsyncStream { captured = $0 }
            continuation = captured!
            var skillCaptured: AsyncStream<ThreadEvent>.Continuation?
            skillEvents = AsyncStream { skillCaptured = $0 }
            skillContinuation = skillCaptured!
        }

        func start() async {}
        func turnStart(_ input: [ChatInput]) async throws {}
        func resume(sessionRef: String) async throws {}
        func interrupt() async throws {}
        func close() async {
            continuation.finish()
            skillContinuation.finish()
        }

        func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
            SkillsListResponse(data: [SkillsListEntry(
                cwd: params.cwds?.first ?? "",
                errors: [],
                skills: [SkillMetadata(
                    description: "grid route skill",
                    enabled: true,
                    name: "review",
                    path: "/skills/review",
                    scope: .user
                )]
            )])
        }

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

    @Test("Codex grid route は single と同じ surface・skill 配線へ到達する")
    func codexGridRouteReusesChatSurfaceAndSkillWiring() async throws {
        let client = RouteClient()
        let sessionID = SessionID()
        let viewModel = ChatSessionViewModel(
            id: sessionID,
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/workspace/grid"
        )

        do {
            let skillState = try #require(viewModel.codexSkillSelectionState)
            await skillState.refresh()
            #expect(skillState.skills.map(\.path) == ["/skills/review"])
            viewModel.draft = "/review"

            let tree = try PaneTree(root: .leaf(
                id: PaneID("grid-route"),
                session: sessionID
            ))
            let pane = PaneLayoutView(
                sessions: [.appServer(viewModel)],
                tree: tree,
                focusedID: .constant(nil),
                onRemove: { _ in },
                onRename: { _ in },
                onChangeWorkspace: { _ in },
                onLayoutAction: { _ in }
            )
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.finishLaunching()
            let hosting = NSHostingView(rootView: pane)
            hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 720)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.alphaValue = 0
            window.contentView = hosting
            defer { window.close() }
            window.orderBack(nil)
            settleHeadlessView(hosting)

            let elements = axElements(in: app)
            #expect(elements.contains { $0.identifier == "CodexSessionSurface" })
            #expect(elements.contains { $0.identifier == "GridComposer.input" })
            #expect(elements.contains { $0.identifier == "GridComposer.suggestions" })
            let displayedText = Set(elements.flatMap {
                [$0.title, $0.value, $0.description].compactMap { $0 }
            })
            #expect(displayedText.contains { $0.contains("/review") })

        } catch {
            await viewModel.terminate()
            throw error
        }
        await viewModel.terminate()
    }
}

@MainActor
private func settleHeadlessView(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    for _ in 0..<3 {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        view.layoutSubtreeIfNeeded()
    }
}

private struct AXTestElement {
    let identifier: String?
    let title: String?
    let value: String?
    let description: String?
    let role: String?
}

@MainActor
private func axElements(in app: NSApplication) -> [AXTestElement] {
    let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    let windows = axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.flatMap(axElements(in:))
}

private func axElements(in element: AXUIElement) -> [AXTestElement] {
    let result = AXTestElement(
        identifier: axValue(element, kAXIdentifierAttribute) as? String,
        title: axValue(element, kAXTitleAttribute) as? String,
        value: axValue(element, kAXValueAttribute) as? String,
        description: axValue(element, kAXDescriptionAttribute) as? String,
        role: axValue(element, kAXRoleAttribute) as? String
    )
    let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [result] + children.flatMap(axElements(in:))
}

private func axValue(_ element: AXUIElement, _ attribute: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}
