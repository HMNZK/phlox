import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// 入力欄の高さポリシー。高さ決定は純関数 `ComposerHeightPolicy` に一本化し、
/// 「差分ガード付き書込は高々1回で固定点に収束する」性質で、描画パス中の書込（updateNSView）の
/// 遅延書込が送信後に入力欄の高さを戻し損ねる不具合とループ化の両方を防ぐ。
@Suite("ComposerHeightPolicy")
struct ComposerHeightPolicyTests {

    @Test
    func composerHeightBoundsDefaultToCompactForGridAndSingle() {
        // 契約変更（ユーザー要件・ADR 0046）: 「約80px」は入力欄パネル全体の見た目高さ。
        // エディタ最小高は1行ぶんの36（縦余白8×2＋36＋間隔4＋フッター28＝パネル84）。
        #expect(ComposerHeightBounds.single.min == 36)
        #expect(ComposerHeightBounds.grid.min == 36)
        #expect(ComposerHeightBounds.grid.max == 160)
        #expect(ComposerHeightBounds.single.max == ComposerHeightBounds.grid.max)
    }

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
    func resolvedHeightCeilsBeforeClampingWithinBounds() {
        let height = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 27.1,
            insetHeight: 16,
            minHeight: 44,
            maxHeight: 160
        )

        #expect(height == 44)

        let taller = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 80.1,
            insetHeight: 16,
            minHeight: 44,
            maxHeight: 160
        )

        #expect(taller == 97)
    }

    @Test
    func fixedHeightComposerAlwaysResolvesToLockedValue() {
        // 純関数の性質: min==max のとき入力量に依らず常にその値へクランプされる（固定高構成の一般契約）。
        // グリッドの現行構成（min 36 / max 160 の auto-grow）を表すものではない（→ GridComposerAutoGrowAcceptanceTests）。
        let short = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 5, insetHeight: 16, minHeight: 40, maxHeight: 40)
        let long = ComposerHeightPolicy.resolvedHeight(usedTextHeight: 400, insetHeight: 16, minHeight: 40, maxHeight: 40)
        #expect(short == 40)
        #expect(long == 40)
    }

    @Test
    func doesNotWriteWithinHalfPointTolerance() {
        // 0.5pt 以内の揺れは書き込まない（微振動でループしない）。ちょうど 0.5pt も書かない。
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.4) == false)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44.4, next: 44) == false)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.5) == false)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44.5, next: 44) == false)
    }

    @Test
    func writesBeyondHalfPointDifference() {
        // 0.5pt 超の差分は書き込む（送信後の 160→44 リセットが反映される）。
        #expect(ComposerHeightPolicy.shouldWrite(current: 160, next: 44) == true)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.6) == true)
    }

    @Test
    func writeGuardConvergesAfterApplyingResolvedHeight() {
        // 固定点収束: 書き込んだ後は shouldWrite(next, next) == false（遅延書込→再 update の連鎖は高々1回で停止する）。
        let next = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 50.2,
            insetHeight: 16,
            minHeight: 44,
            maxHeight: 160
        )

        #expect(ComposerHeightPolicy.shouldWrite(current: 160, next: next) == true)
        #expect(ComposerHeightPolicy.shouldWrite(current: next, next: next) == false)
    }
}
