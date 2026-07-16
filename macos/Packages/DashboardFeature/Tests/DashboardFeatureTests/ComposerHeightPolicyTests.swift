import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-6 白箱テスト — updateNSView の遅延書込を支える高さポリシーの境界を固定する。
@Suite("ComposerHeightPolicy whitebox")
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
    func fixedHeightPolicyDoesNotRequestWriteFromLockedInitialValue() {
        let next = ComposerHeightPolicy.resolvedHeight(
            usedTextHeight: 400,
            insetHeight: 16,
            minHeight: 40,
            maxHeight: 40
        )

        #expect(next == 40)
        #expect(ComposerHeightPolicy.shouldWrite(current: 40, next: next) == false)
    }

    @Test
    func exactlyHalfPointDifferenceDoesNotWrite() {
        #expect(ComposerHeightPolicy.shouldWrite(current: 44, next: 44.5) == false)
        #expect(ComposerHeightPolicy.shouldWrite(current: 44.5, next: 44) == false)
    }

    @Test
    func writeGuardConvergesAfterApplyingResolvedHeight() {
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
