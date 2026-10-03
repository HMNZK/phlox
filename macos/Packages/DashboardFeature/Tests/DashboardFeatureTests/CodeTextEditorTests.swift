import AppKit
import Testing
@testable import DashboardFeature

@Test @MainActor func codeEditorSynchronizesCanonicallyEquivalentBytes() {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.string = "\u{00E9}"
    let replacement = "e\u{0301}"
    #expect(textView.string == replacement)

    CodeTextEditor.synchronizeText(replacement, with: textView)

    #expect(textView.string.utf8.elementsEqual(replacement.utf8))
}

@Test @MainActor func codeEditorKeepsSelectionWhenBytesHaveNotChanged() {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.string = "同じ本文"
    textView.setSelectedRange(NSRange(location: 2, length: 1))

    CodeTextEditor.synchronizeText("同じ本文", with: textView)

    #expect(textView.selectedRange() == NSRange(location: 2, length: 1))
}

@Test @MainActor func blockEditorSynchronizesBeforeCommittingAndCommitsOnlyOnce() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let id = UUID()
    textView.blockEditID = id
    textView.string = "通知を待たず同期"
    var operations: [String] = []
    textView.synchronizeBlockEdit = { received, value in
        #expect(received == id)
        #expect(value == "通知を待たず同期")
        operations.append("同期")
    }
    textView.commitBlockEdit = { received in
        #expect(received == id)
        operations.append("確定")
        return true
    }

    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(operations == ["同期", "確定"])
}

@Test @MainActor func blockEditorRemovalSynchronizesWithoutCommitting() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    textView.string = "撤去時の未確定文字"
    var synchronized: String?
    var commits = 0
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in commits += 1; return true }

    textView.dismantleBlockEdit()
    #expect(textView.synchronizeAndCommitBlockEdit())

    #expect(synchronized == "撤去時の未確定文字")
    #expect(commits == 0)
}

@Test @MainActor func blockEditorRetainsEditWhenCommitIsRejected() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let id = UUID()
    textView.blockEditID = id
    textView.string = "保持する文字"
    var synchronized: String?
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in false }

    #expect(!textView.synchronizeAndCommitBlockEdit())
    #expect(textView.blockEditID == id)
    #expect(synchronized == "保持する文字")
}

@Test @MainActor func blockEditorEndsLocalUndoHistoryOnCommit() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    let undo = textView.undoManager!
    undo.registerUndo(withTarget: textView) { view in view.string = "前の文字" }
    textView.commitBlockEdit = { _ in true }
    #expect(undo.canUndo)

    #expect(textView.synchronizeAndCommitBlockEdit())

    #expect(!undo.canUndo)
}

@Test @MainActor func blockEditorUnmarksJapaneseCompositionBeforeSynchronizing() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    textView.setMarkedText("日本語の変換", selectedRange: NSRange(location: 6, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.hasMarkedText())
    var synchronized: String?
    textView.synchronizeBlockEdit = { _, value in
        #expect(!textView.hasMarkedText())
        synchronized = value
    }
    textView.commitBlockEdit = { _ in true }

    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(synchronized == "日本語の変換")
}

@Test @MainActor func blockEditorWindowRemovalDoesNotCommitPendingInput() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView?.addSubview(textView)
    textView.blockEditID = UUID()
    textView.string = "戻ると復元する入力"
    var synchronized: String?
    var commits = 0
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in commits += 1; return true }
    window.makeFirstResponder(textView)

    textView.removeFromSuperview()

    #expect(synchronized == "戻ると復元する入力")
    #expect(commits == 0)
}
