import Testing
@testable import DesignSystemIOS

@Suite("task-3: DSInputCursorMath whitebox")
struct DSInputCursorMathWhiteboxTests {
    @Test
    func clampedCursorUTF16_clampsBelowZero() {
        #expect(DSInputCursorMath.clampedCursorUTF16(-3, textUTF16Count: 10) == 0)
    }

    @Test
    func clampedCursorUTF16_clampsAboveCount() {
        #expect(DSInputCursorMath.clampedCursorUTF16(15, textUTF16Count: 10) == 10)
    }

    @Test
    func clampedCursorUTF16_keepsInRangeValue() {
        #expect(DSInputCursorMath.clampedCursorUTF16(4, textUTF16Count: 10) == 4)
    }

    @Test
    func normalizedCursorIfNeeded_returnsNilWhenInRange() {
        #expect(DSInputCursorMath.normalizedCursorIfNeeded(2, textUTF16Count: 5) == nil)
    }

    @Test
    func normalizedCursorIfNeeded_returnsClampedWhenOutOfRange() {
        #expect(DSInputCursorMath.normalizedCursorIfNeeded(9, textUTF16Count: 5) == 5)
    }

    @Test
    func shouldPublishSelectionOffset_isFalseForSameValue() {
        #expect(!DSInputCursorMath.shouldPublishSelectionOffset(3, boundCursorUTF16: 3))
    }

    @Test
    func shouldPublishSelectionOffset_isTrueForDifferentValue() {
        #expect(DSInputCursorMath.shouldPublishSelectionOffset(3, boundCursorUTF16: 1))
    }

    @Test
    func shouldPushSelection_isFalseWhenAlreadyPushed() {
        #expect(!DSInputCursorMath.shouldPushSelection(cursorUTF16: 4, lastPushedCursorUTF16: 4))
    }

    @Test
    func shouldPushSelection_isTrueWhenCursorChangedExternally() {
        #expect(DSInputCursorMath.shouldPushSelection(cursorUTF16: 7, lastPushedCursorUTF16: 4))
    }
}
