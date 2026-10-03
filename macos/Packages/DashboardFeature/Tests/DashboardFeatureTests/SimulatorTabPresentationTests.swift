import AgentDomain
import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorTabPresentationTests {
    @Test func 起動済みの画面を表示しても初期フォーカスは端末メニューで入力も状態変更も送らない() async throws {
        let fixture = HubCatalogFixture()
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: session, isFocused: true))
        let window = shownWindow(view)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await waitUntil { hub.connection(for: session) != nil }
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        try await waitUntil { descendants(view).contains { $0 is SimulatorScreenNSView } }
        view.layoutSubtreeIfNeeded()
        let screen = try #require(descendants(view).compactMap { $0 as? SimulatorScreenNSView }.first)
        let menu = try #require(descendants(view).compactMap { $0 as? NSPopUpButton }.first)
        #expect(!screen.isHiddenOrHasHiddenAncestor)
        #expect(screen.acceptsFirstResponder)
        #expect(connection.displayInfo != nil)
        #expect(window.firstResponder === menu)
        hub.requestMenuFocus(for: session)
        try await Task.sleep(for: .milliseconds(30))
        #expect(window.firstResponder === menu)
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
    }

    @Test(arguments: [true, false])
    func ホームのショートカットはフォーカスがあるタブだけ一回送る(focused: Bool) async throws {
        let fixture = HubCatalogFixture()
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: session, isFocused: focused))
        let window = shownWindow(view)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await waitUntil { hub.connection(for: session) != nil }
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        try await waitUntil { descendants(view).contains { $0 is SimulatorScreenNSView } }
        view.layoutSubtreeIfNeeded()
        #expect(fake.inputs == 0)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "h", charactersIgnoringModifiers: "h", isARepeat: false, keyCode: 4))
        let handled = view.performKeyEquivalent(with: event)
        #expect(handled == focused)
        // 補助プロセスの契約では 0 がホーム。
        #expect(fake.buttons == (focused ? [0] : []))
        #expect(fake.inputs == (focused ? 1 : 0))
        #expect(await fixture.mutations().isEmpty)
    }

    @Test func タブのビューを取り外すと画面取得を止め接続を解放する() async throws {
        let fixture = HubCatalogFixture()
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: session, isFocused: true))
        let window = shownWindow(view)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await waitUntil { hub.connection(for: session) != nil }
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        try await waitUntil { descendants(view).contains { $0 is SimulatorScreenNSView } }
        #expect(fake.detached.isEmpty)
        #expect(fake.invalidations == 0)
        window.contentView = nil
        try await waitUntil { hub.connection(for: session) == nil }
        #expect(fake.detached == ["端末A"])
        #expect(fake.invalidations == 1)
        #expect(connection.displayInfo == nil)
        #expect(await fixture.mutations().isEmpty)
    }

    private func shownWindow(_ view: NSView) -> VisibilityWindow {
        _ = NSApplication.shared
        let window = VisibilityWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    @Test(arguments: [320.0, 520.0])
    func 停止端末の帯を画面へ出さず描画する(width: Double) async throws {
        let fixture = HubCatalogFixture(states: ["iPhone 17 Pro": "Shutdown"])
        let hub = SimulatorHub(catalog: fixture.catalog())
        await hub.refresh()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: SessionID(), isFocused: true)
            .frame(width: width, height: 600).background(DSColor.background))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(30))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
        let menu = try #require(descendants(view).compactMap { $0 as? NSPopUpButton }.first)
        #expect(window.firstResponder === menu)
        #expect(menu.selectedItem?.title.contains("iPhone 17 Pro") == true)
        #expect(menu.frame.width <= width - 90, "端末名を省略せず帯の操作ボタンを収める")
        #expect(menu.cell?.lineBreakMode != .byTruncatingTail)
        #expect(await fixture.mutations().isEmpty)
        // 実行時に指定された worktree 内へ検証画像を残す。
        if let path = ProcessInfo.processInfo.environment["PHLOX_SIMULATOR_RENDER_DIR"] {
            let data = try #require(image.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("停止端末-\(Int(width)).png"))
        }
        hub.disconnectAll()
    }

    @Test func 狭い帯では版と状態の文字を縮め端末名と読み上げを保つ() {
        let menu = NSPopUpButton(frame: .zero, pullsDown: false)
        let coordinator = SimulatorDeviceMenu.Coordinator(select: { _ in }, failed: { _ in })
        let device = SimulatorDevice(udid: "専用端末", name: "iPhone 17 Pro", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", state: "Booted")
        coordinator.configure(menu, devices: [device], selected: device.udid)
        #expect(menu.selectedItem?.title == "iPhone 17 Pro · iOS 26.2 · 起動済み")
        coordinator.configure(menu, devices: [device], selected: device.udid, compact: true)
        #expect(menu.selectedItem?.title == device.name)
        #expect(menu.accessibilityLabel() == "端末の選択: iPhone 17 Pro、起動済み")
        coordinator.configure(menu, devices: [], selected: nil, compact: true)
        #expect(menu.selectedItem?.title == "端末なし")
    }

    @Test func 最小化とタブ非表示をウィンドウ通知から反映する() async throws {
        _ = NSApplication.shared
        let window = VisibilityWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SimulatorWindowVisibility.VisibilityView()
        var visibility: [Bool] = []
        view.changed = { visibility.append($0) }
        window.contentView = view
        defer { view.stop(); window.close() }
        try await waitUntil { visibility.last == true }
        window.minimized = true
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        try await waitUntil { visibility.last == false }
        window.minimized = false
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        try await waitUntil { visibility.last == true }
        view.isHidden = true
        try await waitUntil { visibility.last == false }
        view.isHidden = false
        try await waitUntil { visibility.last == true }
        window.unobscured = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        try await waitUntil { visibility.last == false }
        window.unobscured = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        try await waitUntil { visibility.last == true }
        let count = visibility.count
        view.stop()
        try await waitUntil { visibility.count == count + 1 }
        #expect(visibility.last == false)
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        try await Task.sleep(for: .milliseconds(30))
        #expect(visibility.count == count + 1)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}

/// 実際のウィンドウを表示・最小化せず、通知の受け取りだけを検査する。
@MainActor private final class VisibilityWindow: NSWindow {
    var minimized = false
    var unobscured = true
    override var isVisible: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMiniaturized: Bool { minimized }
    override var occlusionState: NSWindow.OcclusionState { unobscured ? [.visible] : [] }
}
