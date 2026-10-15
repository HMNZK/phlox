import AppKit
import DesignSystem
import ObjectiveC
import SwiftUI
import Testing
@testable import DashboardFeature

/// 表示中のアプリや入力ソースを操作せず、実物の View と responder を描画する。
@Suite("一覧と端末の外枠の描画", .serialized) @MainActor
struct FocusBorderRenderTests {
    @Test("クリック後にポインタを外しても選択を塗り、Return はその行を変更する",
          arguments: [false, true])
    func clickedSelection(folder: Bool) async throws {
        try await withAppearance {
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
            try Data("本文".utf8).write(to: root.appendingPathComponent("notes.txt"))
            let model = FileTreeModel(root: root.path, readBranch: { "feature/files" })
            await model.refresh()
            let window = makeWindow(FileTreeView(model: model, openPath: nil, open: { _, _ in }))
            defer { close(window) }
            let host = try #require(window.contentView)
            try await settle(host)
            let path = folder ? "docs" : "notes.txt"
            let row = try #require(IntegrationFixAccessibility.find("file-tree-row-" + path, in: host))
            let rowRect = rect(row, in: host)
            // クリックと同じ activate を呼ぶ AX の押下操作を使う。
            #expect((row as AnyObject).accessibilityPerformPress())
            // ツリーの外へ退出するイベントを届ける。実マウスは動かさない。
            try mouse(.mouseMoved, at: NSPoint(x: 2, y: 2), window: window)
            for view in [host] + descendants(host) {
                for area in view.trackingAreas {
                    let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, trackingNumber: 0, userData: nil))
                    (area.owner as? NSResponder)?.mouseExited(with: exit)
                }
            }
            try await settle(host)
            let selected = try #require(IntegrationFixAccessibility.find("file-tree-row-" + path, in: host))
            #expect((selected as AnyObject).isAccessibilitySelected())
            let bitmap = try bitmap(host)
            let sample = NSPoint(x: rowRect.maxX - 18, y: rowRect.midY)
            let reference = NSHostingView(rootView: DSColor.selectionFill.background(DSColor.panelBackground).frame(width: 20, height: 20))
            reference.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            let expected = try color(self.bitmap(reference), point: NSPoint(x: 10, y: 10))
            let pixel = try color(bitmap, point: sample)
            #expect(distance(pixel, expected) < 0.04, "クリック選択の塗り: \(pixel) / \(expected)")
            try key("\r", code: 36, window: window)
            try await settle(host)
            #expect(model.edit?.originalPath == path)
        }
    }

    @Test("入力先のある一覧・差分・下部端末の外周にフォーカス枠を描かない",
          arguments: ["files", "git-list", "git-diff", "terminal"])
    func focusedPerimeter(target: String) async throws {
        try await withAppearance {
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let window: NSWindow
            var panel: TerminalPanelSession?
            var panelState: BottomPanelState?
            if target == "files" {
                try Data("本文".utf8).write(to: root.appendingPathComponent("notes.txt"))
                let model = FileTreeModel(root: root.path, readBranch: { "feature/files" })
                await model.refresh()
                window = makeWindow(FileTreeView(model: model, openPath: nil, open: { _, _ in }, focusRequest: 1))
            } else if target == "terminal" {
                let session = TerminalPanelSession(controller: UserTerminalController(pty: MockPTYManager(),
                    shellPath: "/bin/zsh", workingDirectory: root.path, environment: [:]))
                let state = BottomPanelState()
                state.open(window: nil)
                panel = session
                panelState = state
                window = makeWindow(BottomPanelView(panel: session, state: state))
            } else {
                let fixture = try GitWorkflowRenderFixture(parent: root)
                if target == "git-diff" { try fixture.prepareContextDiff() }
                let model = fixture.model()
                await model.refresh()
                if target == "git-diff" {
                    await model.select("Sources/Workflow.swift", source: .worktree)
                    window = makeWindow(EditorPanelView(viewModel: model, workingDirectory: fixture.root.path, focusRequest: 1))
                } else {
                    window = makeWindow(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                        openChanges: { _, _, _ in }, openFile: { _ in }, focusRequest: 1))
                }
            }
            let host = try #require(window.contentView)
            do {
                try await settle(host)
                let id = target == "files" ? "file-tree" : target == "terminal" ? "bottom-panel" : target == "git-diff" ? "editor-diff-scroll" : "git-inspector-list"
                let region = try #require(IntegrationFixAccessibility.find(id, in: host))
                let scrolls = descendants(host).compactMap { $0 as? NSScrollView }.sorted {
                    host.convert($0.bounds, from: $0).minY < host.convert($1.bounds, from: $1).minY
                }
                let bounds: NSRect
                if let panel {
                    let terminal = try #require(panel.terminalCoordinator.terminalView.superview)
                    bounds = host.convert(terminal.bounds, from: terminal)
                } else if target == "git-diff" {
                    let scroll = try #require(scrolls.last)
                    bounds = host.convert(scroll.bounds, from: scroll)
                } else { bounds = rect(region, in: host) }
                #expect(bounds.width > 0 && bounds.height > 0)
                if let panel {
                    #expect(window.makeFirstResponder(panel.terminalCoordinator.terminalView))
                    try await settle(host)
                    #expect(window.firstResponder === panel.terminalCoordinator.terminalView)
                    #expect(panelState?.isTerminalFocused == true)
                } else {
                    if target == "git-diff" {
                        // Tab は SwiftUI の実際のフォーカス順に従って差分へ移す。
                        for _ in 0..<8 {
                            if focusedRect(host) == bounds { break }
                            try key("\t", code: 48, window: window)
                            try await settle(host)
                        }
                    }
                    #expect(focusedRect(host) == bounds, "入力先: \(target) / \(String(describing: focusedRect(host))) / \(bounds)")
                }
                let image = try bitmap(host.superview ?? host)
                // 見出し・区切り線・スクロールバーを避け、左右の外周とその外側を検査する。
                // 枠色のアンチエイリアスも背景との差として検出する。
                let background = try color(image, point: NSPoint(x: 2, y: 2))
                let inside = target == "terminal" ? try color(image, point: NSPoint(x: bounds.midX, y: bounds.midY)) : background
                var changed = 0
                for left in [true, false] {
                    for offset in stride(from: -3.0, through: 6.0, by: 0.5) {
                        let x = left ? bounds.minX + offset : bounds.maxX - offset
                        for y in stride(from: bounds.midY - 20, through: bounds.midY + 20, by: 0.5) {
                            let expected = x >= bounds.minX && x < bounds.maxX ? inside : background
                            if distance(try color(image, point: NSPoint(x: x, y: y)), expected) > 0.04 {
                                changed += 1
                            }
                        }
                    }
                }
                var edgeSamples: [String] = []
                if changed > 0 {
                    for left in [true, false] {
                        for offset in [-2.0, 0.0, 2.0, 6.0] {
                            let x = left ? bounds.minX + offset : bounds.maxX - offset
                            let pixel = try color(image, point: NSPoint(x: x, y: bounds.midY))
                            edgeSamples.append("\(left ? "左" : "右")\(offset): \(pixel)")
                        }
                    }
                }
                #expect(changed == 0, "\(target) の外周に背景と異なる画素: \(changed), 領域: \(bounds), 背景: \(background), 内部: \(inside), 中央の外周: \(edgeSamples)")
                if ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" {
                    let output = workspace.appendingPathComponent(".build/design-snapshots")
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try #require(image.representation(using: .png, properties: [:]))
                        .write(to: output.appendingPathComponent("focus-border-\(target).png"))
                }
            } catch {
                close(window)
                await panel?.controller.shutdown()
                throw error
            }
            close(window)
            await panel?.controller.shutdown()
        }
    }

    @Test func 折りたたむと見出しへ入力先が移りキーでindexを変えない() async throws {
        try await withAppearance {
            // 共通の撮影設定の argumentDomain は保存値より優先され、開閉を固定してしまう。
            let defaults = UserDefaults.standard
            let expansionKey = "phlox.inspector.git.changesExpanded"
            var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments.removeValue(forKey: expansionKey)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let previous = defaults.object(forKey: expansionKey)
            defaults.set(true, forKey: expansionKey)
            defer {
                if let previous { defaults.set(previous, forKey: expansionKey) }
                else { defaults.removeObject(forKey: expansionKey) }
            }
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try GitWorkflowRenderFixture(parent: root)
            let model = fixture.model()
            await model.refresh()
            await model.select("Sources/Workflow.swift", source: .worktree)
            let before = try await WorkingTreeService(repositoryRoot: fixture.root).snapshot()
            let index = try await WorkingTreeService(repositoryRoot: fixture.root).fileContents("Sources/Workflow.swift", source: .staged)
            let window = makeWindow(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                openChanges: { _, _, _ in }, openFile: { _ in }, focusRequest: 1))
            defer { close(window) }
            let host = try #require(window.contentView)
            try await settle(host)
            let toggle = try #require(IntegrationFixAccessibility.find("git-section-changes-toggle", in: host))
            #expect((toggle as AnyObject).accessibilityPerformPress())
            try await settle(host)
            let focus = try #require(focusedRect(host))
            #expect(focus.intersects(rect(toggle, in: host)))
            #expect(IntegrationFixAccessibility.find("git-change-worktree-Sources/Workflow.swift", in: host) == nil)
            try key("\u{f701}", code: 125, window: window)
            try key(" ", code: 49, window: window)
            try await settle(host)
            let after = try await WorkingTreeService(repositoryRoot: fixture.root).snapshot()
            #expect(after.stagedChanges == before.stagedChanges)
            #expect(try await WorkingTreeService(repositoryRoot: fixture.root).fileContents("Sources/Workflow.swift", source: .staged) == index)
        }
    }

    @Test func 履歴の開いた区画だけを上下キーで移動する() async throws {
        try await withAppearance {
            let defaults = UserDefaults.standard
            var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["phlox.inspector.git.commitsExpanded"] = true
            arguments["phlox.inspector.git.branchesExpanded"] = false
            arguments["phlox.inspector.git.remotesExpanded"] = false
            arguments["phlox.inspector.git.stashesExpanded"] = false
            arguments["phlox.inspector.git.graphExpanded"] = false
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let fixture = try GitHistoryFixture()
            defer { fixture.remove() }
            let model = fixture.model()
            await model.refresh()
            await model.setHistorySection(.commits, expanded: true)
            let commit = try #require(model.historyCommits.first)
            let window = makeWindow(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                openChanges: { _, _, _ in }, openFile: { _ in }, focusRequest: 1))
            defer { close(window) }
            let host = try #require(window.contentView)
            try await settle(host)
            try key("\u{f701}", code: 125, window: window)
            try await settle(host)
            #expect(model.activeGitRow == .commit(commit.id, graph: false))
            try key("\r", code: 36, window: window)
            try await settle(host)
            #expect(model.expandedHistoryRows.contains(.commit(commit.id)))
            try key("\u{f701}", code: 125, window: window)
            try await settle(host)
            #expect(model.activeGitRow == .file(.init(path: "a.txt", source: .commit(commit.id)), graph: false))
            let index = try Data(contentsOf: fixture.root.appendingPathComponent(".git/index"))
            try key(" ", code: 49, window: window)
            #expect(try Data(contentsOf: fixture.root.appendingPathComponent(".git/index")) == index)
            let toggle = try #require(IntegrationFixAccessibility.find("git-section-commits-toggle", in: host))
            #expect((toggle as AnyObject).accessibilityPerformPress())
            try await settle(host)
            let selected = model.activeGitRow
            try key("\u{f701}", code: 125, window: window)
            try key("\r", code: 36, window: window)
            try await settle(host)
            #expect(model.activeGitRow == selected)
            #expect(try Data(contentsOf: fixture.root.appendingPathComponent(".git/index")) == index)
        }
    }

    @Test func 選択行のControlReturnで行メニューを開く() async throws {
        try await withAppearance {
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try GitWorkflowRenderFixture(parent: root)
            let model = fixture.model()
            await model.refresh()
            await model.select("Sources/Workflow.swift", source: .worktree)
            let window = makeWindow(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                openChanges: { _, _, _ in Issue.record("ControlReturn が差分を開いた") }, openFile: { _ in }, focusRequest: 1))
            defer { close(window) }
            let host = try #require(window.contentView)
            try await settle(host)
            try key("\r", code: 36, modifiers: .control, window: window)
            try await settle(host)
            let menu = NSApp.windows.compactMap(\.contentView).compactMap {
                IntegrationFixAccessibility.find("git-row-menu", in: $0)
            }.first
            #expect(menu != nil)
            try key("\u{1b}", code: 53, window: window)
        }
    }

    @Test func コミット欄のCommandReturnだけがコミットする() async throws {
        try await withAppearance {
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try GitWorkflowRenderFixture(parent: root)
            let model = fixture.model()
            await model.refresh()
            model.commitMessage = "キーからのコミット"
            model.requestCommitFocus()
            let window = makeWindow(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                openChanges: { _, _, _ in }, openFile: { _ in }))
            let host = try #require(window.contentView)
            try await settle(host)
            #expect(model.commitMessageFocused)
            try key("\r", code: 36, modifiers: .command, window: window)
            for _ in 0..<100 {
                if model.commitMessage.isEmpty && !model.isWorkflowBusy { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(model.commitMessage.isEmpty)
            #expect(!model.workflowStatusIsError)
            #expect(model.stagedChanges.isEmpty)
            close(window)
            await model.stage(paths: ["Sources/Workflow.swift"])
            model.commitMessage = "非表示ではコミットしない"
            let other = makeWindow(EmptyView())
            defer { close(other) }
            try await settle(try #require(other.contentView))
            #expect(!model.commitMessageFocused)
            try key("\r", code: 36, modifiers: .command, window: other)
            try await settle(try #require(other.contentView))
            #expect(model.commitMessage == "非表示ではコミットしない")
            #expect(!model.stagedChanges.isEmpty)
        }
    }

    private var workspace: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root
    }
    private func fixtureDirectory() throws -> URL {
        let root = workspace.appendingPathComponent(".build/focus-render-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func withAppearance(_ body: () async throws -> Void) async throws {
        _ = NSApplication.shared
        let originalClass: AnyClass = try #require(object_getClass(NSApp))
        try #require(class_getInstanceSize(originalClass) == class_getInstanceSize(FocusRenderApplication.self))
        object_setClass(NSApp, FocusRenderApplication.self)
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        var dark = arguments
        dark[ThemeStore.themeKey] = AppTheme.phlox.id
        dark["phlox.inspector.git.changesExpanded"] = true
        defaults.setVolatileDomain(dark, forName: UserDefaults.argumentDomain)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer {
            object_setClass(NSApp, originalClass)
            FocusRenderApplication.focusWindow = nil
            NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface")
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
        }
        try await body()
    }
    private func makeWindow(_ content: some View) -> NSWindow {
        let host = NSHostingView(rootView: content.frame(width: 320, height: 420)
            .background(DSColor.panelBackground).padding(12).background(DSColor.panelBackground)
            .environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 344, height: 444)
        let window = FocusRenderWindow(contentRect: NSRect(x: -10000, y: -10000, width: 344, height: 444),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        FocusRenderApplication.focusWindow = window
        window.orderBack(nil)
        return window
    }
    private func close(_ window: NSWindow) { window.contentView = nil; window.close() }
    private func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }
    private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: image) }
        return image
    }
    private func color(_ bitmap: NSBitmapImageRep, point: NSPoint) throws -> NSColor {
        try #require(bitmap.colorAt(x: Int(point.x * CGFloat(bitmap.pixelsWide) / bitmap.size.width),
            y: Int(point.y * CGFloat(bitmap.pixelsHigh) / bitmap.size.height))?.usingColorSpace(.deviceRGB))
    }
    private func distance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.deviceRGB), let rhs = rhs.usingColorSpace(.deviceRGB) else { return 1 }
        return max(abs(lhs.redComponent - rhs.redComponent), abs(lhs.greenComponent - rhs.greenComponent), abs(lhs.blueComponent - rhs.blueComponent))
    }
    private func rect(_ element: NSObject, in host: NSView) -> NSRect {
        host.convert(host.window!.convertFromScreen((element as AnyObject).accessibilityFrame()), from: nil)
    }
    private func focusedRect(_ host: NSView) -> NSRect? {
        let selector = NSSelectorFromString("accessibilityFocusedUIElement")
        guard host.responds(to: selector), let focused = host.perform(selector)?.takeUnretainedValue() as? NSObject else { return nil }
        return rect(focused, in: host)
    }
    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, window: NSWindow) throws {
        try sendMarkdownMouseEvents([mouseEvent(type, at: point, window: window)], in: window)
    }
    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, window: NSWindow) throws -> NSEvent {
        let point = window.contentView!.convert(point, to: nil)
        return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: type == .leftMouseDown ? 1 : 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }
    private func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        window.sendEvent(event)
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

@MainActor private final class FocusRenderWindow: NSWindow {
    override var mouseLocationOutsideOfEventStream: NSPoint {
        markdownTrackingMouseLocation(in: self) ?? super.mouseLocationOutsideOfEventStream
    }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

/// OS のアプリの入力先は変えず、このテストプロセス内の描画条件だけを満たす。
@MainActor private final class FocusRenderApplication: NSApplication {
    static var focusWindow: NSWindow?
    override var isActive: Bool { true }
    override var keyWindow: NSWindow? { Self.focusWindow }
    override var mainWindow: NSWindow? { Self.focusWindow }
}
