import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-6 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// Bug A（updateNSView＝描画パス中の measuredHeight 書込が落ち、送信後に入力欄高さが戻らない）
/// 根治の契約: 高さ決定を純関数 `ComposerHeightPolicy` に一本化し、
/// 「差分ガード付き書込は高々1回で固定点に収束する」性質をここで固定する。
/// 描画パス中に書込が発生しないこと（構造制約）はレビュー Rubric と実機統合検証が担う。
@Suite("task-6 ComposerHeightPolicy acceptance")
struct Task6ComposerHeightPolicyAcceptanceTests {

    @Test
    func clampsUpToMinHeight() {
        // 1行ぶんの短いテキスト → 最小高へクランプ（ChatComposer: min 44）。
        let h = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 10, insetHeight: 16, minHeight: 44, maxHeight: 160)
        #expect(h == 44)
    }

    @Test
    func clampsDownToMaxHeight() {
        // 長文 → 最大高へクランプ（ChatComposer: max 160）。
        let h = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 500, insetHeight: 16, minHeight: 44, maxHeight: 160)
        #expect(h == 160)
    }

    @Test
    func ceilsFractionalHeights() {
        // 端数はピクセル境界へ切り上げ（ceil）。66.2 → 67。
        let h = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 50.2, insetHeight: 16, minHeight: 44, maxHeight: 160)
        #expect(h == 67)
    }

    @Test
    func fixedHeightComposerAlwaysResolvesToLockedValue() {
        // 純関数の性質: min==max のとき入力量に依らず常にその値へクランプされる（固定高構成の一般契約）。
        // 注: グリッド GridComposerBar は task-1 で 40〜160 の可変（auto-grow）へ移行したため、
        // これは「min==max を渡した場合のクランプ挙動」を固定する汎用テストであり、
        // グリッドの現行構成（min 40 / max 160）を表すものではない（→ GridComposerAutoGrowAcceptanceTests）。
        let short = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 5, insetHeight: 16, minHeight: 40, maxHeight: 40)
        let long = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 400, insetHeight: 16, minHeight: 40, maxHeight: 40)
        #expect(short == 40)
        #expect(long == 40)
    }

    @Test
    func doesNotWriteWithinHalfPointTolerance() {
        // 0.5pt 以内の揺れは書き込まない（微振動でループしない）。
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.4) == false)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44.4, next: 44) == false)
    }

    @Test
    func writesBeyondHalfPointDifference() {
        // 0.5pt 超の差分は書き込む（送信後の 160→44 リセットが反映される）。
        #expect(ComposerHeightPolicy.shouldWrite(current: 160, next: 44) == true)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.6) == true)
    }

    @Test
    func convergesToFixedPointAfterSingleWrite() {
        // 固定点収束: next を書き込んだ後は shouldWrite(next, next) == false。
        // すなわち遅延書込→再 update の連鎖は高々1回で停止する（Bug A 対策がループ化しない核心）。
        let next = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 50.2, insetHeight: 16, minHeight: 44, maxHeight: 160)
        #expect(ComposerHeightPolicy.shouldWrite(current: next, next: next) == false)
    }
}
