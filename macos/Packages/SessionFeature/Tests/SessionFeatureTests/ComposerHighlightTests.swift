import AppKit
import Foundation
import Testing
@testable import SessionFeature

// ComposerHighlight.spans(in:) の純関数仕様。
//   - 空白区切りトークンの先頭が "/" のものを各1件 slashCommand（位置不問・最初の空白で停止）
//   - 空白区切りトークンの先頭が "@" のものを各1件 fileReference
//   - トークン途中の "/"（src/main 等）や "@"（a@b 等）は無視
//   - range は UTF16 オフセット・決定論

private func u16Range(of sub: String, in text: String) -> Range<Int> {
    guard let r = text.range(of: sub) else {
        Issue.record("部分文字列 \(sub) が \(text) に見つからない（ハーネス欠陥）")
        return 0..<0
    }
    return r.lowerBound.utf16Offset(in: text)..<r.upperBound.utf16Offset(in: text)
}

@Suite("Composer highlight")
struct ComposerHighlightTests {
    @Test func 先頭スラッシュコマンドを1件返す() {
        let text = "/help"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "/help", in: text), kind: .slashCommand)])
    }

    @Test func スラッシュコマンドは最初の空白で止まる() {
        let text = "/help me"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "/help", in: text), kind: .slashCommand)])
    }

    @Test func 文中でも空白区切り先頭のスラッシュをハイライトする() {
        let text = "hello /run"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "/run", in: text), kind: .slashCommand)])
    }

    @Test func 本文の後ろに並ぶ複数のスラッシュコマンドを各1件返す() {
        let text = "本文 /frontend-design /design-engineering"
        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: u16Range(of: "/frontend-design", in: text), kind: .slashCommand),
            ComposerHighlightSpan(range: u16Range(of: "/design-engineering", in: text), kind: .slashCommand),
        ])
    }

    @Test func トークン途中のスラッシュは無視() {
        #expect(ComposerHighlight.spans(in: "src/main").isEmpty)
    }

    @Test func アット参照トークンを返す() {
        let text = "@file.txt"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "@file.txt", in: text), kind: .fileReference)])
    }

    @Test func 複数のアット参照を各1件返す() {
        let text = "review @a.md and @b.md"
        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: u16Range(of: "@a.md", in: text), kind: .fileReference),
            ComposerHighlightSpan(range: u16Range(of: "@b.md", in: text), kind: .fileReference),
        ])
    }

    @Test func スラッシュとアットが混在() {
        let text = "/deploy @config.yaml"
        #expect(ComposerHighlight.spans(in: text) == [
            ComposerHighlightSpan(range: u16Range(of: "/deploy", in: text), kind: .slashCommand),
            ComposerHighlightSpan(range: u16Range(of: "@config.yaml", in: text), kind: .fileReference),
        ])
    }

    @Test func CJKを含む場合もUTF16オフセットが正しい() {
        let text = "こんにちは @メモ.txt"
        #expect(ComposerHighlight.spans(in: text) ==
            [ComposerHighlightSpan(range: u16Range(of: "@メモ.txt", in: text), kind: .fileReference)])
    }

    @Test func 空文字列は空() {
        #expect(ComposerHighlight.spans(in: "").isEmpty)
    }

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
