import AppKit
import SwiftUI
import AgentDomain
import DesignSystem
import Testing
@testable import DashboardFeature

@Suite("ヘッダーの開閉操作") @MainActor
struct ToolbarInteractionTests {
    @Test("開閉操作は日英で独立した名前と選択状態を持つ", arguments: ["ja", "en"], [false, true])
    func independentLabelsAndSelection(language: String, light: Bool) async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let root = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(root) }
        let strings = try DesignSnapshotRenderTests().localizationBundle(fixtures: root)
        let preferences = UserDefaults.standard
        let savedArguments = preferences.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = savedArguments
        let theme = light ? AppTheme.phloxLight : AppTheme.phlox
        arguments[ThemeStore.themeKey] = theme.id
        preferences.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        defer {
            preferences.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = previousAppearance
        }
        #expect(ThemeStore.active.id == theme.id)
        let router = AppRouter(), state = BottomPanelState()
        router.selectProject(ProjectID())
        router.inspectorVisible = false
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }))
        let controller = NSHostingController(rootView: Color.clear.frame(width: 800, height: 100)
            .toolbar { DashboardToolbar(viewModel: dashboard, router: router, changeCount: 0, bottomPanel: state) }
            .environment(\.locale, Locale(identifier: language))
            .environment(\.localizationBundle, strings)
            .environment(\.colorScheme, light ? .light : .dark))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 100),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        window.contentViewController = controller
        defer { window.contentViewController = nil; window.contentView = nil; window.close() }
        func check(bottom bottomVisible: Bool, inspector inspectorVisible: Bool) async throws {
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutSubtreeIfNeeded()
            for (identifier, label, visible) in [
                ("bottom-panel-toggle", language == "ja" ? "下部パネル（⌘J）" : "Bottom panel (⌘J)", bottomVisible),
                ("inspector-toggle", language == "ja" ? "インスペクタ（⌃⌘I）" : "Inspector (⌃⌘I)", inspectorVisible)
            ] {
                let button = try #require(IntegrationFixAccessibility.find(identifier, in: window))
                #expect((button as AnyObject).accessibilityLabel() == label)
                #expect((button as AnyObject).accessibilityRole() == NSAccessibility.Role.checkBox)
                let value = button.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? NSNumber
                #expect(value?.boolValue == visible)
            }
            #expect(state.isVisible == bottomVisible)
            #expect(router.inspectorVisible == inspectorVisible)
            if ProcessInfo.processInfo.environment["PHLOX_INTEGRATION_FIX_SNAPSHOTS"] == "1" {
                let frame = try #require(window.contentView?.superview)
                try IntegrationFixImage.write(frame, name: "toolbar-bottom-\(bottomVisible)-inspector-\(inspectorVisible)-\(light ? "light" : "dark")-\(language)")
            }
        }
        func press(_ identifier: String) throws {
            let button = try #require(IntegrationFixAccessibility.find(identifier, in: window))
            #expect((button as AnyObject).accessibilityPerformPress())
        }
        try await check(bottom: false, inspector: false)
        try press("bottom-panel-toggle")
        try await check(bottom: true, inspector: false)
        try press("inspector-toggle")
        try await check(bottom: true, inspector: true)
        try press("bottom-panel-toggle")
        try await check(bottom: false, inspector: true)
        try press("inspector-toggle")
        try await check(bottom: false, inspector: false)
    }
}

@MainActor enum IntegrationFixAccessibility {
    static func find(_ identifier: String, in root: NSObject) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                for child in values { if let found = visit(child) { return found } }
            }
            if let view = object as? NSView {
                for child in view.subviews { if let found = visit(child) { return found } }
            }
            let id = NSSelectorFromString("accessibilityIdentifier")
            if object.responds(to: id), object.perform(id)?.takeUnretainedValue() as? String == identifier { return object }
            return nil
        }
        return visit(root)
    }
}

@MainActor enum IntegrationFixImage {
    static func write(_ view: NSView, name: String) throws {
        guard ProcessInfo.processInfo.environment["PHLOX_INTEGRATION_FIX_SNAPSHOTS"] == "1" else { return }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".build/integration-fix-snapshots")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
