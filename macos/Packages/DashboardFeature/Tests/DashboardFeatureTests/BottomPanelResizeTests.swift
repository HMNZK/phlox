import AppKit
import SwiftUI
import Testing
@testable import DesignSystem
@testable import DashboardFeature

@Suite("下部パネルの共通境界") @MainActor
struct BottomPanelResizeTests {
    @Test("VoiceOver の増減と上下キーで高さを変更できる")
    func accessibleAndKeyboardAdjustment() async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let suite = "BottomPanelResizeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = BottomPanelState(defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: BottomPanelHeightGrip(state: state, availableHeight: 800, height: 280))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await waitUntil { self.accessible("bottom-panel-height", in: host) != nil }
        let element = try #require(accessible("bottom-panel-height", in: host))
        #expect((element as AnyObject).accessibilityPerformIncrement())
        #expect(state.preferredHeight == 280 + DSSpacing.l)
        host.rootView = BottomPanelHeightGrip(state: state, availableHeight: 800, height: state.preferredHeight)
        host.layoutSubtreeIfNeeded()
        let updated = try #require(accessible("bottom-panel-height", in: host))
        #expect((updated as AnyObject).accessibilityPerformDecrement())
        #expect(state.preferredHeight == 280)
        host.rootView = BottomPanelHeightGrip(state: state, availableHeight: 800, height: state.preferredHeight)
        host.layoutSubtreeIfNeeded()
        #expect(window.makeFirstResponder(host))
        window.selectNextKeyView(nil)
        try await waitUntil { window.firstResponder is ResizeGripNSView }
        _ = try #require(window.firstResponder as? ResizeGripNSView)
        let up = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}", isARepeat: false, keyCode: 126))
        window.sendEvent(up)
        try await waitUntil { state.preferredHeight == 280 + DSSpacing.l }
        #expect(state.preferredHeight == 280 + DSSpacing.l)
        host.rootView = BottomPanelHeightGrip(state: state, availableHeight: 800, height: state.preferredHeight)
        host.layoutSubtreeIfNeeded()
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
        window.sendEvent(down)
        #expect(state.preferredHeight == 280)
    }

    @Test("上下向きの共通部品を使い、上へドラッグすると終了時に高さを保存する")
    func dragAndReset() async throws {
        let suite = "BottomPanelResizeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = BottomPanelState(defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: BottomPanelHeightGrip(state: state, availableHeight: 800, height: state.preferredHeight))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await waitUntil { self.descendants(host).contains { $0 is ResizeGripNSView } }
        let grip = try #require(descendants(host).compactMap { $0 as? ResizeGripNSView }.first)
        #expect(grip.axis == .vertical)
        #expect(grip.resizeCursor === NSCursor.resizeUpDown)
        #expect(grip.bounds.width == 500)
        #expect(grip.bounds.height == DSLayout.dividerHitWidth)
        grip.mouseDown(with: try event(.leftMouseDown, y: 100, window: window))
        grip.mouseDragged(with: try event(.leftMouseDragged, y: 160, window: window))
        #expect(state.preferredHeight == 280)
        #expect(defaults.object(forKey: BottomPanelState.heightKey) == nil)
        grip.mouseUp(with: try event(.leftMouseUp, y: 160, window: window))
        #expect(state.preferredHeight == 340)
        #expect(defaults.double(forKey: BottomPanelState.heightKey) == 340)
        host.rootView = BottomPanelHeightGrip(state: state, availableHeight: 800, height: state.preferredHeight)
        host.layoutSubtreeIfNeeded()
        grip.mouseDown(with: try event(.leftMouseDown, y: 100, clicks: 2, window: window))
        grip.mouseUp(with: try event(.leftMouseUp, y: 100, window: window))
        #expect(state.preferredHeight == 280)
        #expect(defaults.double(forKey: BottomPanelState.heightKey) == 280)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func accessible(_ identifier: String, in root: NSObject) -> NSObject? {
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

    private func event(_ type: NSEvent.EventType, y: CGFloat, clicks: Int = 1, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: y), modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0))
    }
}
