// task-34（UI-04）の受け入れテスト。
//
// ベースラインでの red 理由: `DSHitTarget` は本タスクが新設を要求する API で、
// baseline_commit には存在しない（参照未解決でコンパイル不能＝red）。
//
// 契約: 絵柄サイズは変えず、小さなアイコン操作の押せる範囲だけを揃えて広げる。

import DesignSystem
import Testing

@Suite("task-34: hit target")
struct AcceptanceHitTargetTests {
    @Test("DSHitTarget.icon は 24 以上")
    func iconIsAtLeast24() {
        #expect(DSHitTarget.icon >= 24)
    }

    @Test("DSHitTarget.modeSegmentHeight は 24 以上")
    func modeSegmentHeightIsAtLeast24() {
        #expect(DSHitTarget.modeSegmentHeight >= 24)
    }

    @Test("DSHitTarget.modeSegmentWidth は modeSegmentHeight 以上")
    func modeSegmentWidthIsAtLeastHeight() {
        #expect(DSHitTarget.modeSegmentWidth >= DSHitTarget.modeSegmentHeight)
    }

    @Test("modeSegmentHeight + 2 * DSSpacing.xxs は 32 以下（行に収まる）")
    func modeSegmentFitsIn32ptRow() {
        #expect(DSHitTarget.modeSegmentHeight + 2 * DSSpacing.xxs <= 32)
    }

    @Test("DSIconSize.s は 10、DSIconSize.m は 12（絵柄を大きくしていない指紋）")
    func iconGlyphSizesUnchanged() {
        #expect(DSIconSize.s == 10)
        #expect(DSIconSize.m == 12)
    }
}
