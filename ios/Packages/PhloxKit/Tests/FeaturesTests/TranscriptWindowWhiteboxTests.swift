import Testing
@testable import Features

@Suite("TranscriptWindow white-box")
struct TranscriptWindowWhiteboxTests {
    @Test("上限を1件超えると先頭1件だけを隠す")
    func oneMessageOverLimitHidesOnlyOne() {
        let range = TranscriptWindow().visibleRange(totalCount: 51)

        #expect(range.startIndex == 1)
        #expect(range.hiddenCount == 1)
    }

    @Test("複数回の展開は毎回50件ずつ表示範囲を広げる")
    func repeatedExpansionGrowsByOneStepEachTime() {
        var window = TranscriptWindow()

        window.expand()
        #expect(window.visibleRange(totalCount: 180).startIndex == 80)

        window.expand()
        #expect(window.visibleRange(totalCount: 180).startIndex == 30)
    }

    @Test("負の件数でも範囲は負にならない")
    func negativeTotalCountIsClamped() {
        let range = TranscriptWindow().visibleRange(totalCount: -1)

        #expect(range.startIndex == 0)
        #expect(range.hiddenCount == 0)
    }
}
