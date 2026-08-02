import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

// task-2（非アクティブウィンドウでも Thinking 表示を止めない）の受け入れテスト。
// PM が著す不変の契約（実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約の骨子（ゲート① でのユーザー決定・2026-08-02）:
// - ウィンドウが「可視だがキーでない」(.inactive) 間は止めない。
//   他アプリを前面にしただけで経過秒が固まるのはユーザー体験として不合理なため。
// - ウィンドウが「不可視」(.background = 最小化・非表示) の間は従来どおり止める。
// - ADR 0067 決定3 の可視性合成のうち `scenePhase == .active` の条件だけを変更する。
//   ライフサイクル (isInViewHierarchy) と viewport (isInTranscriptViewport) の意味は不変。

@Test
func isTimelineVisible_isTrue_whenSceneIsActive() {
    #expect(
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: true,
            isInTranscriptViewport: true,
            scenePhase: .active
        )
    )
}

@Test
func isTimelineVisible_isTrue_whenWindowIsVisibleButNotKey() {
    #expect(
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: true,
            isInTranscriptViewport: true,
            scenePhase: .inactive
        ),
        "可視だが非キーのウィンドウで停止してはならない（ゲート① のユーザー決定）"
    )
}

@Test
func isTimelineVisible_isFalse_whenWindowIsNotVisible() {
    #expect(
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: true,
            isInTranscriptViewport: true,
            scenePhase: .background
        ) == false,
        "不可視（最小化・非表示）では従来どおり停止する"
    )
}

@Test
func isTimelineVisible_isFalse_whenNotInViewHierarchy_regardlessOfScenePhase() {
    for phase in [ScenePhase.active, .inactive, .background] {
        #expect(
            ThinkingAnimationModel.isTimelineVisible(
                isInViewHierarchy: false,
                isInTranscriptViewport: true,
                scenePhase: phase
            ) == false
        )
    }
}

@Test
func isTimelineVisible_isFalse_whenOutsideTranscriptViewport_regardlessOfScenePhase() {
    for phase in [ScenePhase.active, .inactive, .background] {
        #expect(
            ThinkingAnimationModel.isTimelineVisible(
                isInViewHierarchy: true,
                isInTranscriptViewport: false,
                scenePhase: phase
            ) == false
        )
    }
}
