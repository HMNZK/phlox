import Foundation
import SwiftUI

/// Thinking インジケータの位相計算（純関数・task-2 契約面）。
/// ADR 0010: view body から状態を書き換えない。TimelineView が渡す date を入力に取る
/// 純関数としてアニメーション状態を導出する（Timer / repeatForever / body 内 mutate は禁止）。
enum ThinkingAnimationModel {
    /// アニメーション1周期（秒）。
    static let period: TimeInterval = 2.4

    struct DotState: Equatable {
        var opacity: Double
        var scale: Double
        var yOffset: Double
    }

    /// インジケータが表示されない間は TimelineView の更新を停止するスケジュールを返す。
    static func timelineSchedule(isVisible: Bool) -> ThinkingTimelineSchedule {
        ThinkingTimelineSchedule(isVisible: isVisible)
    }

    /// Timeline の稼働条件を純関数として合成する。
    /// transcript の最下部セルである Thinking インジケータは、最下部が viewport 内に
    /// ある間だけ更新する。
    static func isTimelineVisible(
        isInViewHierarchy: Bool,
        isInTranscriptViewport: Bool,
        isSceneActive: Bool
    ) -> Bool {
        isInViewHierarchy && isInTranscriptViewport && isSceneActive
    }

    /// index 番目のドットの表示状態を返す。同じ入力には常に同じ出力（決定論）。
    static func dotState(index: Int, dotCount: Int, date: Date) -> DotState {
        let safeDotCount = max(dotCount, 1)
        let normalizedIndex = ((index % safeDotCount) + safeDotCount) % safeDotCount
        let elapsed = date.timeIntervalSinceReferenceDate
        let cycleProgress = elapsed
            .truncatingRemainder(dividingBy: period) / period
        let phase = 2 * Double.pi * (
            cycleProgress - Double(normalizedIndex) / Double(safeDotCount)
        )
        let wave = (sin(phase) + 1) / 2

        return DotState(
            opacity: 0.35 + 0.65 * wave,
            scale: 0.85 + 0.30 * wave,
            yOffset: 1.5 - 3 * wave
        )
    }
}

/// `AnimationTimelineSchedule(paused: true)` は初期描画用のエントリを返すことがあるため、
/// 非表示時はエントリ列を空にして、更新停止を明示的に保証する。
struct ThinkingTimelineSchedule: TimelineSchedule {
    private let isVisible: Bool
    private let animationSchedule: AnimationTimelineSchedule

    init(isVisible: Bool) {
        self.isVisible = isVisible
        self.animationSchedule = AnimationTimelineSchedule(
            minimumInterval: 1.0 / 30.0,
            paused: !isVisible
        )
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(
            animationEntries: isVisible
                ? animationSchedule.entries(from: startDate, mode: mode)
                : nil
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        private var animationEntries: AnimationTimelineSchedule.Entries?

        fileprivate init(animationEntries: AnimationTimelineSchedule.Entries?) {
            self.animationEntries = animationEntries
        }

        mutating func next() -> Date? {
            animationEntries?.next()
        }
    }
}
