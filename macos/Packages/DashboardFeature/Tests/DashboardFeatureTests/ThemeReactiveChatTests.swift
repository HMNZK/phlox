// テーマ（カラースキーマ）変更がチャットのコードハイライト色へ即時反映される。
// 注意: UserDefaults.standard の themeKey を一時的に書き換える。テスト内で必ず元へ戻す。

import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Theme reactive chat", .serialized)
struct ThemeReactiveChatTests {

    /// AttributedString 中の部分文字列 `word` を含む run の foregroundColor を返す。
    private func color(of word: String, in attributed: AttributedString) -> Color? {
        for run in attributed.runs {
            let text = String(attributed.characters[run.range])
            if text.contains(word) {
                return run.foregroundColor
            }
        }
        return nil
    }

    @Test
    func highlightCacheKeySeparatesSameCodeByTheme() {
        let code = "let theme_cache_probe = \"value\""
        let phlox = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "phlox")
        let githubLight = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "github-light")
        let phloxAgain = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "phlox")

        #expect(phlox != githubLight)
        #expect(phlox == phloxAgain)
        #expect(phlox.hasSuffix(code))
        #expect(githubLight.hasSuffix(code))
    }

    // 契約: 同一コードのハイライトは「その時点のアクティブテーマ」の色で返る。
    // テーマ変更後にキャッシュ由来の旧テーマ色を返してはならない。
    @Test @MainActor
    func highlightFollowsActiveThemeAcrossThemeChange() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: ThemeStore.themeKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        // 一意なプローブ（他テストのキャッシュと衝突させない）
        let code = "let theme_follow_keyword_probe = \"x\""

        defaults.set("phlox", forKey: ThemeStore.themeKey) // 暗色テーマ
        let darkHighlight = ChatCodeHighlighter.highlight(code)
        let darkExpectedKeyword = DSColor.codeSyntaxKeyword
        let darkKeyword = try #require(color(of: "let", in: darkHighlight))
        #expect(darkKeyword == darkExpectedKeyword)

        defaults.set("github-light", forKey: ThemeStore.themeKey) // 明色テーマ
        let lightHighlight = ChatCodeHighlighter.highlight(code)
        let lightExpectedKeyword = DSColor.codeSyntaxKeyword
        let lightKeyword = try #require(color(of: "let", in: lightHighlight))
        #expect(lightKeyword == lightExpectedKeyword)

        // 2テーマの keyword 色は実際に異なる（テストの自己検証: 同色なら比較が無意味）
        #expect(darkExpectedKeyword != lightExpectedKeyword)
        #expect(darkKeyword != lightKeyword)
    }

    // 文字列リテラル色も同様に追随する（keyword 特例でなく全色が対象であることの標本）。
    @Test @MainActor
    func stringLiteralColorFollowsActiveTheme() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: ThemeStore.themeKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        let code = "let theme_follow_string_probe = \"literal_probe\""

        defaults.set("phlox", forKey: ThemeStore.themeKey)
        _ = ChatCodeHighlighter.highlight(code) // 旧テーマでキャッシュを温める

        defaults.set("github-light", forKey: ThemeStore.themeKey)
        let lightHighlight = ChatCodeHighlighter.highlight(code)
        let expected = DSColor.codeSyntaxString
        let literal = try #require(color(of: "literal_probe", in: lightHighlight))
        #expect(literal == expected)
    }
}
