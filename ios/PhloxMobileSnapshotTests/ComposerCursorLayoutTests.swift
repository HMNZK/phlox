import SwiftUI
import Testing
import UIKit
@testable import DesignSystemIOS
import PhotosUI

@MainActor
extension DesignSnapshotRenderTests {
    @Test
    func selectingPhotosWhilePickerIsOpenDoesNotConsumeOrClearSelection() {
        let item = PhotosPickerItem(itemIdentifier: "photo-one")
        var items = [item]
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: true).isEmpty)
        #expect(items == [item])
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: false) == [item])
        #expect(items.isEmpty)
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: false).isEmpty)
    }

    @Test
    func selectionArrivingAfterDismissalIsConsumedOnce() {
        var items: [PhotosPickerItem] = []
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: false).isEmpty)
        let item = PhotosPickerItem(itemIdentifier: "photo-one")
        items = [item]
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: false) == [item])
        #expect(DSInputBar.takeSelectedPhotos(&items, isPresented: false).isEmpty)
    }

    private final class Draft {
        var text: String
        var cursor: Int
        var focused = false

        init(_ text: String, cursor: Int) {
            self.text = text
            self.cursor = cursor
        }
    }

    private final class FocusSpy: UITextView {
        var reportedFirstResponder = false
        var acquisitions = 0
        var resignations = 0
        override var isFirstResponder: Bool { reportedFirstResponder }
        override func becomeFirstResponder() -> Bool {
            acquisitions += 1
            reportedFirstResponder = true
            return true
        }
        override func resignFirstResponder() -> Bool {
            resignations += 1
            reportedFirstResponder = false
            return true
        }
    }

    private func focusHarness(focused: Bool) throws -> (UIWindow, DSInputRichTextEditor.Coordinator, FocusSpy, Draft) {
        let draft = Draft("", cursor: 0)
        draft.focused = focused
        let editor = FocusSpy()
        let controller = UIViewController()
        controller.view.addSubview(editor)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        try #require(editor.window != nil)
        editor.acquisitions = 0
        editor.resignations = 0
        let parent = DSInputRichTextEditor(
            text: .constant(""), cursorUTF16: .constant(0),
            isFocused: Binding(get: { draft.focused }, set: { draft.focused = $0 }),
            dynamicTypeSize: .large, accessibilityLabel: "入力"
        )
        return (window, parent.makeCoordinator(), editor, draft)
    }

    @Test
    func nativeFocusChangesWaitUntilAfterTheViewUpdate() async throws {
        let (window, coordinator, editor, _) = try focusHarness(focused: true)
        defer { window.isHidden = true }
        let pending = try #require(coordinator.updateFocus(in: editor))
        #expect(editor.acquisitions == 0)
        await pending.value
        #expect(editor.acquisitions == 1)
    }

    @Test(arguments: [false, true])
    func staleFocusRequestDoesNotReopenKeyboard(renderedAgain: Bool) async throws {
        let (window, coordinator, editor, draft) = try focusHarness(focused: true)
        defer { window.isHidden = true }
        let pending = try #require(coordinator.updateFocus(in: editor))
        draft.focused = false
        if renderedAgain { coordinator.updateFocus(in: editor) }
        await pending.value
        #expect(editor.acquisitions == 0)
    }

    @Test
    func focusRequestDoesNotActivateDetachedEditor() async throws {
        let (window, coordinator, editor, _) = try focusHarness(focused: true)
        defer { window.isHidden = true }
        let pending = try #require(coordinator.updateFocus(in: editor))
        editor.removeFromSuperview()
        await pending.value
        #expect(editor.acquisitions == 0)
    }

    @Test
    func keyboardResignationAlsoWaitsUntilAfterTheViewUpdate() async throws {
        let (window, coordinator, editor, _) = try focusHarness(focused: false)
        defer { window.isHidden = true }
        editor.reportedFirstResponder = true
        let pending = try #require(coordinator.updateFocus(in: editor))
        #expect(editor.resignations == 0)
        await pending.value
        #expect(editor.resignations == 1)
    }

    @Test
    func repeatedViewUpdatesApplyOnlyLatestFocusRequest() async throws {
        let (window, coordinator, editor, _) = try focusHarness(focused: true)
        defer { window.isHidden = true }
        let first = coordinator.updateFocus(in: editor)
        let second = coordinator.updateFocus(in: editor)
        let latest = coordinator.updateFocus(in: editor)
        await first?.value
        await second?.value
        await latest?.value
        #expect(editor.acquisitions == 1)
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
