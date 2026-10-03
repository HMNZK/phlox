import AgentDomain
import AppKit
import DesignSystem
import IOSurface
import SimulatorBridgeKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorTabPresentationTests {
    @Test(arguments: ["未確認", "表示のみ", "版不一致", "読み込み失敗", "起動失敗", "未登録の版不一致", "未登録の読み込み失敗"])
    func 非対応と表示のみのタブを画面へ出さず描画する(state: String) async throws {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        defer { app.setActivationPolicy(previousPolicy) }
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            if state == "未確認" { connection.policy = SimulatorPolicy(entries: []) }
            if state == "表示のみ" {
                connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "17C52", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", supportsInput: false)])
            }
            return connection
        }
        await hub.refresh()
        let session = SessionID()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: session, isFocused: true)
            .frame(width: 520, height: 600).background(DSColor.background))
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        let window = shownWindow(view)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await waitUntil { hub.connection(for: session) != nil }
        let connection = try #require(hub.connection(for: session))
        if state == "起動失敗" {
            fake.failed?("補助プロセスを起動できません")
            fake.failed?("補助プロセスを起動できません")
        } else if state.contains("版不一致") || state.contains("読み込み失敗") {
            fake.probeReply?(SimulatorBridgeCapability(protocolVersion: state.contains("版不一致") ? 999 : SimulatorBridgeInterfaces.protocolVersion,
                                                      helperBuild: "検証", xcodeBuild: state.hasPrefix("未登録") ? "未登録" : "17C52",
                                                      coreSimulatorLoaded: !state.contains("読み込み失敗"), simulatorKitLoaded: !state.contains("読み込み失敗")))
        } else {
            fake.complete(udid: "端末A", generation: connection.generation.current)
        }
        try await Task.sleep(for: .milliseconds(30))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
        let screens = descendants(view).compactMap { $0 as? SimulatorScreenNSView }
        #expect(screens.count == (state == "表示のみ" ? 1 : 0))
        #expect(screens.allSatisfy { !$0.acceptsFirstResponder })
        #expect(fake.inputs == 0)
        #expect(state == "表示のみ" ? connection.reason == nil : connection.reason != nil)
        let snapshot = accessibilitySnapshot(view)
        let reason = state == "未確認" ? "未確認の組み合わせです"
            : state.contains("版不一致") ? "通信仕様の版が異なります。アプリを再起動してください"
            : state.contains("読み込み失敗") ? "画面取得の部品を読み込めません"
            : state == "起動失敗" ? "補助プロセスを起動できません" : nil
        if let reason {
            #expect(connection.reason == reason)
            let title = state == "未確認" ? "この組み合わせはまだ動作を確認していません"
                : state.contains("版不一致") ? "Phlox を再起動してください"
                : state.contains("読み込み失敗") ? "画面取得の部品を読み込めません"
                : "シミュレーターの補助プロセスに接続できません"
            #expect(snapshot.text.contains(title))
        }
        #expect(snapshot.identifiers.contains("simulator-open-external") == (state != "表示のみ"))
        #expect(snapshot.text.contains("Simulator.app で開く") == (state != "表示のみ"))
        #expect(snapshot.identifiers.contains("simulator-try-unverified") == (state == "未確認"))
        #expect(snapshot.text.contains("未確認でも試す") == (state == "未確認"))
        #expect(snapshot.identifiers.contains("simulator-reconnect") == (state == "起動失敗"))
        #expect(snapshot.text.contains("再接続") == (state == "起動失敗"))
        if state == "表示のみ" {
            #expect(snapshot.textByIdentifier["simulator-support-band"] == "表示のみ（入力は未確認）")
            #expect(snapshot.enabled["simulator-home"] == false)
        }
        if let path = ProcessInfo.processInfo.environment["PHLOX_SIMULATOR_RENDER_DIR"] {
            let data = try #require(image.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("状態-\(state).png"))
        }
    }

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

    @Test func フレーム更新を観測対象から外しても診断文言は毎秒読み直す() async throws {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        defer { app.setActivationPolicy(previousPolicy) }
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: session, isFocused: true)
            .frame(width: 520, height: 600))
        let window = shownWindow(view)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await waitUntil { hub.connection(for: session) != nil }
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        let info = try #require(connection.displayInfo)
        #expect(IOSurfaceLock(info.surface, [], nil) == 0)
        #expect(IOSurfaceUnlock(info.surface, [], nil) == 0)
        connection.observeFrame(info, seed: IOSurfaceGetSeed(info.surface), at: Date().addingTimeInterval(-6))
        let message = "しばらく画面の更新を観測していません"
        // 1秒周期の次の描画とイベント配送を、1.5秒の上限内で待つ。
        func waitForDiagnostic(_ visible: Bool) async throws {
            let deadline = ContinuousClock.now + .milliseconds(1500)
            while ContinuousClock.now < deadline {
                view.layoutSubtreeIfNeeded()
                if accessibilitySnapshot(view).text.contains(message) == visible { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            Issue.record("1.5秒以内に診断文言が\(visible ? "表示" : "非表示")になりませんでした")
        }
        try await waitForDiagnostic(true)
        #expect(IOSurfaceLock(info.surface, [], nil) == 0)
        #expect(IOSurfaceUnlock(info.surface, [], nil) == 0)
        connection.observeFrame(info, seed: IOSurfaceGetSeed(info.surface))
        #expect(accessibilitySnapshot(view).text.contains(message))
        try await waitForDiagnostic(false)
        #expect(fake.inputs == 0)
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
        let snapshot = accessibilitySnapshot(view)
        #expect(snapshot.enabled["simulator-boot"] == true)
        #expect((snapshot.frames["simulator-boot"]?.width ?? 0) >= 30, "320pt でも起動ボタンの文言が収まる")
        #expect(!snapshot.text.contains("キー入力はまだ送っていません"))
        #expect(!snapshot.identifiers.contains("simulator-diagnostics"))
        #expect(await fixture.mutations().isEmpty)
        // 実行時に指定された worktree 内へ検証画像を残す。
        if let path = ProcessInfo.processInfo.environment["PHLOX_SIMULATOR_RENDER_DIR"] {
            let data = try #require(image.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("停止端末-\(Int(width)).png"))
        }
        hub.disconnectAll()
    }

    @Test func 一覧取得エラーの題を本文へ重ねず原因を残す() async throws {
        let catalog = SimulatorCatalog(isXcodeAvailable: { true }) { _, _ in
            .init(status: 42, output: Data(), errorOutput: Data("CoreSimulator への接続失敗".utf8))
        }
        let hub = SimulatorHub(catalog: catalog)
        await hub.refresh()
        let view = NSHostingView(rootView: SimulatorTabView(hub: hub, sessionID: SessionID(), isFocused: false)
            .frame(width: 520, height: 600))
        let window = shownWindow(view)
        defer { window.contentView = nil; window.close(); hub.disconnectAll() }
        try await Task.sleep(for: .milliseconds(30))
        view.layoutSubtreeIfNeeded()
        let snapshot = accessibilitySnapshot(view)
        #expect(snapshot.text.filter { $0.contains("端末一覧を取得できません") }.count == 1)
        #expect(snapshot.text.contains { $0.contains("CoreSimulator への接続失敗") && $0.contains("42") })
    }

    @Test func 狭い帯では版と状態の文字を縮め端末名と読み上げを保つ() {
        let menu = SimulatorDevicePopUpButton(frame: .zero, pullsDown: false)
        let coordinator = SimulatorDeviceMenu.Coordinator(select: { _ in }, failed: { _ in })
        let device = SimulatorDevice(udid: "専用端末", name: "iPhone 17 Pro", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", state: "Booted")
        coordinator.configure(menu, devices: [device], selected: device.udid)
        #expect(menu.selectedItem?.representedObject as? String == device.udid)
        #expect(menu.selectedItem?.attributedTitle?.string == "iPhone 17 Pro\tiOS 26.2")
        #expect(menu.itemArray.first?.title == "起動中")
        #expect(menu.selectedItem?.image != nil)
        let fullWidth = menu.intrinsicContentSize.width
        coordinator.configure(menu, devices: [device], selected: device.udid, compact: true)
        #expect(menu.device?.name == device.name)
        #expect(menu.compact)
        #expect(menu.intrinsicContentSize.width < fullWidth)
        #expect(menu.accessibilityLabel() == "端末の選択: iPhone 17 Pro、起動済み")
        coordinator.configure(menu, devices: [], selected: nil, compact: true)
        #expect(menu.selectedItem?.title == "端末なし")
    }

    @Test(arguments: [320.0, 520.0], ["停止中", "入力中", "更新なし", "更新なし入力中", "未確認", "未確認入力中", "未確認更新なし入力中", "表示のみ"])
    func 長い端末名と状態が重なっても帯の操作を収める(width: Double, state: String) async throws {
        _ = NSApplication.shared
        let name = "iPad Pro 13-inch (M4)"
        let fixture = HubCatalogFixture(states: [name: state == "停止中" ? "Shutdown" : "Booted"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            if state == "表示のみ" {
                connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "17C52",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", supportsInput: false)])
            }
            return connection
        }
        await hub.refresh()
        let session = SessionID(), displayID = UUID()
        hub.setVisible(true, displayID: displayID, sessionID: session)
        defer { hub.disconnectAll() }
        if let connection = hub.connection(for: session) {
            if state.contains("未確認") {
                fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                    helperBuild: "検証", xcodeBuild: "未登録", coreSimulatorLoaded: true, simulatorKitLoaded: true))
                hub.tryUnverified(displayID: displayID)
                fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                    helperBuild: "検証", xcodeBuild: "未登録", coreSimulatorLoaded: true, simulatorKitLoaded: true))
                let surface = try #require(IOSurface(properties: [.width: 4, .height: 8, .bytesPerElement: 4,
                    .bytesPerRow: 16, .allocSize: 128, .pixelFormat: 0x42475241]))
                fake.attachReply?(SimulatorDisplayInfo(udid: name, connectionGeneration: connection.generation.current,
                    displayGeneration: 1, surface: surface, pixelWidth: 4, pixelHeight: 8,
                    orientation: .portrait, surfaceIsRotated: false, pixelFormat: 0x42475241), nil)
                #expect(hub.support(for: session, displayID: displayID) == .unverified)
            } else { fake.complete(udid: name, generation: connection.generation.current) }
            if state.contains("更新なし"), let info = connection.displayInfo {
                try #require(IOSurfaceLock(info.surface, [], nil) == 0)
                try #require(IOSurfaceUnlock(info.surface, [], nil) == 0)
                connection.observeFrame(info, seed: IOSurfaceGetSeed(info.surface), at: Date().addingTimeInterval(-6))
            }
        }
        let view = NSHostingView(rootView: SimulatorTabContent(hub: hub, sessionID: session, displayID: displayID,
            sendsKeys: .constant(state.contains("入力中")), showsDiagnostics: .constant(false),
            select: { _ in }, releaseFocus: {}, screenshot: {}, shutdown: {}, openSimulator: {})
            .frame(width: width, height: 600))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(30))
        view.layoutSubtreeIfNeeded()
        let menu = try #require(descendants(view).compactMap { $0 as? SimulatorDevicePopUpButton }.first)
        let menuFrame = view.convert(menu.bounds, from: menu)
        #expect(menuFrame.minX >= 0 && menuFrame.maxX <= width)
        #expect(menu.device?.name == name)
        #expect(menu.toolTip?.contains(name) == true)
        if width == 520 && ["未確認", "更新なし"].contains(state) {
            #expect(!menu.compact, "文言を縮めれば収まる幅では iOS の版を残す")
        }
        let snapshot = accessibilitySnapshot(view)
        let bounds = window.convertToScreen(view.bounds)
        var identifiers = ["simulator-home", "simulator-screenshot", "simulator-shutdown"]
        if state == "停止中" { identifiers.append("simulator-boot") }
        if state.contains("入力中") { identifiers.append("simulator-input-band") }
        if state.contains("未確認") || state == "表示のみ" { identifiers.append("simulator-support-band") }
        if state.contains("更新なし") { identifiers.append("simulator-diagnostics") }
        if state.contains("更新なし") {
            let fullText = "しばらく画面の更新を観測していません"
            #expect(snapshot.text.contains(fullText), "印だけの帯でも診断の全文を読み上げられる")
            #expect(snapshot.help.contains(fullText), "印だけの帯でも診断の全文をツールチップに残す")
        }
        for identifier in identifiers {
            let frame = try #require(snapshot.frames[identifier])
            #expect(frame.width >= (identifier == "simulator-boot" ? 30 : 10))
            #expect(frame.minX >= bounds.minX && frame.maxX <= bounds.maxX, "\(identifier) が帯に収まる")
            #expect(frame.minX >= window.convertToScreen(menuFrame).maxX, "端末名と重ならない")
        }
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
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

    private func accessibilitySnapshot(_ hosting: NSView) -> (text: Set<String>, help: Set<String>, identifiers: Set<String>, textByIdentifier: [String: String], enabled: [String: Bool], frames: [String: NSRect]) {
        var text = Set<String>()
        var help = Set<String>()
        var identifiers = Set<String>()
        var textByIdentifier: [String: String] = [:]
        var enabled: [String: Bool] = [:]
        var frames: [String: NSRect] = [:]
        var seen = Set<ObjectIdentifier>()
        func visit(_ element: Any) {
            let object = element as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let identifier = object.accessibilityIdentifier() {
                identifiers.insert(identifier)
                textByIdentifier[identifier] = object.accessibilityLabel() ?? object.accessibilityValue()
                enabled[identifier] = object.isAccessibilityEnabled()
                frames[identifier] = object.accessibilityFrame()
            }
            for value in [object.accessibilityLabel(), object.accessibilityValue()] {
                if let value { text.insert(value) }
            }
            if let value = object.accessibilityHelp() { help.insert(value) }
            if let children = object.accessibilityChildren() { children.forEach(visit) }
            if let view = element as? NSView { view.subviews.forEach(visit) }
        }
        visit(hosting)
        return (text, help, identifiers, textByIdentifier, enabled, frames)
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
