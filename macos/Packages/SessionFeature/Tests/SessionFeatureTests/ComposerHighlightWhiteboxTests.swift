import AppKit
import Testing
@testable import SessionFeature

@Suite("ComposerHighlight white-box")
struct ComposerHighlightWhiteboxTests {
    @Test func whitespaceSeparatesReferenceTokens() {
        let text = "prefix\t@tab\n@line"

        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: 7..<11, kind: .fileReference),
            ComposerHighlightSpan(range: 12..<17, kind: .fileReference),
        ])
    }

    @Test func standaloneTriggerCharactersAreTokens() {
        #expect(ComposerHighlight.spans(in: "/ @") == [
            ComposerHighlightSpan(range: 0..<1, kind: .slashCommand),
            ComposerHighlightSpan(range: 2..<3, kind: .fileReference),
        ])
    }

    @Test func emojiBeforeReferenceUsesUTF16Offsets() {
        let text = "😀 @メモ"

        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: 3..<6, kind: .fileReference),
        ])
    }

    @Test func atSignInsideAnotherTokenIsIgnored() {
        #expect(ComposerHighlight.spans(in: "/run@host a@b @ok") == [
            ComposerHighlightSpan(range: 0..<9, kind: .slashCommand),
            ComposerHighlightSpan(range: 14..<17, kind: .fileReference),
        ])
    }

    @MainActor
    @Test func applyingHighlightsRestoresSelectionAndDefaultTypingColor() throws {
        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.textColor = .labelColor
        textView.string = "/go plain @file"
        textView.setSelectedRange(NSRange(location: 7, length: 2))
        let originalSelection = textView.selectedRange()
        let textStorage = try #require(textView.textStorage)
        textStorage.addAttribute(
            .foregroundColor,
            value: NSColor.systemRed,
            range: NSRange(location: 0, length: textStorage.length)
        )
        var defaultTypingAttributes = textView.typingAttributes
        defaultTypingAttributes[.foregroundColor] = NSColor.labelColor
        textView.typingAttributes = defaultTypingAttributes

        textView.applyComposerHighlights()

        let commandColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let plainColor = textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        let referenceColor = textStorage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor
        let typingColor = textView.typingAttributes[.foregroundColor] as? NSColor
        #expect(commandColor != NSColor.labelColor)
        #expect(referenceColor != NSColor.labelColor)
        // スラッシュコマンドと @参照 は別色で種別を判別できる。
        #expect(referenceColor != commandColor)
        #expect(plainColor == NSColor.labelColor)
        #expect(typingColor == NSColor.labelColor)
        #expect(textView.selectedRange() == originalSelection)
    }
}
