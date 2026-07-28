import AppKit
import DesignSystem
import Foundation
import Testing
@testable import SessionFeature

// task-4 白箱テスト（実装役著）。受け入れテストが触れない実装側の契約を覆う:
//   - 入力欄キーワードが専用トークン DSColor.composerKeyword で塗られること
//   - そのトークンがライト／ダーク両テーマで既存2色（紫・緑）と判別できること
//   - トークン種別（スラッシュ／@参照）と重なるキーワードは種別色が勝つこと
//
// テーマ切替は ThemeStore.active（UserDefaults.standard 固定依存）を一時的に書き換えるため、
// 該当スイートのみ .serialized とする（DesignSystem の ChatTokenThemeTests と同じ流儀）。

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

private func color(_ storage: NSTextStorage, at offset: Int) -> NSColor? {
    storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
}

@Suite("白箱: 入力欄キーワードの色トークン（task-4）", .serialized)
struct ComposerKeywordColorTokenTests {

    @Test("暗色テーマで、キーワード色はスラッシュ紫・@参照緑・コード数値のいずれとも違う")
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
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxKeyword)))
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxString)))
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxNumber)),
                "コードブロックの数値色を流用しないこと")
    }

    @Test("明色テーマでも、キーワード色はスラッシュ紫・@参照緑のいずれとも違う")
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
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxKeyword)))
        #expect(keyword != srgbComponents(NSColor(DSColor.codeSyntaxString)))
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

@Suite("白箱: 入力欄キーワードの描画（task-4）")
struct ComposerKeywordRenderingWhiteboxTests {

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
                == srgbComponents(NSColor(DSColor.codeSyntaxKeyword)))
    }

    @MainActor
    @Test("@参照と重なるキーワードは参照色のまま")
    func fileReferenceWinsOverKeyword() throws {
        let (storage, _) = try highlightedColors(text: "@ultrathink.md", highlightsKeywords: true)

        #expect(srgbComponents(try #require(color(storage, at: 1)))
                == srgbComponents(NSColor(DSColor.codeSyntaxString)))
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
