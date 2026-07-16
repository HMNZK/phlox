import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 駆動源#1（composerMaxWidth の計測→@State→レイアウト往復）根治の契約:
/// composer 幅は親から演繹された幅のみを入力とする純関数 `ComposerLayout.maxWidth` に一本化する。
/// 数式は現行と同一: w<=0→nil / 0.6w<800→0.9w / それ以外→min(0.6w,800)=800。
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

    @Test
    func narrowColumnUses90Percent() throws {
        // 60% (600) < 800 → 90% にフォールバック。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1000))
        #expect(abs(w - 900) < 0.001)
    }

    @Test
    func wideColumnCapsAt800() throws {
        // 60% (1200) >= 800 → 上限 800。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 2000))
        #expect(abs(w - 800) < 0.001)
    }

    @Test
    func justBelowBoundaryUses90Percent() throws {
        // 境界直下: 60% of 1332 = 799.2 < 800 → 0.9 * 1332 = 1198.8。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1332))
        #expect(abs(w - 1198.8) < 0.001)
    }

    @Test
    func justAboveBoundaryCapsAt800() throws {
        // 境界直上: 60% of 1334 = 800.4 >= 800 → 800。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1334))
        #expect(abs(w - 800) < 0.001)
    }
}
