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
