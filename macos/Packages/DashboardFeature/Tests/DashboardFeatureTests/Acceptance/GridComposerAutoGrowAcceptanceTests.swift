import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（グリッド入力欄 auto-grow）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約（再更新・ユーザー要件 = ADR 0046）: 「約80px」は入力欄パネル全体の見た目高さであり、
/// エディタ単体 min=80 の実装はパネル約140pxのデグレだった（2026-07-07 実機確認）。
/// デフォルトはコンパクト値（single 44 / grid 40）へ復帰し、160 までの auto-grow を維持する。
/// 高さ境界の単一真実源は `ComposerHeightBounds`（マジックナンバー排除）。
/// View の frame 反映と CPU 非固着（ADR 0030 クラス）は swift test では判定できないため、
/// レビュー Rubric と PM/ユーザーの実機 runtime 検証が担う。ここでは「境界値の契約」を凍結する。
@Suite("task-1 grid composer auto-grow acceptance")
struct GridComposerAutoGrowAcceptanceTests {

    @Test
    func gridBoundsEnableGrowth() {
        // 契約変更（ADR 0046）: グリッドは下限36・上限160。max>min＝伸縮可能。
        #expect(ComposerHeightBounds.grid.min == 36)
        #expect(ComposerHeightBounds.grid.max == 160)
        #expect(ComposerHeightBounds.grid.max > ComposerHeightBounds.grid.min)
    }

    @Test
    func singleBoundsDefaultToCompact() {
        // 契約変更（ADR 0046）: 単一表示もデフォルト36・上限160（パネル全体≈80pxの内訳は
        // ComposerHeightPolicy.swift のコメント参照）。
        #expect(ComposerHeightBounds.single.min == 36)
        #expect(ComposerHeightBounds.single.max == 160)
    }

    @Test
    func gridPolicyGrowsWithLongText() {
        // グリッド境界を通した高さ決定: 長文は上限160へ伸びる。
        let tall = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 400,
            insetHeight: 16,
            minHeight: ComposerHeightBounds.grid.min,
            maxHeight: ComposerHeightBounds.grid.max
        )
        #expect(tall == 160)
    }

    @Test
    func gridPolicyRestsAtMinForShortText() {
        // 短文は下限36に留まる（初期高＝安静時の高さ）。
        let short = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 4,
            insetHeight: 16,
            minHeight: ComposerHeightBounds.grid.min,
            maxHeight: ComposerHeightBounds.grid.max
        )
        #expect(short == 36)
    }

    @Test
    func gridPolicyGrowsMidRange() {
        // 中間量のテキストは 36 と 160 の間の実測高（＋ceil）を返す＝真に可変であることを固定。
        // usedText 120 + inset 16 = 136（36<136<160）。
        let mid = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 120,
            insetHeight: 16,
            minHeight: ComposerHeightBounds.grid.min,
            maxHeight: ComposerHeightBounds.grid.max
        )
        #expect(mid == 136)
    }
}
