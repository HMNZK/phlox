import AppKit
import Foundation
import Testing
@testable import SessionFeature

// task-4 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-4.md
// 入力欄でキーワードを「スラッシュコマンド・@参照・地の文のいずれとも異なる色」で描画し、
// Claude セッションだけで有効にする（有効/無効は highlightsKeywords が受け持つ）。
//
// 注: SwiftUI View（ChatComposer / GridChatColumn）が agentRef を見て
// highlightsKeywords を渡す配線は NSViewRepresentableContext を組めないため本ファイルでは検証しない。
// 実装役の白箱テスト・独立レビュー・フェーズ4の実機確認で担保する。

/// "/go ultrathink plain @file" の UTF16 オフセット。
private enum Offset {
    static let slashCommand = 0    // "/go"
    static let keyword = 4         // "ultrathink"
    static let plain = 15          // "plain"
    static let fileReference = 21  // "@file"
}

private let sampleText = "/go ultrathink plain @file"

@MainActor
private func makeTextView(
    highlightsKeywords: Bool
) throws -> (IMESafeTextView.SubmitAwareTextView, NSTextStorage) {
    let textView = IMESafeTextView.SubmitAwareTextView()
    textView.textColor = .labelColor
    textView.highlightsKeywords = highlightsKeywords
    textView.string = sampleText
    var typingAttributes = textView.typingAttributes
    typingAttributes[.foregroundColor] = NSColor.labelColor
    textView.typingAttributes = typingAttributes
    let textStorage = try #require(textView.textStorage)
    return (textView, textStorage)
}

private func color(_ storage: NSTextStorage, at offset: Int) -> NSColor? {
    storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
}

@Suite("Acceptance: 入力欄キーワードの描画（task-4）")
struct AcceptanceComposerKeywordRenderingTests {

    @MainActor
    @Test("有効時、キーワードはスラッシュ・@参照・地の文のいずれとも違う色になる")
    func keywordUsesDistinctColorWhenEnabled() throws {
        let (textView, storage) = try makeTextView(highlightsKeywords: true)

        textView.applyComposerHighlights()

        let slash = color(storage, at: Offset.slashCommand)
        let keyword = color(storage, at: Offset.keyword)
        let plain = color(storage, at: Offset.plain)
        let reference = color(storage, at: Offset.fileReference)

        #expect(keyword != NSColor.labelColor, "キーワードは地の文と別色であること")
        #expect(keyword != slash, "キーワードはスラッシュコマンドと別色であること")
        #expect(keyword != reference, "キーワードは @参照 と別色であること")
        #expect(slash != reference, "既存の2色の区別を壊さないこと")
        #expect(plain == NSColor.labelColor, "地の文は既定色のままであること")
    }

    @MainActor
    @Test("無効時、キーワードは地の文と同じ色のまま")
    func keywordIsNotHighlightedWhenDisabled() throws {
        let (textView, storage) = try makeTextView(highlightsKeywords: false)

        textView.applyComposerHighlights()

        #expect(color(storage, at: Offset.keyword) == NSColor.labelColor,
                "Claude 以外のセッションではキーワードを強調しないこと")
        #expect(color(storage, at: Offset.slashCommand) != NSColor.labelColor,
                "無効時もスラッシュコマンドの強調は残ること")
        #expect(color(storage, at: Offset.fileReference) != NSColor.labelColor,
                "無効時も @参照 の強調は残ること")
    }

    @MainActor
    @Test("highlightsKeywords の既定値は false")
    func keywordHighlightIsOptOutByDefault() {
        let textView = IMESafeTextView.SubmitAwareTextView()

        #expect(textView.highlightsKeywords == false)
    }

    @MainActor
    @Test("highlightsKeywords を切り替えて再着色すると色が追随する")
    func togglingHighlightsKeywordsRecolors() throws {
        let (textView, storage) = try makeTextView(highlightsKeywords: false)
        textView.applyComposerHighlights()
        #expect(color(storage, at: Offset.keyword) == NSColor.labelColor)

        textView.highlightsKeywords = true
        textView.applyComposerHighlights()
        #expect(color(storage, at: Offset.keyword) != NSColor.labelColor,
                "有効化後の再着色でキーワードが色付くこと")

        textView.highlightsKeywords = false
        textView.applyComposerHighlights()
        #expect(color(storage, at: Offset.keyword) == NSColor.labelColor,
                "無効化後の再着色でキーワードの色が消えること")
    }

    @MainActor
    @Test("再着色しても選択範囲と既定の入力色は保たれる（既存挙動の退行なし）")
    func recoloringPreservesSelectionAndTypingColor() throws {
        let (textView, _) = try makeTextView(highlightsKeywords: true)
        textView.setSelectedRange(NSRange(location: Offset.plain, length: 5))
        let originalSelection = textView.selectedRange()

        textView.applyComposerHighlights()

        #expect(textView.selectedRange() == originalSelection)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == NSColor.labelColor)
    }
}
