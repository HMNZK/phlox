import AppKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite @MainActor
struct ChatComposerNativeAccessibilityTests {
    @Test func newChatTabMovesFocusWithoutChangingTheDraft() throws {
        let input = ComposerDraftInput(
            text: .constant("次の作業"), attachmentStore: ComposerAttachmentStore(),
            workingDirectory: "", placeholder: "メッセージを入力", onSubmit: {}
        )
        let hosting = NSHostingView(rootView: input)
        let next = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        hosting.frame = container.bounds
        container.addSubview(hosting)
        container.addSubview(next)
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(firstTextView(in: hosting))
        textView.nextKeyView = next
        #expect(window.makeFirstResponder(textView))
        let tab = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
        ))
        textView.keyDown(with: tab)
        #expect(textView.string == "次の作業")
        #expect(window.firstResponder === next.currentEditor())
    }

    @Test func newChatInputExposesIdentifierLabelAndValueOnNativeTextView() throws {
        let input = ComposerDraftInput(
            text: .constant("次の作業"), attachmentStore: ComposerAttachmentStore(),
            workingDirectory: "", placeholder: "メッセージを入力",
            accessibilityPrefix: "newChat", inputAccessibilitySuffix: "messageInput", onSubmit: {}
        ).accessibilityIdentifier("newChat.composer")
        let hosting = NSHostingView(rootView: input)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(firstTextView(in: hosting))
        #expect(textView.accessibilityIdentifier() == "newChat.messageInput")
        #expect(textView.accessibilityLabel() == "メッセージ")
        #expect(textView.accessibilityRole() == .textArea)
        #expect(textView.accessibilityValue() == "次の作業")
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { firstTextView(in: $0) }.first
    }
}
