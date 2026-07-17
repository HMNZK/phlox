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
    func singleContext_resetStillReturnsTo200_notGridDefault() {
        var window = TranscriptWindow(context: .single)
        window.expand()
        window.reset()
        #expect(window.visibleRange(totalCount: 1000).startIndex == 800)
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
