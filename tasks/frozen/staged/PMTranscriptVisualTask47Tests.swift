// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift
// task-47 PM 目視ハーネス（PM 著・不変）。製品へデモモードやテスト専用 setter は追加しない。
// 固定シナリオと状態アサーションは環境変数なしでも常時実行する。
// PHLOX_PM_VISUAL_TASK=47 のときだけウィンドウを前面表示し、ハーネス内の終了操作まで保持する。
// 描画ホストは Harness/TranscriptTypographyRenderHarness.swift と同じ NSHostingView + 同一 identity。

import AgentDomain
import AppKit
import DesignSystem
import Foundation
import Observation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("PMTranscriptVisualTask47", .serialized)
@MainActor
struct PMTranscriptVisualTask47Tests {
    @Test("PM visual: ChatTranscriptView host for task-47")
    func pmVisualTask47() async throws {
        let showWindow = ProcessInfo.processInfo.environment["PHLOX_PM_VISUAL_TASK"] == "47"

        let suiteName = "phlox.t47.pmvisual.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        ChatFontSettings.save(1.0, defaults: suite)
        suite.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)

        let client = Task47VisualClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-t47-pm-visual"
        )
        let scenario = Task47VisualScenario(suite: suite, client: client)
        var window: NSWindow?
        var hosting: NSHostingView<Task47VisualRoot>?

        do {
            await client.start()
            try assertFixedFixture(scenario: scenario)

            let columnWidth = scenario.columnWidth
            let contentMaxWidth = ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: columnWidth)
            let bottomMargin = measureComposerHeight(
                viewModel: viewModel,
                columnWidth: columnWidth,
                suite: suite
            )
            scenario.bottomMargin = bottomMargin
            scenario.contentMaxWidth = contentMaxWidth

            let root = Task47VisualRoot(
                scenario: scenario,
                viewModel: viewModel
            )
            let hostView = NSHostingView(rootView: root)
            hosting = hostView
            hostView.frame = NSRect(x: 0, y: 0, width: columnWidth, height: 900)
            hostView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))

            client.yield(.turnStarted)
            try await waitUntil { viewModel.status.isRunning }
            #expect(viewModel.status.isRunning)

            scenario.replaceAnswerSameLength()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.unclosedPartial)

            scenario.growUnclosedAnswer()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.unclosedConfirm)

            scenario.closeUnclosedAnswer()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.closedConfirm)

            scenario.replaceReasoningSameLength()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-summary")?.count == Task47VisualFixture.reasoningWithHeading.count)

            scenario.blankReasoning()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-summary")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)

            scenario.restoreReasoning()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-summary") == Task47VisualFixture.reasoningWithHeading)

            client.yield(.turnCompleted(nativeSessionId: nil))
            try await waitUntil { !viewModel.status.isRunning }
            #expect(!viewModel.status.isRunning)

            if showWindow {
                let nsWindow = NSWindow(
                    contentRect: hostView.frame,
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                nsWindow.title = "task-47 PM visual"
                nsWindow.isReleasedWhenClosed = false
                nsWindow.contentView = hostView
                nsWindow.makeKeyAndOrderFront(nil)
                window = nsWindow
                let finished = Task47VisualFinishBox()
                let closer = Task47VisualWindowCloser(finished: finished)
                nsWindow.delegate = closer
                withExtendedLifetime(closer) {
                    while !finished.value {
                        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                    }
                }
            }

            await finishVisual(
                viewModel: viewModel,
                client: client,
                window: window,
                hosting: hosting,
                suiteName: suiteName,
                suite: suite,
                previousTheme: previousTheme
            )
        } catch {
            await finishVisual(
                viewModel: viewModel,
                client: client,
                window: window,
                hosting: hosting,
                suiteName: suiteName,
                suite: suite,
                previousTheme: previousTheme
            )
            throw error
        }
    }
}

@MainActor
private func finishVisual(
    viewModel: ChatSessionViewModel,
    client: Task47VisualClient,
    window: NSWindow?,
    hosting: NSHostingView<Task47VisualRoot>?,
    suiteName: String,
    suite: UserDefaults,
    previousTheme: Any?
) async {
    await viewModel.terminate()
    client.finish()
    window?.orderOut(nil)
    window?.contentView = nil
    hosting?.removeFromSuperview()
    suite.removePersistentDomain(forName: suiteName)
    if let previousTheme {
        UserDefaults.standard.set(previousTheme, forKey: ThemeStore.themeKey)
    } else {
        UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
    }
}

@MainActor
private func assertFixedFixture(scenario: Task47VisualScenario) throws {
    let ids = scenario.items.map(\.id)
    #expect(ids.contains("a-md"))
    #expect(ids.contains("r-summary"))
    #expect(ids.contains("r-code"))
    #expect(ids.contains("cmd-stars"))
    #expect(ids.contains("err-1"))
    #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.markdownAnswer)
    #expect(scenario.reasoningText(id: "r-summary") == Task47VisualFixture.reasoningWithHeading)
    #expect(scenario.reasoningText(id: "r-code") == Task47VisualFixture.codeOnlyReasoning)
    #expect(Set([360, 720] as [CGFloat]).isSuperset(of: [scenario.columnWidth]))
    #expect(([0.8, 1.0, 2.0] as [CGFloat]).contains(scenario.fontScale))
}

@Observable
@MainActor
final class Task47VisualScenario {
    var items: [ChatItem]
    var columnWidth: CGFloat = 720
    var fontScale: CGFloat = 1.0
    var themeID: String = AppTheme.phloxLight.id
    var colorScheme: ColorScheme = .light
    var contentMaxWidth: CGFloat = 720
    var bottomMargin: CGFloat = 84
    let suite: UserDefaults
    let client: Task47VisualClient

    init(suite: UserDefaults, client: Task47VisualClient) {
        self.suite = suite
        self.client = client
        items = Task47VisualFixture.transcriptItems
    }

    func agentText(id: String) -> String? {
        for item in items {
            if case .agentMessage(let itemID, let text, _) = item, itemID == id {
                return text
            }
        }
        return nil
    }

    func reasoningText(id: String) -> String? {
        for item in items {
            if case .reasoning(let itemID, let text, _) = item, itemID == id {
                return text
            }
        }
        return nil
    }

    func replaceAnswerSameLength() {
        items = items.map { item in
            guard case .agentMessage(let id, let text, let timestamp) = item, id == "a-md" else {
                return item
            }
            _ = text
            return .agentMessage(id: id, text: Task47VisualFixture.unclosedPartial, timestamp: timestamp)
        }
    }

    func growUnclosedAnswer() {
        items = items.map { item in
            guard case .agentMessage(let id, _, let timestamp) = item, id == "a-md" else {
                return item
            }
            return .agentMessage(id: id, text: Task47VisualFixture.unclosedConfirm, timestamp: timestamp)
        }
    }

    func closeUnclosedAnswer() {
        items = items.map { item in
            guard case .agentMessage(let id, _, let timestamp) = item, id == "a-md" else {
                return item
            }
            return .agentMessage(id: id, text: Task47VisualFixture.closedConfirm, timestamp: timestamp)
        }
    }

    func replaceReasoningSameLength() {
        items = items.map { item in
            guard case .reasoning(let id, let text, let timestamp) = item, id == "r-summary" else {
                return item
            }
            let next = String(repeating: "あ", count: text.count)
            return .reasoning(id: id, text: next, timestamp: timestamp)
        }
    }

    func blankReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-summary" else {
                return item
            }
            return .reasoning(id: id, text: " \n", timestamp: timestamp)
        }
    }

    func restoreReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-summary" else {
                return item
            }
            return .reasoning(id: id, text: Task47VisualFixture.reasoningWithHeading, timestamp: timestamp)
        }
    }

    func startTurn() {
        client.yield(.turnStarted)
    }

    func completeTurn() {
        client.yield(.turnCompleted(nativeSessionId: nil))
    }

    func applyWidth(_ width: CGFloat) {
        columnWidth = width
        contentMaxWidth = ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width)
    }

    func applyScale(_ scale: CGFloat) {
        fontScale = scale
        ChatFontSettings.save(scale, defaults: suite)
    }

    func applyLightTheme() {
        themeID = AppTheme.phloxLight.id
        colorScheme = .light
        suite.set(themeID, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
    }

    func applyDarkTheme() {
        themeID = AppTheme.dracula.id
        colorScheme = .dark
        suite.set(themeID, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
    }
}

private struct Task47VisualRoot: View {
    @Bindable var scenario: Task47VisualScenario
    @Bindable var viewModel: ChatSessionViewModel
    @State private var composerText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            ChatTranscriptView(
                viewModel: viewModel,
                transcript: scenario.items,
                showsThinkingIndicator: true,
                contentMaxWidth: scenario.contentMaxWidth,
                bottomScrollContentMargin: scenario.bottomMargin
            )
            composer
        }
        .frame(width: scenario.columnWidth, height: 900)
        .background(DSColor.chatBackground)
        .defaultAppStorage(scenario.suite)
        .preferredColorScheme(scenario.colorScheme)
        .environment(\.colorScheme, scenario.colorScheme)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button("**確") { scenario.replaceAnswerSameLength() }
                Button("**確認") { scenario.growUnclosedAnswer() }
                Button("**確認**") { scenario.closeUnclosedAnswer() }
                Button("思考同長") { scenario.replaceReasoningSameLength() }
                Button("空白") { scenario.blankReasoning() }
                Button("再表示") { scenario.restoreReasoning() }
            }
            HStack {
                Button("実行開始") { scenario.startTurn() }
                Button("実行終了") { scenario.completeTurn() }
                Button("幅360") { scenario.applyWidth(360) }
                Button("幅720") { scenario.applyWidth(720) }
                Button("0.8") { scenario.applyScale(0.8) }
                Button("1.0") { scenario.applyScale(1.0) }
                Button("2.0") { scenario.applyScale(2.0) }
                Button("明") { scenario.applyLightTheme() }
                Button("暗") { scenario.applyDarkTheme() }
            }
        }
        .padding(8)
    }

    private var composer: some View {
        let proposed = ComposerLayout.proposedWidth(mainColumnWidth: scenario.columnWidth) ?? scenario.columnWidth
        let layout = ComposerLayout.controlsLayout(proposedWidth: proposed)
        return ChatComposer(
            viewModel: viewModel,
            text: $composerText,
            isRunning: viewModel.status.isRunning,
            canSend: true,
            controlsLayout: layout,
            onSend: {},
            onInterrupt: {}
        )
        .frame(maxWidth: proposed)
        .frame(width: scenario.columnWidth)
        .defaultAppStorage(scenario.suite)
    }
}

private final class Task47VisualClient: StructuredAgentClient, @unchecked Sendable {
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

private final class Task47VisualFinishBox: @unchecked Sendable {
    var value = false
}

private final class Task47VisualWindowCloser: NSObject, NSWindowDelegate {
    let finished: Task47VisualFinishBox

    init(finished: Task47VisualFinishBox) {
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
private func measureComposerHeight(
    viewModel: ChatSessionViewModel,
    columnWidth: CGFloat,
    suite: UserDefaults
) -> CGFloat {
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
    .defaultAppStorage(suite)

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
    window.contentView = nil
    return height
}

private enum Task47VisualFixture {
    static let time = Date(timeIntervalSince1970: 1_700_000_000)
    static let unclosedPartial = "**確"
    static let unclosedConfirm = "**確認"
    static let closedConfirm = "**確認**"

    static let markdownAnswer = """
    # 確認結果

    **太字** と *斜体*

    - 箇条書き

    > 引用

    [詳細](https://example.com)

    | A | B |
    | --- | --- |
    | x | y |
    """

    static let reasoningWithHeading = """
    ## 有効

    ## 
    """

    static let codeOnlyReasoning = """
    ```swift
    let value = "**x"
    ```
    """

    static let commandOutput = """
    ** not markdown
    ## also not
    /tmp/a/**/b: ok
    """

    static var transcriptItems: [ChatItem] {
        [
            .userMessage(id: "u1", text: "Markdown と思考色を確認する。", timestamp: time),
            .agentMessage(id: "a-md", text: markdownAnswer, timestamp: time),
            .reasoning(id: "r-summary", text: reasoningWithHeading, timestamp: time),
            .reasoning(id: "r-code", text: codeOnlyReasoning, timestamp: time),
            .commandExecution(
                id: "cmd-stars",
                command: "echo **ok",
                output: commandOutput,
                timestamp: time
            ),
            .error(id: "err-1", message: "a/**/b: error", timestamp: time),
        ]
    }
}
