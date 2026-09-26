import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 駆動源#1（composerMaxWidth の計測→@State→レイアウト往復）根治の契約:
/// composer 幅は親から演繹された幅のみを入力とする純関数 `ComposerLayout.maxWidth` に一本化する。
/// UI-02（2026-09-05）の新仕様: w<=0→nil / 正の幅→min(0.9w,800)。2026-09-26 から 0.8w（上限なし）。
/// 旧境界で約400pt縮む不連続を除き、単一真実源と上限は維持する。
/// 「計測フィードバックが消えたこと」自体は構造制約のためレビュー（Rubric）と実機統合検証が担う。
@Suite("task-5 ComposerLayout acceptance")
struct Task5ComposerLayoutAcceptanceTests {

    @Test
    func zeroWidthFallsBackToNil() {
        // 初回フレーム（幅未確定）は制約なし。
        #expect(ComposerLayout.maxWidth(mainColumnWidth: 0) == nil)
    }

    @Test
    func negativeWidthFallsBackToNil() {
        // 演繹式のクランプ前提が崩れても破綻しない。
        #expect(ComposerLayout.maxWidth(mainColumnWidth: -50) == nil)
    }

    // 2026-09-26 ユーザー決定: 90%・上限 760 から「上限なしで 80%」へ。
    @Test
    func narrowColumnUses80Percent() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 500))
        #expect(abs(w - 400) < 0.001)
    }

    @Test
    func wideColumnHasNoCap() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 2000))
        #expect(abs(w - 1600) < 0.001)
    }

    @Test
    func oldBoundaryHasNoJump() throws {
        // 旧境界の前後でも同じ割合: 親を広げた際の急減が無い。
        let below = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1332))
        let above = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1334))
        #expect(abs(below - 1065.6) < 0.001)
        #expect(abs(above - 1067.2) < 0.001)
    }
}
