import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 駆動源#1（composerMaxWidth の計測→@State→レイアウト往復）根治の契約:
/// composer 幅は親から演繹された幅のみを入力とする純関数 `ComposerLayout.maxWidth` に一本化する。
/// UI-02（2026-09-05）の新仕様: w<=0→nil / 正の幅→min(0.9w,800)。
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

    @Test
    func narrowColumnUses90Percent() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 500))
        #expect(abs(w - 450) < 0.001)
    }

    @Test
    func mediumColumnAlsoRespectsMaximumWidth() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1000))
        #expect(abs(w - 760) < 0.001)
    }

    @Test
    func wideColumnCapsAt800() throws {
        // 上限 760（2026-09-24 ユーザー承認で 800 → 760）。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 2000))
        #expect(abs(w - 760) < 0.001)
    }

    @Test
    func justBelowOldBoundaryCapsAt800() throws {
        // 旧境界直下も上限: 親を広げた際の急減を除去する。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1332))
        #expect(abs(w - 760) < 0.001)
    }

    @Test
    func justAboveBoundaryCapsAt800() throws {
        // 境界直上も上限 760。
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1334))
        #expect(abs(w - 760) < 0.001)
    }
}
