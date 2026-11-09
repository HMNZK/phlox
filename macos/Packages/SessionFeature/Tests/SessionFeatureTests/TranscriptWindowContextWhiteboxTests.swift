import Foundation
import Testing
@testable import SessionFeature

/// task-2 白箱テスト（実装役著述）。表示文脈別の窓挙動を内部不変条件として符号化する。
@Suite(.serialized)
struct TranscriptWindowContextWhiteboxTests {

    @Test
    func gridTile_resetReturnsToGridDefault_afterExpand() {
        let total = 1000
        var window = TranscriptWindow(context: .gridTile)
        // 1000 - 16（gridTile 既定件数。ADR 0116 で 40 から引き下げ）
        #expect(window.visibleRange(totalCount: total).startIndex == 984)

        window.expand()
        window.reset()
        #expect(window.visibleRange(totalCount: total).startIndex == 984)
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
    func singleContext_visibleRangeKeepsNewestItemVisibleAsTranscriptGrows() {
        let window = TranscriptWindow(context: .single)

        for totalCount in [50, 51, 1000, 1001] {
            let range = window.visibleRange(totalCount: totalCount)
            #expect(range.startIndex <= totalCount - 1)
            #expect(totalCount - range.startIndex <= 50)
        }
    }
}
