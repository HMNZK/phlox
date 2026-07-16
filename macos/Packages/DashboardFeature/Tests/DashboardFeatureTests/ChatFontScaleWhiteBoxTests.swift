import Testing
import Foundation
@testable import DashboardFeature
@testable import SessionFeature

/// task-2 白箱テスト — 最重要ハザード（RichMarkdownView の static テーマキャッシュ）の回帰ガード。
/// キャッシュキーがスケールを含まないと、最初に生成したテーマが固定され Cmd+/- で本文が
/// 変わらなくなる。キーがスケール依存であること（＝スケール違いで別キー＝別テーマ生成）を固定する。
@Suite("ChatFontScale whitebox")
struct ChatFontScaleWhiteBoxTests {

    @Test @MainActor
    func themeCacheKeyVariesByScale() {
        let k10 = RichMarkdownView.themeCacheKey(themeID: "phlox", scale: 1.0)
        let k15 = RichMarkdownView.themeCacheKey(themeID: "phlox", scale: 1.5)
        #expect(k10 != k15, "スケール違いでキャッシュキーが分かれること（キーにスケールが含まれる）")
    }

    @Test @MainActor
    func themeCacheKeyIsStableForSameInputs() {
        #expect(
            RichMarkdownView.themeCacheKey(themeID: "phlox", scale: 1.0)
            == RichMarkdownView.themeCacheKey(themeID: "phlox", scale: 1.0)
        )
    }

    @Test @MainActor
    func themeCacheKeyVariesByTheme() {
        #expect(
            RichMarkdownView.themeCacheKey(themeID: "phlox", scale: 1.0)
            != RichMarkdownView.themeCacheKey(themeID: "nord", scale: 1.0)
        )
    }
}
