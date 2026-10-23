import AppKit
import AgentDomain
import DesignSystem
import IOSurface
import QuartzCore
import SimulatorBridgeKit
@testable import SessionFeature
import SwiftUI
import TerminalUI
import Testing
import WebKit
@testable import DashboardFeature

private final class Stage8SnapshotClients: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [EventYieldingStructuredClient] = []

    func make() -> EventYieldingStructuredClient {
        lock.lock()
        defer { lock.unlock() }
        let client = EventYieldingStructuredClient()
        clients.append(client)
        return client
    }

    func client(at index: Int) -> EventYieldingStructuredClient? {
        lock.lock()
        defer { lock.unlock() }
        return clients.indices.contains(index) ? clients[index] : nil
    }
}

/// 実画面を表示せず、比較用の部品画像を明示指定時だけ書き出す。
extension ThemeRenderingTests {
@Suite @MainActor
struct DesignSnapshotRenderTests {
    @Test func bottomPanelSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1",
              ["all", "bottom-panel", "focus-borders"].contains(ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] ?? "all") else { return }
        let focusOnly = ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] == "focus-borders"
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let axGetter = NSSelectorFromString("accessibilityAttributeValue:")
        let axSetter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previousAX = NSApp.perform(axGetter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(axSetter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(axSetter, with: previousAX, with: "AXEnhancedUserInterface") }
        var worktree = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { worktree.deleteLastPathComponent() }
        let output = worktree.appendingPathComponent(".build/design-snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) { try FileManager.default.removeItem(at: cachedStrings) }
        let preferences = UserDefaults.standard
        let arguments = preferences.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        let terminalPalette = TerminalCoordinator.activePalette
        defer {
            preferences.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
            TerminalCoordinator.activePalette = terminalPalette
        }
        for english in [false, true] {
            for light in [false, true] {
                var themeArguments = arguments
                themeArguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
                themeArguments[TerminalFontSettings.fontSizeKey] = 13.0
                preferences.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
                NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                TerminalCoordinator.activePalette = DashboardViewModel.makeTerminalPalette(from: light ? .phloxLight : .phlox)
                for variant in focusOnly ? [] : ["open", "focused", "exited", "shell-warning"] {
                    let strings = try localizationBundle(fixtures: output)
                    let locale = Locale(identifier: english ? "en" : "ja")
                    let pty = MockPTYManager()
                    let panel = TerminalPanelSession(controller: UserTerminalController(
                        pty: pty, shellPath: "/bin/zsh", workingDirectory: "/Users/ryosuke/Projects/Phlox-oss", environment: [:],
                        resolveShell: { UserShellResolution(path: "/bin/zsh", unavailablePath: variant == "shell-warning" ? "/opt/homebrew/bin/fish" : nil) },
                        shellWarning: { path in String(format: AppLocalizedString.string(
                            "設定のシェル（%@）が見つからないため、システムの既定で起動しました", locale: locale, bundle: strings), path) }))
                    try await panel.controller.ensureStarted()
                    if variant == "shell-warning" {
                        try await waitUntil { panel.terminalCoordinator.visibleText().contains("/opt/homebrew/bin/fish") }
                    }
                    panel.terminalCoordinator.feed(Data("Last login: Wed Oct 14 09:12:03 on ttys004\r\nryosuke@mac Phlox-oss % pwd\r\n/Users/ryosuke/Projects/Phlox-oss\r\nryosuke@mac Phlox-oss % ".utf8))
                    if variant == "exited", let id = panel.controller.sessionID {
                        pty.finishOutput(for: id)
                        pty.emitExit(for: id, code: 0)
                        try await waitUntil { !panel.controller.isRunning }
                    }
                    let state = BottomPanelState()
                    state.open(window: nil)
                    let id = "13-bp-\(variant)-\(light ? "light" : "dark")-\(english ? "en" : "ja")"
                    let frame = Frame(id: id, name: "下部パネル", width: 900, height: 300, light: light, language: english ? "en" : "ja")
                    do {
                        try await capture(BottomPanelView(panel: panel, state: state), frame: frame, output: output, prepare: { _, window in
                            #expect(panel.terminalCoordinator.terminalView.font.pointSize == 13)
                            if variant != "open" { window.makeFirstResponder(panel.terminalCoordinator.terminalView) }
                            else { window.makeFirstResponder(nil) }
                            try await waitUntil { state.isTerminalFocused == (variant != "open") }
                        })
                    } catch { await panel.controller.shutdown(); throw error }
                    await panel.controller.shutdown()
                    #expect(FileManager.default.fileExists(atPath: destination(frame, output).path))
                }
                for variant in focusOnly ? ["terminal-focused", "files-focused"] : ["open", "closed", "grid", "split", "overlay", "no-project", "terminal-focused", "files-focused"] {
                    let id = "13-bp-window-\(variant)-\(light ? "light" : "dark")-\(english ? "en" : "ja")"
                    let frame = Frame(id: id, name: "下部パネルの配置", width: variant == "overlay" ? 1000 : 1600, height: 1000, light: light, language: english ? "en" : "ja")
                    let scene = try await makeStage8Scene(frame, fixtures: output.appendingPathComponent("bottom-panel-fixtures"), sessionCount: 4)
                    let bottomPanel = BottomPanelState()
                    scene.router.inspectorVisible = true
                    scene.router.inspectorTab = .files
                    scene.router.selectedSession = scene.sessionIDs.first
                    if variant == "grid" { scene.router.viewMode = .grid }
                    if variant == "split", let first = scene.sessionIDs.first, let second = scene.sessionIDs.dropFirst().first {
                        scene.router.tabs.updateLayout(for: scene.project.id) {
                            $0.select(.chat(first))
                            $0.splitRight(.chat(second), chats: scene.sessionIDs.map { .chat($0) })
                        }
                        #expect(scene.router.tabs.layout(for: scene.project.id).right == .chat(second))
                    }
                    if variant == "no-project" {
                        scene.router.selectedProjectID = nil
                        scene.router.selectedSession = nil
                    } else if variant != "closed" { bottomPanel.open(window: nil) }
                    let store = ProjectTerminalStore { directory in
                        let panel = TerminalPanelSession(controller: UserTerminalController(pty: MockPTYManager(), shellPath: "/bin/zsh", workingDirectory: directory, environment: [:]))
                        panel.terminalCoordinator.feed(Data("ryosuke@mac Phlox-oss % pwd\r\n\(directory)\r\nryosuke@mac Phlox-oss % ".utf8))
                        return panel
                    }
                    do {
                        try await capture(DashboardView(viewModel: scene.dashboard, router: scene.router, usageMonitor: scene.usageMonitor,
                            newChatDraftStore: scene.draftStore, sessionTerminals: store, initiallyExpandedProjectIDs: [scene.project.id], bottomPanel: bottomPanel), frame: frame, output: output,
                            prepare: { host, window in
                                guard variant == "terminal-focused" || variant == "files-focused" else { return }
                                let terminal = store.bottomTerminal(for: scene.project.id, workingDirectory: scene.project.directoryPath)
                                try await waitUntil { terminal.terminalCoordinator.terminalView.window === window }
                                #expect(window.makeFirstResponder(terminal.terminalCoordinator.terminalView))
                                try await waitUntil { bottomPanel.isTerminalFocused }
                                if variant == "files-focused" {
                                    scene.router.showFilesInInspector()
                                    try await waitUntil {
                                        guard !bottomPanel.isTerminalFocused, let responder = window.firstResponder as? NSView else { return false }
                                        // SwiftUI の入力先は右ペイン専用の NSView ではなく、画面全体のホスト。
                                        return responder !== terminal.terminalCoordinator.terminalView && responder.isDescendant(of: host)
                                    }
                                    let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                        characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
                                    window.sendEvent(down)
                                    try await waitUntil {
                                        guard let row = snapshotAccessibilityElement("file-tree-row-README.md", in: host) else { return false }
                                        return (row as AnyObject).isAccessibilitySelected()
                                    }
                                }
                            })
                    } catch {
                        await store.shutdownAll()
                        for session in scene.dashboard.sessions { await session.kill() }
                        throw error
                    }
                    await store.shutdownAll()
                    for session in scene.dashboard.sessions { await session.kill() }
                    #expect(FileManager.default.fileExists(atPath: destination(frame, output).path))
                }
            }
        }
    }

    @Test func gitInspectorSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "bottom-panel" else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var worktree = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { worktree.deleteLastPathComponent() }
        let output = worktree.appendingPathComponent(".build/design-snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) { try FileManager.default.removeItem(at: cachedStrings) }
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain); NSApp.appearance = appearance }
        let changes: [WorkingTreeChange] = [
            .init(path: "docs/notes/bottom-panel.md", kind: .untracked, isBinary: false),
            .init(path: "macos/App/Resources/panel@2x.png", kind: .added, isBinary: true),
            .init(path: "macos/Packages/DashboardFeature/Sources/BottomPanel/BottomPanelModel.swift", kind: .added, isBinary: false),
            .init(path: "macos/Packages/DashboardFeature/Sources/BottomPanel/BottomPanelView.swift", kind: .modified, isBinary: false),
            .init(path: "macos/Packages/DashboardFeature/Sources/Git/GitChangesList.swift", kind: .renamed, isBinary: false),
            .init(path: "macos/Packages/DashboardFeature/Sources/Inspector/InspectorFilesOnlyView.swift", kind: .deleted, isBinary: false),
            .init(path: "macos/Packages/DashboardFeature/Sources/Inspector/InspectorView.swift", kind: .modified, isBinary: false)
        ]
        let gitFixture = output.appendingPathComponent("git-fixture")
        let binaryFile = gitFixture.appendingPathComponent(changes[1].path)
        try FileManager.default.createDirectory(at: binaryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 24_000).write(to: binaryFile)
        let diff = "@@ -18,3 +18,5 @@ struct BottomPanelView: View {\n     @Bindable var model: BottomPanelModel\n-    var body: some View {\n-        TerminalHostView(session: model.session)\n+    @FocusState private var isTerminalFocused: Bool\n+\n+    var body: some View {\n+        BottomPanelHeader(model: model, isFocused: isTerminalFocused)\n+        TerminalHostView(session: model.session)\n"
        for english in [false, true] {
            for light in [false, true] {
                var themeArguments = arguments
                themeArguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
                defaults.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
                NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                for width in [260, 280, 340] {
                    for state in ["list", "fresh", "clean", "nogit", "error", "long", "binary", "untracked"] {
                        let model = EditorPanelViewModel(service: nil, changeScope: .isolated(repositoryRoot: gitFixture.path))
                        if state == "fresh" {
                            model.acceptSnapshot(.init(branch: "feature/bottom-panel", changes: Array(changes.dropFirst().dropLast()), lineCounts: [:]))
                        }
                        if state != "nogit" {
                            model.acceptSnapshot(.init(branch: "feature/bottom-panel", changes: state == "clean" || state == "error" ? [] : changes,
                                lineCounts: Dictionary(uniqueKeysWithValues: changes.filter { !$0.isBinary }.map { ($0.path, WorkingTreeLineCount(added: 12, deleted: 3)) })))
                        } else { model.setSnapshotNotRepository() }
                        if state == "error" { model.listErrorMessage = "fatal: detected dubious ownership in repository at '/Users/ryosuke/Projects/Phlox-oss'" }
                        let detail: WorkingTreeDetail
                        let path: String
                        switch state {
                        case "long":
                            detail = .untrackedContent((1...86).map { "    let line\($0) = model.session" }.joined(separator: "\n")); path = changes[2].path
                        case "binary": detail = .binary; path = changes[1].path
                        case "untracked": detail = .untrackedContent("# 下部パネル メモ\n\n- 閉じてもシェルは終了しない\n"); path = changes[0].path
                        default: detail = .diff(diff); path = changes[3].path
                        }
                        let id = "13-gt-\(state)-\(width)-\(light ? "light" : "dark")-\(english ? "en" : "ja")"
                        let frame = Frame(id: id, name: "Git", width: CGFloat(width), height: 620, light: light, language: english ? "en" : "ja")
                        try await capture(VStack(spacing: 0) {
                            InspectorTabPicker(selection: .constant(.git))
                            GitInspectorView(model: model, workingDirectory: "/Users/ryosuke/Projects/design-notes", openChanges: { _, _, _ in }, openFile: { _ in })
                        }.background(DSColor.surface), frame: frame, output: output)
                        #expect(FileManager.default.fileExists(atPath: destination(frame, output).path))
                    }
                }
            }
        }
    }

    @Test func fileTreeOperationSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "bottom-panel" else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var worktree = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { worktree.deleteLastPathComponent() }
        let output = worktree.appendingPathComponent(".build/design-snapshots")
        let fixtures = output.appendingPathComponent("file-tree-operations")
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) { try FileManager.default.removeItem(at: cachedStrings) }
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain); NSApp.appearance = appearance }
        try FileManager.default.createDirectory(at: fixtures.appendingPathComponent("docs/guides"), withIntermediateDirectories: true)
        for name in ["file-tree.md", "step-1-setup.md"] {
            try Data("本文".utf8).write(to: fixtures.appendingPathComponent("docs/guides/" + name))
        }
        for english in [false, true] {
            for light in [false, true] {
                var themeArguments = arguments
                themeArguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
                defaults.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
                NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                let suffix = (english ? "-en" : "-ja") + (light ? "-light" : "-dark")
                for state in ["new-file", "new-folder", "rename", "error-file", "error-folder", "error-slash", "error-empty", "failure"] {
                    for width in [260, 280] {
                    let model = FileTreeModel(root: fixtures.path, readBranch: { "feature/files" })
                    await model.refresh()
                    await model.expand("docs")
                    await model.expand("docs/guides")
                    if state == "rename", let entry = model.rows.first(where: { $0.id == "docs/guides/file-tree.md" })?.entry {
                        model.beginRename(entry)
                    } else if state == "failure" {
                        model.operationFailure = FileTreeFailure(operationKey: "名前を変更できませんでした: %@", error: CocoaError(.fileWriteNoPermission))
                    } else {
                        let parent = try #require(model.rows.first { $0.id == "docs/guides" }?.entry)
                        await model.beginCreate(at: parent, folder: state == "new-folder")
                        switch state {
                        case "error-file": model.updateName("file-tree.md")
                        case "error-folder":
                            model.edit?.error = "同じ名前のフォルダがあります"
                            model.edit?.name = "guides"
                        case "error-slash": model.updateName("a/b.md")
                        case "error-empty": _ = model.submitEdit()
                        default: break
                        }
                    }
                    let frame = Frame(id: "13-ft-" + state + suffix + (width == 260 ? "-260" : ""), name: "ファイル操作", width: CGFloat(width), height: 440,
                        light: light, language: english ? "en" : "ja")
                    try await capture(FileTreeView(model: model, openPath: "docs/guides/file-tree.md", open: { _, _ in },
                                                  inputRequestsFocus: false), frame: frame, output: output,
                        prepare: { host, window in
                            if state == "new-file" || state == "new-folder" {
                                let field = try #require(descendants(host).compactMap { $0 as? NSTextField }
                                    .first { $0.accessibilityIdentifier() == "file-tree-name-input" })
                                #expect(field.stringValue.isEmpty)
                                #expect(field.placeholderAttributedString?.string == (english ? (state == "new-file" ? "File name" : "Folder name")
                                    : (state == "new-file" ? "ファイル名" : "フォルダ名")))
                            }
                            guard state == "rename" else { return }
                            let field = try #require(descendants(host).compactMap { $0 as? NSTextField }
                                .first { $0.accessibilityIdentifier() == "file-tree-name-input" })
                            window.makeFirstResponder(field)
                            let editor = try #require(field.currentEditor() as? NSTextView)
                            editor.setSelectedRange(FileTreeOperations.nameSelection(field.stringValue, folder: false))
                            #expect(editor.selectedRange().length == ("file-tree" as NSString).length)
                        })
                    }
                }
                for dirty in [false, true] {
                    let locale = Locale(identifier: english ? "en" : "ja")
                    let bundle = try localizationBundle(fixtures: output)
                    let confirmation = FileTreeTrashConfirmation(
                        entry: .init(relativePath: "docs/guides/file-tree.md", name: "file-tree.md", kind: .file),
                        root: fixtures.path, count: nil, openItems: [.init(path: "docs/guides/file-tree.md", dirty: dirty)])
                    let alert = FileTreeTrashAlert.make(confirmation, locale: locale, bundle: bundle)
                    #expect(!alert.informativeText.contains("。 "))
                    if english { #expect(alert.informativeText.contains("The open tab will be closed.")) }
                    let multiple = FileTreeTrashConfirmation(entry: confirmation.entry, root: fixtures.path, count: nil,
                        openItems: confirmation.openItems + [.init(path: "docs/guides/step-1-setup.md", dirty: false)])
                    if english { #expect(multiple.message(locale: locale, bundle: bundle).contains("Open tabs will be closed.")) }
                    alert.window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                    alert.layout()
                    alert.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                    let content = try #require(alert.window.contentView)
                    content.layoutSubtreeIfNeeded()
                    let frame = Frame(id: "13-ft-trash-" + (dirty ? "unsaved" : "light") + suffix,
                                      name: "NSAlert", width: content.bounds.width, height: content.bounds.height)
                    try saveBitmap(content, bounds: content.bounds, to: destination(frame, output))
                    alert.window.close()
                    // 標準アラートの画面外描画がOSで欠けても、実際のaccessoryの比較画像を残す。
                    try await capture(FileTreeTrashContent(confirmation: confirmation).padding(DSSpacing.m),
                        frame: Frame(id: frame.id + "-content", name: "確認の一覧", width: 320, height: dirty ? 180 : 100,
                                     light: light, language: english ? "en" : "ja"), output: output)
                }
            }
        }
    }

    @Test func commandDescriptionSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "bottom-panel" else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let worktree = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = worktree.appendingPathComponent(".build/design-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let titles = ["/skill-authoring", "/skill-creator", "/skill-creator:skill-creator", "/skills-pipeline-updater", "/skill-creator", "/skill-installer"]
        let descriptions = [
            "既存の Claude Code スキル (SKILL.md) を監査・改善・最適化する。",
            "Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, update or optimize an existing skill. End of description.",
            "Create new skills, modify and improve existing skills.",
            "ユーザーがスキルを追加したときにHTMLを更新する。",
            "Create or update a Codex skill with appropriate instructions.",
            "Install Codex skills into $CODEX_HOME/skills from a curated list.",
        ]
        let candidates = titles.indices.map { index in
            SuggestionCandidate(title: titles[index], insertionText: titles[index], subtitle: descriptions[index], kind: .slashCommand,
                skillIdentity: SkillIdentity(name: titles[index], path: "/fixture/\(index)"), origin: .skills)
        }
        let controller = ComposerSuggestionController(slashProvider: { candidates }, fileProvider: { _ in [] })
        controller.update(text: "/", cursorUTF16: 1)
        controller.select(1)
        for width in [320, 460] {
            for phase in ["start", "middle", "end"] {
                let frame = Frame(id: "command-description-\(width)-\(phase)", name: "コマンド説明", width: CGFloat(width), height: 265)
                try await capture(ComposerSuggestionPopup(controller: controller, onAccept: { _ in })
                    .padding(4), frame: frame, output: output,
                    prepare: { host, _ in
                        let views = descendants(host).compactMap { $0 as? SuggestionDescriptionScrollView }
                        let view = try #require(views.first)
                        let animation = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey) as? CAKeyframeAnimation)
                        let values = try #require(animation.values as? [NSNumber]).map { CGFloat(truncating: $0) }
                        // cacheDisplayは表示中のCA変形を採らないため、同じ移動距離の制御した位置を描画する。
                        view.stopScrolling()
                        view.textLayer.frame.origin.x = values[2] * (phase == "middle" ? 0.5 : phase == "end" ? 1 : 0)
                    })
            }
        }
    }

    @Test func attachmentSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "bottom-panel" else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let worktree = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = worktree.appendingPathComponent(".build/design-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"))
        for width in [320, 820] {
            for english in [false, true] {
                let store = ComposerAttachmentStore()
                for name in ["ui-grid.png", "ui-single.png", "ui-team.png", "ui-narrow.png"] {
                    store.addImage(data: png, mediaType: "image/png", filename: name)
                }
                store.addImage(data: png, mediaType: "image/png")
                #expect(store.attachments.count == 4)
                #expect(store.lastError == ImageAttachmentLimits.countMessage)
                let frame = Frame(id: "attachment-\(width)\(english ? "-en" : "")", name: "添付上限", width: CGFloat(width), height: 140)
                try await capture(ComposerAttachmentStrip(store: store, layout: .standard, onRemove: { _ in })
                    .padding(12), frame: frame, output: output)
                store.setError("解像度を保ったまま送信容量に収まりません。必要な部分を切り出してください")
                let qualityFrame = Frame(id: "attachment-quality-\(width)\(english ? "-en" : "")",
                    name: "解像度保持", width: CGFloat(width), height: 160)
                try await capture(ComposerAttachmentStrip(store: store, layout: .standard, onRemove: { _ in })
                    .padding(12), frame: qualityFrame, output: output)
            }
        }
    }

    private struct Frame {
        let id: String
        let name: String
        let width: CGFloat
        let height: CGFloat
        var light = false
        var state: String? = nil
        var language: String? = nil
        var stateID: String { state ?? id }
        var english: Bool { language == "en" || id == "3k" || id.hasSuffix("-en") }
    }

    private let frames: [Frame] = [
        .init(id: "1a", name: "配置1600", width: 1600, height: 1000),
        .init(id: "1b", name: "配置1000", width: 1000, height: 700),
        .init(id: "1e", name: "配置1200", width: 1200, height: 800),
        .init(id: "1c", name: "サイドバーなし", width: 1200, height: 800),
        .init(id: "1d", name: "タブ追加メニュー", width: 1200, height: 800),
        .init(id: "2a", name: "展開と選択", width: 300, height: 860),
        .init(id: "2b", name: "キーボード移動", width: 300, height: 860),
        .init(id: "2c", name: "右クリック", width: 300, height: 860),
        .init(id: "2d", name: "ルート外ホバー", width: 300, height: 860),
        .init(id: "2d-click", name: "ルート外クリック", width: 300, height: 860, state: "2d"),
        .init(id: "2e1", name: "ブランチ", width: 300, height: 100),
        .init(id: "2e2", name: "detachedHEAD", width: 300, height: 100),
        .init(id: "2e3", name: "Git管理外", width: 300, height: 100),
        .init(id: "2e4", name: "ブランチ取得失敗", width: 300, height: 100),
        .init(id: "2f", name: "5000件超", width: 300, height: 620),
        .init(id: "2g", name: "読込中", width: 300, height: 620),
        .init(id: "2h", name: "フォルダ読込エラー", width: 300, height: 620),
        .init(id: "2h-en", name: "フォルダ読込エラー英語", width: 300, height: 620, state: "2h"),
        .init(id: "2i", name: "セッション未選択", width: 300, height: 620),
        .init(id: "2i-en", name: "セッション未選択英語", width: 300, height: 620, state: "2i"),
        .init(id: "2j", name: "ルート読込エラー", width: 300, height: 620),
        .init(id: "2j-en", name: "ルート読込エラー英語", width: 300, height: 620, state: "2j"),
        .init(id: "2k", name: "重ね表示", width: 280, height: 620),
        .init(id: "3a", name: "Markdown保存済み", width: 720, height: 300),
        .init(id: "3b", name: "Markdown未保存", width: 720, height: 300),
        .init(id: "3c", name: "Markdownソース", width: 720, height: 300),
        .init(id: "3d", name: "HTML表示", width: 720, height: 300),
        .init(id: "3e", name: "Swiftソース", width: 720, height: 300),
        .init(id: "3f", name: "2000ブロック超", width: 720, height: 300),
        .init(id: "3g", name: "500KB超", width: 720, height: 300),
        .init(id: "3h", name: "ブロック確定失敗", width: 720, height: 300),
        .init(id: "3i", name: "幅480", width: 480, height: 420),
        .init(id: "3j", name: "幅320", width: 320, height: 420),
        .init(id: "3k", name: "幅320英語", width: 320, height: 420),
        .init(id: "3i400", name: "Markdown幅400", width: 400, height: 420, state: "3i"),
        .init(id: "3i560", name: "Markdown幅560", width: 560, height: 420, state: "3i"),
        .init(id: "3f-en", name: "ブロック上限英語", width: 720, height: 300, state: "3f"),
        .init(id: "3g-en", name: "サイズ上限英語", width: 720, height: 300, state: "3g"),
        .init(id: "3f-help-en", name: "ブロック上限全文英語", width: 720, height: 300, state: "3f"),
        .init(id: "3g-help-en", name: "サイズ上限全文英語", width: 720, height: 300, state: "3g"),
        .init(id: "3h-en", name: "確定失敗英語", width: 720, height: 300, state: "3h"),
        .init(id: "3h-help-en", name: "確定失敗全文英語", width: 720, height: 300, state: "3h"),
        .init(id: "3l", name: "20MB超", width: 720, height: 380),
        .init(id: "3readonly", name: "閲覧のみ", width: 720, height: 380),
        .init(id: "3readonly-truncated", name: "長い行の省略", width: 720, height: 380),
        .init(id: "3readonly-truncated-en", name: "長い行の省略英語", width: 720, height: 380, state: "3readonly-truncated"),
        .init(id: "3readonly-truncated-light", name: "長い行の省略ライト", width: 720, height: 380, light: true, state: "3readonly-truncated"),
        .init(id: "3readonly-en", name: "閲覧のみ英語", width: 720, height: 380, state: "3readonly"),
        .init(id: "3readonly320", name: "閲覧のみ最小幅", width: 320, height: 380, state: "3readonly"),
        .init(id: "3readonly-light", name: "閲覧のみライト", width: 720, height: 380, light: true, state: "3readonly"),
        .init(id: "3readonly-md", name: "Markdown閲覧のみ", width: 720, height: 380),
        .init(id: "3readonly-html", name: "HTMLソース閲覧のみ", width: 720, height: 380),
        .init(id: "3readonly-rendered", name: "HTMLレンダリング閲覧のみ", width: 720, height: 380),
        .init(id: "3readonly-fallback", name: "HTML準備失敗の閲覧のみ", width: 720, height: 380),
        .init(id: "3large", name: "色付けなし", width: 720, height: 380),
        .init(id: "3large-en", name: "色付けなし英語", width: 720, height: 380, state: "3large"),
        .init(id: "3large320", name: "色付けなし最小幅", width: 320, height: 380, state: "3large"),
        .init(id: "3large-light", name: "色付けなしライト", width: 720, height: 380, light: true, state: "3large"),
        .init(id: "changes-deleted", name: "削除ファイルの差分", width: 720, height: 500),
        .init(id: "changes-deleted-light", name: "削除ファイルの差分ライト", width: 720, height: 500, light: true, state: "changes-deleted"),
        .init(id: "changes-readonly", name: "変更パネル閲覧のみ", width: 720, height: 500),
        .init(id: "changes-oversized", name: "変更パネル20MB超", width: 720, height: 500),
        .init(id: "3m", name: "バイナリ", width: 720, height: 380),
        .init(id: "3n", name: "ルート外", width: 720, height: 380),
        .init(id: "3o", name: "UTF8以外", width: 720, height: 380),
        .init(id: "3l-en", name: "大容量英語", width: 720, height: 380, state: "3l"),
        .init(id: "3n-en", name: "ルート外英語", width: 720, height: 380, state: "3n"),
        .init(id: "4a", name: "表示とホバー", width: 760, height: 720),
        .init(id: "4b", name: "段落編集中", width: 760, height: 720),
        .init(id: "4c", name: "frontmatter編集中", width: 760, height: 720),
        .init(id: "4d", name: "長い表編集中", width: 760, height: 720),
        .init(id: "4e", name: "原文", width: 760, height: 340),
        .init(id: "4f", name: "空文書", width: 760, height: 340),
        .init(id: "4g", name: "確定失敗", width: 760, height: 420),
        .init(id: "4g-save", name: "確定失敗保存時", width: 760, height: 420, state: "4g"),
        .init(id: "4h", name: "キーボード選択", width: 760, height: 720),
        .init(id: "4i", name: "リンクホバー", width: 760, height: 720),
        .init(id: "4j", name: "面と輪", width: 560, height: 300),
        .init(id: "4k", name: "面だけ", width: 560, height: 300),
        .init(id: "4l", name: "前後を薄くする", width: 560, height: 300),
        .init(id: "4m", name: "ブロック間選択", width: 560, height: 300),
        .init(id: "5a", name: "HTML通常", width: 760, height: 540),
        .init(id: "5b", name: "遮断説明", width: 760, height: 540),
        .init(id: "5c", name: "ファイルリンク", width: 760, height: 540),
        .init(id: "5d", name: "ブラウザリンク", width: 760, height: 540),
        .init(id: "5e", name: "未保存HTML", width: 760, height: 540),
        .init(id: "5f", name: "表示プロセス終了", width: 760, height: 540),
        .init(id: "5g", name: "遮断準備失敗", width: 760, height: 540),
        .init(id: "5h", name: "HTML幅480", width: 480, height: 540),
        .init(id: "5h400", name: "HTML幅400", width: 400, height: 540, state: "5h"),
        .init(id: "5h560", name: "HTML幅560", width: 560, height: 540, state: "5h"),
        .init(id: "5b-en", name: "説明英語", width: 760, height: 540, state: "5b"),
        .init(id: "5g-en", name: "遮断準備失敗英語", width: 760, height: 540, state: "5g"),
        .init(id: "5g-help-en", name: "遮断準備失敗全文英語", width: 760, height: 540, state: "5g"),
        .init(id: "5h-en", name: "閲覧のみ英語", width: 480, height: 540, state: "5h"),
        .init(id: "5h-help-en", name: "閲覧のみ全文英語", width: 480, height: 540, state: "5h"),
        .init(id: "6a", name: "未保存2件", width: 400, height: 340),
        .init(id: "6b", name: "未保存9件", width: 400, height: 440),
        .init(id: "6c", name: "未確定ブロック", width: 400, height: 400),
        .init(id: "6d", name: "2ウィンドウ", width: 400, height: 420),
        .init(id: "6e", name: "3ウィンドウ11件", width: 400, height: 460),
        .init(id: "6c-en", name: "未確定一覧英語", width: 400, height: 400, state: "6c"),
        .init(id: "6single-en", name: "未保存1件英語", width: 400, height: 400, state: "6c"),
        .init(id: "6d-en", name: "ウィンドウ一覧英語", width: 400, height: 420, state: "6d"),
        .init(id: "7r", name: "ショートカット直後", width: 520, height: 760),
        .init(id: "7a", name: "表示中", width: 520, height: 760),
        .init(id: "7b", name: "入力送信中", width: 520, height: 760),
        .init(id: "7c", name: "タップ中", width: 520, height: 760),
        .init(id: "7c2", name: "スクロール中", width: 520, height: 760),
        .init(id: "7d", name: "端末メニュー", width: 520, height: 760),
        .init(id: "7e", name: "停止確認", width: 520, height: 760),
        .init(id: "7f", name: "停止中", width: 520, height: 760),
        .init(id: "7g", name: "起動中", width: 520, height: 760),
        .init(id: "7h", name: "表示のみ", width: 520, height: 760),
        .init(id: "7iOpen", name: "診断展開中", width: 520, height: 760, state: "7i"),
        .init(id: "7j", name: "未確認", width: 520, height: 760),
        .init(id: "7j2", name: "未確認でも試す", width: 520, height: 760),
        .init(id: "7k", name: "Xcodeなし", width: 520, height: 760),
        .init(id: "7l", name: "接続失敗", width: 520, height: 760),
        .init(id: "7m", name: "再起動必要", width: 520, height: 760),
        .init(id: "7n", name: "狭幅の帯", width: 320, height: 700),
        .init(id: "7nStopped", name: "停止中幅320", width: 320, height: 700),
        .init(id: "7TrialInput520", name: "未確認入力中幅520", width: 520, height: 760),
        .init(id: "7StaleInput520", name: "更新なし入力中幅520", width: 520, height: 760),
        .init(id: "7LongStopped320", name: "長い端末名停止中幅320", width: 320, height: 700),
        .init(id: "7LongInput320", name: "長い端末名入力中幅320", width: 320, height: 700),
        .init(id: "7LongTrialStale320", name: "長い端末名未確認更新なし入力中幅320", width: 320, height: 700),
        .init(id: "7ListingError", name: "端末一覧取得失敗", width: 520, height: 760),
        .init(id: "7o", name: "広幅の帯", width: 700, height: 760),
        .init(id: "7p", name: "ベゼルなし", width: 520, height: 640),
        .init(id: "8L1", name: "ライトツリー", width: 300, height: 560, light: true),
        .init(id: "8L2", name: "ライトMarkdown", width: 560, height: 420, light: true),
        .init(id: "8L3", name: "ライト入力送信", width: 520, height: 520, light: true),
    ]

    private var stage8Frames: [Frame] {
        [
            .init(id: "10-WS1-dark-ja", name: "worktree 起点メニュー", width: 1440, height: 1000, language: "ja"),
            .init(id: "10-WS2-light-en", name: "worktree 起点メニュー", width: 1440, height: 1000, light: true, language: "en"),
            .init(id: "10-WS3-dark-ja", name: "worktree 起点メニュー狭幅", width: 720, height: 1000, language: "ja"),
            .init(id: "10-WS4-light-en", name: "worktree 起点メニュー狭幅", width: 720, height: 1000, light: true, language: "en"),
            .init(id: "10-A1-dark-ja", name: "新規チャット A1", width: 1440, height: 900, language: "ja"),
            .init(id: "10-A2-light-ja", name: "新規チャット A2", width: 1440, height: 900, light: true, language: "ja"),
            .init(id: "10-C1-dark-ja", name: "新規チャット C1", width: 720, height: 900, language: "ja"),
            .init(id: "10-N2-dark-en", name: "新規チャット N2", width: 720, height: 900, language: "en"),
            .init(id: "10-C2-dark-en", name: "新規チャット 900pt幅", width: 900, height: 560, language: "en"),
            .init(id: "10-N3-light-en", name: "新規チャット N3", width: 1440, height: 900, light: true, language: "en"),
            .init(id: "10-M1-dark-ja", name: "ハーネス・モデルメニュー", width: 1440, height: 900, language: "ja"),
            .init(id: "10-M2-light-en", name: "ハーネス・モデルメニュー", width: 720, height: 900, light: true, language: "en"),
            .init(id: "10-R1-dark-en", name: "送信不可の理由", width: 720, height: 900, language: "en"),
            .init(id: "10-R2-light-ja", name: "送信不可の理由", width: 1440, height: 900, light: true, language: "ja"),
            .init(id: "10-F1-dark-ja", name: "送信ボタンのフォーカス", width: 720, height: 900, language: "ja"),
            .init(id: "10-F2-light-en", name: "送信ボタンのフォーカス", width: 720, height: 900, light: true, language: "en"),
            .init(id: "11-T1-dark", name: "プロジェクトタブ T1", width: 1440, height: 900, language: "ja"),
            .init(id: "11-T3-dark", name: "プロジェクトタブ T3", width: 1440, height: 900, language: "ja"),
            .init(id: "11-T5-dark", name: "プロジェクトタブ T5", width: 720, height: 900, language: "ja"),
            .init(id: "11-T7-light", name: "プロジェクトタブ T7", width: 1440, height: 900, light: true, language: "ja"),
            .init(id: "11-T12-dark", name: "プロジェクトタブ T12 サイドバーなし", width: 1440, height: 900, language: "ja"),
            .init(id: "11-T1-light-en", name: "プロジェクトタブ T1 英語ライト", width: 720, height: 900, light: true, language: "en"),
            .init(id: "11-T3-dark-en", name: "プロジェクトタブ T3 英語", width: 1440, height: 900, language: "en"),
            .init(id: "11-T8-project-delete-dark-ja", name: "プロジェクト削除確認", width: 1440, height: 900, language: "ja"),
            .init(id: "11-T8-project-delete-light-en", name: "プロジェクト削除確認", width: 720, height: 900, light: true, language: "en"),
            .init(id: "11-T9-session-delete-dark-en", name: "セッション削除確認", width: 720, height: 900, language: "en"),
            .init(id: "11-T9-session-delete-light-ja", name: "セッション削除確認", width: 1440, height: 900, light: true, language: "ja"),
            .init(id: "12-U1-dark", name: "ヘッダーと使用量 U1", width: 1440, height: 900, language: "ja"),
            .init(id: "12-U3-dark", name: "ヘッダーと使用量 U3", width: 720, height: 900, language: "ja"),
            .init(id: "12-U4-low-unavailable-dark", name: "残りわずかと未取得", width: 1440, height: 900, language: "ja"),
            .init(id: "12-U5-light", name: "ヘッダーと使用量 U5", width: 1440, height: 900, light: true, language: "ja"),
            .init(id: "12-U8-low-unavailable-light", name: "残りわずかと未取得", width: 720, height: 900, light: true, language: "ja"),
            .init(id: "12-U1-light-en", name: "ヘッダーと使用量 U1 英語", width: 720, height: 900, light: true, language: "en"),
            .init(id: "12-U4-dark-en", name: "ヘッダーと使用量 U4 英語", width: 1440, height: 900, language: "en"),
        ]
    }

    private struct Unavailable: Error { let reason: String }

    private var browserFrames: [Frame] {
        [false, true].flatMap { light in
            ["empty", "loading", "local", "error", "narrow", "entry", "find", "notfound"].map { state in
                Frame(id: "9-\(state)-\(light ? "light" : "dark")", name: "ブラウザ",
                      width: state == "narrow" ? 320 : 720, height: 420, light: light, state: "9-\(state)")
            }
        }
    }

    private var syntaxFrames: [Frame] {
        let sources = ["swift", "json", "yaml", "tsx", "css", "log", "python", "markdown", "html", "diff", "csv", "shell", "unknown",
         "block", "frontmatter", "fence", "heading-edited", "heading-synced"].flatMap { kind in
            [false, true].map { light in
                Frame(id: "syntax-\(kind)-\(light ? "light" : "dark")", name: "色付け",
                      width: 760, height: 420, light: light, state: "syntax-\(kind)")
            }
        }
        let selection = ["4j", "4m"].flatMap { (state: String) in
            [false, true].map { light in
                Frame(id: "syntax-\(state)-\(light ? "light" : "dark")", name: "編集と選択",
                      width: 560, height: 300, light: light, state: state)
            }
        }
        return sources + selection
    }

    private func syntaxSample(_ id: String) -> (path: String, source: String)? {
        switch id {
        case "syntax-swift":
            return ("Sources/Greeting.swift", "import Foundation\n\n// 名前から挨拶を作る\nstruct Greeting {\n    let name: String\n    let count = 42\n\n    func message() -> String {\n        return \"こんにちは、\\(name)\"\n    }\n}\n")
        case "syntax-json":
            return ("config/settings.json", "{\n  \"name\": \"Phlox\",\n  \"enabled\": true,\n  \"count\": 42,\n  \"missing\": null,\n  \"agents\": [\"Claude\", \"Codex\"]\n}\n")
        case "syntax-yaml":
            return ("config/settings.yaml", "# true と false はコメントのまま\nuser-name: Phlox\nenabled: true\ncount: 42\ndescription: it's fine\nquoted: 'true isn''t false'\nmessage: |\n  true と false も本文。\nname: \"閉じ忘れの文字列 true\n")
        case "syntax-tsx":
            return ("Sources/Greeting.tsx", "import { useState } from 'react';\n// const と return はコメントのまま\nconst [count, setCount] = useState<number>(0);\nconst title = `return \\` if`;\nconst view = <Box title=\"const return\">\n  {count < 10 ? 'return' : 'const'}\n</Box>;\nconst unfinished = \"閉じ忘れの文字列 return\n")
        case "syntax-css":
            return ("styles/main.css", "/* color と return はコメントのまま */\n.box {\n  background: url(https://example.com/image.png);\n  color: #333;\n  margin: 12px;\n  content: \"color return\";\n}\n.note { content: \"閉じ忘れの文字列 color\n")
        case "syntax-log":
            return ("logs/session.log", "2026-10-04 12:00:00 INFO session started\nWARN can't connect\nERROR \"INFO return true\" 42\nTRACE if return は本文\nDEBUG \"閉じ忘れの文字列 ERROR\n")
        case "syntax-python":
            return ("scripts/greeting.py", "# def と return はコメントのまま\ndef greeting(name):\n    title = \"return if\"\n    text = '''def と return\n複数行文字列'''\n    if name is None:\n        return False\n    return title\nunfinished = \"閉じ忘れの文字列 return\n")
        case "syntax-markdown", "syntax-block":
            return ("README.md", "# Phlox\n\n**並べて走らせる**。`swift test` で確かめる。\n\n- セッションを開く\n- [設計書](docs/specs/overview.md) を読む\n\n> 判断だけを前に出す。\n")
        case "syntax-heading-edited":
            return ("README.md", "# 日本語の見出し\n\n本文です\n")
        case "syntax-heading-synced":
            return ("README.md", "# Title\n本文です\n")
        case "syntax-html":
            return ("docs/index.html", "<!doctype html>\n<html lang=\"ja\">\n<head>\n  <style>body { color: #333; margin: 12px; }</style>\n</head>\n<body>\n  <!-- 挨拶 -->\n  <h1 class=\"title\">Phlox</h1>\n  <script>const count = 42; console.log(\"hello\");</script>\n</body>\n</html>\n")
        case "syntax-diff":
            return ("changes.diff", "diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1,3 +1,3 @@\n # Phlox\n-古い説明\n+新しい説明\n そのままの行\n")
        case "syntax-csv":
            return ("data/agents.csv", "name,status,count\nClaude,active,42\nCodex,waiting,12\n\"Cursor, Agent\",\"hello \"\"world\"\"\",3\n\"複数行の\n名前\",ready,8\n")
        case "syntax-shell":
            return ("scripts/check.sh", "#!/bin/bash\n# パッケージを検証する\nROOT=\"${HOME}/Projects\"\nif [ -d \"$ROOT\" ]; then\n  printf '%s\\n' \"検証開始\"\n  swift test --package-path \"$ROOT/Phlox\"\nfi\n")
        case "syntax-unknown":
            return ("notes.custom", "# 種類の分からない文書\nlet count = 42\n\"色付けせず、そのまま表示する\"\n")
        case "syntax-frontmatter":
            return ("README.md", "---\ntitle: Phlox\nenabled: true\ncount: 42\n---\n\n# Phlox\n\n本文。\n")
        case "syntax-fence":
            return ("README.md", "# Phlox\n\n```swift\n// 挨拶\nlet name = \"Phlox\"\nprint(name)\n```\n\n本文。\n")
        default: return nil
        }
    }

    @Test func 英語の未保存件数は単数と複数を切り替える() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = package.appendingPathComponent(".build/localization-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: fixtures) }
            catch { Issue.record("翻訳検証用データを削除できません: \(error)") }
        }
        let bundle = try localizationBundle(fixtures: fixtures)
        let locale = Locale(identifier: "en")
        let key = "未保存のファイル %lld 件"
        let format = AppLocalizedString.string(key, locale: locale, bundle: bundle)
        #expect(String(format: format, Int64(1)) == "1 unsaved file")
        #expect(String(format: format, Int64(2)) == "2 unsaved files")
        #expect(AppLocalizedString.string(key, locale: Locale(identifier: "ja"), bundle: bundle) == key)
        let alert = FileTabDocumentRegistry.alert(windows: [.init(name: "Phlox", files: [
            .init(name: "README.md", context: "", editingBlock: false),
        ])], terminating: false, locale: locale, bundle: bundle)
        #expect(alert.messageText.contains("1 unsaved file?"))
        let file = UnsavedFile(name: "README.md", context: "", editingBlock: false)
        let omitted = UnsavedChangesContent(windows: [
            .init(name: "一つ目", files: Array(repeating: file, count: 5)),
            .init(name: "二つ目", files: [file]),
        ], locale: locale)
        #expect(omitted.omitted(bundle: bundle) == "1 more file (1 window)")
    }

    @Test func 比較用画像を書き出す() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "bottom-panel" else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let worktree = package.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_OUTPUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? worktree.appendingPathComponent(".build/design-snapshots", isDirectory: true)
        let fixtures = output.appendingPathComponent("fixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) {
            try FileManager.default.removeItem(at: cachedStrings)
        }
        defer {
            do { try FileManager.default.removeItem(at: fixtures) }
            catch { Issue.record("撮影用データを削除できません: \(error)") }
        }
        var rows = ["| 状態 id | 結果 | 補足 |", "|---|---|---|"]
        var written = 0
        var failures: [String] = []
        let scope = ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] ?? "all"
        try #require(["all", "files", "simulator", "syntax", "large-files", "browser", "worktree-start", "setting-cards"].contains(scope), "撮影範囲は all・files・simulator・syntax・large-files・browser・worktree-start・setting-cards のいずれか")
        let selectedFrames = (frames + syntaxFrames + browserFrames + stage8Frames).filter { frame in
            if scope == "setting-cards" { return frame.id.hasPrefix("10-M") }
            if scope == "worktree-start" { return frame.id.hasPrefix("10-WS") }
            if scope == "browser" { return frame.id.hasPrefix("9-") }
            if scope == "large-files" { return ["3l", "3large", "changes-deleted", "changes-readonly", "changes-oversized"].contains(frame.stateID) || frame.stateID.hasPrefix("3readonly") }
            if scope == "syntax" { return frame.id.hasPrefix("syntax-") }
            let simulator = frame.id.hasPrefix("7") || frame.id == "8L3"
            return scope == "all" || (scope == "simulator" ? simulator : !simulator)
        }
        for frame in selectedFrames {
            do {
                let existing = destination(frame, output)
                if FileManager.default.fileExists(atPath: existing.path) { try FileManager.default.removeItem(at: existing) }
                let note = try await render(frame, fixtures: fixtures, output: output)
                written += 1
                rows.append("| \(frame.id) | 書き出した | \(note) |")
            } catch let error as Unavailable {
                rows.append("| \(frame.id) | 書き出せない | \(error.reason) |")
            } catch {
                failures.append("\(frame.id): \(error)")
                rows.append("| \(frame.id) | 書き出せない | 描画失敗: \(error) |")
            }
        }
        let report = "# 画面外描画の結果\n\n生成 PNG: \(written) 枚。倍率 2。色・言語は状態 ID に記載。\n\n"
            + rows.joined(separator: "\n") + "\n"
        try Data(report.utf8).write(to: output.appendingPathComponent("結果.md"), options: .atomic)
        print(report)
        #expect(failures.isEmpty, "予期しない描画失敗: \(failures.joined(separator: "; "))")
        #expect(written > 0)
        #expect(written == selectedFrames.filter { !["4k", "4l"].contains($0.stateID) }.count)
    }

    private func render(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        // ThemeStore は環境の colorScheme ではなく標準設定を読む。永続設定には書き込まない。
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var themeArguments = arguments
        themeArguments[ThemeStore.themeKey] = frame.light ? AppTheme.phloxLight.id : AppTheme.phlox.id
        defaults.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: frame.light ? .aqua : .darkAqua)
        defer {
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
        }
        let id = frame.stateID
        if id.hasPrefix("9-") {
            let root = fixtures.appendingPathComponent(frame.id, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("slides.html")
            try Data("<!doctype html><html><head><meta charset='utf-8'><title>ローカルのスライド</title></head><body style='margin:0;padding:32px;font:16px -apple-system;background:white;color:#222'><h1 style='font-size:28px;margin:0 0 16px'>Phlox のブラウザ</h1><p id='result'>実行前</p><script>document.querySelector('#result').textContent='JavaScript が実行されました';</script></body></html>".utf8).write(to: file)
            if id == "9-entry" {
                let document = FileTabDocument(path: "slides.html", root: root.path)
                await document.loadIfNeeded()
                let preview = HTMLPreviewModel(document: document)
                await preview.prepare()
                try await capture(FileTabView(document: document, lastWriter: { _ in nil }, isFocused: false,
                                               openFile: { _, _ in }, openBrowser: { _ in }, htmlPreview: preview), frame: frame, output: output)
                return "HTML の帯のブラウザ入口。プレビューの JavaScript は無効"
            }
            let model = BrowserTabModel()
            defer { model.close() }
            if ["9-local", "9-narrow", "9-find", "9-notfound"].contains(id) { model.open(file) }
            let router = AppRouter()
            let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
            defer { continuation.finish() }
            let node = SessionNode.pty(SessionViewModel(id: SessionID(), ptyManager: MockPTYManager(),
                hookEvents: events, terminalCoordinator: TerminalCoordinator(),
                spawnRequest: .init(command: "/bin/sh", args: [], env: [:], workingDirectory: root.path,
                                    kind: .claudeCode, statusBootstrap: .viaHook)))
            var layout = ProjectTabLayout()
            layout.open(.browser)
            let content = VStack(spacing: 0) {
                ChildTabBar(router: router, viewModel: DashboardViewModel(environment: makeTestEnvironment(pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() })), project: Project(name: node.workspaceName, directoryPath: node.rawWorkspacePath, createdAt: Date(), isManagedDirectory: false), layout: layout, chats: [.chat(node.id)], changeCount: 0, files: FileTabDocuments())
                Rectangle().fill(DSColor.separator).frame(height: 1)
                BrowserTabView(model: model, tellAgent: { _ in })
            }
            try await capture(content, frame: frame, output: output, afterMount: {
                if id == "9-loading" {
                    model.url = URL(fileURLWithPath: "/Users/ryosuke/Downloads/slides.html")
                    model.isLoading = true
                } else if id == "9-find" {
                    model.zoom(by: 2)
                    model.showsFind = true
                } else if id == "9-notfound" {
                    model.showsFind = true
                    model.findNotFound = true
                } else if id == "9-error" {
                    model.url = URL(fileURLWithPath: "/Users/ryosuke/Downloads/slides.html")
                    model.error = "ページの表示が停止しました。再読込してください。"
                }
            })
            return id == "9-loading" ? "帯の読み込み状態を固定した描画用状態" : "ブラウザの画面外描画"
        }
        if id.hasPrefix("changes-") {
            let root = fixtures.appendingPathComponent(frame.id)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("gone.swift")
            try Data("let value = 42\nlet title = \"Phlox\" // 削除したファイル\n".utf8).write(to: file)
            for arguments in [["init", "-q"], ["add", "gone.swift"], ["commit", "-q", "-m", "撮影の初期状態"]] {
                let git = Process()
                git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                git.currentDirectoryURL = root
                git.arguments = ["-c", "user.name=phlox-test", "-c", "user.email=test@phlox.local",
                                 "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + arguments
                try git.run()
                git.waitUntilExit()
                try #require(git.terminationStatus == 0)
            }
            if id == "changes-deleted" {
                try FileManager.default.removeItem(at: file)
            } else {
                let size = id == "changes-readonly" ? 5_000_001 : 20_000_001
                let unit = "let value = 42 // 大きい変更ファイル\n"
                try Data(String(repeating: unit, count: size / unit.utf8.count + 1).utf8).write(to: file)
            }
            let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
            await model.refresh()
            await model.select("gone.swift")
            #expect(model.syntaxHighlightingEnabled)
            if id != "changes-deleted" {
                #expect(!model.canEdit)
                #expect(model.canViewContent == (id == "changes-readonly"))
            }
            try await capture(EditorPanelView(viewModel: model, projectName: "phlox-oss", workingDirectory: root.path),
                              frame: frame, output: output)
            return id == "changes-deleted" ? "削除した小さいSwiftファイル。実gitから読み込んだ差分の字句色・削除色を描画"
                : "実gitの差分。編集上限／閲覧上限の案内とファイルタブ入口を描画"
        }
        if id.hasPrefix("10-") { return try await renderStage8NewChat(frame, fixtures: fixtures, output: output) }
        if id.hasPrefix("11-") { return try await renderStage8ProjectTabs(frame, fixtures: fixtures, output: output) }
        if id.hasPrefix("12-") { return try await renderStage8Usage(frame, fixtures: fixtures, output: output) }
        if id == "1d" { return try await renderTabChooser(frame, fixtures: fixtures, output: output) }
        if id.hasPrefix("1") { return try await renderDashboard(frame, fixtures: fixtures, output: output) }
        if id.hasPrefix("6") {
            return try await renderUnsaved(frame, fixtures: fixtures, output: output)
        }
        let reasons = [
            "4k": "未採用の比較案で切替実装がない",
            "4l": "未採用の比較案で切替実装がない",
        ]
        if let reason = reasons[id] { throw Unavailable(reason: reason) }
        if id.hasPrefix("2") || id == "8L1" {
            return try await renderTree(frame, fixtures: fixtures, output: output)
        }
        if id.hasPrefix("7") || id == "8L3" {
            return try await renderSimulator(frame, output: output)
        }
        let sessionID = SessionID()
        let files = FileTabDocuments()
        let projectID = ProjectID()
        let document = try await makeDocument(frame, fixtures: fixtures, files: files, projectID: projectID)
        defer { document.invalidate() }
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let node = SessionNode.pty(SessionViewModel(id: sessionID, ptyManager: MockPTYManager(),
            hookEvents: events, terminalCoordinator: TerminalCoordinator(),
            spawnRequest: .init(command: "/bin/sh", args: [], env: [:], workingDirectory: document.root,
                                kind: .claudeCode, statusBootstrap: .viaHook)))
        var layout = ProjectTabLayout()
        layout.open(.terminal(TerminalTabID()))
        layout.open(.file(document.path))
        let preview = HTMLPreviewModel(document: document)
        if document.isHTML {
            if id == "5g" || id == "3readonly-fallback" { preview.stopWithPreparationError("遮断ルールを準備できませんでした") }
            else { await preview.prepare() }
            if id == "5f" { preview.didTerminate() }
            if id == "5c" { await preview.hover(WorktreeURL.url(for: "docs/guides/file-tree.md")) }
            if id == "5d" { await preview.hover(URL(string: "https://github.com/phlox-oss/phlox")) }
        }
        let strings = try localizationBundle(fixtures: fixtures)
        let fileView = FileTabView(document: document, lastWriter: { _ in nil }, isFocused: false, openFile: { _, _ in },
                               htmlPreview: preview,
                               showsIsolationExplanation: id == "5b", emphasizesMarkdownReason: frame.id == "4g-save")
        let body = fileView
            .environment(\.localizationBundle, strings)
            .environment(\.locale, Locale(identifier: frame.english ? "en" : "ja"))
        if frame.id.contains("-help-") {
            let help = id == "5h" ? fileView.presentationHelp(.rendered, bundle: strings) : id == "5g" ? fileView.htmlPreparationHelp(bundle: strings)
                : Text(verbatim: fileView.markdownReasonDetail(locale: Locale(identifier: "en"), bundle: strings))
            try await capture(body, frame: frame, output: output,
                              foreground: AnyView(help.font(DSFont.meta).padding(10).frame(width: min(380, frame.width - 20))
                                .background(DSColor.popoverBackground)
                                .environment(\.locale, Locale(identifier: "en"))),
                              foregroundOrigin: CGPoint(x: 10, y: frame.height - 140))
        } else if id.hasPrefix("4"), ["4a", "4f", "4h", "4i", "4m", "4j"].contains(id) {
            let blocks = document.markdownBlocks
            let hovered = blocks.first { $0.original.hasPrefix("- ") }?.id
            let selected = blocks.first { $0.original.hasPrefix("|") }?.id
            let linked = WorktreeURL.url(for: "docs/architecture/overview.md")!
            let destination = FileLinkDestination(url: linked, decision: .openFile("docs/architecture/overview.md"))
            try await capture(VStack(spacing: 0) {
                if id != "4j" { ChildTabBar(router: AppRouter(), viewModel: DashboardViewModel(environment: makeTestEnvironment(pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() })), project: Project(id: projectID, name: node.workspaceName, directoryPath: node.rawWorkspacePath, createdAt: Date(), isManagedDirectory: false), layout: layout, chats: [.chat(node.id)], changeCount: 0, files: files) }
                FileTabView(document: document, lastWriter: { _ in nil }, isFocused: false, openFile: { _, _ in }, markdownEditor:
                    MarkdownBlockEditor(document: document, openURL: { _ in .discarded }, linkDestination: { _ in destination },
                                    hoveredBlock: id == "4a" ? hovered : id == "4f" ? blocks.first?.id : nil, focusedBlock: id == "4h" ? selected : nil,
                                    hoveredLink: id == "4i" ? URL(string: "docs/architecture/overview.md") : nil, hoveredDestination: id == "4i" ? destination : nil,
                                    selectionCrossesBlock: id == "4m"))
            }, frame: frame, output: output, selectsParagraph: id == "4m")
        } else if id == "5b" {
            let explanation = FileTabView(document: document, lastWriter: { _ in nil }, isFocused: false, openFile: { _, _ in }).isolationExplanation(bundle: strings)
            try await capture(body, frame: frame, output: output,
                              foreground: AnyView(explanation.environment(\.locale, Locale(identifier: frame.english ? "en" : "ja"))), foregroundOrigin: CGPoint(x: frame.width - 440, y: frame.height - 210))
        } else if id == "5c" || id == "5d" {
            let url = id == "5c" ? WorktreeURL.url(for: "docs/guides/file-tree.md")! : URL(string: "https://github.com/phlox-oss/phlox")!
            let decision: HTMLNavigationPolicy.Decision = id == "5c" ? .openFile("docs/guides/file-tree.md") : .openBrowser(url)
            try await capture(body, frame: frame, output: output,
                              foreground: AnyView(FileLinkDestinationView(destination: .init(url: url, decision: decision)).padding(DSSpacing.l)),
                              foregroundOrigin: CGPoint(x: DSSpacing.s - DSSpacing.l, y: DSSpacing.s - DSSpacing.l))
        } else {
            try await capture(VStack(spacing: 0) {
                if id != "8L2" {
                    ChildTabBar(router: AppRouter(), viewModel: DashboardViewModel(environment: makeTestEnvironment(pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() })), project: Project(id: projectID, name: node.workspaceName, directoryPath: node.rawWorkspacePath, createdAt: Date(), isManagedDirectory: false), layout: layout, chats: [.chat(node.id)], changeCount: 0,
                                files: files)
                }
                body
            }, frame: frame, output: output, prepare: { host, _ in
                if id == "3readonly-truncated" {
                    let view = try #require(descendants(host).compactMap { $0 as? CurrentLineTextView }.first)
                    let marker = (view.string as NSString).range(of: "…")
                    try #require(marker.location != NSNotFound)
                    view.scrollRangeToVisible(marker)
                    return
                }
                guard ["syntax-heading-edited", "syntax-heading-synced"].contains(id) else { return }
                let view = try #require(descendants(host).compactMap { $0 as? CurrentLineTextView }.first)
                let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
                view.layoutManager?.ensureLayout(for: view.textContainer!)
                var complete = false
                coordinator.highlights.onHighlightComplete = { _ in complete = true }
                if id == "syntax-heading-edited" {
                    view.insertText("", replacementRange: NSRange(location: 0, length: 2))
                } else {
                    document.draft = "# Title\n本文です。\n"
                    #expect(CodeTextEditor.synchronizeText(document.draft, with: view,
                                                          beforeReplacement: { coordinator.highlights.invalidate() }))
                    coordinator.updateHighlights(view, path: document.path)
                }
                try await waitUntil(deadline: ContinuousClock.now + .seconds(10)) { complete }
            })
        }
        return frame.id.contains("-help-") ? "実際のhelp本文を描画。標準ツールチップの外枠とホバー操作は対象外"
            : "実物の部品。ホバー・選択・障害状態は既存モデルとビューの初期状態で再現"
    }

    private let markdown = """
    ---
    title: Phlox
    status: draft
    ---

    # Phlox

    Phlox は Claude Code・Codex・Cursor のセッションを並べて走らせ、
    承認待ちと質問だけを前に出す macOS アプリです。詳しくは[設計書][design]を参照してください。

    ## 必要なもの

    - macOS 14 以降
    - Xcode と Claude Code・Codex・Cursor

    ```sh
    cd macos
    swift test
    ```

    | 機能 | 説明 |
    | --- | --- |
    | ファイルツリー | 作業ディレクトリのファイル |
    | Markdown | ブロックごとに編集 |

    [design]: docs/architecture/overview.md
    """

    func localizationBundle(fixtures: URL) throws -> Bundle {
        let url = fixtures.appendingPathComponent("FileLocalization.bundle")
        if !FileManager.default.fileExists(atPath: url.path) {
            let resources = url.appendingPathComponent("en.lproj")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let macos = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: macos.appendingPathComponent("App/Localizable.xcstrings"))) as? [String: Any])
            let strings = try #require(catalog["strings"] as? [String: [String: Any]])
            var english: [String: String] = [:]
            var plurals: [String: [String: Any]] = [:]
            for (key, entry) in strings {
                if let locales = entry["localizations"] as? [String: [String: Any]],
                   let unit = locales["en"]?["stringUnit"] as? [String: String], let value = unit["value"] {
                    english[key] = value
                }
                if let locales = entry["localizations"] as? [String: [String: Any]],
                   let variations = locales["en"]?["variations"] as? [String: Any],
                   let plural = variations["plural"] as? [String: [String: Any]] {
                    var count: [String: Any] = ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                                               "NSStringFormatValueTypeKey": "lld"]
                    for (category, value) in plural {
                        if let unit = value["stringUnit"] as? [String: String] { count[category] = unit["value"] }
                    }
                    plurals[key] = ["NSStringLocalizedFormatKey": "%#@count@", "count": count]
                }
            }
            let data = try PropertyListSerialization.data(fromPropertyList: english, format: .xml, options: 0)
            try data.write(to: resources.appendingPathComponent("Localizable.strings"))
            try PropertyListSerialization.data(fromPropertyList: plurals, format: .xml, options: 0)
                .write(to: resources.appendingPathComponent("Localizable.stringsdict"))
            let japanese = url.appendingPathComponent("ja.lproj")
            try FileManager.default.createDirectory(at: japanese, withIntermediateDirectories: true)
            let japaneseStrings = Dictionary(uniqueKeysWithValues: strings.map { key, entry in
                let locales = entry["localizations"] as? [String: [String: Any]]
                let value = (locales?["ja"]?["stringUnit"] as? [String: String])?["value"]
                return (key, value ?? key)
            })
            try PropertyListSerialization.data(fromPropertyList: japaneseStrings, format: .xml, options: 0)
                .write(to: japanese.appendingPathComponent("Localizable.strings"))
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "cc.phlox.file-design-localization", "CFBundleDevelopmentRegion": "ja"], format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Info.plist"))
        }
        return try #require(Bundle(url: url))
    }

    private func renderTabChooser(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        try await capture(NewTabChooser(router: AppRouter(), project: Project(name: "タブ検証", directoryPath: "/tmp", createdAt: Date(), isManagedDirectory: false), simulatorHub: nil),
                          frame: .init(id: frame.id, name: frame.name, width: 320, height: 240), output: output)
        return "実物のタブ追加メニュー。ポップオーバーの外枠は対象外"
    }

    private func renderUnsaved(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let id = frame.stateID
        let count = frame.id == "6single-en" ? 1 : id == "6b" ? 9 : id == "6e" ? 11 : id == "6d" ? 3 : 2
        let files = (0..<count).map { index in
            UnsavedFile(name: index < 2 ? "README.md" : "file-\(index).md",
                        context: UnsavedFileContext(project: "phlox-oss", session: "アザミ")
                            .description(folder: index == 0 ? "docs/guides" : "examples", includeProject: id != "6d" && id != "6e"),
                        editingBlock: ["6c", "6d"].contains(id) && index == 0)
        }
        let windows: [UnsavedWindow]
        if id == "6d" {
            windows = [.init(name: "phlox-oss", files: Array(files.prefix(2))), .init(name: "notes", files: Array(files.dropFirst(2)))]
        } else if id == "6e" {
            windows = [.init(name: "phlox-oss", files: Array(files.prefix(4))), .init(name: "notes", files: Array(files.dropFirst(4).prefix(4))),
                       .init(name: "tools", files: Array(files.dropFirst(8)))]
        } else { windows = [.init(name: "phlox-oss", files: files)] }
        let locale = Locale(identifier: frame.english ? "en" : "ja")
        let strings = try localizationBundle(fixtures: fixtures)
        let alert = FileTabDocumentRegistry.alert(windows: windows, terminating: id == "6d" || id == "6e", locale: locale, bundle: strings)
        #expect(alert.buttons.first?.keyEquivalent == "\r")
        try await capture(UnsavedChangesContent(windows: windows, locale: locale).padding(10), frame: frame, output: output)
        return "実物の一覧と保存案内。NSAlert全体の非表示描画は欠けるため、題・警告・キー・標準破棄設定はテストで確認"
    }

    private struct Stage8Scene {
        let dashboard: DashboardViewModel
        let router: AppRouter
        let project: Project
        let draftStore: NewChatDraftStore
        let draft: NewChatDraft
        let usageMonitor: UsageMonitor
        let sessionIDs: [SessionID]
    }

    private func makeStage8Scene(_ frame: Frame, fixtures: URL, sessionCount: Int = 0) async throws -> Stage8Scene {
        let root = fixtures.appendingPathComponent(frame.id, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var projects = [Project]()
        for (index, name) in ["Aster", "Cedar"].enumerated() {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("# \(name)\n".utf8).write(to: directory.appendingPathComponent("README.md"))
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-C", directory.path, "init", "-q", "--initial-branch=main"]
            try git.run()
            git.waitUntilExit()
            try #require(git.terminationStatus == 0, "撮影用 Git リポジトリを作れません: \(directory.path)")
            projects.append(Project(name: name, directoryPath: directory.path,
                                    createdAt: Date(timeIntervalSince1970: 1_000 + Double(index)),
                                    isManagedDirectory: false))
        }
        let project = try #require(projects.first)
        let projectStore = InMemoryProjectStore()
        try await projectStore.save(projects)
        let sessionIDs = (0..<sessionCount).map { _ in SessionID() }
        let descriptors = sessionIDs.enumerated().map { index, id in
            PersistedSessionDescriptor(
                id: id,
                kind: .claudeCode,
                workingDirectory: project.directoryPath,
                name: ["README の英語版を、今の仕様に合わせて更新してください。", "PaneTree 正規化の修正", "承認ダイアログの文言を統一"][index % 3],
                projectID: project.id,
                startedAt: Date().addingTimeInterval(index == 2 ? -2 * 60 * 60 : -10 * 60),
                command: "/usr/bin/false",
                args: [],
                env: [:],
                backend: .appServer,
                chatNativeSessionId: "snapshot-session-\(index)",
                token: "snapshot-token-\(index)"
            )
        }
        let sessions = InMemorySessionStore(descriptors)
        let snapshotClients = Stage8SnapshotClients()
        let agentBinaryPaths: [AgentKind: String]
        if frame.id == "10-M1-dark-ja" {
            agentBinaryPaths = [.claudeCode: "/bin/true", .codex: "/bin/true", .cursor: "/bin/true"]
        } else if frame.id == "10-M2-light-en" {
            agentBinaryPaths = [.claudeCode: "/bin/true", .codex: "/bin/true"]
        } else if frame.id.contains("-R") {
            agentBinaryPaths = [:]
        } else {
            agentBinaryPaths = [.codex: "/bin/true"]
        }
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: AsyncStream { $0.finish() },
            projects: projectStore,
            sessions: sessions,
            workspaceDirectory: root,
            agentBinaryPaths: agentBinaryPaths,
            appServerClientFactory: { _, _, _, _, _ in snapshotClients.make() }
        ))
        await dashboard.start()
        if sessionCount >= 3 {
            for node in dashboard.sessionNodes {
                if case .appServer(let session) = node { session.userNotificationGate = { _ in false } }
            }
            snapshotClients.client(at: 0)?.yield(.turnStarted)
            if case .appServer(let session) = dashboard.sessionNodes[1] {
                session.enterAwaitingApproval(prompt: "snapshot approval")
            }
            for _ in 0..<5 { await Task.yield() }
        }

        let defaults = UserDefaults(suiteName: "phlox.design-snapshot.\(UUID().uuidString)")!
        let draftStore = NewChatDraftStore(lastUsedChatSettingsStore: LastUsedChatSettingsStore(defaults: defaults))
        let draft = draftStore.draft
        draft.selectHarness(.builtin(.codex))
        draft.settings = CodexAppServerSessionSettings(
            selectedModel: AgentModelCatalog.defaultModel(for: .codex),
            selectedEffort: "high",
            selectedPermissionProfile: ":danger-full-access"
        )
        let router = AppRouter(viewMode: .single, sidebarVisible: frame.id != "11-T12-dark")
        router.selectedProjectID = project.id

        let lowRemaining = frame.id.contains("U4") || frame.id.contains("U8")
        let now = Date()
        let fiveHour = frame.english ? "5h" : "5時間"
        let weekly = frame.english ? "Weekly" : "週次"
        let claude = CLIUsage(kind: .claudeCode, state: .ok([
            UsageBucket(id: "5h", label: fiveHour, usedPercent: lowRemaining ? 88 : 28,
                        resetsAt: now.addingTimeInterval(lowRemaining ? 38 * 60 : 2 * 60 * 60)),
            UsageBucket(id: "weekly", label: weekly, usedPercent: 60,
                        resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60)),
        ]), updatedAt: now)
        let codex: CLIUsage = lowRemaining
            ? CLIUsage(kind: .codex, state: .unavailable(reason: "fixture unavailable"), updatedAt: now)
            : CLIUsage(kind: .codex, state: .ok([
                UsageBucket(id: "5h", label: fiveHour, usedPercent: 1, resetsAt: now.addingTimeInterval(4 * 60 * 60)),
                UsageBucket(id: "weekly", label: weekly, usedPercent: 15, resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60)),
            ]), updatedAt: now)
        let cursor: CLIUsage = lowRemaining
            ? CLIUsage(kind: .cursor, state: .unavailable(reason: "fixture unavailable"), updatedAt: now)
            : CLIUsage(kind: .cursor, state: .ok([
                UsageBucket(id: "auto", label: "Auto", usedPercent: 20),
                UsageBucket(id: "api", label: "API", usedPercent: 5),
            ]), updatedAt: now)
        let usageMonitor = UsageMonitor(providers: [
            .claudeCode: DesignSnapshotUsageProvider(kind: .claudeCode, usage: claude),
            .codex: DesignSnapshotUsageProvider(kind: .codex, usage: codex),
            .cursor: DesignSnapshotUsageProvider(kind: .cursor, usage: cursor),
        ])
        await usageMonitor.refresh()
        return Stage8Scene(dashboard: dashboard, router: router, project: project,
                           draftStore: draftStore, draft: draft, usageMonitor: usageMonitor, sessionIDs: sessionIDs)
    }

    private func dashboard(
        _ scene: Stage8Scene,
        initialSidebarWidth: CGFloat? = nil,
        initiallyExpandedProjectIDs: Set<ProjectID> = []
    ) -> DashboardView {
        DashboardView(viewModel: scene.dashboard, router: scene.router, usageMonitor: scene.usageMonitor,
                      newChatDraftStore: scene.draftStore,
                      initialSidebarWidth: initialSidebarWidth,
                      initiallyExpandedProjectIDs: initiallyExpandedProjectIDs)
    }

    private func renderStage8NewChat(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let scene = try await makeStage8Scene(frame, fixtures: fixtures)
        let isUnavailable = frame.id.contains("-R")
        let isFocusedSend = frame.id.contains("-F")
        let hasOpenMenu = frame.id.contains("-M")
        let hasStartPointMenu = frame.id.contains("-WS")
        if hasStartPointMenu {
            scene.draft.usesWorktree = true
            scene.draft.selectWorktreeStartPoint(.localBranch("feature/chat"), projectID: scene.project.id, directory: nil)
        }
        if frame.id == "10-C2-dark-en" {
            scene.draft.selectHarness(.builtin(.claudeCode))
            scene.draft.settings = CodexAppServerSessionSettings(
                selectedModel: "sonnet",
                selectedEffort: "high",
                selectedPermissionProfile: "bypassPermissions"
            )
        }
        if isUnavailable {
            scene.draft.selectHarness(.builtin(.codex))
            scene.draft.text = "まず現状を確認してください"
        } else if isFocusedSend {
            scene.draft.text = "この変更を要約してください"
        }
        scene.router.showNewChat(projectID: scene.project.id)
        let sidebarWidth = frame.width <= 720 ? DSLayout.sidebarWidth.min : nil
        let content = dashboard(scene, initialSidebarWidth: sidebarWidth)
            .environment(\.newChatSendButtonInitiallyFocused, isFocusedSend)
            .environment(\.newChatSendValidationInitiallyShown, isUnavailable)
            .environment(\.newChatModelMenuInitiallyOpen, hasOpenMenu)
            .environment(\.worktreeStartPointSnapshotItems, hasStartPointMenu ? [
                .init(point: .head),
                .init(point: .localBranch("main")),
                .init(point: .localBranch("feature/chat")),
                .init(point: .remoteBranch("origin/main")),
                .init(point: .tag("v1.10.0")),
                .init(point: .commit("9f3c2e1234567890"), summary: "Improve new chat workflow"),
            ] : nil)
        do {
            try await capture(content, frame: frame, output: output)
        } catch {
            for session in scene.dashboard.sessions { await session.kill() }
            throw error
        }
        for session in scene.dashboard.sessions { await session.kill() }
        return isUnavailable ? "実際の新規チャット。Codex 未検出の送信不可理由を表示"
            : hasStartPointMenu ? "新規チャットの起点ポップオーバー。区分と選択状態を画面外で描画"
            : hasOpenMenu ? "実際のモデル選択メニューをボタン位置に重ねて描画"
            : isFocusedSend ? "実際の新規チャットで送信ボタンへキーボードフォーカスを設定"
            : "実際のダッシュボードで下段の新規チャットタブを選択"
    }

    private func renderStage8ProjectTabs(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let isDialog = frame.id.contains("-delete-")
        let scene = try await makeStage8Scene(frame, fixtures: fixtures, sessionCount: isDialog ? 2 : 3)
        if isDialog {
            scene.router.showNewChat(projectID: scene.project.id)
            let locale = Locale(identifier: frame.english ? "en" : "ja")
            let bundle = try localizationBundle(fixtures: output)
            func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
            let dialog: AnyView
            if frame.id.contains("project-delete") {
                let title = String(format: localized("プロジェクト「%@」を削除しますか?"), scene.project.name)
                let message = String(format: localized("このプロジェクトのセッション %lld 件を停止し、一覧から外します。会話は元に戻せません。"), 2)
                let note = String(format: localized("フォルダ「%@」とその中のファイルは削除されません。"), "~/Projects/Aster")
                dialog = AnyView(DSDialog(.irreversible, title: title, message: message, note: note,
                    buttons: [DSDialogButton("削除", role: .destructive) {}, DSDialogButton("キャンセル", role: .primary) {}],
                    onCancel: {}).padding(10))
            } else {
                let title = String(format: localized("「%@」と子セッション %lld 件を削除しますか?"), "調査を続ける", 2)
                let rows = [
                    DSDialogList.Row(id: 0, title: "設計を確認する", meta: localized("実行中")),
                    DSDialogList.Row(id: 1, title: "修正内容をまとめる", meta: localized("実行中")),
                ]
                dialog = AnyView(DSDialog(.irreversible, title: title,
                    message: localized("実行中のエージェントは停止します。会話とターミナルの内容は元に戻せません。"),
                    note: localized("プロジェクトのフォルダとファイルは削除されません。"),
                    buttons: [DSDialogButton("削除", role: .destructive) {}, DSDialogButton("キャンセル", role: .primary) {}],
                    onCancel: {}) { DSDialogList(rows: rows) }.padding(10))
            }
            let content = ZStack {
                dashboard(scene)
                Color.black.opacity(0.42).ignoresSafeArea()
                dialog
            }
            do {
                try await capture(content, frame: frame, output: output)
            } catch {
                for session in scene.dashboard.sessions { await session.kill() }
                throw error
            }
            for session in scene.dashboard.sessions { await session.kill() }
            return frame.id.contains("project-delete") ? "実際の DSDialog とプロジェクト削除文言" : "実際の DSDialog とセッション削除文言"
        }

        let chats = scene.sessionIDs.map(ProjectTab.chat)
        var layout = ProjectTabLayout()
        for chat in chats { layout.open(chat) }
        layout.open(.terminal(TerminalTabID()))
        layout.open(.file("DashboardView.swift"))
        let selectsNewChat = frame.id.contains("T3") || scene.sessionIDs.isEmpty
        if let first = scene.sessionIDs.first, !selectsNewChat {
            layout.select(.chat(first))
            scene.router.selectedSession = first
        }
        scene.router.tabs.updateLayout(for: scene.project.id) { $0 = layout }
        if selectsNewChat { scene.router.showNewChat(projectID: scene.project.id) }
        let hideSidebarAfterMount = frame.id == "11-T12-dark"
        let sidebarWidth = frame.width <= 720 ? DSLayout.sidebarWidth.min : nil
        do {
            try await capture(dashboard(scene, initialSidebarWidth: sidebarWidth,
                                        initiallyExpandedProjectIDs: [scene.project.id]), frame: frame, output: output,
                              afterMount: { if hideSidebarAfterMount { scene.router.sidebarVisible = false } })
        } catch {
            for session in scene.dashboard.sessions { await session.kill() }
            throw error
        }
        for session in scene.dashboard.sessions { await session.kill() }
        return selectsNewChat ? "実際のタブ列で新規チャットを選択" : "実際のタブ列で会話を選択" + (frame.id.contains("T12") ? "、サイドバーを非表示" : "")
    }

    private func renderStage8Usage(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let scene = try await makeStage8Scene(frame, fixtures: fixtures)
        scene.router.showNewChat(projectID: scene.project.id)
        let sidebarWidth = frame.width <= 720 ? DSLayout.sidebarWidth.min : nil
        do {
            try await capture(dashboard(scene, initialSidebarWidth: sidebarWidth), frame: frame, output: output)
        } catch {
            for session in scene.dashboard.sessions { await session.kill() }
            throw error
        }
        for session in scene.dashboard.sessions { await session.kill() }
        return frame.id.contains("U4") || frame.id.contains("U8")
            ? "実際の下部バー。残り 4% と Codex の取得不可状態を表示"
            : "実際のヘッダーと下部使用量バー"
    }

    private func renderDashboard(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let root = fixtures.appendingPathComponent(frame.id)
        let path = "docs/guides/file-tree.md"
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: file)
        // 作業ディレクトリをこの撮影用ルートに固定する。空の Git リポジトリだけを作り、コミットしない。
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", root.path, "init", "-q", "--initial-branch=main"]
        try git.run()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0)
        let project = Project(name: "phlox-oss", directoryPath: root.path,
                              createdAt: Date(timeIntervalSince1970: 1_000), isManagedDirectory: false)
        let projects = InMemoryProjectStore()
        try await projects.save([project])
        let sessionID = SessionID()
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: events, projects: projects,
            sessions: InMemorySessionStore([makePersistedSessionDescriptor(id: sessionID, workingDirectory: root.path,
                name: "ファイルツリーをインスペクタに追加", projectID: project.id, startedAt: Date(timeIntervalSince1970: 2_000))]),
            workspaceDirectory: root, agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]))
        await dashboard.start()
        try #require(dashboard.sessionNodes.contains { $0.id == sessionID })
        let router = AppRouter(viewMode: .single, sidebarVisible: frame.id != "1c", inspectorVisible: true)
        router.selectedSession = sessionID
        router.selectedProjectID = project.id
        router.tabs.updateLayout(for: project.id) {
            $0.open(.file(path))
            $0.open(.simulator)
            $0.select(.file(path))
            $0.splitRight(.simulator)
            $0.focusesRight = false
        }
        let fixture = HubCatalogFixture(states: ["iPhone 17": "Shutdown"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) { SimulatorDisplayConnection { fake } }
        await hub.refresh()
        defer { hub.disconnectAll() }
        do {
            try await capture(DashboardView(viewModel: dashboard, router: router,
                usageMonitor: UsageMonitor(providers: [:]), simulatorHub: hub), frame: frame, output: output,
                afterMount: { if frame.id == "1c" { router.sidebarVisible = false } })
        } catch {
            for session in dashboard.sessions { await session.kill() }
            throw error
        }
        for session in dashboard.sessions { await session.kill() }
        #expect(await fixture.mutations().isEmpty)
        return "本物のダッシュボード全体。端末は停止状態の偽物。セッションは1件、タイトルバー・実端末映像は対象外。狭幅の縮退は現在の実装に従う"
    }

    private let html = """
    <!doctype html><html lang="ja"><head><meta charset="utf-8"><style>
    body{margin:0;padding:28px;background:#fff;color:#222;font:14px -apple-system,BlinkMacSystemFont,sans-serif}
    nav{display:flex;gap:24px;border-bottom:1px solid #ddd;padding-bottom:16px}a{color:#a54e2e}
    h1{font-size:32px}p{max-width:520px;line-height:1.7}article{padding:16px;background:#f7f7f8;border-radius:8px}
    </style></head><body><nav><b>Phlox</b><a href="../guides/file-tree.md">ドキュメント</a>
    <a href="releases.html">リリースノート</a><a href="https://github.com/phlox-oss/phlox">GitHub</a></nav>
    <h1>並べて走らせ、判断だけを前に。</h1><p>Phlox は Claude Code・Codex・Cursor のセッションを並べて走らせ、承認待ちと質問だけを前に出します。</p>
    <article><h2>ファイルツリー</h2><p>右サイドバーで作業ツリーを開き、Markdown と HTML を表示します。</p></article></body></html>
    """

    private func makeDocument(_ frame: Frame, fixtures: URL, files: FileTabDocuments, projectID: ProjectID) async throws -> FileTabDocument {
        let id = frame.stateID
        var path = "docs/guides/file-tree.md"
        var bytes = Data(markdown.utf8)
        if let sample = syntaxSample(id) {
            path = sample.path
            bytes = Data(sample.source.utf8)
        }
        if id.hasPrefix("3"), !["3d", "3e", "3f", "3g", "3l", "3m", "3n", "3o"].contains(id) {
            bytes = Data("# ファイルツリー\n\n右サイドバーの「ファイル」タブに、選択中セッションの作業ツリーを表示します。\n\n## 操作\n\n- クリックで開く。開いているタブがあれば前に出す\n- 右クリックで「右に分割して開く」「Finder で表示」「パスをコピー」\n- `⌃⌘B` でツリーを表示\n".utf8)
        }
        if ["3i", "3j", "3k"].contains(id) { path = "macos/Packages/DashboardFeature/docs/guides/file-tree.md" }
        if ["4j", "4m", "8L2"].contains(id) {
            bytes = Data(markdown.replacingOccurrences(of: "---\ntitle: Phlox\nstatus: draft\n---\n\n", with: "").utf8)
            path = "README.md"
        }
        switch id {
        case "3d", "5a", "5b", "5c", "5d", "5e", "5f", "5g", "5h": path = "docs/site/index.html"; bytes = Data(html.utf8)
        case "3e":
            path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Files/FileTreeRows.swift"
            bytes = Data("import Foundation\n\nenum FileTreeRows {\n    static func visibleRows() {}\n}\n".utf8)
        case "3f":
            path = "docs/changelog/CHANGELOG.md"
            bytes = Data(("# 変更履歴\n\n" + (1...2430).map { "## 変更 \($0)\n\n" }.joined()).utf8)
        case "3g": path = "fixtures/transcripts/long-session.md"; bytes = Data(String(repeating: "変更履歴\n", count: 60_000).utf8)
        case "3l": path = "fixtures/transcripts/session-2026-09-30.jsonl"; bytes = Data(repeating: 65, count: WorkingTreeText.maximumReadableFileSize + 3_400_000)
        case "3readonly-truncated":
            path = "pages/long-line.txt"
            bytes = Data(("長い行は省略して表示します。\n" + String(repeating: "a", count: 5_000_001) + "\n次の行はそのまま表示します。\n").utf8)
        case "3readonly", "3readonly-md", "3readonly-html", "3readonly-rendered", "3readonly-fallback":
            path = id == "3readonly-md" ? "docs/large.md" : ["3readonly-html", "3readonly-rendered", "3readonly-fallback"].contains(id) ? "pages/large.html" : "Sources/large.swift"
            let unit = id == "3readonly-md" ? "# 大きいMarkdown\n\n内容を選択・コピーできます。\n"
                : path.hasSuffix("html") ? "<!-- 内容を選択・コピーできます -->\n"
                : "let value = 42 // 閲覧のみ・選択とコピーができます\n"
            bytes = Data(String(repeating: unit, count: 5_000_001 / unit.utf8.count + 1).utf8)
            if path.hasSuffix("html") { bytes = Data("<!doctype html><html><body><h1>閲覧のみ</h1><p>選択・コピーできます。</p></body></html>\n".utf8) + bytes }
            if id == "3readonly-rendered" {
                let padding = String(repeating: " 撮影用のコメント\n", count: 250_000)
                bytes = Data((html + "\n<!--" + padding + "-->\n").utf8)
                try #require(bytes.count > WorkingTreeText.maximumEditableFileSize)
                try #require(bytes.count <= WorkingTreeText.maximumReadableFileSize)
            }
        case "3large":
            path = "Sources/large.swift"
            bytes = Data(String(repeating: "let value = 42 // 色付けなしで編集・保存できます\n", count: 30_000).utf8)
        case "3m": path = "assets/logo.png"; bytes = Data([137, 80, 78, 71, 0])
        case "3o": path = "legacy/README_sjis.txt"; bytes = Data([0x82, 0xa0, 0x82, 0xa2])
        case "4e": path = "docs/links.md"; bytes = Data("[design]: docs/architecture/overview.md\n[adr-0090]: docs/adr/0090-inspector.md\n[simulator]: docs/specs/embedded-ios-simulator.md\n".utf8)
        case "4f": path = "docs/NOTES.md"; bytes = Data()
        case "4d":
            bytes = Data(("| 機能 | 説明 |\n| --- | --- |\n" + (1...20).map { "| 機能\($0) | 長い表の説明 |\n" }.joined()).utf8)
        default: break
        }
        let root = fixtures.appendingPathComponent(frame.id)
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if id == "3n" {
            let outside = fixtures.appendingPathComponent("style-guide.md")
            try bytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        } else { try bytes.write(to: file) }
        if id.hasPrefix("5") {
            let linked = root.appendingPathComponent("docs/guides/file-tree.md")
            try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(markdown.utf8).write(to: linked)
        }
        let document = files.document(for: projectID, path: path, root: root.path)
        await document.loadIfNeeded()
        switch id {
        case "3l": try #require(document.loadState == .tooLarge)
        case "3m": try #require(document.loadState == .binary)
        case "3n":
            guard case .outsideRoot = document.loadState else { throw Unavailable(reason: "ルート外のリンク拒否を再現できなかった") }
        case "3o": try #require(document.loadState == .loadFailed)
        default: try #require(document.isLoaded)
        }
        if id.hasPrefix("3readonly") {
            try #require(document.isReadOnly)
            if id != "3readonly-rendered" { try #require(document.setPresentation(.source)) }
        }
        if id == "3f" || id == "3g" { try #require(document.markdownPresentationLocked) }
        if ["3b", "3c", "3i", "3j", "3k"].contains(id) { document.draft += "\n編集した内容。\n" }
        if id == "3c" { document.presentation = .source }
        if id.hasPrefix("syntax-") {
            if ["syntax-block", "syntax-frontmatter", "syntax-fence"].contains(id) {
                let block = try #require(document.markdownBlocks.first { block in
                    switch id {
                    case "syntax-frontmatter": block.original.hasPrefix("---")
                    case "syntax-fence": block.original.hasPrefix("```")
                    default: block.original.hasPrefix("**")
                    }
                })
                #expect(document.beginBlockEdit(range: block.range))
            } else {
                document.presentation = .source
            }
        }
        if id == "5e" {
            document.draft = html.replacingOccurrences(of: "並べて走らせ、判断だけを前に。", with: "未保存の下書きを表示しています。")
            document.reloadHTMLPreview()
        }
        if ["3h", "4b", "4c", "4d", "4g", "4j", "8L2"].contains(id) {
            let blocks = document.markdownBlocks
            let block = try #require(id == "4c" || id == "4d" || id == "3h" ? blocks.first : blocks.first { $0.original.contains("Phlox は") })
            #expect(document.beginBlockEdit(range: block.range))
            if ["4b", "4j", "8L2"].contains(id) {
                let edit = try #require(document.activeBlockEdit)
                let original = edit.current as NSString
                let content = edit.current.trimmingCharacters(in: .newlines)
                let separator = original.substring(from: content.utf16.count)
                let current = content + "\n編集中の内容です。" + separator
                #expect(!current.contains("\n\n編集中の内容です。"))
                document.updateActiveBlockEdit(id: edit.id, current: current)
            }
            if id == "3h" || id == "4g" {
                let edit = try #require(document.activeBlockEdit)
                document.updateActiveBlockEdit(id: edit.id, current: edit.current + "\n編集内容は保持します。")
                document.draft += "\n文書側の変更。\n"
                #expect(!document.commitActiveBlockEdit())
                #expect(document.blockEditFailure != nil)
            }
        }
        return document
    }

    private func renderTree(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let id = frame.stateID
        let previousCeiling = ProcessInfo.processInfo.environment["GIT_CEILING_DIRECTORIES"]
        if id == "2e3" { setenv("GIT_CEILING_DIRECTORIES", fixtures.path, 1) }
        defer {
            if id == "2e3" {
                if let previousCeiling { setenv("GIT_CEILING_DIRECTORIES", previousCeiling, 1) }
                else { unsetenv("GIT_CEILING_DIRECTORIES") }
            }
        }
        let root = id == "2e1" ? fixtures.deletingLastPathComponent().deletingLastPathComponent().path
            : fixtures.appendingPathComponent(id).path
        if id != "2e4" { try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true) }
        let loader = FileTreeLoader(root: root) { _, path in
            if id == "2j" { throw CocoaError(.fileReadNoSuchFile) }
            if id == "2h" && path == "docs" { throw CocoaError(.fileReadNoPermission) }
            if id == "2g", path == "docs" { try await Task.sleep(for: .seconds(30)) }
            if path == "" {
                return .init(entries: [
                    .init(relativePath: "docs", name: "docs", kind: .directory),
                    .init(relativePath: "macos", name: "macos", kind: .directory),
                    .init(relativePath: "latest", name: "latest", kind: .symlinkToDirectory, resolvedPath: root + "/docs"),
                    .init(relativePath: "shared-assets", name: "shared-assets", kind: .symlinkOutsideRoot,
                          resolvedPath: "/Users/ryosuke/Projects/phlox-shared/assets", outsideTargetIsDirectory: true),
                    .init(relativePath: "README.md", name: "README.md", kind: .file),
                    .init(relativePath: "CLAUDE.md", name: "CLAUDE.md", kind: .symlinkToFile, resolvedPath: root + "/README.md"),
                ], omittedCount: 0)
            }
            return .init(entries: [
                .init(relativePath: "docs/file-tree.md", name: "file-tree.md", kind: .file),
                .init(relativePath: "docs/step-2.md", name: "step-2.md", kind: .file),
                .init(relativePath: "docs/step-10-release.md", name: "step-10-release.md", kind: .file),
            ], omittedCount: id == "2f" ? 7412 : 0)
        }
        let branches = ["2e1": "main", "2e2": "9f3c2e1 detached HEAD", "2e3": "Git 管理外", "2e4": ""]
        let branch = branches[id] ?? "feature/file-tree"
        let model = FileTreeModel(root: root, loader: loader, readBranch: { branch })
        await model.refresh()
        if id == "2e3" { try #require(model.branch == "Git 管理外") }
        if id == "2e4" { try #require(model.branch.isEmpty) }
        if id == "2i" {
            let view = FileTreeInspectorView(router: AppRouter(), project: nil, models: .constant([:]), files: FileTabDocuments())
            try await capture(view, frame: frame, output: output)
        } else {
            let expansion = Task { await model.expand("docs") }
            if id == "2g" {
                try await waitUntil { model.loading.contains("docs") }
            } else { await expansion.value }
            defer { expansion.cancel() }
            let tree = FileTreeView(model: model, openPath: "docs/file-tree.md", open: { _, _ in },
                                    keyboardPath: id == "2b" || id == "8L1" ? "docs/step-2.md" : nil,
                                    hoverPath: id == "2a" ? "README.md" : id == "2d" ? "shared-assets" : nil,
                                    contextPath: id == "2c" ? "docs/file-tree.md" : nil,
                                    isOverlay: id == "2k",
                                    blockedPath: frame.id == "2d-click" ? "shared-assets" : nil)
            try await capture(tree, frame: frame, output: output)
        }
        return id == "2f" ? "件数上限の表示を偽ローダーで再現。5000行の末尾へのスクロールは対象外"
            : id == "2c" ? "右クリック対象の輪を描画。標準メニューの展開は画面外では確認できず"
            : id == "2d" ? "ルート外の行をホバー状態で描画。標準helpの浮いた表示は画面外では確認できず"
            : "実物のツリー。ルートのパスは worktree 内の撮影用データ"
    }

    private func renderSimulator(_ frame: Frame, output: URL) async throws -> String {
        let id = frame.stateID
        let displayID = UUID()
        let session = ProjectID()
        let icon = NSApp.applicationIconImage
        if id == "7e" {
            let macos = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let applicationIcon = try #require(NSImage(contentsOf: macos
                .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/512.png")))
            NSApp.applicationIconImage = applicationIcon
        }
        defer { if id == "7e" { NSApp.applicationIconImage = icon } }
        var states = [
            "iPhone 17 Pro": ["7f", "7g", "7nStopped"].contains(id) ? "Shutdown" : "Booted",
            "iPhone 17": "Shutdown", "iPhone 16e": "Shutdown",
            "iPad Air 13 インチ（M3）": "Booted",
        ]
        if id.hasPrefix("7Long") { states["iPad Pro 13-inch (M4)"] = id == "7LongStopped320" ? "Shutdown" : "Booted" }
        if id == "7d" { states["iPhone SE（第3世代）"] = "Shutdown" }
        let fixture = HubCatalogFixture(states: states, runtimeIdentifiers: id == "7d" ? [
            "iPhone 16e": "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
            "iPhone SE（第3世代）": "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
        ] : [:])
        if id == "7g" { await fixture.setState("Booting", udid: "iPhone 17") }
        let fake = HubTransport()
        let catalog = ["7k", "7ListingError"].contains(id) ? SimulatorCatalog(isXcodeAvailable: { id != "7k" }) { _, _ in
            .init(status: 72, output: Data(), errorOutput: Data((id == "7k"
                ? "xcrun: unable to find utility \"simctl\"" : "CoreSimulator のサービスに接続できません").utf8))
        } : fixture.catalog()
        let hub = SimulatorHub(catalog: catalog, refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            if id == "7h" {
                connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "17C52",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", supportsInput: false)])
            }
            return connection
        }
        await hub.refresh()
        hub.select(udid: ["7k", "7ListingError"].contains(id) ? nil : id.hasPrefix("7Long")
            ? "iPad Pro 13-inch (M4)" : ["7f", "7g"].contains(id) ? "iPhone 17" : "iPhone 17 Pro", for: session)
        hub.setVisible(true, displayID: displayID, projectID: session)
        defer { hub.disconnectAll() }
        if id == "7e" {
            let otherSession = ProjectID()
            hub.select(udid: "iPhone 17 Pro", for: otherSession)
            hub.setVisible(true, displayID: UUID(), projectID: otherSession)
        }
        if let connection = hub.connection(for: session) {
            try await waitUntil { fake.probeReply != nil }
            if id == "7l" {
                fake.failed?("シミュレーターの補助プロセスに接続できません")
                fake.failed?("自動の再接続後も応答がありません")
                try #require(connection.canReconnect)
            } else {
                let unverified = ["7j", "7j2", "7TrialInput520", "7LongTrialStale320"].contains(id)
                let capability = SimulatorBridgeCapability(
                    protocolVersion: id == "7m" ? SimulatorBridgeInterfaces.protocolVersion - 1 : SimulatorBridgeInterfaces.protocolVersion,
                    helperBuild: "検証", xcodeBuild: unverified ? "17D21" : "17C52",
                    coreSimulatorLoaded: true, simulatorKitLoaded: true)
                fake.probeReply?(capability)
                if unverified && id != "7j" {
                    hub.tryUnverified(displayID: displayID)
                    fake.probeReply?(capability)
                }
                if id != "7j" && id != "7m" {
                    let width = 402, height = 874
                    let surface = try #require(IOSurface(properties: [.width: width, .height: height,
                        .bytesPerElement: 4, .bytesPerRow: width * 4, .allocSize: width * height * 4,
                        .pixelFormat: 0x42475241]))
                    try #require(IOSurfaceLock(surface, [], nil) == 0)
                    let pixels = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt32.self)
                    for index in 0..<(width * height) { pixels[index] = 0xfff7f2f2 }
                    try #require(IOSurfaceUnlock(surface, [], nil) == 0)
                    fake.attachReply?(SimulatorDisplayInfo(udid: hub.selectedDevice(for: session)?.udid ?? "iPhone 17 Pro",
                        connectionGeneration: connection.generation.current, displayGeneration: 1,
                        surface: surface, pixelWidth: width, pixelHeight: height,
                        orientation: .portrait, surfaceIsRotated: false, pixelFormat: 0x42475241), nil)
                    try #require(connection.displayInfo != nil)
                    if ["7i", "7StaleInput520", "7LongTrialStale320"].contains(id), let info = connection.displayInfo {
                        try #require(IOSurfaceLock(surface, [], nil) == 0)
                        try #require(IOSurfaceUnlock(surface, [], nil) == 0)
                        connection.observeFrame(info, seed: IOSurfaceGetSeed(surface),
                                                at: Date().addingTimeInterval(-6))
                    }
                }
            }
        }
        let focused = ["7b", "7c", "7n", "8L3", "7TrialInput520", "7StaleInput520", "7LongInput320", "7LongTrialStale320"].contains(id)
        let content = SimulatorTabContent(hub: hub, projectID: session, displayID: displayID,
            confirmsShutdown: id == "7e",
            sendsKeys: .constant(focused), showsDiagnostics: .constant(frame.id == "7iOpen"),
            select: { _ in }, releaseFocus: {}, screenshot: {}, shutdown: {}, openSimulator: {}, tellAgent: {})
            .overlay(alignment: .topLeading) {
                if frame.id == "7iOpen" {
                    SimulatorDiagnostics().background(DSColor.popoverBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.row))
                        .offset(x: 160, y: 34)
                }
            }
            .overlay(alignment: .top) {
                if id == "7e" {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.4)
                        SimulatorShutdownDialog(deviceName: "iPhone 17 Pro", displayCount: hub.displayCount(udid: "iPhone 17 Pro"),
                                                shutdown: {}, cancel: {})
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.l)).padding(.top, 70)
                    }
                }
            }
        try await capture(content, frame: frame, output: output, prepare: { host, window in
            let views = descendants(host)
            if id == "7r", let menu = views.first(where: { $0 is NSPopUpButton }) {
                window.makeFirstResponder(menu)
            }
            if let screen = views.compactMap({ $0 as? SimulatorScreenNSView }).first {
                if id == "7c" || id == "7c2" {
                    screen.showPointer(at: CGPoint(x: screen.bounds.width * 0.45, y: screen.bounds.height * 0.5),
                                       touching: id == "7c")
                }
            }
            if id == "7d", let menu = views.compactMap({ $0 as? NSPopUpButton }).first?.menu {
                let list = SimulatorMenuSnapshot(menu: menu)
                list.frame = NSRect(x: 8, y: 30, width: 310, height: CGFloat(menu.items.count * 26 + 10))
                host.addSubview(list)
            }

        })
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        return "偽の接続・単色 IOSurface と実物の表示部品。実端末操作なし"
    }

    private func snapshotAccessibilityElement(_ identifier: String, in root: NSObject) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            let id = NSSelectorFromString("accessibilityIdentifier")
            if object.responds(to: id), object.perform(id)?.takeUnretainedValue() as? String == identifier { return object }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                for child in values { if let found = visit(child) { return found } }
            }
            if let view = object as? NSView {
                for child in view.subviews { if let found = visit(child) { return found } }
            }
            return nil
        }
        return visit(root)
    }

    private func destination(_ frame: Frame, _ output: URL) -> URL {
        let name = ["10-", "11-", "12-"].contains(where: frame.id.hasPrefix)
            ? "\(frame.id).png" : "\(frame.id)-\(frame.name).png"
        return output.appendingPathComponent(name)
    }

    func makeSnapshotWindow<V: View>(_ content: V, id: String, width: CGFloat, height: CGFloat, light: Bool = false) -> NSWindow {
        let includesTitlebar = id.hasPrefix("13-bp-window-")
        let controller = includesTitlebar ? NSHostingController(rootView: content) : nil
        let host: NSView = controller?.view ?? NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: includesTitlebar ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        if let controller { window.contentViewController = controller }
        else { window.contentView = host }
        return window
    }

    private func capture<V: View>(_ content: V, frame: Frame, output: URL,
                                 foreground: AnyView? = nil, foregroundOrigin: CGPoint = .zero,
                                 afterMount: (() -> Void)? = nil, selectsParagraph: Bool = false,
                                 prepare: ((NSView, NSWindow) async throws -> Void)? = nil) async throws {
        let strings = try localizationBundle(fixtures: output)
        let includesTitlebar = frame.id.hasPrefix("13-bp-window-")
        let rootView = content
            .environment(\.localizationBundle, strings)
            .frame(width: frame.width, height: frame.height)
            .background(DSColor.background)
            .environment(\.locale, Locale(identifier: frame.english ? "en" : "ja"))
            .environment(\.colorScheme, frame.light ? .light : .dark)
        let window = makeSnapshotWindow(rootView, id: frame.id, width: frame.width, height: frame.height, light: frame.light)
        let host = try #require(window.contentView)
        defer { window.contentViewController = nil; window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        if frame.id.hasPrefix("syntax-") { try await Task.sleep(for: .milliseconds(200)) }
        afterMount?()
        if frame.id.hasPrefix("1") { try await Task.sleep(for: .milliseconds(500)) }
        host.layoutSubtreeIfNeeded()
        if selectsParagraph {
            let field = try #require(descendants(host).compactMap { $0 as? NSTextField }
                .first { $0.stringValue.hasPrefix("Phlox は") })
            #expect(field.isSelectable)
            field.selectText(nil)
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: 0, length: 6))
            #expect(editor.selectedRange().length == 6)
            #expect(editor.selectedTextAttributes[.backgroundColor] as? NSColor == NSColor(DSColor.textSelection))
        }
        try await prepare?(host, window)
        host.layoutSubtreeIfNeeded()
        // WebKit はホストの cacheDisplay に入らないので、完了した画像を合成する。
        let deadline = ContinuousClock.now + .seconds(10)
        if ["3d", "5a", "5e", "5h"].contains(frame.id) {
            try await waitUntil(deadline: deadline) { descendants(host).contains { $0 is WKWebView } }
        }
        var snapshots: [(NSImage, NSRect)] = []
        for web in descendants(host).compactMap({ $0 as? WKWebView }) {
            if frame.id.hasPrefix("9-"), web.url == nil { continue }
            try await waitUntil(deadline: deadline) { !web.isLoading && web.url != nil }
            let ready = try await web.evaluateJavaScript("document.readyState")
            try #require(ready as? String == "complete")
            _ = try await web.callAsyncJavaScript(
                "await document.fonts.ready; return true",
                arguments: [:], in: nil, contentWorld: .defaultClient)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = web.bounds
            configuration.snapshotWidth = NSNumber(value: Double(web.bounds.width * 2))
            configuration.afterScreenUpdates = false
            let image = try await web.takeSnapshot(configuration: configuration)
            var rect = host.convert(web.bounds, from: web)
            if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
            snapshots.append((image, rect))
        }
        host.layoutSubtreeIfNeeded()
        var foregrounds: [(NSImage, NSRect)] = []
        if let foreground {
            let renderer = ImageRenderer(content: foreground
                .environment(\.localizationBundle, strings)
                .environment(\.locale, Locale(identifier: frame.english ? "en" : "ja"))
                .environment(\.colorScheme, frame.light ? .light : .dark))
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            foregrounds.append((image, NSRect(origin: foregroundOrigin, size: image.size)))
        }
        let drawingView = includesTitlebar ? try #require(window.contentView?.superview) : host
        if includesTitlebar {
            #expect(window.toolbar != nil)
            #expect(drawingView.bounds.height > host.bounds.height)
        }
        try saveBitmap(drawingView, bounds: drawingView.bounds, to: destination(frame, output), snapshots: snapshots, foregrounds: foregrounds)
        #expect(!window.isVisible)
    }

    private func saveBitmap(_ view: NSView, bounds: NSRect, to url: URL, snapshots: [(NSImage, NSRect)] = [],
                            foregrounds: [(NSImage, NSRect)] = []) throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        view.layoutSubtreeIfNeeded()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: bitmap)
        }
        if !snapshots.isEmpty || !foregrounds.isEmpty {
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for (image, rect) in snapshots { image.draw(in: rect, from: .zero, operation: .copy, fraction: 1) }
            for (image, rect) in foregrounds { image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
            NSGraphicsContext.restoreGraphicsState()
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
        let decoded = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
        #expect(decoded.pixelsWide == Int(bounds.width * 2))
        #expect(decoded.pixelsHigh == Int(bounds.height * 2))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitUntil(deadline: ContinuousClock.Instant = .now + .seconds(3), _ condition: () -> Bool) async throws {
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard condition() else { throw Unavailable(reason: "画面外描画の準備が時間内に完了しなかった") }
    }
}
}


private struct DesignSnapshotUsageProvider: UsageProvider {
    let kind: AgentKind
    let usage: CLIUsage

    func fetch() async -> CLIUsage { usage }
}

/// OS のメニューを開かず、本物の項目の文字・印を描く。
@MainActor private final class SimulatorMenuSnapshot: NSView {
    let sourceMenu: NSMenu
    init(menu: NSMenu) {
        self.sourceMenu = menu
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(DSColor.popoverBackground).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        for (index, item) in sourceMenu.items.enumerated() {
            let y = CGFloat(index * 26 + 5)
            if item.isSeparatorItem {
                NSColor(DSColor.separator).setFill()
                NSRect(x: 10, y: y + 12, width: bounds.width - 20, height: 1).fill()
            } else {
                if item.state == .on {
                    ("✓" as NSString).draw(at: NSPoint(x: 8, y: y + 5), withAttributes: [
                        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(DSColor.textPrimary),
                    ])
                }
                item.image?.draw(in: NSRect(x: 22, y: y + 7, width: 10, height: 12))
                let title = item.attributedTitle ?? NSAttributedString(string: item.title,
                    attributes: [.font: NSFont.systemFont(ofSize: 13),
                                 .foregroundColor: NSColor(DSColor.textPrimary)])
                title.draw(at: NSPoint(x: item.representedObject == nil ? 12 : 40, y: y + 5))
            }
        }
    }
}
