// task-3 白箱テスト（実装役著）— GridComposerBar 配線はレビューで確認。ここでは
// `.compact` 固有の純ロジック（レイアウトメトリクス）を検証する。

import Testing
@testable import SessionFeature

@Suite("GridComposer parity")
struct GridComposerParityTests {

    @Test
    func indicatorMetrics_compactDonutIsSmallerThanRegular() {
        #expect(ComposerIndicatorMetrics.donutDiameter(for: .compact) == 12)
        #expect(ComposerIndicatorMetrics.donutDiameter(for: .regular) == 14)
        #expect(ComposerIndicatorMetrics.donutDiameter(for: .compact)
            < ComposerIndicatorMetrics.donutDiameter(for: .regular))
    }

    @Test
    func indicatorMetrics_compactBranchMaxWidthIsNarrowerThanRegular() {
        let compact = ComposerIndicatorMetrics.branchNameMaxWidth(for: .compact)
        let regular = ComposerIndicatorMetrics.branchNameMaxWidth(for: .regular)
        #expect(compact == 100)
        #expect(regular == nil)
    }

    @Test
    func indicatorMetrics_compactUsesMiddleTruncation() {
        #expect(ComposerIndicatorMetrics.branchTruncationMode(for: .compact) == .middle)
        #expect(ComposerIndicatorMetrics.branchTruncationMode(for: .regular) == .middle)
    }
}
