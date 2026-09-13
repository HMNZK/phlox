// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift
// task-46 PM 目視ハーネス（PM 著・不変）。製品へデモモードやテスト専用 setter は追加しない。
// 固定シナリオと状態アサーションは環境変数なしでも常時実行する。
// PHLOX_PM_VISUAL_TASK=46 のときだけウィンドウを前面表示し、ハーネス内の終了操作まで保持する。
// 描画ホストは Harness/TranscriptTypographyRenderHarness.swift と同じ NSHostingView + cacheDisplay 方式。

import AgentDomain
import AppKit
import DesignSystem
import Foundation
import Observation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("PMTranscriptVisualTask46", .serialized)
@MainActor
struct PMTranscriptVisualTask46Tests {
    @Test("PM visual: ChatTranscriptView host for task-46")
    func pmVisualTask46() async throws {
        let showWindow = ProcessInfo.processInfo.environment["PHLOX_PM_VISUAL_TASK"] == "46"

        let suiteName = "phlox.t46.pmvisual.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        ChatFontSettings.save(1.0, defaults: suite)
        suite.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)

        let client = Task46VisualClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-t46-pm-visual"
        )
        let scenario = Task46VisualScenario(suite: suite, client: client)
        var window: NSWindow?
        var hosting: NSHostingView<Task46VisualRoot>?

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

            let root = Task46VisualRoot(
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

            scenario.replaceReasoningSameLength()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-short")?.count == Task46VisualFixture.shortReasoning.count)

            scenario.blankReasoning()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-short")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)

            scenario.restoreReasoning()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.reasoningText(id: "r-short") == Task46VisualFixture.shortReasoning)

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
                nsWindow.title = "task-46 PM visual"
                nsWindow.isReleasedWhenClosed = false
                nsWindow.contentView = hostView
                nsWindow.makeKeyAndOrderFront(nil)
                window = nsWindow
                let finished = Task46VisualFinishBox()
                let closer = Task46VisualWindowCloser(finished: finished)
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
    client: Task46VisualClient,
    window: NSWindow?,
    hosting: NSHostingView<Task46VisualRoot>?,
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
private func assertFixedFixture(scenario: Task46VisualScenario) throws {
    let items = scenario.items
    let blocks = ChatTranscriptGrouping.blocks(from: items)

    let oneItemGroups = blocks.compactMap { block -> [ChatItem]? in
        if case .commandGroup(_, let grouped) = block, grouped.count == 1 { return grouped }
        return nil
    }
    #expect(oneItemGroups.count == 1)
    #expect(oneItemGroups.first?.first?.id == "cmd-one-group")

    let fiftyOne = blocks.compactMap { block -> [ChatItem]? in
        if case .commandGroup(_, let grouped) = block, grouped.count == 51 { return grouped }
        return nil
    }
    #expect(fiftyOne.count == 1)
    #expect(fiftyOne.first?.first?.id == "c01")
    #expect(fiftyOne.first?.last?.id == "c51")

    let mergedProbe = ChatTranscriptGrouping.blocks(from: [
        Task46VisualFixture.singleCommandItem,
        commandItem(id: "cmd-a", output: Task46VisualFixture.twentyOneLineOutput),
        commandItem(id: "cmd-b", output: ""),
    ])
    #expect(mergedProbe.count == 1)
    if case .commandGroup(_, let grouped) = mergedProbe[0] {
        #expect(grouped.count == 3)
    } else {
        Issue.record("連続コマンドは 1 グループになる")
    }

    let singleView = ChatItemView(
        item: scenario.singleCommand,
        isRunningCommand: false,
        agentDescriptor: AgentRegistry.descriptor(for: .claudeCode)
    )
    #expect(singleView.item.id == "cmd-single")

    let cell = FileChangeCell(
        changes: [Task46VisualFixture.fileChange501],
        timestamp: Task46VisualFixture.time
    )
    let sections = cell.visibleSections
    #expect(sections.count == 1)
    #expect(sections[0].codeView.lines.count == FileChangeDisplayPolicy.visibleLineLimit)
    #expect(ChatMessageRenderCache.diffLines(Task46VisualFixture.fileChange501.diff).count == 501)

    #expect(Set([360, 720] as [CGFloat]).isSuperset(of: [scenario.columnWidth]))
    #expect(([0.8, 1.0, 2.0] as [CGFloat]).contains(scenario.fontScale))
}

private func commandItem(id: String, output: String) -> ChatItem {
    .commandExecution(id: id, command: "echo ok", output: output, timestamp: Task46VisualFixture.time)
}

@Observable
@MainActor
final class Task46VisualScenario {
    var items: [ChatItem]
    var singleCommand: ChatItem
    var columnWidth: CGFloat = 720
    var fontScale: CGFloat = 1.0
    var themeID: String = AppTheme.phloxLight.id
    var colorScheme: ColorScheme = .light
    var contentMaxWidth: CGFloat = 720
    var bottomMargin: CGFloat = 84
    let suite: UserDefaults
    let client: Task46VisualClient

    init(suite: UserDefaults, client: Task46VisualClient) {
        self.suite = suite
        self.client = client
        items = Task46VisualFixture.transcriptItems
        singleCommand = Task46VisualFixture.singleCommandItem
    }

    func reasoningText(id: String) -> String? {
        for item in items {
            if case .reasoning(let itemID, let text, _) = item, itemID == id {
                return text
            }
        }
        return nil
    }

    func replaceReasoningSameLength() {
        items = items.map { item in
            guard case .reasoning(let id, let text, let timestamp) = item, id == "r-short" else {
                return item
            }
            let next = String(repeating: "x", count: text.count)
            return .reasoning(id: id, text: next, timestamp: timestamp)
        }
    }

    func blankReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-short" else {
                return item
            }
            return .reasoning(id: id, text: " \n", timestamp: timestamp)
        }
    }

    func restoreReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-short" else {
                return item
            }
            return .reasoning(id: id, text: Task46VisualFixture.shortReasoning, timestamp: timestamp)
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

private struct Task46VisualRoot: View {
    @Bindable var scenario: Task46VisualScenario
    @Bindable var viewModel: ChatSessionViewModel
    @State private var composerText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            ChatItemView(
                item: scenario.singleCommand,
                isRunningCommand: viewModel.status.isRunning,
                agentDescriptor: AgentRegistry.descriptor(for: .claudeCode)
            )
            .accessibilityIdentifier("Task46.singleCommandPath")
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
                Button("同長置換") { scenario.replaceReasoningSameLength() }
                Button("空白") { scenario.blankReasoning() }
                Button("再表示") { scenario.restoreReasoning() }
                Button("実行開始") { scenario.startTurn() }
                Button("実行終了") { scenario.completeTurn() }
            }
            HStack {
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

private enum Task46VisualFixture {
    static let time = Date(timeIntervalSince1970: 1_700_000_000)
    static let shortReasoning = "短い思考"
    static let longReasoning = String(repeating: "思考の本文を長く書いて折りたたみと展開を見る。", count: 8)

    static let twentyOneLineOutput: String = {
        (1...21).map { "output line \($0)" }.joined(separator: "\n")
    }()

    static let fileChange501 = FilePatchChange(
        path: "macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift",
        diff: {
            let additions = (1...501).map { "+line\($0)" }.joined(separator: "\n")
            return "--- a/A.swift\n+++ b/A.swift\n@@ -1,501 +1,501 @@\n\(additions)"
        }(),
        kind: "edit"
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

    static var singleCommandItem: ChatItem {
        .commandExecution(id: "cmd-single", command: "echo ok", output: "ok", timestamp: time)
    }

    static var fiftyOneCommands: [ChatItem] {
        (1...51).map { index in
            let id = String(format: "c%02d", index)
            return .commandExecution(id: id, command: "echo ok", output: "ok", timestamp: time)
        }
    }

    static var transcriptItems: [ChatItem] {
        [
            .userMessage(id: "u1", text: "回答と詳細の差を確認する。", timestamp: time),
            .agentMessage(
                id: "a1",
                text: "第一段落の回答本文。\n\n第二段落も常時読む。",
                timestamp: time
            ),
            .reasoning(id: "r-short", text: shortReasoning, timestamp: time),
            .reasoning(id: "r-long", text: longReasoning, timestamp: time),
            .userMessage(id: "sep-1", text: "単体グループ区切り", timestamp: time),
            .commandExecution(
                id: "cmd-one-group",
                command: "echo ok",
                output: twentyOneLineOutput,
                timestamp: time
            ),
            .userMessage(id: "sep-2", text: "51件グループ区切り", timestamp: time),
        ]
            + fiftyOneCommands
            + [
                .fileChange(id: "file-501", changes: [fileChange501], timestamp: time),
                emptyTasks,
                tasks,
                .error(id: "err-1", message: "a/**/b: error", timestamp: time),
            ]
    }
}
