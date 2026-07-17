import Foundation
import Testing
import SwiftUI
@testable import SessionFeature

// task-2（グリッド描画コストの削減）の受け入れテスト。PM が著す不変の契約
// （実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を
// 得たうえでハーネス部分に限り修理してよい）。
//
// 契約の骨子:
// - transcript の表示窓（TranscriptWindow）は表示文脈で既定件数を変える:
//   single = 200（従来どおり）/ gridTile = 40（タイルは小さく、全タイル常時描画のため）。
// - reset() は自分の文脈の既定値へ戻る（gridTile が 200 へ膨らまない）。
// - hangAssessment 用 1Hz スケジュールは非表示時にエントリを空にして更新停止を保証する
//   （ThinkingTimelineSchedule と同じ設計。ADR 0067 の既知残余の解消）。

// MARK: - TranscriptWindow の文脈別既定値

@Test
func transcriptWindow_defaultLimitDependsOnPresentationContext() {
    #expect(TranscriptWindow.defaultLimit(for: .single) == 200)
    #expect(TranscriptWindow.defaultLimit(for: .gridTile) == 40)
}

@Test
func transcriptWindow_gridTileContext_visibleRangeUsesGridLimit() {
    let window = TranscriptWindow(context: .gridTile)
    let range = window.visibleRange(totalCount: 1000)
    #expect(range.startIndex == 960)
    #expect(range.hiddenCount == 960)
}

@Test
func transcriptWindow_singleContext_visibleRangeUnchangedFromLegacyDefault() {
    let window = TranscriptWindow(context: .single)
    let range = window.visibleRange(totalCount: 1000)
    #expect(range.startIndex == 800)
    #expect(range.hiddenCount == 800)
}

@Test
func transcriptWindow_gridTile_resetReturnsToGridDefault() {
    var window = TranscriptWindow(context: .gridTile)
    window.expand()
    window.reset()
    #expect(window.visibleRange(totalCount: 1000).hiddenCount == 960)
}

@Test
func transcriptWindow_gridTile_expandStillGrowsWindow() {
    var window = TranscriptWindow(context: .gridTile)
    window.expand()
    // 拡張後は 40 より多く表示される（単調増加の保存。正確な step は契約で固定しない）。
    #expect(window.visibleRange(totalCount: 1000).hiddenCount < 960)
}

// MARK: - hangAssessment 1Hz スケジュールの非表示停止

@Test
func hangSchedule_invisible_yieldsNoEntries() {
    let schedule = HangStatusTimelineSchedule(isVisible: false)
    var iterator = schedule
        .entries(from: Date(timeIntervalSinceReferenceDate: 0), mode: .normal)
        .makeIterator()
    #expect(iterator.next() == nil, "非表示なのに 1Hz エントリが供給されている（更新が止まらない）")
}

@Test
func hangSchedule_visible_ticksAtOneSecondCadence() throws {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let schedule = HangStatusTimelineSchedule(isVisible: true)
    var iterator = schedule.entries(from: start, mode: .normal).makeIterator()
    let firstEntry = iterator.next()
    let secondEntry = iterator.next()
    let first = try #require(firstEntry)
    let second = try #require(secondEntry)
    #expect(abs(second.timeIntervalSince(first) - 1.0) < 0.001)
}
