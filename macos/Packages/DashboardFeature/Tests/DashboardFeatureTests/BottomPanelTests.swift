import AppKit
import AgentDomain
import DesignSystem
import PTYKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("下部パネル") @MainActor
struct BottomPanelTests {
    private let defaultsSuite = "BottomPanelTests.\(UUID().uuidString)"
    private func defaults() -> UserDefaults {
        // 他のテストや実アプリと保存値を共有しない。
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        return defaults
    }

    @Test("高さの上限・下限と狭い中央でも上の内容を保つ", arguments: [
        (CGFloat(1000), CGFloat(900), CGFloat(700)),
        (600, 900, 400), (600, 10, 120), (600, 300, 300),
        (320, 300, 120), (250, 300, 50), (100, 300, 0), (0, 300, 0)
    ])
    func heightBounds(_ values: (CGFloat, CGFloat, CGFloat)) {
        #expect(BottomPanelLayout.clamped(values.1, availableHeight: values.0) == values.2)
    }

    @Test("高さは保存して次の状態に復元し、窓縮小では保存値を変えない")
    func persistedHeight() {
        let preferences = defaults()
        defer { preferences.removePersistentDomain(forName: defaultsSuite) }
        let first = BottomPanelState(defaults: preferences)
        #expect(first.preferredHeight == 280)
        first.saveHeight(300, availableHeight: 800)
        #expect(preferences.double(forKey: BottomPanelState.heightKey) == 300)
        let restored = BottomPanelState(defaults: preferences)
        #expect(restored.preferredHeight == 300)
        #expect(BottomPanelLayout.clamped(restored.preferredHeight, availableHeight: 400) == 200)
        #expect(restored.preferredHeight == 300)
    }

    @Test("選択がないと開閉せず、プロジェクトを替えてもウィンドウの開閉状態を保つ")
    func windowVisibility() {
        let state = BottomPanelState(defaults: defaults())
        state.toggle(projectID: nil, window: nil)
        #expect(!state.isVisible)
        state.toggle(projectID: ProjectID(), window: nil)
        #expect(state.isVisible)
        // 別のプロジェクトでも同じ状態に対する開閉。
        state.toggle(projectID: ProjectID(), window: nil)
        #expect(!state.isVisible)
    }

    @Test("グリッドでは選択タイルのプロジェクトを優先する")
    func gridTarget() {
        let tab = ProjectID(), tile = ProjectID()
        #expect(BottomPanelState.targetProjectID(mode: .grid, selectedProjectID: tab, selectedTileProjectID: tile) == tile)
        #expect(BottomPanelState.targetProjectID(mode: .single, selectedProjectID: tab, selectedTileProjectID: tile) == tab)
        #expect(BottomPanelState.targetProjectID(mode: .grid, selectedProjectID: nil, selectedTileProjectID: nil) == nil)
    }

    @Test("閉じると開く直前の同じウィンドウの入力先へ戻す")
    func focusReturn() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let terminal = NSTextView(frame: NSRect(x: 0, y: 100, width: 200, height: 100))
        let content = NSView(frame: window.contentView!.bounds)
        content.addSubview(input); content.addSubview(terminal); window.contentView = content
        #expect(window.makeFirstResponder(input))
        let state = BottomPanelState(defaults: defaults())
        state.toggle(projectID: ProjectID(), window: window)
        #expect(window.makeFirstResponder(terminal))
        // 既に開いているときの再起動要求で戻り先を上書きしない。
        state.open(window: window)
        state.close()
        #expect(window.firstResponder === input)
        state.open(window: window)
        input.removeFromSuperview()
        window.makeFirstResponder(terminal)
        state.close()
        #expect(window.firstResponder === terminal)
    }

    @Test("初回だけ起動し、閉じても所有者・画面・履歴が残り、プロジェクト終了で止める")
    func projectOwnershipAndRestart() async throws {
        let pty = MockPTYManager()
        let store = makeStore(pty)
        defer { Task { await store.shutdownAll() } }
        let a = ProjectID(), b = ProjectID()
        #expect(!store.canRestartBottomTerminal(for: a))
        #expect(store.existingBottomTerminal(for: b) == nil)
        let first = store.bottomTerminal(for: a, workingDirectory: "/tmp/project-a")
        #expect(pty.spawnCalls.isEmpty)
        #expect(!store.canRestartBottomTerminal(for: a))
        try await first.controller.ensureStarted()
        first.terminalCoordinator.feed(Data("echo a\r\na\r\n".utf8))
        let screen = first.terminalCoordinator.ansiScreenText()
        let state = BottomPanelState(defaults: defaults())
        state.open(window: nil); state.close(); state.open(window: nil)
        let reopened = store.bottomTerminal(for: a, workingDirectory: "/tmp/project-a")
        #expect(reopened === first)
        #expect(reopened.terminalCoordinator.ansiScreenText() == screen)
        #expect(first.controller.isRunning)
        #expect(pty.spawnCalls.count == 1)
        #expect(store.canRestartBottomTerminal(for: a))
        let second = store.bottomTerminal(for: b, workingDirectory: "/tmp/project-b")
        #expect(second !== first)
        pty.setSpawnSessionID(SessionID())
        try await second.controller.ensureStarted()
        #expect(pty.spawnCalls.map(\.workingDirectory) == ["/tmp/project-a", "/tmp/project-b"])
        #expect(store.bottomTerminal(for: a, workingDirectory: "/tmp/project-a") === first)
        await store.closeProject(a)
        #expect(!first.controller.isRunning)
        #expect(second.controller.isRunning)
        #expect(!store.canRestartBottomTerminal(for: a))
        await store.shutdownAll()
        #expect(!second.controller.isRunning)
        #expect(store.existingBottomTerminal(for: b) == nil)
    }

    @Test("終了後は開き直しても起動せず、明示再起動は閉じていても可能")
    func exitedShell() async throws {
        let pty = MockPTYManager(), project = ProjectID()
        let store = makeStore(pty)
        let panel = store.bottomTerminal(for: project, workingDirectory: "/tmp")
        defer { Task { await store.shutdownAll() } }
        try await panel.controller.ensureStarted()
        let id = try #require(panel.controller.sessionID)
        pty.finishOutput(for: id)
        pty.emitExit(for: id, code: 7)
        let deadline = ContinuousClock.now + .seconds(1)
        while panel.controller.isRunning, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!panel.controller.isRunning)
        #expect(panel.controller.exitCode == 7)
        #expect(store.bottomTerminal(for: project, workingDirectory: "/tmp") === panel)
        await panel.ensureBottomStarted()
        #expect(pty.spawnCalls.count == 1)
        #expect(store.canRestartBottomTerminal(for: project))
        let state = BottomPanelState(defaults: defaults())
        #expect(!state.isVisible)
        state.open(window: nil)
        try await panel.controller.restart()
        #expect(state.isVisible)
        #expect(panel.controller.isRunning)
        #expect(panel.controller.exitCode == nil)
        #expect(pty.spawnCalls.count == 2)
    }

    private func makeStore(_ pty: MockPTYManager) -> ProjectTerminalStore {
        ProjectTerminalStore { directory in
            TerminalPanelSession(controller: UserTerminalController(pty: pty, shellPath: "/bin/sh", workingDirectory: directory, environment: [:]))
        }
    }

    @Test("2ウィンドウで開閉状態を分離し、子タブと同じ単一表示器で本文200ptを残す")
    func twoWindowsAndContentHeight() async throws {
        _ = NSApplication.shared
        let root = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let project = Project(name: "Panel", directoryPath: root.path, createdAt: Date(), isManagedDirectory: false)
        let projects = InMemoryProjectStore()
        try await projects.save([project])
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }, projects: projects, workspaceDirectory: root))
        await dashboard.start()
        let router = AppRouter(sidebarVisible: false)
        router.selectedProjectID = project.id
        let preferences = defaults()
        defer { preferences.removePersistentDomain(forName: defaultsSuite) }
        preferences.set(true, forKey: UsageSettings.showInHeaderKey)
        preferences.set(17.0, forKey: TerminalFontSettings.fontSizeKey)
        let first = BottomPanelState(defaults: preferences), second = BottomPanelState(defaults: preferences)
        first.saveHeight(9999, availableHeight: 9999)
        let pty = MockPTYManager(), store = makeStore(pty)
        let monitor = UsageMonitor(providers: [.codex: BottomPanelUsageProvider()])
        await monitor.refresh()
        #expect(!UsageDisplay.bottomBarGroups(usages: monitor.usages, showUnavailable: false).isEmpty)
        let windows = [first, second].map { state in
            let view = DashboardView(viewModel: dashboard, router: router, usageMonitor: monitor, sessionTerminals: store, bottomPanel: state)
                .defaultAppStorage(preferences)
                .frame(width: 1000, height: 600)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            return window
        }
        defer {
            for window in windows { window.contentView = nil; window.close() }
            Task { await store.shutdownAll() }
        }
        #expect(store.existingBottomTerminal(for: project.id) == nil)
        first.open(window: windows[0])
        try await eventually { store.existingBottomTerminal(for: project.id)?.controller.isRunning == true }
        let a = store.bottomTerminal(for: project.id, workingDirectory: root.path)
        try await eventually { a.terminalCoordinator.terminalView.window === windows[0] }
        let expectedFontSize = TerminalFontSettings.currentSize(defaults: preferences)
        try await eventually { a.terminalCoordinator.terminalView.font.pointSize == expectedFontSize }
        #expect(a.terminalCoordinator.terminalView.font.pointSize == expectedFontSize)
        print("下部パネルの実測文字サイズ: \(a.terminalCoordinator.terminalView.font.pointSize)pt、専用設定: \(expectedFontSize)pt、システム既定: \(NSFont.systemFontSize)pt")
        #expect(first.isVisible)
        #expect(!second.isVisible)
        windows[0].contentView?.layoutSubtreeIfNeeded()
        let bodyHeight = CGFloat(600) - DSLayout.usageBarHeight - DSLayout.tabBarHeight - DSLayout.childTabBarHeight
        let expected = BottomPanelLayout.maximumHeight(availableHeight: bodyHeight)
        let actual = a.terminalCoordinator.hostingView.bounds.height + DSLayout.bottomPanelHeaderHeight + DSSpacing.s
        #expect(abs(actual - expected) < 1)
        #expect(bodyHeight - actual >= 199.5)
        #expect(actual <= bodyHeight * DSLayout.bottomPanelMaximumFraction)
        second.open(window: windows[1])
        let b = store.bottomTerminal(for: project.id, workingDirectory: root.path)
        try await eventually { b.terminalCoordinator.terminalView.window === windows[1] }
        #expect(a.controller === b.controller)
        #expect(a === b)
        #expect(a.terminalCoordinator === b.terminalCoordinator)
        #expect(a.terminalCoordinator.terminalView.window === windows[1])
        #expect(pty.spawnCalls.count == 1)
        let id = try #require(a.controller.sessionID)
        pty.emitOutput(for: id, data: Data("echo shared\r\nshared-output\r\n".utf8))
        try await eventually {
            a.terminalCoordinator.visibleText().contains("shared-output") && b.terminalCoordinator.visibleText().contains("shared-output")
        }
        first.close()
        try await eventually { !first.isTerminalFocused }
        #expect(b.terminalCoordinator.onFocusChange != nil)
        windows[1].makeFirstResponder(nil)
        try await eventually { !second.isTerminalFocused }
        windows[1].makeFirstResponder(b.terminalCoordinator.terminalView)
        try await eventually { second.isTerminalFocused }
        #expect(second.isVisible)
        #expect(b.controller.isRunning)
        #expect(a.terminalCoordinator.terminalView.window === windows[1])
        // 子タブと同じく、有効な所有者から旧 mount は奪い返さない。
        // 所有中のパネルを閉じて解放してから、元の窓で再表示する。
        second.close()
        try await eventually { a.terminalCoordinator.terminalView.window == nil }
        #expect(a.controller.isRunning)
        first.open(window: windows[0])
        try await eventually { a.terminalCoordinator.terminalView.window === windows[0] }
        try await eventually { first.isTerminalFocused }
        second.open(window: windows[1])
        try await eventually { a.terminalCoordinator.terminalView.window === windows[1] }
        try await eventually { !first.isTerminalFocused && second.isTerminalFocused }
        second.close()
        // 開いたままの最初のパネルへの自動再アタッチでも通知先を更新する。
        try await eventually { a.terminalCoordinator.terminalView.window === windows[0] }
        #expect(a.terminalCoordinator.onFocusChange != nil)
        windows[0].makeFirstResponder(nil)
        try await eventually { !first.isTerminalFocused }
        windows[0].makeFirstResponder(a.terminalCoordinator.terminalView)
        try await eventually { first.isTerminalFocused }
        #expect(store.bottomTerminal(for: project.id, workingDirectory: root.path) === a)
        #expect(a.terminalCoordinator.visibleText().contains("shared-output"))
        #expect(pty.spawnCalls.count == 1)
        await store.closeProject(project.id)
        #expect(!a.controller.isRunning)
        #expect(!b.controller.isRunning)
    }

    private func eventually(line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw BottomPanelTestTimeout(line: line) }
            await Task.yield()
        }
    }

    @Test("全体画像のウィンドウに標準タイトルバーと開閉操作を載せる")
    func snapshotWindowIncludesToolbar() async throws {
        _ = NSApplication.shared
        let previousAccessibility = try enableAccessibility()
        defer { NSApp.accessibilitySetValue(previousAccessibility, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }))
        let monitor = UsageMonitor(providers: [.codex: BottomPanelUsageProvider()])
        let window = DesignSnapshotRenderTests().makeSnapshotWindow(
            DashboardView(viewModel: dashboard, router: AppRouter(), usageMonitor: monitor).frame(width: 1600, height: 1000),
            id: "13-bp-window-open-dark-ja", width: 1600, height: 1000)
        defer { window.contentViewController = nil; window.contentView = nil; window.close() }
        try await eventually { window.toolbar != nil }
        #expect(window.styleMask.contains(.titled))
        let host = try #require(window.contentView)
        #expect(window.contentView?.superview?.bounds.height ?? 0 > host.bounds.height)
        try await eventually { accessibleFrame(identifier: "bottom-panel-toggle", in: window) != nil }
        let toggle = try #require(accessibleFrame(identifier: "bottom-panel-toggle", in: window))
        #expect(toggle.width > 0 && toggle.height > 0)
        #expect(!window.isVisible)
    }

    @Test("900ptの英語の注意表示でも再起動と閉じる操作が見出し内に収まる")
    func narrowEnglishWarningKeepsHeaderActions() async throws {
        _ = NSApplication.shared
        let previousAccessibility = try enableAccessibility()
        defer { NSApp.accessibilitySetValue(previousAccessibility, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        let root = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let bundle = try DesignSnapshotRenderTests().localizationBundle(fixtures: root)
        let panel = TerminalPanelSession(controller: UserTerminalController(
            pty: MockPTYManager(), shellPath: "/bin/zsh", workingDirectory: "/Users/ryosuke/Projects/Phlox-oss", environment: [:],
            resolveShell: { UserShellResolution(path: "/bin/zsh", unavailablePath: "/opt/homebrew/bin/fish") }))
        try await panel.controller.ensureStarted()
        do {
            let state = BottomPanelState()
            state.open(window: nil)
            let window = DesignSnapshotRenderTests().makeSnapshotWindow(
                BottomPanelView(panel: panel, state: state)
                    .environment(\.localizationBundle, bundle).environment(\.locale, Locale(identifier: "en"))
                    .frame(width: 900, height: 300),
                id: "13-bp-shell-warning-dark-en", width: 900, height: 300)
            defer { window.contentViewController = nil; window.contentView = nil; window.close() }
            try await eventually { accessibleFrame(identifier: "bottom-panel-shell-warning", in: window) != nil }
            window.contentView?.layoutSubtreeIfNeeded()
            let header = try #require(accessibleFrame(identifier: "bottom-panel-header", in: window))
            let warning = try #require(accessibleFrame(identifier: "bottom-panel-shell-warning", in: window))
            let host = try #require(window.contentView)
            #expect(warning.width > 0 && warning.height > 0)
            #expect(host.bounds.width == 900)
            for identifier in ["bottom-panel-restart", "bottom-panel-close"] {
                let action = try #require(accessibleFrame(identifier: identifier, in: window))
                #expect(action.width >= DSLayout.bottomPanelButtonWidth)
                #expect(action.height > 0)
                #expect(header.contains(action))
                #expect(window.convertToScreen(host.bounds).contains(action))
            }
            #expect(!window.isVisible)
        } catch {
            await panel.controller.shutdown()
            throw error
        }
        await panel.controller.shutdown()
    }

    private func enableAccessibility() throws -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        try #require(NSApp.responds(to: selector))
        let previous = NSApp.perform(selector, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        return previous
    }

    private func accessibleFrame(identifier: String, in root: NSObject) -> NSRect? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSRect? {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            let selector = NSSelectorFromString("accessibilityIdentifier")
            if object.responds(to: selector), object.perform(selector)?.takeUnretainedValue() as? String == identifier,
               object.responds(to: NSSelectorFromString("accessibilityFrame")) {
                return (object as AnyObject).accessibilityFrame()
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let elements = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                for child in elements { if let frame = visit(child) { return frame } }
            }
            if let window = object as? NSWindow, let view = window.contentView?.superview,
               let frame = visit(view) { return frame }
            if let view = object as? NSView {
                for child in view.subviews { if let frame = visit(child) { return frame } }
            }
            return nil
        }
        return visit(root)
    }

    @Test("代替したシェルの注意は設定を変更しても次の再起動まで残す")
    func fallbackWarningUntilRestart() async throws {
        let pty = MockPTYManager()
        var resolution = UserShellResolution(path: "/bin/zsh", unavailablePath: "/missing/fish")
        let panel = TerminalPanelSession(controller: UserTerminalController(
            pty: pty, shellPath: "/bin/zsh", workingDirectory: "/tmp", environment: [:], resolveShell: { resolution }))
        defer { Task { await panel.controller.shutdown() } }
        await panel.ensureBottomStarted()
        #expect(panel.controller.shellResolution?.unavailablePath == "/missing/fish")
        resolution = UserShellResolution(path: "/bin/bash")
        await panel.ensureBottomStarted()
        #expect(panel.controller.shellResolution?.unavailablePath == "/missing/fish")
        try await panel.controller.restart()
        #expect(panel.controller.shellResolution?.path == "/bin/bash")
        #expect(panel.controller.shellResolution?.unavailablePath == nil)
        #expect(pty.spawnCalls.map { $0.env["SHELL"] } == ["/bin/zsh", "/bin/bash"])
    }

    @Test("同じプロジェクトは同じセッションと表示器で、カーソル・色・モードを保持する")
    func singleDisplayKeepsTerminalState() {
        let store = makeStore(MockPTYManager()), project = ProjectID()
        let owner = store.bottomTerminal(for: project, workingDirectory: "/tmp")
        owner.terminalCoordinator.feed(Data("one\r\ntwo\r\n\u{1b}[?2004h\u{1b}[?1h\u{1b}[2;3H\u{1b}]10;#ff0000\u{7}".utf8))
        let reopened = store.bottomTerminal(for: project, workingDirectory: "/tmp")
        #expect(reopened === owner)
        #expect(reopened.terminalCoordinator.terminalView === owner.terminalCoordinator.terminalView)
        #expect(reopened.terminalCoordinator.bracketedPasteMode)
        #expect(reopened.terminalCoordinator.terminalView.getTerminal().applicationCursor)
        #expect(reopened.terminalCoordinator.terminalView.getTerminal().buffer.x == 2)
        #expect(reopened.terminalCoordinator.terminalView.getTerminal().buffer.y == 1)
        let foreground = reopened.terminalCoordinator.terminalView.nativeForegroundColor.usingColorSpace(.deviceRGB)
        #expect(foreground == NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        owner.terminalCoordinator.feed(Data("\u{1b}[?1049halt-screen".utf8))
        #expect(reopened.terminalCoordinator.terminalView.getTerminal().isCurrentBufferAlternate)
        #expect(reopened.terminalCoordinator.visibleText().contains("alt-screen"))
        owner.terminalCoordinator.feed(Data("\u{1b}[?1049l".utf8))
        #expect(!reopened.terminalCoordinator.terminalView.getTerminal().isCurrentBufferAlternate)
        #expect(reopened.terminalCoordinator.visibleText().contains("two"))
        reopened.terminalCoordinator.feed(Data("X".utf8))
        #expect(!owner.terminalCoordinator.visibleText().contains("XX"))
    }

    @Test("見出しは日英でシェル・省略しない場所・入力状態を読む", arguments: ["ja", "en"])
    func headerAccessibility(language: String) throws {
        let root = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let bundle = try DesignSnapshotRenderTests().localizationBundle(fixtures: root)
        for focused in [true, false] {
            let label = BottomPanelView.headerAccessibilityLabel(shellPath: "/bin/zsh", workingDirectory: "/tmp/project-with-long-name",
                focused: focused, locale: Locale(identifier: language), bundle: bundle)
            #expect(label == (language == "ja"
                ? "下部パネル、ターミナル、zsh、/tmp/project-with-long-name、\(focused ? "入力中" : "キー入力なし")"
                : "Bottom panel, terminal, zsh, /tmp/project-with-long-name, \(focused ? "Accepting keyboard input" : "Not accepting keyboard input")"))
        }
    }

    @Test("起動・再起動・入力失敗の端末案内は表示言語に従う", arguments: ["ja", "en"])
    func localizedTerminalErrors(language: String) async throws {
        let root = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let bundle = try DesignSnapshotRenderTests().localizationBundle(fixtures: root)
        let suiteName = "BottomPanelTests.localizedTerminalErrors.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(language, forKey: "phlox.appLanguage")
        let pty = MockPTYManager()
        pty.setSpawnErrors([.spawnFailed(errno: 13), .spawnFailed(errno: 13)])
        let panel = TerminalPanelSession(controller: UserTerminalController(pty: pty, shellPath: "/bin/sh", workingDirectory: "/tmp", environment: [:]), localizationBundle: bundle, defaults: preferences)
        defer { Task { await panel.controller.shutdown() } }
        let expectedStart = language == "en" ? "[Could not start the shell]" : "[シェルを開始できませんでした]"
        await panel.ensureBottomStarted()
        #expect(panel.controller.startError != nil)
        #expect(panel.terminalCoordinator.visibleText().contains(expectedStart))
        if language == "en" { #expect(panel.controller.startError?.contains("シェル") == false) }
        panel.terminalCoordinator.resetBuffer()
        await panel.restart()
        #expect(panel.controller.startError != nil)
        #expect(panel.terminalCoordinator.visibleText().contains(expectedStart))
        await panel.restart()
        #expect(panel.controller.isRunning)
        pty.setWriteError(.writeFailed(errno: 5))
        panel.terminalCoordinator.onInput(Data("input".utf8))
        let expectedInput = language == "en" ? "[Could not send terminal input]" : "[ターミナル入力を送信できませんでした]"
        try await eventually { panel.terminalCoordinator.visibleText().contains(expectedInput) }
        if language == "en" { #expect(!panel.terminalCoordinator.visibleText().contains("できませんでした")) }
    }

    @Test("初回起動失敗では再起動メニューを有効にせず、エラーを保持する")
    func failedFirstLaunch() async throws {
        let pty = MockPTYManager()
        pty.setSpawnErrors([.spawnFailed(errno: 13)])
        let store = makeStore(pty), project = ProjectID()
        let panel = store.bottomTerminal(for: project, workingDirectory: "/tmp")
        defer { Task { await store.shutdownAll() } }
        await panel.ensureBottomStarted()
        #expect(!panel.controller.hasStarted)
        #expect(panel.controller.startError != nil)
        #expect(!store.canRestartBottomTerminal(for: project))
        try await panel.controller.restart()
        #expect(panel.controller.hasStarted)
        #expect(panel.controller.startError == nil)
        #expect(store.canRestartBottomTerminal(for: project))
    }

}

private struct BottomPanelTestTimeout: Error {
    let line: UInt
}

private struct BottomPanelUsageProvider: UsageProvider {
    let kind: AgentKind = .codex
    func fetch() async -> CLIUsage {
        CLIUsage(kind: .codex, state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 20)]), updatedAt: .now)
    }
}
