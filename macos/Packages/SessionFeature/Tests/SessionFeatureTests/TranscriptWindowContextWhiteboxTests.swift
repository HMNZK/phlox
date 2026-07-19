import Foundation
import Testing
@testable import SessionFeature

/// task-2 白箱テスト（実装役著述）。表示文脈別の窓挙動を内部不変条件として符号化する。
@Suite(.serialized)
struct TranscriptWindowContextWhiteboxTests {

    @Test
    func gridTile_reveal_makesHiddenIndexVisibleWithinGridWindow() {
        let total = 1000
        var window = TranscriptWindow(context: .gridTile)
        #expect(window.visibleRange(totalCount: total).startIndex == 960)

        window.reveal(index: 100, totalCount: total)
        let start = window.visibleRange(totalCount: total).startIndex
        #expect(start <= 100, "gridTile reveal 後に index=100 が可視域に入っていない start=\(start)")

        window.expand()
        window.reset()
        #expect(window.visibleRange(totalCount: total).startIndex == 960)
    }

    @Test
    func singleContext_resetReturnsTo50_notGridDefault() {
        var window = TranscriptWindow(context: .single)
        window.expand()
        window.reset()
        #expect(window.visibleRange(totalCount: 1000).startIndex == 950)
    }

    @Test
    func singleContext_expandStepIsFifty_andExpandShowsOneHundredItems() {
        #expect(TranscriptWindow.expandStep == 50)

        var window = TranscriptWindow(context: .single)
        window.expand()

        #expect(window.visibleRange(totalCount: 1000).startIndex == 900)
    }

    @Test
    func singleContext_revealMarginToleratesStreamingGrowthUpToNewExpandStep() {
        let targetIndex = 949
        let oldTotal = 1000
        var window = TranscriptWindow(context: .single)
        #expect(window.visibleRange(totalCount: oldTotal).startIndex == 950)

        window.reveal(index: targetIndex, totalCount: oldTotal)

        for delta in [0, 1, 49, 50] {
            let start = window.visibleRange(totalCount: oldTotal + delta).startIndex
            #expect(start <= targetIndex,
                    "single reveal: index=\(targetIndex) が delta=\(delta) の成長で隠れ域へ落ちた start=\(start)")
        }
    }

    @Test
    func singleContext_visibleRangeKeepsNewestItemVisibleAsTranscriptGrows() {
        let window = TranscriptWindow(context: .single)

        for totalCount in [50, 51, 1000, 1001] {
            let range = window.visibleRange(totalCount: totalCount)
            #expect(range.startIndex <= totalCount - 1)
            #expect(totalCount - range.startIndex <= 50)
        }
    }

    @Test
    func gridTile_reveal_marginToleratesStreamingGrowthUpToExpandStep() {
        let targetIndex = 10
        var window = TranscriptWindow(context: .gridTile)
        let oldTotal = 500
        #expect(window.visibleRange(totalCount: oldTotal).startIndex > targetIndex)
        window.reveal(index: targetIndex, totalCount: oldTotal)
        for delta in [0, 1, TranscriptWindow.expandStep] {
            let start = window.visibleRange(totalCount: oldTotal + delta).startIndex
            #expect(start <= targetIndex,
                    "gridTile reveal: index=\(targetIndex) が delta=\(delta) の成長で隠れ域へ落ちた start=\(start)")
        }
    }
}
