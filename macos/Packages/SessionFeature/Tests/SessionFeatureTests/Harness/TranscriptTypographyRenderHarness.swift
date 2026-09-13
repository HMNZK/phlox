// PM 目視ゲート B（SessionFeature fixture）の描画ハーネス。
// 凍結対象外・PM 所有。製品コード・凍結テスト・契約・台帳は変更しない。
//
// TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT が無ければ何もせず成功する（通常の swift test を汚さない）。

import AgentDomain
import AppKit
import DesignSystem
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("TranscriptTypographyRenderHarness", .serialized)
@MainActor
struct TranscriptTypographyRenderHarness {
    @Test("PM gate B: ChatTranscriptView fixture PNGs")
    func renderTranscriptTypographyFixture() throws {
        guard let outPath = ProcessInfo.processInfo.environment["TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT"],
              !outPath.isEmpty
        else {
            return
        }

        let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let suiteName = "phlox.t40.gateB.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        let storeNote = try confirmSettingsStore(suiteName: suiteName)
        try storeNote.write(to: outDir.appendingPathComponent("settings-store.txt"), atomically: true, encoding: .utf8)

        let client = DisconnectedHarnessClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-t40-gateB-harness"
        )
        let items = GateBFixture.items
        let widths: [CGFloat] = [360, 720]
        let scales: [(label: String, value: CGFloat)] = [
            ("0.8", 0.8),
            ("1.0", 1.0),
            ("2.0", 2.0),
        ]
        let themes: [(label: String, id: String)] = [
            ("phlox-light", AppTheme.phloxLight.id),
            ("dracula", AppTheme.dracula.id),
        ]

        var manifest: [String] = [
            "path\tpixelWidth\tpixelHeight\twidthPt\tscale\ttheme\texpansion\tkind",
        ]

        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        defer { restoreStandardTheme(previousTheme) }

        var composerHeights: [CGFloat: CGFloat] = [:]
        for width in widths {
            composerHeights[width] = measureComposerHeight(viewModel: viewModel, columnWidth: width)
        }

        for width in widths {
            let contentMaxWidth = ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width)
            let bottomMargin = composerHeights[width] ?? 84
            for scale in scales {
                ChatFontSettings.save(scale.value, defaults: suite)
                #expect(ChatFontSettings.currentScale(defaults: suite) == scale.value)
                for theme in themes {
                    suite.set(theme.id, forKey: ThemeStore.themeKey)
                    UserDefaults.standard.set(theme.id, forKey: ThemeStore.themeKey)

                    let host = hostedTranscript(
                        viewModel: viewModel,
                        items: items,
                        columnWidth: width,
                        contentMaxWidth: contentMaxWidth,
                        bottomScrollContentMargin: bottomMargin,
                        defaults: suite
                    )

                    let collapsedName = "transcript-w\(int(width))-s\(scale.label)-\(theme.label)-collapsed.png"
                    let collapsedURL = outDir.appendingPathComponent(collapsedName)
                    let collapsed = try captureTranscriptPNG(
                        root: host,
                        width: width,
                        url: collapsedURL,
                        expand: false
                    )
                    manifest.append(
                        row(
                            collapsedURL.path,
                            collapsed,
                            width: width,
                            scale: scale.label,
                            theme: theme.label,
                            expansion: "collapsed",
                            kind: "transcript"
                        )
                    )

                    let expandedName = "transcript-w\(int(width))-s\(scale.label)-\(theme.label)-expanded.png"
                    let expandedURL = outDir.appendingPathComponent(expandedName)
                    let expanded = try captureTranscriptPNG(
                        root: host,
                        width: width,
                        url: expandedURL,
                        expand: true
                    )
                    manifest.append(
                        row(
                            expandedURL.path,
                            expanded,
                            width: width,
                            scale: scale.label,
                            theme: theme.label,
                            expansion: "expanded",
                            kind: "transcript"
                        )
                    )
                }
            }
        }

        ChatFontSettings.save(1.0, defaults: suite)
        suite.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        try writeCellPNGs(outDir: outDir, viewModel: viewModel, defaults: suite, manifest: &manifest)
        try writeExpandedStatePNGs(outDir: outDir, defaults: suite, manifest: &manifest)

        try manifest.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("manifest.tsv"),
            atomically: true,
            encoding: .utf8
        )
        try writeComposerHeights(composerHeights, to: outDir.appendingPathComponent("composer-heights.txt"))
    }
}

// MARK: - 通信しないクライアント（DashboardFeature の DisconnectedStructuredAgentClient と同型）

private final class DisconnectedHarnessClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>

    init() {
        events = AsyncStream { $0.finish() }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}

// MARK: - 設定保存先の実コード確認

@MainActor
private func confirmSettingsStore(suiteName: String) throws -> String {
    let sessionSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SessionFeature")
    let designSources = sessionSources
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("DesignSystem/Sources/DesignSystem")

    let transcriptSource = try String(
        contentsOf: sessionSources.appendingPathComponent("ChatTranscriptView.swift"),
        encoding: .utf8
    )
    let fontSettingsSource = try String(
        contentsOf: designSources.appendingPathComponent("ChatFontSettings.swift"),
        encoding: .utf8
    )
    let tokensSource = try String(
        contentsOf: designSources.appendingPathComponent("Tokens.swift"),
        encoding: .utf8
    )
    let appThemeSource = try String(
        contentsOf: designSources.appendingPathComponent("AppTheme.swift"),
        encoding: .utf8
    )

    let appStorageScale = transcriptSource.contains(
        "@AppStorage(ChatFontSettings.scaleKey) private var chatScale"
    )
    let appStorageHasExplicitStore = transcriptSource.contains(
        "@AppStorage(ChatFontSettings.scaleKey, store:"
    )
    let appStorageTheme = transcriptSource.contains(
        "@AppStorage(ThemeStore.themeKey) private var themeID"
    )
    let saveDefaultsStandard = fontSettingsSource.contains(
        "defaults: UserDefaults = .standard"
    )
    let dsColorUsesActive = tokensSource.contains("ThemeStore.active")
    let themeStoreActiveStandard = appThemeSource.contains("active(in: .standard)")

    var lines: [String] = []
    lines.append("suiteName=\(suiteName)")
    lines.append("ChatTranscriptView.chatScale=@AppStorage(ChatFontSettings.scaleKey) store指定なし=\(appStorageScale && !appStorageHasExplicitStore)")
    lines.append("ChatTranscriptView.themeID=@AppStorage(ThemeStore.themeKey) store指定なし=\(appStorageTheme)")
    lines.append("ChatFontSettings.save/currentScale 既定は UserDefaults.standard=\(saveDefaultsStandard)")
    lines.append("DSColor.theme は ThemeStore.active=\(dsColorUsesActive)")
    lines.append("ThemeStore.active は UserDefaults.standard=\(themeStoreActiveStandard)")
    lines.append("隔離: 倍率はテスト用 suite へ ChatFontSettings.save し、ホスト View に .defaultAppStorage(suite) を付ける。")
    lines.append("隔離: テーマ id は suite（@AppStorage / Markdown キャッシュ）と UserDefaults.standard（DSColor）の両方へ書き、終了時に standard を復元する。")
    lines.append("suite だけ作って defaultAppStorage も standard へのテーマ書込も省略すると、View は standard を読む。")
    return lines.joined(separator: "\n") + "\n"
}

@MainActor
private func restoreStandardTheme(_ previous: Any?) {
    if let previous {
        UserDefaults.standard.set(previous, forKey: ThemeStore.themeKey)
    } else {
        UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
    }
}

// MARK: - ホスト

@MainActor
private func hostedTranscript(
    viewModel: ChatSessionViewModel,
    items: [ChatItem],
    columnWidth: CGFloat,
    contentMaxWidth: CGFloat?,
    bottomScrollContentMargin: CGFloat,
    defaults: UserDefaults
) -> some View {
    ChatTranscriptView(
        viewModel: viewModel,
        transcript: items,
        showsThinkingIndicator: true,
        contentMaxWidth: contentMaxWidth,
        bottomScrollContentMargin: bottomScrollContentMargin
    )
    .frame(width: columnWidth)
    .background(DSColor.chatBackground)
    .defaultAppStorage(defaults)
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

@MainActor
private func writeComposerHeights(_ heights: [CGFloat: CGFloat], to url: URL) throws {
    let text = heights
        .sorted { $0.key < $1.key }
        .map { "columnWidth=\(int($0.key)) composerHeight=\($0.value)" }
        .joined(separator: "\n") + "\n"
    try text.write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - 描画

private struct CaptureSize {
    var pixelWidth: Int
    var pixelHeight: Int
    var pressedCount: Int
}

@MainActor
private func captureTranscriptPNG<Content: View>(
    root: Content,
    width: CGFloat,
    url: URL,
    expand: Bool
) throws -> CaptureSize {
    let probeHeight: CGFloat = 8_000
    let hosting = NSHostingView(rootView: root)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: probeHeight)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: min(probeHeight, 1_200)),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setContentSize(NSSize(width: width, height: probeHeight))
    window.makeKeyAndOrderFront(nil)
    layoutPass(hosting)

    var pressed = 0
    if expand {
        pressed = expandHostedDisclosures(in: hosting)
        layoutPass(hosting)
    }

    let measured = max(measuredContentHeight(in: hosting), 1)
    if abs(measured - probeHeight) > 1 {
        hosting.frame.size.height = measured
        window.setContentSize(NSSize(width: width, height: measured))
        layoutPass(hosting)
        if expand {
            pressed += expandHostedDisclosures(in: hosting)
            layoutPass(hosting)
            let grown = max(measuredContentHeight(in: hosting), measured)
            hosting.frame.size.height = grown
            window.setContentSize(NSSize(width: width, height: grown))
            layoutPass(hosting)
        }
    }

    let size = try writePNG(from: hosting, url: url, preferTranscriptScroll: true)
    window.orderOut(nil)
    return CaptureSize(pixelWidth: size.width, pixelHeight: size.height, pressedCount: pressed)
}

@MainActor
private func captureCellPNG<Content: View>(
    root: Content,
    width: CGFloat,
    url: URL,
    expand: Bool
) throws -> CaptureSize {
    let hosting = NSHostingView(rootView: root.frame(width: width))
    var height = max(hosting.fittingSize.height, 40)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    layoutPass(hosting)
    var pressed = 0
    if expand {
        pressed = expandHostedDisclosures(in: hosting)
        layoutPass(hosting)
    }
    height = max(hosting.fittingSize.height, measuredContentHeight(in: hosting), 40)
    hosting.frame.size.height = height
    window.setContentSize(NSSize(width: width, height: height))
    layoutPass(hosting)
    let size = try writePNG(from: hosting, url: url, preferTranscriptScroll: false)
    window.orderOut(nil)
    return CaptureSize(pixelWidth: size.width, pixelHeight: size.height, pressedCount: pressed)
}

@MainActor
private func writePNG(from hosting: NSView, url: URL, preferTranscriptScroll: Bool) throws -> (width: Int, height: Int) {
    let target: NSView
    let bounds: NSRect
    if preferTranscriptScroll,
       let scroll = outermostScrollView(in: hosting),
       let document = scroll.documentView
    {
        document.layoutSubtreeIfNeeded()
        target = document
        let height = max(document.bounds.height, document.frame.height, 1)
        bounds = NSRect(
            x: 0,
            y: 0,
            width: max(document.bounds.width, hosting.bounds.width, 1),
            height: height
        )
    } else {
        target = hosting
        bounds = NSRect(
            x: 0,
            y: 0,
            width: max(hosting.bounds.width, 1),
            height: max(hosting.bounds.height, 1)
        )
    }
    let rep = try #require(target.bitmapImageRepForCachingDisplay(in: bounds))
    target.cacheDisplay(in: bounds, to: rep)
    let png = try #require(rep.representation(using: .png, properties: [:]))
    try png.write(to: url, options: .atomic)
    return (rep.pixelsWide, rep.pixelsHigh)
}

@MainActor
private func layoutPass(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    view.layoutSubtreeIfNeeded()
}

@MainActor
private func measuredContentHeight(in root: NSView) -> CGFloat {
    if let scroll = outermostScrollView(in: root), let document = scroll.documentView {
        document.layoutSubtreeIfNeeded()
        return max(document.frame.height, document.bounds.height, document.fittingSize.height)
    }
    return max(root.fittingSize.height, root.bounds.height)
}

@MainActor
private func outermostScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView {
        return scroll
    }
    for subview in view.subviews {
        if let found = outermostScrollView(in: subview) {
            return found
        }
    }
    return nil
}

@MainActor
private func expandHostedDisclosures(in root: NSView) -> Int {
    // DisclosureCard の Button は NSView AX に `折りたたみ中` を出さない。
    // Cell へ合成マウスイベントを送ると ChatTranscriptView のレイアウトループでハングしたため、
    // ここでは AX performPress のみ試す（ヒットしなければ 0）。
    layoutPass(root)
    return pressMatchingControls(in: root, includeHeaders: false)
}

@MainActor
private func dumpAXIfNeeded(_ root: NSView) {
    let marker = URL(fileURLWithPath: "/tmp/phlox-t13-visual.SPfR9c/t40-gateB/ax-dump.txt")
    guard !FileManager.default.fileExists(atPath: marker.path) else { return }
    var lines: [String] = []
    var seen = Set<ObjectIdentifier>()
    func visit(_ element: Any, depth: Int) {
        let object = element as AnyObject
        let identity = ObjectIdentifier(object)
        guard seen.insert(identity).inserted else { return }
        let pad = String(repeating: "  ", count: depth)
        let typeName = String(describing: type(of: object))
        lines.append(
            "\(pad)\(typeName) role=\(stringValue(object.accessibilityRole() as Any?)) value=\(stringValue(object.accessibilityValue())) label=\(stringValue(object.accessibilityLabel())) title=\(stringValue(object.accessibilityTitle())) id=\(stringValue(object.accessibilityIdentifier()))"
        )
        if let children = object.accessibilityChildren() {
            for child in children.prefix(40) {
                visit(child, depth: depth + 1)
            }
        }
        if let view = element as? NSView {
            for subview in view.subviews.prefix(40) {
                visit(subview, depth: depth + 1)
            }
        }
    }
    visit(root, depth: 0)
    try? lines.joined(separator: "\n").write(to: marker, atomically: true, encoding: .utf8)
}

@MainActor
private func pressMatchingControls(in root: NSView, includeHeaders: Bool) -> Int {
    var pressed = 0
    var seen = Set<ObjectIdentifier>()
    guard let window = root.window else { return 0 }

    func visit(_ element: Any) {
        let object = element as AnyObject
        let identity = ObjectIdentifier(object)
        guard seen.insert(identity).inserted else { return }

        if shouldPress(element, includeHeaders: includeHeaders) {
            if performPress(element) {
                pressed += 1
                return
            }
            let frame = object.accessibilityFrame()
            if !frame.isEmpty, clickScreenFrame(frame, window: window) {
                pressed += 1
                return
            }
        }

        if let children = object.accessibilityChildren() {
            for child in children {
                visit(child)
            }
        }
        if let view = element as? NSView {
            for subview in view.subviews {
                visit(subview)
            }
        }
    }

    visit(root)
    return pressed
}

@MainActor
private func shouldPress(_ element: Any, includeHeaders: Bool) -> Bool {
    let object = element as AnyObject
    let value = stringValue(object.accessibilityValue())
    let label = stringValue(object.accessibilityLabel())
    let title = stringValue(object.accessibilityTitle())
    let identifier = stringValue(object.accessibilityIdentifier())
    let role = stringValue(object.accessibilityRole() as Any?)
    let combined = [value, label, title, identifier, role].joined(separator: " ")
    if value == "折りたたみ中" || value.contains("折りたたみ") {
        return true
    }
    if combined.contains("さらに") && combined.contains("行を表示") {
        return true
    }
    if identifier == "CommandGroupExecutionRow.showMoreOutput" {
        return true
    }
    guard includeHeaders else { return false }
    let headerHints = [
        "swift test --filter TranscriptTypography",
        "rg \"TranscriptTypography\" macos/Packages/SessionFeature",
        "git log --oneline --decorate --graph",
        "連続コマンドのグループを一旦閉じ",
        "空出力のコマンドグループを独立",
        "編集済み TranscriptTypography.swift",
    ]
    if headerHints.contains(where: { hint in
        value.contains(hint) || label.contains(hint) || title.contains(hint)
    }) {
        return true
    }
    if role.contains("Button") || role.contains("button") || role == NSAccessibility.Role.button.rawValue {
        if combined.contains("chevron") || combined.contains("展開") || combined.contains("折りたたみ") {
            return true
        }
        if identifier == "CommandGroupCell" {
            return true
        }
    }
    return false
}

@MainActor
private func performPress(_ element: Any) -> Bool {
    if let button = element as? NSButton {
        button.performClick(nil)
        return true
    }
    let object = element as AnyObject
    let names = object.accessibilityActionNames()
    if names.contains(NSAccessibility.Action.press) {
        object.accessibilityPerformAction(.press)
        return true
    }
    if object.responds(to: #selector(NSAccessibilityProtocol.accessibilityPerformPress)) {
        return object.accessibilityPerformPress()
    }
    return false
}

@MainActor
private func clickScreenFrame(_ screenFrame: NSRect, window: NSWindow) -> Bool {
    let screenPoint = NSPoint(x: screenFrame.midX, y: screenFrame.midY)
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    guard window.contentView?.bounds.contains(windowPoint) == true
            || window.contentView?.superview != nil
    else {
        return false
    }
    let timestamp = ProcessInfo.processInfo.systemUptime
    guard
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ),
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: timestamp + 0.02,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )
    else {
        return false
    }
    window.sendEvent(down)
    window.sendEvent(up)
    return true
}

@MainActor
private func stringValue(_ raw: Any?) -> String {
    if let text = raw as? String {
        return text
    }
    if let attributed = raw as? NSAttributedString {
        return attributed.string
    }
    if let array = raw as? [Any] {
        return array.compactMap { stringValue($0) }.joined(separator: " ")
    }
    return ""
}

// MARK: - 個別セル

@MainActor
private func writeCellPNGs(
    outDir: URL,
    viewModel: ChatSessionViewModel,
    defaults: UserDefaults,
    manifest: inout [String]
) throws {
    let width: CGFloat = 720
    let scaleLabel = "1.0"
    let themeLabel = "phlox-light"
    let descriptor = AgentRegistry.descriptor(for: .claudeCode)
    let items = GateBFixture.items

    func wrap<V: View>(_ view: V) -> some View {
        view
            .frame(width: width)
            .padding(16)
            .background(DSColor.chatBackground)
            .defaultAppStorage(defaults)
    }

    func appendCell(name: String, size: CaptureSize, expansion: String) {
        manifest.append(
            row(
                outDir.appendingPathComponent(name).path,
                size,
                width: width,
                scale: scaleLabel,
                theme: themeLabel,
                expansion: expansion,
                kind: "cell"
            )
        )
    }

    let cellSpecs: [(name: String, view: AnyView, expand: Bool)] = [
        (
            "cell-user-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: items[0], isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-agent-markdown-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: items[1], isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-command-group-collapsed-w720-s1.0-phlox-light.png",
            AnyView(wrap(CommandGroupCell(
                items: [items[3], items[4]],
                lastTranscriptID: nil,
                isTurnRunning: false
            ))),
            false
        ),
        (
            "cell-command-group-expanded-w720-s1.0-phlox-light.png",
            AnyView(wrap(CommandGroupCell(
                items: [items[3], items[4]],
                lastTranscriptID: nil,
                isTurnRunning: false
            ))),
            true
        ),
        (
            "cell-reasoning-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: items[5], isRunningCommand: false, agentDescriptor: descriptor))),
            true
        ),
        (
            "cell-file-change-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: GateBFixture.fileChange, isRunningCommand: false, agentDescriptor: descriptor))),
            true
        ),
        (
            "cell-task-list-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: GateBFixture.taskList, isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-question-answered-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: GateBFixture.answeredQuestion, isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-question-expired-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: GateBFixture.expiredQuestion, isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-turn-cost-w720-s1.0-phlox-light.png",
            AnyView(wrap(ChatItemView(item: GateBFixture.turnCost, isRunningCommand: false, agentDescriptor: descriptor))),
            false
        ),
        (
            "cell-thinking-w720-s1.0-phlox-light.png",
            AnyView(wrap(ThinkingIndicatorCell(descriptor: descriptor, state: .thinking))),
            false
        ),
    ]

    for spec in cellSpecs {
        let url = outDir.appendingPathComponent(spec.name)
        let size = try captureCellPNG(root: spec.view, width: width, url: url, expand: spec.expand)
        appendCell(name: spec.name, size: size, expansion: spec.expand ? "expanded" : "default")
    }

    _ = viewModel
}

// MARK: - 展開状態のセル単位描画（製品コード変更なし）

/// CommandGroupCell / ReasoningSummaryView / FileChangeCell / CommandGroupExecutionRow は
/// `@State private var isExpanded = false`（差分は `userExpandedOverride: Bool? = nil`）で、
/// 展開を init・環境値・AppStorage 記憶キーから与える経路は無い。
/// 製品の公開面として使えるのは `DisclosureCard(isExpanded: Binding<Bool>)` と
/// `CommandGroupExecutionDisplayData.outputDisplay(isExpanded:)`。合成クリックはしない。
@MainActor
private func writeExpandedStatePNGs(
    outDir: URL,
    defaults: UserDefaults,
    manifest: inout [String]
) throws {
    let width: CGFloat = 720
    let scaleLabel = "1.0"
    ChatFontSettings.save(1.0, defaults: defaults)
    #expect(ChatFontSettings.currentScale(defaults: defaults) == 1.0)

    let themes: [(label: String, id: String)] = [
        ("phlox-light", AppTheme.phloxLight.id),
        ("dracula", AppTheme.dracula.id),
    ]
    let commandItems = [GateBFixture.items[3], GateBFixture.items[4]]
    let reasoning = GateBFixture.items[5]
    let reasoningText: String = {
        if case .reasoning(_, let text, _) = reasoning { return text }
        return ""
    }()
    let filePatches: [FilePatchChange] = {
        if case .fileChange(_, let changes, _) = GateBFixture.fileChange {
            return changes
        }
        return []
    }()

    func wrap<V: View>(_ view: V) -> some View {
        view
            .frame(width: width)
            .padding(16)
            .background(DSColor.chatBackground)
            .defaultAppStorage(defaults)
    }

    var pathNote: [String] = [
        "DisclosureCard.init(isExpanded: Binding<Bool>) ChatMessageCellsCommon.swift:55-67",
        "CommandGroupExecutionDisplayData.outputDisplay(isExpanded:) ChatMessageCells+CommandGroup.swift:73-77",
        "CommandGroupCell.isExpanded @State private = false / init に展開引数なし ChatMessageCells+CommandGroup.swift:163-175",
        "ReasoningSummaryView.isExpanded @State private = false ChatMessageCells+Structured.swift:195-196",
        "FileChangeCell.userExpandedOverride @State private = nil / FileChangeDisplayPolicy.isExpanded(userOverride: nil) => false ChatMessageCells+Structured.swift:291-316 ChatMessageRenderCache.swift:181-183",
        "CommandGroupExecutionRow.isOutputExpanded @State private = false（private struct） ChatMessageCells+CommandGroup.swift:232-235",
        "展開記憶の @AppStorage キーは無い。合成マウスは使わない。",
    ]

    for theme in themes {
        defaults.set(theme.id, forKey: ThemeStore.themeKey)
        UserDefaults.standard.set(theme.id, forKey: ThemeStore.themeKey)

        let specs: [(name: String, view: AnyView)] = [
            (
                "expanded-command-group-w720-s1.0-\(theme.label).png",
                AnyView(wrap(GateBExpandedCommandGroup(items: commandItems)))
            ),
            (
                "expanded-reasoning-w720-s1.0-\(theme.label).png",
                AnyView(wrap(GateBExpandedReasoning(text: reasoningText)))
            ),
            (
                "expanded-file-change-w720-s1.0-\(theme.label).png",
                AnyView(wrap(GateBExpandedFileChange(changes: filePatches)))
            ),
            (
                "expanded-output-20plus-w720-s1.0-\(theme.label).png",
                AnyView(wrap(GateBExpandedCommandRow(
                    command: "swift test --filter TranscriptTypography",
                    output: GateBFixture.twentyFiveLineOutput
                )))
            ),
        ]

        for spec in specs {
            let hosted = spec.view
            // AcceptanceCommandGroupRecapHeaderTests と同じく製品 View を ImageRenderer でホストできることを確認する。
            // PNG の寸法は既存セルと同じ NSHostingView + cacheDisplay（Retina 2x）で書く。
            #expect(ImageRenderer(content: hosted.frame(width: width)).cgImage != nil)
            let url = outDir.appendingPathComponent(spec.name)
            let size = try captureCellPNG(root: hosted, width: width, url: url, expand: false)
            manifest.append(
                row(
                    url.path,
                    size,
                    width: width,
                    scale: scaleLabel,
                    theme: theme.label,
                    expansion: "expanded",
                    kind: "expanded-cell"
                )
            )
            pathNote.append("\(spec.name)\t\(size.pixelWidth)x\(size.pixelHeight)")
        }
    }

    try pathNote.joined(separator: "\n").write(
        to: outDir.appendingPathComponent("expanded-path.txt"),
        atomically: true,
        encoding: .utf8
    )
}

private struct GateBExpandedCommandGroup: View {
    let items: [ChatItem]
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        let header = CommandGroupHeader(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        let rowsSlice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )
        DisclosureCard(
            isExpanded: .constant(true),
            title: header.title,
            subtitle: nil,
            isToolCall: true
        ) {
            VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
                ForEach(rowsSlice.rows) { row in
                    GateBExpandedCommandRow(command: row.command, output: row.output)
                        .id(row.id)
                }
            }
            .padding(.top, TranscriptTypography.withinAnswer)
        }
        .frame(maxWidth: 800, alignment: .leading)
    }
}

private struct GateBExpandedReasoning: View {
    let text: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = ReasoningPresentation(text: text)
        DisclosureCard(
            isExpanded: .constant(true),
            title: presentation.headline,
            subtitle: nil,
            isToolCall: true
        ) {
            Text(text)
                .font(ChatScaledFont.body(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .chatTextSelection()
                .lineSpacing(TranscriptTypography.textLineSpacing)
                .padding(.top, TranscriptTypography.withinAnswer)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

private struct GateBExpandedFileChange: View {
    let changes: [FilePatchChange]
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let counts = FileChangePresentation.counts(for: changes)
        DisclosureCard(
            isExpanded: .constant(true),
            subtitle: nil,
            titleContent: {
                HStack(spacing: DSSpacing.xxs) {
                    Text(FileChangePresentation.title(for: changes))
                    Text("+\(counts.additions)")
                        .foregroundStyle(DSColor.diffAdded)
                    Text("-\(counts.deletions)")
                        .foregroundStyle(DSColor.diffRemoved)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
                ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                    let codeView = ChatMessageRenderCache.diffCodeView(diff: change.diff, path: change.path)
                    ChatCodeCard(
                        copyText: change.diff,
                        copyAccessibilityIdentifier: "GateBExpandedFileChange.copyDiff.\(index)",
                        header: {
                            Text(change.path)
                                .font(ChatScaledFont.caption(scale: scale))
                                .foregroundStyle(DSColor.chatTextSecondary)
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(codeView.lines) { codeLine in
                                GateBExpandedDiffLine(
                                    codeLine: codeLine,
                                    hasLineNumbers: codeView.hasLineNumbers,
                                    lineNumberWidth: codeView.lineNumberWidth,
                                    scale: scale
                                )
                            }
                        }
                    }
                }
            }
            .padding(.top, TranscriptTypography.withinAnswer)
        }
        .frame(maxWidth: 860, alignment: .leading)
    }
}

private struct GateBExpandedDiffLine: View {
    let codeLine: DiffCodeLine
    let hasLineNumbers: Bool
    let lineNumberWidth: Int
    let scale: CGFloat

    var body: some View {
        let line = codeLine.line
        HStack(spacing: DSSpacing.s) {
            if hasLineNumbers {
                Text(line.displayLineNumber.map(String.init) ?? "")
                    .font(ChatScaledFont.monoCaption(scale: scale))
                    .foregroundStyle(markerForeground)
                    .frame(width: CGFloat(lineNumberWidth) * 7 * scale, alignment: .trailing)
            }
            Text(marker)
                .font(ChatScaledFont.monoCaption(scale: scale))
                .foregroundStyle(markerForeground)
                .frame(width: 8 * scale, alignment: .leading)
            Text(codeLine.body)
                .font(ChatScaledFont.monoCaption(scale: scale))
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle().fill(lineBackground)
        }
        .diffLineTextSelection()
    }

    private var marker: String {
        switch codeLine.line.kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        case .fileHeader, .hunk: ""
        }
    }

    private var markerForeground: Color {
        switch codeLine.line.kind {
        case .addition: DSColor.diffAdded
        case .deletion: DSColor.diffRemoved
        case .hunk, .fileHeader: DSColor.chatTextSecondary
        case .context: DSColor.chatTextPrimary
        }
    }

    private var lineBackground: Color {
        switch codeLine.line.kind {
        case .addition: DSColor.diffAdded.opacity(0.12)
        case .deletion: DSColor.diffRemoved.opacity(0.12)
        case .hunk, .fileHeader, .context: .clear
        }
    }
}

/// CommandGroupExecutionRow 相当。`outputDisplay(isExpanded: true)` で 20 行超も全文。
private struct GateBExpandedCommandRow: View {
    let command: String?
    let output: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let display = ChatMessageRenderCache.commandExecution(command: command, output: output)
        ChatCodeCard(
            copyText: display.copyText,
            copyAccessibilityIdentifier: "GateBExpandedCommandRow.copyOutput",
            header: {
                Text(display.label)
                    .font(TranscriptTypography.font(for: .processSummary, scale: scale))
                    .foregroundStyle(DSColor.chatTextSecondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if display.commandBody.isEmpty {
                    Text("(コマンドなし)")
                        .font(ChatScaledFont.mono(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("$ ")
                        Text(display.highlightedCommand)
                    }
                    .font(ChatScaledFont.mono(scale: scale))
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .chatTextSelection()
                }
                if !output.isEmpty {
                    let outputDisplay = display.outputDisplay(isExpanded: true)
                    Text(outputDisplay.displayedOutput)
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .chatTextSelection()
                        .padding(.top, TranscriptTypography.withinAnswer)
                }
            }
            .padding(.horizontal, TranscriptTypography.cardHorizontalInset)
            .padding(.bottom, TranscriptTypography.codeContentInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - fixture

private enum GateBFixture {
    static let time = Date(timeIntervalSince1970: 1_700_000_000)

    static let longCodeLine =
        "let horizontalReach = \"" + String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 6) + "\""

    static let twentyFiveLineOutput: String = {
        (1...25).map { "test output line \($0) 日本語混在の長い出力で省略と展開を見る" }.joined(separator: "\n")
    }()

    static let agentMarkdown = """
    # 見出し1 本文の階層を見る

    日本語の長文段落その1。同じ回答内では8pt、入力後の内容では16pt、次のユーザー入力の前では24ptが並ぶことを後続ブロックと見比べる。文字倍率を変えても間隔トークンは拡大しない。幅360ptでは必ず折り返し、見出し・本文・補助情報の読順が崩れないかを確認する。

    ## これは非常に長く折り返すことを意図した節見出しで、狭い幅360ポイントでも1行に収まらず複数行へ折り曲がるほど詳細な説明を含む見出しテキストです

    日本語の長文段落その2。インラインコードは `ComposerLayout.transcriptContentMaxWidth` のように埋め込み、フェンスは Swift とする。長いコード行は水平方向へ到達できるかも見る。

    ### 見出し3 箇条書きと番号

    #### 見出し4 補助的な節
    ##### 見出し5 さらに小さい節
    ###### 見出し6 最下位の節

    - 長い箇条書きの項目その1。トランスクリプトの本文幅いっぱいに伸ばして折り返しと行間、マーカー位置の重なりを確認する。
    - 長い箇条書きの項目その2。入れ子を続ける。
      - 入れ子の子項目。番号付きリストと混在させて字下げを見る。
      - さらに入れ子の子項目。長い説明を足して折り返す。
    - 長い箇条書きの項目その3。インライン `gap(after:before:)` を含む。

    1. 番号付きの長い項目。幅360では必ず折り返し、番号と本文の間隔を確認する。
    2. 番号付きの2番。入れ子番号を続ける。
       1. 入れ子番号の子。
       2. 入れ子番号のもう一つの子。
    3. 番号付きの3番。

    | 役割 | 基準pt | 確認点 |
    | --- | --- | --- |
    | body | 15 | 本文 |
    | processSummary | 15 | 処理見出し |
    | metadata | 10 | 時刻と料金 |

    ```swift
    struct TranscriptTypographyFixture {
        func render() {
            print(horizontalReach)
        }
    }
    ```

    長いコード行:

    ```
    let horizontalReach = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789"
    ```
    """

    static let answeredQuestion = ChatItem.userQuestion(
        id: "q-answered",
        requestId: "req-answered",
        questions: [
            ChatUserQuestion(
                question: "文字階層の確認をどの幅で残しますか？",
                header: "目視幅",
                options: [
                    ChatUserQuestionOption(label: "360と720の両方", description: "契約どおり"),
                    ChatUserQuestionOption(label: "720のみ", description: nil),
                ],
                multiSelect: false
            ),
        ],
        answers: ["文字階層の確認をどの幅で残しますか？": ["360と720の両方"]],
        state: .answered,
        timestamp: time
    )

    static let expiredQuestion = ChatItem.userQuestion(
        id: "q-expired",
        requestId: "req-expired",
        questions: [
            ChatUserQuestion(
                question: "期限切れの質問カードは補助色と操作不能が分かるか？",
                header: "期限切れ",
                options: [
                    ChatUserQuestionOption(label: "はい", description: nil),
                    ChatUserQuestionOption(label: "いいえ", description: nil),
                ],
                multiSelect: false
            ),
        ],
        answers: nil,
        state: .expired,
        timestamp: time
    )

    static let taskList = ChatItem.taskList(
        id: "task-list",
        tasks: [
            AgentTaskItem(id: "task-pending", title: "未着手の調査項目を長く書いて折り返しを見る", status: .pending),
            AgentTaskItem(id: "task-running", title: "実行中の項目は semibold の本文強調", status: .inProgress),
            AgentTaskItem(id: "task-done", title: "完了した項目は取り消し線と補助色", status: .completed),
        ],
        timestamp: time
    )

    static let fileChange = ChatItem.fileChange(
        id: "file-1",
        changes: [
            FilePatchChange(
                path: "macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift",
                diff: """
                diff --git a/TranscriptTypography.swift b/TranscriptTypography.swift
                @@ -1,8 +1,10 @@
                 public enum TranscriptTypography {
                -    static let body = 13
                +    static let body = 15
                +    static let processSummary = 15
                     static let metadata = 10
                 }
                """,
                kind: "edit"
            ),
        ],
        timestamp: time
    )

    static let turnCost = ChatItem.turnCost(id: "cost-1", costUSD: 0.42, timestamp: time)

    static var items: [ChatItem] {
        [
            .userMessage(
                id: "u1",
                text: "UI-03の本文・処理見出し・補助情報の文字と余白を、混在する会話として並べて確認したい。",
                timestamp: time
            ),
            .agentMessage(id: "a1", text: agentMarkdown, timestamp: time),
            .agentMessage(
                id: "a2",
                text: "続きの分割出力です。同じ回答内の8pt間隔を、直前の本文ブロックと見比べます。",
                timestamp: time
            ),
            .commandExecution(
                id: "cmd-a",
                command: "git log \\\n  --oneline \\\n  --decorate --graph",
                output: "abc123 見出しと本文の間隔を整える\ndef456 コマンドグループの折りたたみを残す",
                timestamp: time
            ),
            .commandExecution(
                id: "cmd-b",
                command: "swift test --filter TranscriptTypography",
                output: twentyFiveLineOutput,
                timestamp: time
            ),
            .reasoning(
                id: "reason-1",
                text: "連続コマンドのグループを一旦閉じ、Reasoning で区切った別グループを続ける。折りたたみと展開の両方をホストした実 View で操作する。",
                timestamp: time
            ),
            .commandExecution(
                id: "cmd-c",
                command: "rg \"TranscriptTypography\" macos/Packages/SessionFeature",
                output: "ChatTranscriptView.swift\nChatMessageCellsCommon.swift",
                timestamp: time
            ),
            .reasoning(
                id: "reason-2",
                text: "空出力のコマンドグループを独立させるための区切り。",
                timestamp: time
            ),
            .commandExecution(id: "cmd-empty-1", command: "true", output: "", timestamp: time),
            .commandExecution(id: "cmd-empty-2", command: ":", output: "   \n", timestamp: time),
            fileChange,
            taskList,
            answeredQuestion,
            expiredQuestion,
            .agentMessage(
                id: "a3",
                text: "処理カードから回答本文へ切り替わる16pt境界の直後です。時刻と料金の10pt補助を続けます。",
                timestamp: time
            ),
            turnCost,
            .userMessage(
                id: "u2",
                text: "追加の質問です。直前の料金行との24pt境界を同時に比較する。",
                timestamp: time
            ),
        ]
    }
}

// MARK: - 行

@MainActor
private func row(
    _ path: String,
    _ size: CaptureSize,
    width: CGFloat,
    scale: String,
    theme: String,
    expansion: String,
    kind: String
) -> String {
    "\(path)\t\(size.pixelWidth)\t\(size.pixelHeight)\t\(int(width))\t\(scale)\t\(theme)\t\(expansion)\t\(kind)"
}

private func int(_ value: CGFloat) -> Int {
    Int(value.rounded())
}
