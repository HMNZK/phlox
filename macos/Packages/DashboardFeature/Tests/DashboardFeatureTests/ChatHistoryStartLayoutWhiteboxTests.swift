import CoreGraphics
import Testing
@testable import SessionFeature

// task-1 白箱テスト（実装役著述）。
// 契約: ChatHistoryStartLayout のクランプ・単調性・予約量の名指しハザードを純関数経路で捕まえる。

@Suite("ChatHistoryStartLayout whitebox")
struct ChatHistoryStartLayoutWhiteboxTests {

    @Test
    func verticalReserveMatchesOuterPaddingAndGap() {
        #expect(ChatHistoryStartLayout.verticalReserve == 56)
        #expect(ChatHistoryStartLayout.minCardHeight == 120)
        #expect(ChatHistoryStartLayout.maxCardHeightCap == 360)
    }

    @Test
    func maxCardHeightIsMonotonicInAvailableHeight() {
        let low = ChatHistoryStartLayout.maxCardHeight(availableHeight: 300, composerHeight: 80)
        let high = ChatHistoryStartLayout.maxCardHeight(availableHeight: 500, composerHeight: 80)
        #expect(high >= low)
    }

    @Test
    func maxCardHeightDecreasesWhenComposerGrows() {
        let compact = ChatHistoryStartLayout.maxCardHeight(availableHeight: 500, composerHeight: 60)
        let tall = ChatHistoryStartLayout.maxCardHeight(availableHeight: 500, composerHeight: 140)
        #expect(compact > tall)
    }

    @Test
    func maxCardHeightNeverExceedsCapOrDropsBelowFloor() {
        let samples: [(CGFloat, CGFloat)] = [
            (120, 0), (200, 160), (800, 120), (536, 120), (400, 120),
        ]
        for (available, composer) in samples {
            let height = ChatHistoryStartLayout.maxCardHeight(
                availableHeight: available,
                composerHeight: composer
            )
            #expect(height >= ChatHistoryStartLayout.minCardHeight)
            #expect(height <= ChatHistoryStartLayout.maxCardHeightCap)
        }
    }

    @Test
    func bottomInsetTracksComposerHeightLinearly() {
        #expect(ChatHistoryStartLayout.bottomInset(composerHeight: 0) == 0)
        #expect(ChatHistoryStartLayout.bottomInset(composerHeight: 88) == 88)
        #expect(ChatHistoryStartLayout.bottomInset(composerHeight: 200) == 200)
    }
}
