import SwiftUI
import Testing
import UIKit
import DesignSystemIOS

@MainActor
extension DesignSnapshotRenderTests {
    private final class Draft {
        var text: String
        var cursor: Int

        init(_ text: String, cursor: Int) {
            self.text = text
            self.cursor = cursor
        }
    }

    private func host(_ draft: Draft) throws -> (UIWindow, UIHostingController<DSInputBar>, UITextView) {
        let text = Binding(get: { draft.text }, set: { draft.text = $0 })
        let cursor = Binding(get: { draft.cursor }, set: { draft.cursor = $0 })
        let bar = DSInputBar(text: text, cursorUTF16: cursor, onSubmit: {})
        let controller = UIHostingController(rootView: bar)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        let editor = try #require(findTextView(in: controller.view))
        return (window, controller, editor)
    }

    private func findTextView(in view: UIView) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        return view.subviews.lazy.compactMap(findTextView).first
    }

    @Test(arguments: ["m", "あ", "🙂", "a🙂日本語"])
    func boldMarkerAndFollowingGlyphShareCaretLayout(suffix: String) throws {
        let marker = "[Image #1]"
        let draft = Draft(marker, cursor: marker.utf16.count)
        let (window, controller, editor) = try host(draft)
        defer { window.isHidden = true; controller.view.removeFromSuperview() }

        let markerFont = try #require(editor.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(markerFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        editor.selectedRange = NSRange(location: marker.utf16.count, length: 0)
        editor.insertText(suffix)
        controller.view.layoutIfNeeded()

        #expect(editor.text == marker + suffix)
        #expect(editor.selectedRange.location == (marker + suffix).utf16.count)
        let lastCharacter = try #require(suffix.last)
        let end = editor.endOfDocument
        let start = try #require(editor.position(from: end, offset: -String(lastCharacter).utf16.count))
        let glyphRange = try #require(editor.textRange(from: start, to: end))
        let glyph = editor.firstRect(for: glyphRange)
        let caret = editor.caretRect(for: end)
        #expect(abs(caret.minX - glyph.maxX) <= 2)
    }

    @Test
    func externalTextAndSelectionDoNotReplaceMarkedText() async throws {
        let marker = "[Image #1]"
        let draft = Draft(marker, cursor: marker.utf16.count)
        let (window, controller, editor) = try host(draft)
        defer { window.isHidden = true; controller.view.removeFromSuperview() }

        editor.selectedRange = NSRange(location: marker.utf16.count, length: 0)
        editor.setMarkedText("へんかん", selectedRange: NSRange(location: 4, length: 0))
        let marked = try #require(editor.markedTextRange)
        let markedText = editor.text(in: marked)
        draft.text = "外部更新"
        draft.cursor = 0
        controller.rootView = DSInputBar(
            text: Binding(get: { draft.text }, set: { draft.text = $0 }),
            cursorUTF16: Binding(get: { draft.cursor }, set: { draft.cursor = $0 }),
            onSubmit: {}
        )
        await Task.yield()
        controller.view.layoutIfNeeded()

        #expect(findTextView(in: controller.view) === editor)
        #expect(editor.markedTextRange != nil)
        #expect(editor.text(in: marked) == markedText)
    }

    @Test
    func insertionBetweenBoldMarkerAndFollowingTextKeepsSelection() throws {
        let marker = "[Image #1]"
        let draft = Draft(marker + "後", cursor: marker.utf16.count)
        let (window, controller, editor) = try host(draft)
        defer { window.isHidden = true; controller.view.removeFromSuperview() }

        editor.selectedRange = NSRange(location: marker.utf16.count, length: 0)
        editor.insertText("🙂m")
        controller.view.layoutIfNeeded()

        #expect(editor.text == marker + "🙂m後")
        #expect(editor.selectedRange == NSRange(location: marker.utf16.count + "🙂m".utf16.count, length: 0))
        #expect(findTextView(in: controller.view) === editor)
    }

    @Test
    func externalCursorKeepsMiddleSelectionWithoutChangingEditorIdentity() async throws {
        let draft = Draft("前[Image #1]後", cursor: 0)
        let (window, controller, editor) = try host(draft)
        defer { window.isHidden = true; controller.view.removeFromSuperview() }

        draft.cursor = "前[Image #1]".utf16.count
        controller.rootView = DSInputBar(
            text: Binding(get: { draft.text }, set: { draft.text = $0 }),
            cursorUTF16: Binding(get: { draft.cursor }, set: { draft.cursor = $0 }),
            onSubmit: {}
        )
        await Task.yield()
        controller.view.layoutIfNeeded()

        #expect(findTextView(in: controller.view) === editor)
        #expect(editor.selectedRange == NSRange(location: draft.cursor, length: 0))
    }
}
