// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — テーマ（カラースキーマ）変更がチャットの描画色へ即時反映される。
// 保留中は LOOPFLOW_PENDING_TASK3=1 で suite ごとスキップできる（PM の検証運用用。実装役は使わない）。
//
// 注意: UserDefaults.standard の themeKey を一時的に書き換える。テスト内で必ず元へ戻す。

import DesignSystem
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite(
    "ChatFix task-3: テーマ変更へのハイライト追随",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["LOOPFLOW_PENDING_TASK3"] != "1")
)
struct ChatFixTask3ThemeHighlightAcceptanceTests {

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
        let code = "let chatfix_task3_probe = \"x\""

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

        let code = "let chatfix_task3_probe2 = \"literal_probe\""

        defaults.set("phlox", forKey: ThemeStore.themeKey)
        _ = ChatCodeHighlighter.highlight(code) // 旧テーマでキャッシュを温める

        defaults.set("github-light", forKey: ThemeStore.themeKey)
        let lightHighlight = ChatCodeHighlighter.highlight(code)
        let expected = DSColor.codeSyntaxString
        let literal = try #require(color(of: "literal_probe", in: lightHighlight))
        #expect(literal == expected)
    }
}
