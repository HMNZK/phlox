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

/// hangAssessment（実行中ターンの経過表示）用の 1Hz スケジュール（task-2 契約面）。
/// 非表示時はエントリ列を空にして更新停止を保証する（ThinkingTimelineSchedule と同じ設計・
/// ADR 0067 の既知残余の解消）。
struct HangStatusTimelineSchedule: TimelineSchedule {
    private let isVisible: Bool

    init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(
            periodicEntries: isVisible
                ? PeriodicTimelineSchedule(from: startDate, by: 1).entries(from: startDate, mode: mode)
                : nil
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        private var periodicEntries: PeriodicTimelineSchedule.Entries?

        fileprivate init(periodicEntries: PeriodicTimelineSchedule.Entries?) {
            self.periodicEntries = periodicEntries
        }

        mutating func next() -> Date? {
            periodicEntries?.next()
        }
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

// MARK: - シマー（明度が左→右へ流れる）純関数（task-3 契約面）

extension ThinkingAnimationModel {
    /// シマー1周期（秒）。
    static let shimmerPeriod: TimeInterval = 1.6

    /// 明度の下限（帯から最も遠い位置の明度倍率）。
    static let shimmerMinBrightness: Double = 0.45

    /// 明度帯の中心位置（0=左端, 1=右端）。時間とともに前進し（左→右）、周期 shimmerPeriod で反復。戻り値 [0,1)。
    /// ADR 0067 と同じ設計: TimelineView の date のみを入力に取る純関数（Timer/repeatForever/@State 不使用）。
    /// シグネチャは受け入れテスト AcceptanceThinkingShimmerTests が凍結（実装役が本体を埋める）。
    static func shimmerPhase(date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let remainder = elapsed.truncatingRemainder(dividingBy: shimmerPeriod)
        let normalizedRemainder = remainder >= 0 ? remainder : remainder + shimmerPeriod
        return normalizedRemainder / shimmerPeriod
    }

    /// 正規化位置 position(0=左,1=右) の明度倍率。position==phase で最大 1.0、離れるほど shimmerMinBrightness へ減衰。
    /// 戻り値 [shimmerMinBrightness, 1.0]。決定論。
    static func shimmerBrightness(position: Double, phase: Double) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        let clampedPhase = min(max(phase, 0), 1)
        let distance = abs(clampedPosition - clampedPhase)
        let bandWidth = 0.22
        let normalizedDistance = distance / bandWidth
        let falloff = exp(-0.5 * normalizedDistance * normalizedDistance)
        return shimmerMinBrightness + (1 - shimmerMinBrightness) * falloff
    }
}
