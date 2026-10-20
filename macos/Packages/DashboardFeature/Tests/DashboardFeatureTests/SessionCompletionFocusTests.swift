import Foundation
import AppKit
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature
@testable import SessionFeature

@Suite @MainActor struct SessionCompletionFocusTests {
    @Test(arguments: [ViewMode.single, .grid])
    func firstAndRepeatedCompletionsRemainUntilFocusChanges(mode: ViewMode) async throws {
        let fixture = try await fixture()
        defer { cleanupTemporaryWorkspaceRoot(fixture.root); fixture.events.finish() }
        let (dashboard, router) = (fixture.dashboard, fixture.router)
        let completed = try #require(dashboard.sessions.first { $0.id == fixture.completed })
        let other = try #require(dashboard.sessions.first { $0.id == fixture.other })
        router.viewMode = mode
        router.selectTab(.chat(completed.id), in: fixture.projectID)
        let focus = TestWindowFocus()
        let _ = NSApplication.shared
        let host = NSHostingView(rootView: CompletionFocusTestView(
            dashboard: dashboard, router: router, focus: focus
        ))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await settle(host)

        for _ in 0..<2 {
            fixture.events.yield((completed.id, .userPromptSubmit(turnId: nil)))
            try await waitUntil { completed.status == .running }
            fixture.events.yield((completed.id, .stop(turnId: nil)))
            try await waitUntil { completed.status != .running }
            try await settle(host)
            #expect(completed.hasUnseenCompletion)
            #expect(dashboard.sessionNode(id: completed.id)?.tabDisplayState == .doneUnread)
        }

        // 完了後に会話を開いたまま再実行しても、上の2回とも表示を残す。
        // 別の会話を選んでも、元の会話のチェックは消さない。
        router.selectTab(.chat(other.id), in: fixture.projectID)
        try await settle(host)
        #expect(completed.hasUnseenCompletion)
        router.selectTab(.chat(completed.id), in: fixture.projectID)
        try await waitUntil { !completed.hasUnseenCompletion }

        // 背面での完了も残し、ウインドウに戻った時に消す。
        focus.isFocused = false
        try await settle(host)
        fixture.events.yield((completed.id, .userPromptSubmit(turnId: nil)))
        try await waitUntil { completed.status == .running }
        fixture.events.yield((completed.id, .stop(turnId: nil)))
        try await waitUntil { completed.status != .running }
        try await settle(host)
        #expect(completed.hasUnseenCompletion)
        focus.isFocused = true
        try await waitUntil { !completed.hasUnseenCompletion }
        for id in [completed.id, other.id] { _ = await dashboard.removeSession(id) }
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    @Test(arguments: [ViewMode.single, .grid])
    func completionRemainsUntilItsConversationHasFocus(mode: ViewMode) async throws {
        let fixture = try await fixture()
        defer { cleanupTemporaryWorkspaceRoot(fixture.root); fixture.events.finish() }
        let (dashboard, router) = (fixture.dashboard, fixture.router)
        let completed = try #require(dashboard.sessions.first { $0.id == fixture.completed })
        let other = try #require(dashboard.sessions.first { $0.id == fixture.other })
        router.viewMode = mode

        fixture.events.yield((completed.id, .userPromptSubmit(turnId: nil)))
        try await waitUntil { completed.status == .running }
        fixture.events.yield((completed.id, .stop(turnId: nil)))
        try await waitUntil { completed.hasUnseenCompletion }
        #expect(dashboard.sessionNode(id: completed.id)?.tabDisplayState == .doneUnread)

        router.selectTab(.chat(other.id), in: fixture.projectID)
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: true)
        #expect(completed.hasUnseenCompletion)

        router.selectTab(.chat(completed.id), in: fixture.projectID)
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: false)
        #expect(completed.hasUnseenCompletion)

        other.hasUnseenCompletion = true
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: true)
        #expect(!completed.hasUnseenCompletion)
        #expect(dashboard.sessionNode(id: completed.id)?.tabDisplayState == .idle)
        #expect(other.hasUnseenCompletion)
        for id in [completed.id, other.id] { _ = await dashboard.removeSession(id) }
    }

    @Test func nonConversationTabsAndNewChatPreserveTheCompletion() async throws {
        let fixture = try await fixture()
        defer { cleanupTemporaryWorkspaceRoot(fixture.root); fixture.events.finish() }
        let (dashboard, router) = (fixture.dashboard, fixture.router)
        let completed = try #require(dashboard.sessions.first { $0.id == fixture.completed })
        completed.hasUnseenCompletion = true
        router.selectTab(.chat(completed.id), in: fixture.projectID)
        router.openChildTab(.file("notes.txt"))
        try #require(router.tabs.layout(for: fixture.projectID).selected == .file("notes.txt"))
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: true)
        #expect(completed.hasUnseenCompletion)
        router.showNewChat(projectID: fixture.projectID)
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: true)
        #expect(completed.hasUnseenCompletion)
        router.selectTab(.chat(completed.id), in: fixture.projectID)
        dashboard.markFocusedCompletionSeen(router: router, isWindowFocused: true)
        #expect(!completed.hasUnseenCompletion)
        for id in [fixture.completed, fixture.other] { _ = await dashboard.removeSession(id) }
    }

    private func fixture() async throws -> (
        root: URL, dashboard: DashboardViewModel, router: AppRouter,
        projectID: ProjectID, completed: SessionID, other: SessionID,
        events: AsyncStream<(SessionID, HookEvent)>.Continuation
    ) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".verification/completion-check/focus-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: events, workspaceDirectory: root
        ))
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Completion", directoryPath: root.path))
        let completed = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let other = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        return (root, dashboard, AppRouter(), projectID, completed, other, continuation)
    }
}

@Observable @MainActor private final class TestWindowFocus {
    var isFocused = true
}

private struct CompletionFocusTestView: View {
    let dashboard: DashboardViewModel
    let router: AppRouter
    let focus: TestWindowFocus

    var body: some View {
        Color.clear.background {
            SessionCompletionFocusEvents(
                viewModel: dashboard, router: router, isWindowFocused: focus.isFocused
            )
        }
    }
}
