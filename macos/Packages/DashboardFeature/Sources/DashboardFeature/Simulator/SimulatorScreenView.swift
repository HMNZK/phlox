import AppKit
import SwiftUI
import QuartzCore
import IOSurface
import SimulatorBridgeKit

public struct SimulatorScreenView: NSViewRepresentable {
    public let displayInfo: SimulatorDisplayInfo?
    public var connection: SimulatorDisplayConnection?
    public var isVisible: Bool
    public var releaseFocus: (() -> Void)?
    public var deviceName: String
    public var inputFocusChanged: ((Bool) -> Void)?
    public var inputEnabled: Bool

    public init(displayInfo: SimulatorDisplayInfo?, connection: SimulatorDisplayConnection? = nil,
                isVisible: Bool = true, releaseFocus: (() -> Void)? = nil,
                deviceName: String = "端末", inputFocusChanged: ((Bool) -> Void)? = nil,
                inputEnabled: Bool = true) {
        self.displayInfo = displayInfo
        self.connection = connection
        self.isVisible = isVisible
        self.releaseFocus = releaseFocus
        self.deviceName = deviceName
        self.inputFocusChanged = inputFocusChanged
        self.inputEnabled = inputEnabled
    }

    public func makeNSView(context: Context) -> SimulatorScreenNSView { SimulatorScreenNSView() }
    public func updateNSView(_ view: SimulatorScreenNSView, context: Context) {
        view.connection = connection
        view.releaseFocus = releaseFocus
        view.inputFocusChanged = inputFocusChanged
        view.inputEnabled = inputEnabled
        view.setAccessibilityLabel("\(deviceName) の画面。端末内の UI は VoiceOver で操作できません")
        view.isHidden = !isVisible
        view.update(displayInfo)
    }
    public static func dismantleNSView(_ view: SimulatorScreenNSView, coordinator: ()) { view.stop() }
}

public final class SimulatorScreenNSView: NSView {
    private let screen = CALayer()
    private var info: SimulatorDisplayInfo?
    private var lastSeed: UInt32 = 0
    private var displayLink: CADisplayLink?
    public var connection: SimulatorDisplayConnection? {
        willSet {
            if connection !== newValue {
                releaseInput()
                update(nil)
            }
        }
    }
    public var releaseFocus: (() -> Void)?
    public var inputFocusChanged: ((Bool) -> Void)?
    public var inputEnabled = true {
        willSet { if inputEnabled && !newValue { releaseInput() } }
    }
    private var hasInputFocus = false
    public private(set) var inputReason: String?
    private var touching = false
    private var touchRevision = 0
    private var pasteTask: Task<Void, Never>?
    var copyPasteboard: (String, String) async throws -> Void = { udid, text in
        try await SimulatorCatalog().copyPasteboard(udid: udid, text: text)
    }

    public override var acceptsFirstResponder: Bool { inputEnabled && connection?.inputEnabled == true && !isHiddenOrHasHiddenAncestor }

    private var acceptsInput: Bool {
        guard let window, window.firstResponder === self, window.isKeyWindow,
              !window.isMiniaturized, !isHiddenOrHasHiddenAncestor,
              inputEnabled, connection?.inputEnabled == true, let info, let current = connection?.displayInfo else { return false }
        return current.udid == info.udid && current.connectionGeneration == info.connectionGeneration
    }

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        screen.contentsGravity = .resizeAspect
        layer?.addSublayer(screen)
        setAccessibilityElement(true)
        setAccessibilityRole(NSAccessibility.Role(rawValue: "AXApplication"))
        setAccessibilityIdentifier("simulator-screen")
        setAccessibilityLabel("端末 の画面。端末内の UI は VoiceOver で操作できません")
    }

    required init?(coder: NSCoder) { nil }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screen.frame = bounds
        CATransaction.commit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        releaseInput()
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(releaseInput), name: name, object: window)
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(restoreInputFocus), name: name, object: window)
            }
            let link = displayLink(target: self, selector: #selector(refresh))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    public func update(_ next: SimulatorDisplayInfo?) {
        if let next, let info {
            guard next.connectionGeneration > info.connectionGeneration ||
                    next.isCurrent(udid: info.udid, connectionGeneration: info.connectionGeneration,
                                   minimumDisplayGeneration: info.displayGeneration) else { return }
        }
        if info?.udid != next?.udid || info?.connectionGeneration != next?.connectionGeneration {
            releaseInput()
        }
        info = next
        lastSeed = next.map { IOSurfaceGetSeed($0.surface) } ?? 0
        setContents(next?.surface)
    }

    @objc private func refresh() {
        guard !isHiddenOrHasHiddenAncestor, window?.isMiniaturized == false, let info else { return }
        let seed = IOSurfaceGetSeed(info.surface)
        connection?.observeFrame(info, seed: seed)
        guard seed != lastSeed else { return }
        lastSeed = seed
        setContents(info.surface)
    }

    private func setContents(_ surface: IOSurface?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 同じ surface の変更を Core Animation に通知する（試作で確認済み）。
        screen.contents = nil
        screen.contents = surface
        CATransaction.commit()
    }

    public func stop() {
        releaseInput()
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
        update(nil)
    }

    public override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder, super.becomeFirstResponder() else { return false }
        hasInputFocus = true
        inputFocusChanged?(true)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        releaseInput()
        hasInputFocus = false
        inputFocusChanged?(false)
        return super.resignFirstResponder()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        releaseInput()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        restoreInputFocus()
    }

    @objc private func restoreInputFocus() {
        hasInputFocus = acceptsInput
        inputFocusChanged?(hasInputFocus)
    }

    private func acquireInputFocus() {
        guard !hasInputFocus else { return }
        hasInputFocus = true
        inputFocusChanged?(true)
    }

    @objc private func releaseInput() {
        let ownedInput = hasInputFocus || touching || pasteTask != nil
        hasInputFocus = false
        touching = false
        pasteTask?.cancel()
        pasteTask = nil
        if ownedInput { connection?.releaseAll() }
        inputFocusChanged?(false)
    }

    private func point(for event: NSEvent, continuingTouch: Bool = false) -> CGPoint? {
        guard let info else { return nil }
        return SimulatorInputMapper.normalizedPoint(
            convert(event.locationInWindow, from: nil), in: bounds,
            pixelSize: CGSize(width: info.pixelWidth, height: info.pixelHeight),
            orientation: info.orientation, surfaceIsRotated: info.surfaceIsRotated,
            continuingTouch: continuingTouch
        )
    }

    public override func mouseDown(with event: NSEvent) {
        guard point(for: event) != nil else { return }
        window?.makeFirstResponder(self)
        guard acceptsInput, let point = point(for: event), let connection else { return }
        acquireInputFocus()
        touching = true
        touchRevision = connection.inputRevision
        connection.sendTouch(phase: 0, point: point)
    }

    public override func mouseDragged(with event: NSEvent) { continueTouch(event, phase: 1) }
    public override func mouseUp(with event: NSEvent) { continueTouch(event, phase: 2) }

    private func continueTouch(_ event: NSEvent, phase: Int) {
        guard touching else { return }
        guard touchRevision == connection?.inputRevision else { touching = false; return }
        guard acceptsInput,
              let point = point(for: event, continuingTouch: true) else {
            if touching { releaseInput() }
            return
        }
        connection?.sendTouch(phase: phase, point: point)
        if phase == 2 { touching = false }
    }

    public override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase == [], acceptsInput, !touching else { return }
        acquireInputFocus()
        let continuing = !event.phase.intersection([.changed, .stationary, .ended, .cancelled]).isEmpty
        guard let point = point(for: event, continuingTouch: continuing) else {
            if event.phase != [] { releaseInput() }
            return
        }
        let phase: Int
        if event.phase.contains(.cancelled) { phase = 4 }
        else if event.phase.contains(.ended) { phase = 3 }
        else if event.phase.contains(.began) { phase = 1 }
        else if event.phase.contains(.changed) || event.phase.contains(.stationary) { phase = 2 }
        else { phase = 0 }
        if event.phase.contains(.mayBegin) { return }
        // マウスの行単位とトラックパッドのポイント単位を揃える。
        let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        connection?.sendScroll(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale, point: point, phase: phase)
    }

    public override func keyDown(with event: NSEvent) {
        if !routeKey(event, down: true) { super.keyDown(with: event) }
    }

    public override func keyUp(with event: NSEvent) {
        if !routeKey(event, down: false) { super.keyUp(with: event) }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard acceptsInput else { return false }
        return routeKey(event, down: true)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard acceptsInput else { return }
        // Caps Lock は状態を切り替えるキーなので、切替ごとに一組送る。
        if event.keyCode == 57 {
            _ = routeKey(event, down: true)
            _ = routeKey(event, down: false)
            return
        }
        // 左右の修飾キーは device-dependent ビットで区別する。
        let masks: [UInt16: UInt] = [56: 0x2, 60: 0x4, 59: 0x1, 62: 0x2000,
                                   58: 0x20, 61: 0x40, 55: 0x8, 54: 0x10]
        guard let mask = masks[event.keyCode] else { return }
        _ = routeKey(event, down: event.modifierFlags.rawValue & mask != 0)
    }

    @discardableResult private func routeKey(_ event: NSEvent, down: Bool) -> Bool {
        guard acceptsInput, let connection else { return false }
        acquireInputFocus()
        // 送信済みの物理キーのリピートは、新しいショートカットにしない。
        if down, event.type == .keyDown, event.isARepeat, connection.sentKeyCodes.contains(event.keyCode) { return true }
        switch SimulatorKeyRouting.route(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                         down: down, sentKeyCodes: connection.sentKeyCodes) {
        case .send:
            connection.sendKey(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue, down: down)
            return true
        case .releaseFocus:
            releaseInput()
            if let releaseFocus { releaseFocus() }
            else { window?.selectNextKeyView(self) }
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            return true
        case .copyPasteboard:
            guard !event.isARepeat, pasteTask == nil else { return true }
            paste(connection, modifiers: event.modifierFlags)
            return true
        case .sendPressAndRelease, .handleInPhlox:
            return false
        }
    }

    private func paste(_ connection: SimulatorDisplayConnection, modifiers: NSEvent.ModifierFlags) {
        guard let info = connection.displayInfo, let text = NSPasteboard.general.string(forType: .string) else { return }
        let revision = connection.inputRevision
        let copy = copyPasteboard
        inputReason = nil
        pasteTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.pasteTask = nil } }
            do {
                try await copy(info.udid, text)
                guard let self, !Task.isCancelled, self.acceptsInput, self.connection === connection,
                      connection.inputRevision == revision,
                      SimulatorKeyRouting.route(keyCode: 9, modifiers: modifiers, down: true,
                                                sentKeyCodes: connection.sentKeyCodes,
                                                pasteSucceeded: true) == .sendPressAndRelease else { return }
                connection.sendKey(keyCode: 9, modifiers: modifiers.rawValue, down: true)
                connection.sendKey(keyCode: 9, modifiers: modifiers.rawValue, down: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.inputReason = "貼り付けを準備できません: \(error.localizedDescription)"
                NSLog("貼り付けを準備できません: %@", error.localizedDescription)
            }
        }
    }
}
