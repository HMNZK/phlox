// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift
// task-46 PM 目視ハーネス（PM 著・不変）。製品へデモモードやテスト専用 setter は追加しない。
// PHLOX_PM_VISUAL_TASK=46 のときだけウィンドウを開き、ハーネス内の終了操作まで保持する。
// 環境変数が無ければ即成功する（通常の swift test を汚さない）。
// 描画ホストは Harness/TranscriptTypographyRenderHarness.swift と同じ NSHostingView + cacheDisplay 方式。

import AgentDomain
import AppKit
import DesignSystem
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("PMTranscriptVisualTask46", .serialized)
@MainActor
struct PMTranscriptVisualTask46Tests {
    @Test("PM visual: ChatTranscriptView host for task-46")
    func pmVisualTask46() async throws {
        let visualFlag = ProcessInfo.processInfo.environment["PHLOX_PM_VISUAL_TASK"]
        guard visualFlag == "46" else {
            return
        }

        let suiteName = "phlox.t46.pmvisual.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        ChatFontSettings.save(1.0, defaults: suite)
        suite.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        defer {
            suite.removePersistentDomain(forName: suiteName)
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: ThemeStore.themeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        let client = Task46VisualClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-t46-pm-visual"
        )
        await client.start()

        client.yield(.turnStarted)
        try await waitUntil { viewModel.status.isRunning }
        #expect(viewModel.status.isRunning)

        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { !viewModel.status.isRunning }
        #expect(!viewModel.status.isRunning)

        let columnWidth: CGFloat = 720
        let contentMaxWidth = ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: columnWidth)
        let bottomMargin = measureComposerHeight(viewModel: viewModel, columnWidth: columnWidth)
        let items = Task46VisualFixture.items
        let host = ChatTranscriptView(
            viewModel: viewModel,
            transcript: items,
            showsThinkingIndicator: true,
            contentMaxWidth: contentMaxWidth,
            bottomScrollContentMargin: bottomMargin
        )
        .frame(width: columnWidth, height: 900)
        .background(DSColor.chatBackground)
        .defaultAppStorage(suite)

        let hosting = NSHostingView(rootView: host)
        hosting.frame = NSRect(x: 0, y: 0, width: columnWidth, height: 900)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "task-46 PM visual"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))

        let finished = Task46VisualFinishBox()
        let closer = Task46VisualWindowCloser(finished: finished)
        window.delegate = closer
        withExtendedLifetime(closer) {
            while !finished.value {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            }
        }

        window.orderOut(nil)
        window.contentView = nil
        client.finish()
    }
}

private final class Task46VisualClient: StructuredAgentClient, @unchecked Sendable {
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

    func finish() {
        continuation.finish()
    }
}

private final class Task46VisualFinishBox: @unchecked Sendable {
    var value = false
}

private final class Task46VisualWindowCloser: NSObject, NSWindowDelegate {
    let finished: Task46VisualFinishBox

    init(finished: Task46VisualFinishBox) {
        self.finished = finished
    }

    func windowWillClose(_ notification: Notification) {
        finished.value = true
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<50 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    try #require(condition())
}

@MainActor
private func measureComposerHeight(viewModel: ChatSessionViewModel, columnWidth: CGFloat) -> CGFloat {
    let proposed = ComposerLayout.proposedWidth(mainColumnWidth: columnWidth) ?? columnWidth
    let layout = ComposerLayout.controlsLayout(proposedWidth: proposed)
    let composer = ChatComposer(
        viewModel: viewModel,
        text: .constant(""),
        isRunning: false,
        canSend: true,
        controlsLayout: layout,
        onSend: {},
        onInterrupt: {}
    )
    .frame(maxWidth: proposed)
    .frame(width: columnWidth)

    let hosting = NSHostingView(rootView: composer)
    hosting.frame = NSRect(x: 0, y: 0, width: columnWidth, height: 200)
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    hosting.layoutSubtreeIfNeeded()
    let height = max(hosting.fittingSize.height, 84)
    window.orderOut(nil)
    return height
}

private enum Task46VisualFixture {
    static let time = Date(timeIntervalSince1970: 1_700_000_000)

    static let longReasoning = String(repeating: "思考の本文を長く書いて折りたたみと展開を見る。", count: 8)

    static let twentyOneLineOutput: String = {
        (1...21).map { "output line \($0)" }.joined(separator: "\n")
    }()

    static let fileChange = ChatItem.fileChange(
        id: "file-1",
        changes: [
            FilePatchChange(
                path: "macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift",
                diff: """
                diff --git a/TranscriptItemPresentation.swift b/TranscriptItemPresentation.swift
                @@ -1,3 +1,6 @@
                +struct TranscriptItemPresentation {
                +    let heading: String
                +}
                """,
                kind: "edit"
            ),
        ],
        timestamp: time
    )

    static let emptyTasks = ChatItem.taskList(id: "task-empty", tasks: [], timestamp: time)

    static let tasks = ChatItem.taskList(
        id: "task-list",
        tasks: [
            AgentTaskItem(id: "t1", title: "調査", status: .pending),
            AgentTaskItem(id: "t2", title: "実装", status: .inProgress),
        ],
        timestamp: time
    )

    static var items: [ChatItem] {
        [
            .userMessage(id: "u1", text: "回答と詳細の差を確認する。", timestamp: time),
            .agentMessage(
                id: "a1",
                text: "第一段落の回答本文。\n\n第二段落も常時読む。",
                timestamp: time
            ),
            .reasoning(id: "r-short", text: "短い思考", timestamp: time),
            .reasoning(id: "r-long", text: longReasoning, timestamp: time),
            .commandExecution(
                id: "cmd-single",
                command: "echo ok",
                output: "ok",
                timestamp: time
            ),
            .commandExecution(
                id: "cmd-a",
                command: "echo ok",
                output: twentyOneLineOutput,
                timestamp: time
            ),
            .commandExecution(
                id: "cmd-b",
                command: "echo ok",
                output: "",
                timestamp: time
            ),
            fileChange,
            emptyTasks,
            tasks,
            .error(id: "err-1", message: "a/**/b: error", timestamp: time),
        ]
    }
}
