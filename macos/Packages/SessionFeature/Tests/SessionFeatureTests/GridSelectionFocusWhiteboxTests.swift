import AppKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Grid selection focus whitebox")
@MainActor
struct GridSelectionFocusWhiteboxTests {
    @Test("枠ポリシーはドロップ状態を問わずフォーカスと注意喚起を独立して保持する")
    func borderPolicyKeepsFocusAndAttentionIndependent() {
        for isDropTargeted in [false, true] {
            for requiresAttention in [false, true] {
                for isFocused in [false, true] {
                    let appearance = GridTileBorderPolicy.appearance(
                        isFocused: isFocused,
                        requiresAttention: requiresAttention,
                        isDropTargeted: isDropTargeted
                    )

                    #expect(appearance.showsFocusHighlight == isFocused)
                    #expect(appearance.showsAttention == requiresAttention)
                }
            }
        }
    }

    @Test("入力欄がファーストレスポンダになるイベントでフォーカス通知を同期する")
    func inputFocusSynchronouslyNotifiesOwner() throws {
        var notificationCount = 0
        let view = IMESafeTextView(
            text: .constant(""),
            isComposing: .constant(false),
            measuredHeight: .constant(40),
            minHeight: 40,
            maxHeight: 160,
            suggestionController: nil,
            onSubmit: {},
            onFocusGained: { notificationCount += 1 }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(firstTextView(in: hosting))

        #expect(window.makeFirstResponder(textView))
        #expect(notificationCount == 1)

        window.orderOut(nil)
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }
}
