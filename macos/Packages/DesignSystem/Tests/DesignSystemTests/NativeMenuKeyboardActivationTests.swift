#if os(macOS)
import AppKit
import Testing
@testable import DesignSystem

@Suite @MainActor
struct NativeMenuKeyboardActivationTests {
    @Test func activationMovesNativeFirstResponderAndForwardsTheSameKeyboardEvent() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let popup = RecordingPopup(frame: NSRect(x: 0, y: 0, width: 100, height: 40), pullsDown: false)
        let anchor = NSView(frame: popup.frame)
        root.addSubview(popup)
        root.addSubview(anchor)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.orderOut(nil) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        #expect(NativeMenuKeyboardActivation.activate(for: anchor, event: event))
        #expect(popup.openedWithNativeFocus)
        #expect(popup.receivedEvent === event)
        #expect(window.firstResponder === popup)
    }

    @Test func targetsOnlyItsOwnEnabledVisibleNativePopup() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        let neighbor = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 40), pullsDown: false)
        let target = NSPopUpButton(frame: NSRect(x: 200, y: 0, width: 100, height: 40), pullsDown: false)
        let anchor = NSView(frame: target.frame)
        root.addSubview(neighbor)
        root.addSubview(target)
        root.addSubview(anchor)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.orderOut(nil) }

        #expect(NativeMenuKeyboardActivation.button(for: anchor) === target)
        target.isEnabled = false
        #expect(NativeMenuKeyboardActivation.button(for: anchor) == nil)
        target.isEnabled = true
        target.isHidden = true
        #expect(NativeMenuKeyboardActivation.button(for: anchor) == nil)
        anchor.removeFromSuperview()
        #expect(NativeMenuKeyboardActivation.button(for: anchor) == nil)
    }
}

@MainActor
private final class RecordingPopup: NSPopUpButton {
    var openedWithNativeFocus = false
    var receivedEvent: NSEvent?
    override func performClick(_ sender: Any?) {
        openedWithNativeFocus = window?.firstResponder === self
    }
    override func keyDown(with event: NSEvent) {
        openedWithNativeFocus = window?.firstResponder === self
        receivedEvent = event
    }
}
#endif
