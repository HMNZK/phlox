// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift
// task-47 PM 目視ハーネス（PM 著・不変）。製品へデモモードやテスト専用 setter は追加しない。
// 固定シナリオと状態アサーションは環境変数なしでも常時実行する。
// PHLOX_PM_VISUAL_TASK=47 のときだけウィンドウを前面表示し、ハーネス内の終了操作まで保持する。
// 窓表示モードのみ PHLOX_PM_VISUAL_WIDTH（360|720）/ SCALE（0.8|1.0|2.0）/ THEME（light|dark）を読む。

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
        var previousTheme: Any?
        var shouldRestoreTheme = false
        var previousActivationPolicy: NSApplication.ActivationPolicy?

        do {
            if showWindow, let themeRaw = ProcessInfo.processInfo.environment["PHLOX_PM_VISUAL_THEME"] {
                #expect(
                    themeRaw == "light" || themeRaw == "dark",
                    "PHLOX_PM_VISUAL_THEME は light|dark、実際は \(themeRaw)"
                )
                if themeRaw == "dark" || themeRaw == "light" {
                    previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
                    shouldRestoreTheme = true
                    if themeRaw == "dark" {
                        scenario.applyDarkTheme()
                    } else {
                        scenario.applyLightTheme()
                    }
                }
            }

            if showWindow {
                let app = NSApplication.shared
                previousActivationPolicy = app.activationPolicy()
                app.setActivationPolicy(.regular)
                app.finishLaunching()
                NSApp.activate(ignoringOtherApps: true)
            }

            await client.start()
            try assertFixedFixture(scenario: scenario)

            let columnWidth = scenario.columnWidth
            scenario.contentMaxWidth = ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: columnWidth)

            let root = Task47VisualRoot(
                scenario: scenario,
                viewModel: viewModel
            )
            let hostView = NSHostingView(rootView: root)
            hosting = hostView
            hostView.frame = NSRect(x: 0, y: 0, width: columnWidth, height: 900)
            if showWindow {
                hostView.appearance = visualAppearance(for: scenario.colorScheme)
            }

            let nsWindow = NSWindow(
                contentRect: hostView.frame,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            nsWindow.title = "task-47 PM visual"
            nsWindow.isReleasedWhenClosed = false
            if showWindow {
                nsWindow.appearance = visualAppearance(for: scenario.colorScheme)
            }
            nsWindow.contentView = hostView
            window = nsWindow
            hostView.layoutSubtreeIfNeeded()
            pumpMainRunLoop(seconds: 0.12)
            if showWindow {
                fitVisualWindow(scenario: scenario, hostView: hostView, nsWindow: nsWindow)
            }

            client.yield(.turnStarted)
            try await waitUntil { viewModel.status.isRunning }
            #expect(viewModel.status.isRunning)

            try assertCardExpansionSequence(host: hostView, scenario: scenario)
            try await assertRealEventAppend(viewModel: viewModel, client: client, scenario: scenario, host: hostView)
            try assertSameLengthAnswer(scenario: scenario, host: hostView)
            try assertCodeBoundaryAndCommands(scenario: scenario, host: hostView)
            scenario.restoreFullAnswer()
            hostView.layoutSubtreeIfNeeded()
            #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.markdownAnswer)

            client.yield(.turnCompleted(nativeSessionId: nil))
            try await waitUntil { !viewModel.status.isRunning }
            #expect(!viewModel.status.isRunning)

            if showWindow {
                applyWindowLaunchEnvironment(to: scenario, hostView: hostView, nsWindow: nsWindow)
                NSApplication.shared.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                nsWindow.makeKeyAndOrderFront(nil)
                nsWindow.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                let finished = Task47VisualFinishBox()
                let closer = Task47VisualWindowCloser(finished: finished)
                nsWindow.delegate = closer
                withExtendedLifetime(closer) {
                    while !finished.value {
                        pumpMainRunLoop(seconds: 0.2)
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
                previousTheme: previousTheme,
                shouldRestoreTheme: shouldRestoreTheme,
                previousActivationPolicy: previousActivationPolicy
            )
        } catch {
            await finishVisual(
                viewModel: viewModel,
                client: client,
                window: window,
                hosting: hosting,
                suiteName: suiteName,
                suite: suite,
                previousTheme: previousTheme,
                shouldRestoreTheme: shouldRestoreTheme,
                previousActivationPolicy: previousActivationPolicy
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
    previousTheme: Any?,
    shouldRestoreTheme: Bool,
    previousActivationPolicy: NSApplication.ActivationPolicy?
) async {
    await viewModel.terminate()
    client.finish()
    window?.orderOut(nil)
    window?.contentView = nil
    hosting?.removeFromSuperview()
    suite.removePersistentDomain(forName: suiteName)
    if shouldRestoreTheme {
        if let previousTheme {
            UserDefaults.standard.set(previousTheme, forKey: ThemeStore.themeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
        }
    }
    if let previousActivationPolicy {
        NSApplication.shared.setActivationPolicy(previousActivationPolicy)
    }
}

@MainActor
private func applyWindowLaunchEnvironment(
    to scenario: Task47VisualScenario,
    hostView: NSView,
    nsWindow: NSWindow
) {
    let env = ProcessInfo.processInfo.environment
    var needsLayout = false

    if let widthRaw = env["PHLOX_PM_VISUAL_WIDTH"] {
        let allowed: [String: CGFloat] = ["360": 360, "720": 720]
        let parsed = allowed[widthRaw]
        #expect(parsed != nil, "PHLOX_PM_VISUAL_WIDTH は 360|720、実際は \(widthRaw)")
        if let parsed {
            scenario.applyWidth(parsed)
            needsLayout = true
        }
    }

    if let scaleRaw = env["PHLOX_PM_VISUAL_SCALE"] {
        let allowed: [String: CGFloat] = ["0.8": 0.8, "1.0": 1.0, "2.0": 2.0]
        let parsed = allowed[scaleRaw]
        #expect(parsed != nil, "PHLOX_PM_VISUAL_SCALE は 0.8|1.0|2.0、実際は \(scaleRaw)")
        if let parsed {
            scenario.applyScale(parsed)
            needsLayout = true
        }
    }

    if needsLayout {
        fitVisualWindow(scenario: scenario, hostView: hostView, nsWindow: nsWindow)
        pumpMainRunLoop(seconds: 0.12)
    }
}

@MainActor
private func fitVisualWindow(
    scenario: Task47VisualScenario,
    hostView: NSView,
    nsWindow: NSWindow
) {
    hostView.layoutSubtreeIfNeeded()
    let height = max(hostView.fittingSize.height, 900)
    hostView.frame = NSRect(
        x: hostView.frame.origin.x,
        y: hostView.frame.origin.y,
        width: scenario.columnWidth,
        height: height
    )
    nsWindow.setContentSize(NSSize(width: scenario.columnWidth, height: height))
    hostView.layoutSubtreeIfNeeded()
}

private func visualAppearance(for colorScheme: ColorScheme) -> NSAppearance? {
    NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
}

@MainActor
private func assertFixedFixture(scenario: Task47VisualScenario) throws {
    let ids = scenario.items.map(\.id)
    #expect(ids.contains("a-md"))
    #expect(ids.contains("r-summary"))
    #expect(ids.contains("r-code"))
    #expect(ids.contains("cmd-past"))
    #expect(ids.contains("cmd-latest"))
    #expect(ids.contains("err-1"))
    #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.markdownAnswer)
    #expect(scenario.reasoningText(id: "r-summary") == Task47VisualFixture.reasoningWithHeading)
    #expect(scenario.reasoningText(id: "r-code") == Task47VisualFixture.codeOnlyReasoning)
    #expect(ids.last == "cmd-latest")
    #expect(Set([360, 720] as [CGFloat]).isSuperset(of: [scenario.columnWidth]))
    #expect(([0.8, 1.0, 2.0] as [CGFloat]).contains(scenario.fontScale))
    #expect(Task47VisualFixture.sameLengthLeft.count == Task47VisualFixture.sameLengthRight.count)
    #expect(Task47VisualFixture.unclosedPartial.count != Task47VisualFixture.markdownAnswer.count)
}

@MainActor
private func assertCardExpansionSequence(host: NSView, scenario: Task47VisualScenario) throws {
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))

    assertReasoningBody(
        in: host,
        fragment: Task47VisualFixture.reasoningBodyFragment,
        contains: false,
        context: "初期状態は折りたたみ"
    )

    scenario.requestReasoningExpansion()
    #expect(scenario.reasoningExpansionRequest == 1)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    assertReasoningBody(
        in: host,
        fragment: Task47VisualFixture.reasoningBodyFragment,
        contains: true,
        context: "展開操作後"
    )

    scenario.replaceReasoningSameLength()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    #expect(scenario.reasoningText(id: "r-summary")?.count == Task47VisualFixture.reasoningWithHeading.count)
    assertReasoningBody(
        in: host,
        fragment: Task47VisualFixture.replacedReasoningBodyFragment,
        contains: true,
        context: "同一 ID の本文再適用後"
    )

    scenario.blankReasoning()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    #expect(scenario.reasoningText(id: "r-summary")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)

    scenario.restoreReasoning()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    #expect(scenario.reasoningText(id: "r-summary") == Task47VisualFixture.reasoningWithHeading)
    assertReasoningBody(
        in: host,
        fragment: Task47VisualFixture.reasoningBodyFragment,
        contains: false,
        context: "再マウント後"
    )
}

@MainActor
private func assertRealEventAppend(
    viewModel: ChatSessionViewModel,
    client: Task47VisualClient,
    scenario: Task47VisualScenario,
    host: NSView
) async throws {
    client.yield(.agentMessageDelta(itemId: "a-append", Task47VisualFixture.appendedAnswer))
    try await waitUntil {
        viewModel.transcript.contains { item in
            if case .agentMessage(let id, let text, _) = item {
                return id == "a-append" && text == Task47VisualFixture.appendedAnswer
            }
            return false
        }
    }
    scenario.absorbAppended(from: viewModel.transcript)
    host.layoutSubtreeIfNeeded()
    #expect(scenario.agentText(id: "a-append") == Task47VisualFixture.appendedAnswer)
}

@MainActor
private func assertSameLengthAnswer(scenario: Task47VisualScenario, host: NSView) throws {
    scenario.applySameLengthLeft()
    host.layoutSubtreeIfNeeded()
    #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.sameLengthLeft)
    scenario.applySameLengthRight()
    host.layoutSubtreeIfNeeded()
    #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.sameLengthRight)
    #expect(Task47VisualFixture.sameLengthLeft.count == Task47VisualFixture.sameLengthRight.count)
    scenario.restoreFullAnswer()
    host.layoutSubtreeIfNeeded()
    #expect(scenario.agentText(id: "a-md") == Task47VisualFixture.markdownAnswer)
}

@MainActor
private func assertCodeBoundaryAndCommands(scenario: Task47VisualScenario, host: NSView) throws {
    for fixture in Task47VisualFixture.codeBoundaryCases {
        scenario.showCodeBoundary(fixture)
        host.layoutSubtreeIfNeeded()
        #expect(scenario.agentText(id: "a-code") == fixture.text)
    }
    scenario.showLatestCommand()
    host.layoutSubtreeIfNeeded()
    #expect(scenario.items.last?.id == "cmd-latest")
    scenario.showPastCommand()
    host.layoutSubtreeIfNeeded()
    #expect(scenario.items.contains { $0.id == "cmd-past" })
    #expect(scenario.items.last?.id != "cmd-past")
}

@Observable
@MainActor
private final class Task47VisualScenario {
    var items: [ChatItem]
    var columnWidth: CGFloat = 720
    var fontScale: CGFloat = 1.0
    var colorScheme: ColorScheme = .light
    var contentMaxWidth: CGFloat? = 720
    var bottomMargin: CGFloat = 0
    var reasoningExpansionRequest = 0
    var reasoningMount = 0
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

    func replaceAnswerUnclosedPartial() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.unclosedPartial)
    }

    func growUnclosedAnswer() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.unclosedConfirm)
    }

    func closeUnclosedAnswer() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.closedConfirm)
    }

    func restoreFullAnswer() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.markdownAnswer)
    }

    func applySameLengthLeft() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.sameLengthLeft)
    }

    func applySameLengthRight() {
        replaceAgent(id: "a-md", text: Task47VisualFixture.sameLengthRight)
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

    func requestReasoningExpansion() {
        reasoningExpansionRequest += 1
    }

    func blankReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-summary" else {
                return item
            }
            return .reasoning(id: id, text: " \n", timestamp: timestamp)
        }
        reasoningMount += 1
    }

    func restoreReasoning() {
        items = items.map { item in
            guard case .reasoning(let id, _, let timestamp) = item, id == "r-summary" else {
                return item
            }
            return .reasoning(id: id, text: Task47VisualFixture.reasoningWithHeading, timestamp: timestamp)
        }
    }

    func absorbAppended(from transcript: [ChatItem]) {
        for item in transcript {
            if case .agentMessage(let id, _, _) = item, id == "a-append", !items.contains(where: { $0.id == id }) {
                items.append(item)
            }
        }
    }

    func showCodeBoundary(_ fixture: Task47VisualCodeBoundary) {
        if items.contains(where: { $0.id == "a-code" }) {
            replaceAgent(id: "a-code", text: fixture.text)
        } else {
            items.append(.agentMessage(id: "a-code", text: fixture.text, timestamp: Task47VisualFixture.time))
        }
    }

    func showLatestCommand() {
        items = Task47VisualFixture.transcriptItems
    }

    func showPastCommand() {
        items = Task47VisualFixture.pastCommandItems
    }

    func startTurn() {
        client.yield(.turnStarted)
    }

    func completeTurn() {
        client.yield(.turnCompleted(nativeSessionId: nil))
    }

    func appendViaEvent() {
        client.yield(.agentMessageDelta(itemId: "a-append", Task47VisualFixture.appendedAnswer))
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
        colorScheme = .light
        suite.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
    }

    func applyDarkTheme() {
        colorScheme = .dark
        suite.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
    }

    private func replaceAgent(id: String, text: String) {
        items = items.map { item in
            guard case .agentMessage(let itemID, _, let timestamp) = item, itemID == id else {
                return item
            }
            return .agentMessage(id: itemID, text: text, timestamp: timestamp)
        }
    }
}

private struct Task47VisualRoot: View {
    @Bindable var scenario: Task47VisualScenario
    @Bindable var viewModel: ChatSessionViewModel
    @State private var composerText = ""

    var body: some View {
        VStack(spacing: 0) {
            controls
            ChatTranscriptView(
                viewModel: viewModel,
                transcript: scenario.items,
                showsThinkingIndicator: true,
                contentMaxWidth: scenario.contentMaxWidth,
                bottomScrollContentMargin: scenario.bottomMargin
            )
            .frame(width: scenario.columnWidth, height: 900)
            .background(DSColor.chatBackground)
            .overlay(alignment: .bottom) {
                composer
                    .background {
                        DSColor.chatBackground
                            .padding(.top, DSSpacing.m)
                            .padding(.trailing, ComposerLayout.scrollerCorridorWidth)
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        scenario.bottomMargin = height
                    }
            }
            .background {
                if scenario.reasoningText(id: "r-summary")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Task47VisualReasoningProbe(
                        text: scenario.reasoningText(id: "r-summary") ?? "",
                        expansionRequest: scenario.reasoningExpansionRequest
                    )
                    .id(scenario.reasoningMount)
                    .opacity(0.01)
                }
            }
        }
        .frame(width: scenario.columnWidth)
        .background(DSColor.chatBackground)
        .defaultAppStorage(scenario.suite)
        .preferredColorScheme(scenario.colorScheme)
        .environment(\.colorScheme, scenario.colorScheme)
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button("全文へ戻す") { scenario.restoreFullAnswer() }
                    Button("同長左") { scenario.applySameLengthLeft() }
                    Button("同長右") { scenario.applySameLengthRight() }
                    Button("**確") { scenario.replaceAnswerUnclosedPartial() }
                    Button("**確認") { scenario.growUnclosedAnswer() }
                    Button("**確認**") { scenario.closeUnclosedAnswer() }
                }
                HStack {
                    Button("思考同長") { scenario.replaceReasoningSameLength() }
                    Button("空白") { scenario.blankReasoning() }
                    Button("再表示") { scenario.restoreReasoning() }
                    Button("実イベント追記") { scenario.appendViaEvent() }
                }
                HStack {
                    Button("実行開始") { scenario.startTurn() }
                    Button("実行終了") { scenario.completeTurn() }
                    Button("幅360") { scenario.applyWidth(360) }
                    Button("幅720") { scenario.applyWidth(720) }
                    Button("0.8") { scenario.applyScale(0.8) }
                    Button("1.0") { scenario.applyScale(1.0) }
                    Button("2.0") { scenario.applyScale(2.0) }
                }
                HStack {
                    Button("最新コマンド") { scenario.showLatestCommand() }
                    Button("過去コマンド") { scenario.showPastCommand() }
                    ForEach(Task47VisualFixture.codeBoundaryCases, id: \.id) { fixture in
                        Button(fixture.id) { scenario.showCodeBoundary(fixture) }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
        }
        .frame(width: scenario.columnWidth, alignment: .leading)
        .background(DSColor.chatBackground)
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
private func assertReasoningBody(in root: NSView, fragment: String, contains expected: Bool, context: String) {
    let texts = viewTexts(in: root)
    if texts.isEmpty {
        Issue.record("\(context): NSView 階層からテキストを収集できません: \(texts)")
    }
    #expect(
        texts.contains { $0.contains(fragment) } == expected,
        "\(context): 収集テキスト=\(texts)"
    )
}

@MainActor
private func viewTexts(in root: NSView) -> [String] {
    var texts: [String] = []

    func visit(_ view: NSView) {
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            texts.append(field.stringValue)
        }
        if let textView = view as? NSTextView, !textView.string.isEmpty {
            texts.append(textView.string)
        }
        for subview in view.subviews {
            visit(subview)
        }
    }

    visit(root)
    return texts
}

@MainActor
private struct Task47VisualReasoningProbe: View {
    let text: String
    let expansionRequest: Int
    @State private var isExpanded = false

    var body: some View {
        DisclosureCard(isExpanded: $isExpanded, title: "思考の詳細", subtitle: nil) {
            AgentMessageBody(text: text, bodyColor: DSColor.chatTextSecondary)
        }
        .onChange(of: expansionRequest) { _, _ in
            isExpanded.toggle()
        }
    }
}

private struct Task47VisualCodeBoundary: Equatable {
    let id: String
    let text: String
}

private enum Task47VisualFixture {
    static let time = Date(timeIntervalSince1970: 1_700_000_000)
    static let unclosedPartial = "**確"
    static let unclosedConfirm = "**確認"
    static let closedConfirm = "**確認**"
    static let sameLengthLeft = "**確認"
    static let sameLengthRight = "**更新"
    static let appendedAnswer = "追記された回答"
    static let reasoningBodyFragment = "有効"
    static let replacedReasoningBodyFragment = "あああ"

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

    static let codeBoundaryCases: [Task47VisualCodeBoundary] = [
        Task47VisualCodeBoundary(id: "0空白", text: "```swift\n\t  **x  \n\n```"),
        Task47VisualCodeBoundary(id: "3空白", text: "   ```swift\n\t  **x  \n\n   ```"),
        Task47VisualCodeBoundary(id: "4空白", text: "    ```swift\n    **x  \n\n    ```\n\n"),
        Task47VisualCodeBoundary(id: "タブ", text: "\t```swift\n\t**x\n\t```\n\n"),
        Task47VisualCodeBoundary(id: "3本", text: "```\na\n```"),
        Task47VisualCodeBoundary(id: "4本", text: "````\na\n```\nb\n````"),
        Task47VisualCodeBoundary(id: "チルダ", text: "~~~\n**x\n~~~\n"),
        Task47VisualCodeBoundary(id: "未閉じ", text: "```json\n**x\n\n"),
        Task47VisualCodeBoundary(id: "インライン", text: "`**未閉じ` と **確認"),
        Task47VisualCodeBoundary(id: "CRLF", text: "```swift\r\n\t  x  \r\n\r\n```"),
        Task47VisualCodeBoundary(id: "末尾空行", text: "```swift\n\t  **x  \n\n```\n\n"),
    ]

    static var transcriptItems: [ChatItem] {
        [
            .userMessage(id: "u1", text: "Markdown と思考色を確認する。", timestamp: time),
            .agentMessage(id: "a-md", text: markdownAnswer, timestamp: time),
            .reasoning(id: "r-summary", text: reasoningWithHeading, timestamp: time),
            .reasoning(id: "r-code", text: codeOnlyReasoning, timestamp: time),
            .commandExecution(
                id: "cmd-past",
                command: "echo past",
                output: commandOutput,
                timestamp: time
            ),
            .error(id: "err-1", message: "a/**/b: error", timestamp: time),
            .commandExecution(
                id: "cmd-latest",
                command: "echo **ok",
                output: commandOutput,
                timestamp: time
            ),
        ]
    }

    static var pastCommandItems: [ChatItem] {
        [
            .userMessage(id: "u1", text: "Markdown と思考色を確認する。", timestamp: time),
            .agentMessage(id: "a-md", text: markdownAnswer, timestamp: time),
            .reasoning(id: "r-summary", text: reasoningWithHeading, timestamp: time),
            .commandExecution(
                id: "cmd-past",
                command: "echo past",
                output: commandOutput,
                timestamp: time
            ),
            .error(id: "err-1", message: "a/**/b: error", timestamp: time),
        ]
    }
}

private func pumpMainRunLoop(seconds: TimeInterval) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
}
