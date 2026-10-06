import AppKit
import DesignSystem
import Foundation
import Testing
@testable import SessionFeature

// 入力欄でキーワードを「スラッシュコマンド・@参照・地の文のいずれとも異なる色」で描画し、
// Claude セッションだけで有効にする（有効/無効は highlightsKeywords が受け持つ）。
// キーワードは専用トークン DSColor.composerKeyword で塗り、トークン種別（スラッシュ／@参照）と
// 重なるキーワードは種別色が勝つ。トークンはライト／ダーク両テーマでスラッシュ・@参照と判別できる。
//
// 注: SwiftUI View（ChatComposer / GridChatColumn）が agentRef を見て
// highlightsKeywords を渡す配線は NSViewRepresentableContext を組めないため本ファイルでは検証しない。

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

@Suite("Composer keyword rendering")
struct ComposerKeywordRenderingTests {

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

    @MainActor
    @Test("有効時、キーワードは DSColor.composerKeyword で塗られる")
    func keywordUsesDedicatedToken() throws {
        let (storage, _) = try highlightedColors(text: "think ultrathink now", highlightsKeywords: true)

        #expect(srgbComponents(try #require(color(storage, at: 6)))
                == srgbComponents(NSColor(DSColor.composerKeyword)))
    }

    @MainActor
    @Test("スラッシュコマンドと重なるキーワードはスラッシュ色のまま")
    func slashTokenWinsOverKeyword() throws {
        let (storage, _) = try highlightedColors(text: "/ultrathink", highlightsKeywords: true)

        #expect(srgbComponents(try #require(color(storage, at: 1)))
                == srgbComponents(NSColor(DSColor.accentInk)))
    }

    @MainActor
    @Test("@参照と重なるキーワードは参照色のまま")
    func fileReferenceWinsOverKeyword() throws {
        let (storage, _) = try highlightedColors(text: "@ultrathink.md", highlightsKeywords: true)

        #expect(srgbComponents(try #require(color(storage, at: 1)))
                == srgbComponents(NSColor(DSColor.attentionInk(.question))))
    }

    @MainActor
    @Test("キーワードが複数あればすべて塗られる")
    func multipleKeywordsAreColored() throws {
        let (storage, _) = try highlightedColors(text: "ultrathink and ultrareview", highlightsKeywords: true)

        let expected = srgbComponents(NSColor(DSColor.composerKeyword))
        #expect(srgbComponents(try #require(color(storage, at: 0))) == expected)
        #expect(srgbComponents(try #require(color(storage, at: 15))) == expected)
    }

    @MainActor
    @Test("空文字でも再着色は落ちない")
    func emptyTextIsSafe() throws {
        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.highlightsKeywords = true
        textView.string = ""

        textView.applyComposerHighlights()

        #expect(textView.string.isEmpty)
    }
}

private func srgbComponents(_ color: NSColor) -> [CGFloat]? {
    guard let converted = color.usingColorSpace(.sRGB) else { return nil }
    return [converted.redComponent, converted.greenComponent, converted.blueComponent]
}

@MainActor
private func highlightedColors(
    text: String,
    highlightsKeywords: Bool
) throws -> (storage: NSTextStorage, textView: IMESafeTextView.SubmitAwareTextView) {
    let textView = IMESafeTextView.SubmitAwareTextView()
    textView.textColor = .labelColor
    textView.highlightsKeywords = highlightsKeywords
    textView.string = text
    var typingAttributes = textView.typingAttributes
    typingAttributes[.foregroundColor] = NSColor.labelColor
    textView.typingAttributes = typingAttributes
    let storage = try #require(textView.textStorage)
    textView.applyComposerHighlights()
    return (storage, textView)
}

@Suite("Composer keyword color token", .serialized)
struct ComposerKeywordColorTokenTests {

    @Test("暗色テーマで、キーワード色はスラッシュ・@参照・コード数値のいずれとも違う")
    func keywordTokenIsDistinctInDarkTheme() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }
        defaults.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)

        let keyword = try #require(srgbComponents(NSColor(DSColor.composerKeyword)))
        #expect(keyword != srgbComponents(NSColor(DSColor.accentInk)))
        #expect(keyword != srgbComponents(NSColor(DSColor.attentionInk(.question))))
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxNumber)),
                "コードブロックの数値色を流用しないこと")
    }

    @Test("明色テーマでも、キーワード色はスラッシュ・@参照のいずれとも違う")
    func keywordTokenIsDistinctInLightTheme() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }
        defaults.set(AppTheme.githubLight.id, forKey: ThemeStore.themeKey)

        let keyword = try #require(srgbComponents(NSColor(DSColor.composerKeyword)))
        #expect(keyword != srgbComponents(NSColor(DSColor.accentInk)))
        #expect(keyword != srgbComponents(NSColor(DSColor.attentionInk(.question))))
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxNumber)),
                "コードブロックの数値色を流用しないこと")
    }

    @Test("明色テーマと暗色テーマでキーワード色が切り替わる（値が1つではない）")
    func keywordTokenFollowsTheme() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        defaults.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        let dark = try #require(srgbComponents(NSColor(DSColor.composerKeyword)))
        defaults.set(AppTheme.githubLight.id, forKey: ThemeStore.themeKey)
        let light = try #require(srgbComponents(NSColor(DSColor.composerKeyword)))

        #expect(dark != light)
    }
}
