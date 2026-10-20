import AppKit
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
import SessionFeature
import DesignSystem
@testable import DashboardFeature

private actor FirstCompletionClient: StructuredAgentClient {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@MainActor private final class TestApplicationActivity {
    var isActive = false
}

@Suite @MainActor struct FirstChatCompletionTests {
    @Test(arguments: [AgentKind.codex, .claudeCode, .cursor], [false, true])
    func activationBeforeFirstCompletionAcknowledgesVisibleConversation(kind: AgentKind, restored: Bool) async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".verification/session-activity-state/focus/fixtures/chat-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let client = FirstCompletionClient()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() },
            workspaceDirectory: root, agentBinaryPaths: [kind: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, _ in client }
        ))
        let defaultsSuite = "com.phlox.verification.first-chat-completion.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        dashboard.lastUsedChatSettingsStoreForTesting = LastUsedChatSettingsStore(defaults: defaults)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "初回完了", directoryPath: root.path))
        let router = AppRouter()
        router.showNewChat(projectID: projectID)
        let activity = TestApplicationActivity()
        let _ = NSApplication.shared
        let host = NSHostingView(rootView: FirstChatFocusHost(
            dashboard: dashboard, router: router, activity: activity
        ))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 200, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await settle(host)
        let id: SessionID
        if restored {
            id = try await dashboard.spawnNewSession(kind: kind, projectID: projectID, backend: .appServer)
            let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
            await vm.restore(threadId: "existing-chat", approvalPolicy: .named("never"), sandbox: .named("danger-full-access"))
            router.completeNewChat(sessionID: id, projectID: projectID)
            try await vm.sendText("復元後の最初の指示", submit: true)
        } else {
            id = try await dashboard.launchNewChat(NewChatLaunchRequest(
                projectID: projectID, agentRef: .builtin(kind),
                settings: .init(), usesWorktree: false, text: "最初の指示", attachments: []
            )) { id in router.completeNewChat(sessionID: id, projectID: projectID) }
        }
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        try await settle(host)
        activity.isActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await settle(host)

        for turn in 1...2 {
            if turn == 2 { try await vm.sendText("2回目の指示", submit: true) }
            client.continuation.yield(.turnStarted)
            client.continuation.yield(.agentMessageDelta(itemId: "reply-\(turn)", "OK"))
            client.continuation.yield(.turnCompleted(nativeSessionId: "first-chat-native"))
            try await waitUntil { vm.completedTurnSeq == turn }
            try await settle(host)
            #expect(!vm.hasUnseenCompletion, "開いて見ている会話の第\(turn)回の完了を既読にする")
            #expect(dashboard.sessionNode(id: id)?.tabDisplayState == .idle)
            if let output = ProcessInfo.processInfo.environment["FIRST_CHAT_COMPLETION_OUT"] {
                try await Task.sleep(for: .seconds(1.05))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let name = "\(kind.rawValue)-\(restored ? "restored" : "new")-turn\(turn).png"
                try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
            }
        }
        activity.isActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        try await settle(host)
        activity.isActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitUntil { !vm.hasUnseenCompletion }
        _ = await dashboard.removeSession(id)
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }
}

private struct FirstChatFocusHost: View {
    let dashboard: DashboardViewModel
    let router: AppRouter
    let activity: TestApplicationActivity

    var body: some View {
        let node = dashboard.sessionNodes.first
        let completedTurns = node?.appServer?.completedTurnSeq ?? 0
        VStack {
            if let node {
                Text(node.displayName).foregroundStyle(DSColor.textPrimary)
                SessionActivityIndicator(state: node.tabDisplayState)
                    .scaleEffect(3).frame(height: 54)
            }
            SessionCompletionFocusObserver(
                viewModel: dashboard, router: router,
                isApplicationActive: { [activity, completedTurns] in
                    // 転写の更新で、外部のアプリ状態を読み直す。
                    let _ = completedTurns
                    return activity.isActive
                }
            )
            .environment(\.controlActiveState, .key)
        }.frame(width: 200, height: 100).background(DSColor.windowBackground)
    }
}
