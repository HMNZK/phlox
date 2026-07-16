import Foundation
import Testing
@testable import SessionFeature

private let thinkingAnimationTestDate = Date(timeIntervalSinceReferenceDate: 1_000.3)

@Test func thinkingTimeline_pausesWhenIndicatorIsNotVisible() {
    let schedule = ThinkingAnimationModel.timelineSchedule(isVisible: false)
    var entries = schedule.entries(from: .now, mode: .normal)

    #expect(entries.next() == nil)
}

@Test func thinkingTimeline_stopsWhenCellLeavesViewport() {
    let isVisible = ThinkingAnimationModel.isTimelineVisible(
        isInViewHierarchy: true,
        isInTranscriptViewport: false,
        isSceneActive: true
    )
    let schedule = ThinkingAnimationModel.timelineSchedule(isVisible: isVisible)
    var entries = schedule.entries(from: .now, mode: .normal)

    #expect(!isVisible)
    #expect(entries.next() == nil)
}

@Test func thinkingAnimation_normalizesIndicesAtDotCountBoundary() {
    let first = ThinkingAnimationModel.dotState(
        index: 0,
        dotCount: 3,
        date: thinkingAnimationTestDate
    )
    let wrapped = ThinkingAnimationModel.dotState(
        index: 3,
        dotCount: 3,
        date: thinkingAnimationTestDate
    )
    let negativeWrapped = ThinkingAnimationModel.dotState(
        index: -1,
        dotCount: 3,
        date: thinkingAnimationTestDate
    )
    let last = ThinkingAnimationModel.dotState(
        index: 2,
        dotCount: 3,
        date: thinkingAnimationTestDate
    )

    #expect(wrapped == first)
    #expect(negativeWrapped == last)
}

@Test func thinkingAnimation_recomputesPhaseSpacingWhenDotCountChanges() {
    let twoDots = ThinkingAnimationModel.dotState(
        index: 1,
        dotCount: 2,
        date: thinkingAnimationTestDate
    )
    let threeDots = ThinkingAnimationModel.dotState(
        index: 1,
        dotCount: 3,
        date: thinkingAnimationTestDate
    )

    #expect(twoDots != threeDots)
}

@Test func thinkingAnimation_singleOrEmptyDotCountRemainsFiniteAndBounded() {
    for dotCount in [0, 1] {
        for index in [-1, 0, 1] {
            let state = ThinkingAnimationModel.dotState(
                index: index,
                dotCount: dotCount,
                date: thinkingAnimationTestDate
            )

            #expect(state.opacity.isFinite)
            #expect(state.scale.isFinite)
            #expect(state.yOffset.isFinite)
            #expect(state.opacity >= 0.1 && state.opacity <= 1)
            #expect(state.scale >= 0.4 && state.scale <= 1.8)
            #expect(abs(state.yOffset) <= 6)
        }
    }
}
