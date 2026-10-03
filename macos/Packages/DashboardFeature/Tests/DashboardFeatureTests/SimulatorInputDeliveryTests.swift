import AppKit
import IOSurface
import Testing
import SimulatorBridgeKit
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorInputDeliveryTests {
    @Test func タップと余白へ出たドラッグとスクロールとホームを配送する() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 10, y: 200))
        #expect(fake.inputs.isEmpty)
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 200, y: 200))
        #expect(fake.inputs.isEmpty)
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 500, y: -100))
        view.mouseUp(with: mouse(.leftMouseUp, x: 500, y: -100))
        #expect(fake.inputs == [.touch(0, 0.5, 0.5), .touch(1, 1, 1), .touch(2, 1, 1)])
        let scroll = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                         wheelCount: 2, wheel1: 20, wheel2: 10, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: scroll))
        // scrollWheel の実際の座標変換にはウィンドウ座標のイベントを使う。
        scroll.location = NSPoint(x: 200, y: NSScreen.screens[0].frame.maxY - 200)
        let positioned = try #require(NSEvent(cgEvent: scroll))
        view.scrollWheel(with: positioned)
        #expect(fake.inputs.last == .scroll(event.scrollingDeltaX, event.scrollingDeltaY, 0.5, 0.5))
        connection.sendHome()
        #expect(fake.inputs.last == .home)
    }

    @Test func キー解放を修飾変更後も送りショートカットを除外する() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        view.keyDown(with: key(0))
        view.flagsChanged(with: key(55, flags: [.command, NSEvent.ModifierFlags(rawValue: 0x8)], type: .flagsChanged))
        view.keyUp(with: key(0, flags: .command, type: .keyUp))
        #expect(fake.inputs == [.key(0, 0, true), .key(0, NSEvent.ModifierFlags.command.rawValue, false)])
        for flags: NSEvent.ModifierFlags in [.command, .control, [.control, .shift]] {
            #expect(!view.performKeyEquivalent(with: key(48, flags: flags)))
        }
        #expect(!view.performKeyEquivalent(with: key(1, flags: .command)))
        view.keyDown(with: key(48))
        view.keyDown(with: key(53))
        view.flagsChanged(with: key(56, flags: [.shift, NSEvent.ModifierFlags(rawValue: 0x2)], type: .flagsChanged))
        view.flagsChanged(with: key(56, type: .flagsChanged))
        #expect(Array(fake.inputs.suffix(4)) == [.key(48, 0, true), .key(53, 0, true),
                                                .key(56, NSEvent.ModifierFlags.shift.rawValue | 0x2, true), .key(56, 0, false)])
        view.keyUp(with: key(53, type: .keyUp))
        let releases = fake.releases
        #expect(view.performKeyEquivalent(with: key(53, flags: .command)))
        #expect(window.firstResponder !== view)
        #expect(fake.releases > releases)
        #expect(connection.sentKeyCodes.isEmpty)
    }

    @Test func firstResponder以外と非表示の画面から入力しない() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        window.makeFirstResponder(nil)
        view.keyDown(with: key(0))
        view.keyUp(with: key(0, type: .keyUp))
        view.flagsChanged(with: key(56, flags: .shift, type: .flagsChanged))
        #expect(!view.performKeyEquivalent(with: key(9, flags: .command)))
        #expect(fake.inputs.isEmpty)
        window.makeFirstResponder(view)
        let focusWindow = try #require(window as? InputWindow)
        focusWindow.hasFocus = false
        view.keyDown(with: key(0))
        #expect(fake.inputs.isEmpty)
        focusWindow.hasFocus = true
        let releases = fake.releases
        view.isHidden = true
        #expect(fake.releases > releases)
        view.keyDown(with: key(0))
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        #expect(fake.inputs.isEmpty)
    }

    @Test func 再接続後は古い接触とキーを再送せずCapsLockを一組ずつ送る() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        let old = try #require(connection.displayInfo)
        view.keyDown(with: key(0))
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        fake.failed?("切断")
        connection.attach(udid: "端末")
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                                                   helperBuild: "検証", xcodeBuild: "検証",
                                                   coreSimulatorLoaded: true, simulatorKitLoaded: true))
        let next = SimulatorDisplayInfo(udid: old.udid, connectionGeneration: connection.generation.current,
                                       displayGeneration: 2, surface: old.surface, pixelWidth: 4, pixelHeight: 8,
                                       orientation: .portrait, surfaceIsRotated: false, pixelFormat: old.pixelFormat)
        fake.attachReply?(next, nil)
        view.update(next)
        let count = fake.inputs.count
        view.keyUp(with: key(0, type: .keyUp))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 250, y: 200))
        #expect(fake.inputs.count == count)
        for flags: NSEvent.ModifierFlags in [.capsLock, []] {
            view.flagsChanged(with: key(57, flags: flags, type: .flagsChanged))
        }
        #expect(Array(fake.inputs.suffix(4)) == [.key(57, NSEvent.ModifierFlags.capsLock.rawValue, true),
                                                .key(57, NSEvent.ModifierFlags.capsLock.rawValue, false),
                                                .key(57, 0, true), .key(57, 0, false)])
    }

    @Test(arguments: ["フォーカス", "ウィンドウ", "最小化", "終了", "切断", "端末切替"])
    func 押下中の入力を失効時に解放する(trigger: String) throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        view.keyDown(with: key(0))
        let releases = fake.releases
        switch trigger {
        case "フォーカス": window.makeFirstResponder(nil)
        case "ウィンドウ": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        case "最小化": NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        case "終了": view.stop()
        case "切断": fake.failed?("切断")
        default: connection.attach(udid: "別端末")
        }
        #expect(fake.releases > releases)
        #expect(connection.sentKeyCodes.isEmpty)
        let count = fake.inputs.count
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 220, y: 200))
        view.mouseUp(with: mouse(.leftMouseUp, x: 220, y: 200))
        #expect(fake.inputs.count == count)
        if trigger == "切断" || trigger == "端末切替" {
            #expect(fake.lifecycle.suffix(3) == ["解放", "切離", "破棄"])
        }
    }

    @Test(arguments: ["成功", "失敗", "フォーカス喪失", "非表示", "切断"])
    func 貼り付け成功時だけ押下と解放を一組送る(outcome: String) async throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        pasteboard.clearContents()
        pasteboard.setString("貼り付け", forType: .string)
        var resume: CheckedContinuation<Void, any Error>?
        var copied: (String, String)?
        view.copyPasteboard = { udid, text in
            copied = (udid, text)
            try await withCheckedThrowingContinuation { resume = $0 }
        }
        #expect(view.performKeyEquivalent(with: key(9, flags: .command)))
        for _ in 0..<100 {
            if resume != nil { break }
            await Task.yield()
        }
        let pending = try #require(resume)
        #expect(copied?.0 == "端末")
        #expect(copied?.1 == "貼り付け")
        #expect(fake.inputs.isEmpty)
        switch outcome {
        case "フォーカス喪失": window.makeFirstResponder(nil)
        case "非表示": view.isHidden = true
        case "切断": fake.failed?("切断")
        default: break
        }
        if outcome == "失敗" { pending.resume(throwing: NSError(domain: "検証", code: 1)) }
        else { pending.resume() }
        for _ in 0..<100 { await Task.yield() }
        if outcome == "成功" {
            #expect(fake.inputs == [.key(9, NSEvent.ModifierFlags.command.rawValue, true),
                                    .key(9, NSEvent.ModifierFlags.command.rawValue, false)])
        } else { #expect(fake.inputs.isEmpty) }
        if outcome == "失敗" { #expect(view.inputReason?.contains("貼り付け") == true) }
    }

    @Test(arguments: [1, 2, 3]) func 慣性フェーズを配送しない(momentum: Int64) throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        let event = try scroll(delta: 20, momentum: momentum)
        #expect(event.momentumPhase != [])
        view.scrollWheel(with: event)
        #expect(fake.inputs.isEmpty)
    }

    @Test func トラックパッドの位相と差分ゼロの終了を配送する() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        for (phase, delta): (Int64, Int32) in [(1, 0), (2, -20), (4, 0)] {
            view.scrollWheel(with: try scroll(delta: delta, phase: phase))
        }
        #expect(fake.scrollPhases == [1, 2, 3])
        #expect(fake.inputs.count == 3)
    }

    @Test func 表示寸法を失ったドラッグは接触を解放する() throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        let releases = fake.releases
        view.setFrameSize(.zero)
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 0, y: 0))
        #expect(fake.releases == releases + 1)
        let count = fake.inputs.count
        view.mouseUp(with: mouse(.leftMouseUp, x: 0, y: 0))
        #expect(fake.inputs.count == count)
    }

    @Test(arguments: [false, true]) func 送信済みキーのリピートへ後から押したCommandを付けない(equivalent: Bool) throws {
        let (view, window, connection, fake) = try setup()
        defer { view.stop(); window.close(); connection.disconnect() }
        view.keyDown(with: key(0))
        let repeated = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: true, keyCode: 0))
        if equivalent { #expect(view.performKeyEquivalent(with: repeated)) }
        else { view.keyDown(with: repeated) }
        #expect(fake.inputs == [.key(0, 0, true)])
        view.keyUp(with: key(0, flags: .command, type: .keyUp))
        #expect(connection.sentKeyCodes.isEmpty)
    }

    private func scroll(delta: Int32, phase: Int64 = 0, momentum: Int64 = 0) throws -> NSEvent {
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.location = NSPoint(x: 200, y: NSScreen.screens[0].frame.maxY - 200)
        return try #require(NSEvent(cgEvent: event))
    }

    private func setup() throws -> (SimulatorScreenNSView, NSWindow, SimulatorDisplayConnection, InputTransport) {
        _ = NSApplication.shared
        let fake = InputTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.attach(udid: "端末")
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                                                   helperBuild: "検証", xcodeBuild: "検証",
                                                   coreSimulatorLoaded: true, simulatorKitLoaded: true))
        let surface = try #require(IOSurface(properties: [.width: 4, .height: 8, .bytesPerElement: 4]))
        let info = SimulatorDisplayInfo(udid: "端末", connectionGeneration: connection.generation.current,
                                       displayGeneration: 1, surface: surface, pixelWidth: 4, pixelHeight: 8,
                                       orientation: .portrait, surfaceIsRotated: false, pixelFormat: 0x42475241)
        fake.attachReply?(info, nil)
        let window = InputWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = SimulatorScreenNSView()
        window.contentView = view
        view.connection = connection
        view.update(info)
        window.makeFirstResponder(view)
        #expect(window.isKeyWindow)
        #expect(window.firstResponder === view)
        return (view, window, connection, fake)
    }

    private func mouse(_ type: NSEvent.EventType, x: Double, y: Double) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
}

// CLI のテストランナーはキーウィンドウを持てないため、窓のアクティブ状態だけを代替する。
// first responder の遷移は AppKit 本体を使い、実際の窓は端末ハーネスで検査する。
@MainActor private final class InputWindow: NSWindow {
    var hasFocus = true
    override var isKeyWindow: Bool { hasFocus }
}

@MainActor private final class InputTransport: SimulatorDisplayTransport {
    enum Input: Equatable {
        case touch(Int, Double, Double)
        case scroll(Double, Double, Double, Double)
        case key(UInt16, UInt, Bool)
        case home
    }
    var inputs: [Input] = []
    var scrollPhases: [Int] = []
    var releases = 0
    var lifecycle: [String] = []
    var failed: (@MainActor (String) -> Void)?
    var probeReply: (@MainActor (SimulatorBridgeCapability) -> Void)?
    var attachReply: (@MainActor (SimulatorDisplayInfo?, NSError?) -> Void)?

    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void) { self.failed = failed }
    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void) { probeReply = reply }
    func attach(udid: String, generation: Int, reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void) {
        attachReply = reply
    }
    func detach(udid: String) { lifecycle.append("切離") }
    func invalidate() { lifecycle.append("破棄") }
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) { inputs.append(.touch(phase, x, y)) }
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {
        inputs.append(.scroll(dx, dy, x, y))
        scrollPhases.append(phase)
    }
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) { inputs.append(.key(keyCode, modifiers, down)) }
    func sendButton(udid: String, button: Int) { inputs.append(.home) }
    func releaseAll(udid: String) { releases += 1; lifecycle.append("解放") }
}
