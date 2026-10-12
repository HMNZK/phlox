#if os(macOS)
import AppKit
import SwiftUI

@MainActor
enum NativeMenuKeyboardActivation {
    static func activate(for anchor: NSView, event: NSEvent) -> Bool {
        guard event.type == .keyDown, let button = button(for: anchor),
              button.window?.makeFirstResponder(button) == true else { return false }
        button.keyDown(with: event)
        return true
    }

    static func button(for anchor: NSView) -> NSPopUpButton? {
        guard let root = anchor.window?.contentView, !anchor.bounds.isEmpty else { return nil }
        let center = NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        func find(in view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton, button.isEnabled,
               !button.isHiddenOrHasHiddenAncestor, button.convert(button.bounds, to: anchor).contains(center) {
                return button
            }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return find(in: root)
    }
}

public extension View {
    @MainActor
    func nativeMenuKeyboardActivation() -> some View {
        modifier(NativeMenuKeyboardActivationModifier())
    }
}

@MainActor
private struct NativeMenuKeyboardActivationModifier: ViewModifier {
    @State private var anchor = NSView()

    func body(content: Content) -> some View {
        content
            .background(MenuActivationAnchor(view: anchor).allowsHitTesting(false))
            .focusable()
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                NSLog("PhloxMenuEvent type=%@", String(describing: NSApp.currentEvent?.type))
                guard let event = NSApp.currentEvent else { return .ignored }
                return NativeMenuKeyboardActivation.activate(for: anchor, event: event) ? .handled : .ignored
            }
    }
}

private struct MenuActivationAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView {
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
