import SwiftUI

/// シマー（明度が左→右へ流れる）アニメーション位相を計算する純関数群（テスト可能にするため View から分離）。
/// macOS `ThinkingAnimationModel` のシマー関数と同一セマンティクス。入力は iOS 慣習の `TimeInterval`。
public enum DSThinkingAnimationModel {
    /// シマー1周期（秒）。
    public static let shimmerPeriod: TimeInterval = 1.6

    /// 明度の下限（帯から最も遠い位置の明度倍率）。
    public static let shimmerMinBrightness: Double = 0.45

    /// 帯を画面外まで逃がすための左右余白（正規化幅）。
    public static let shimmerMargin: Double = 0.6

    /// 時刻 `time` を `shimmerPeriod` で割った余りを [0,1) へ正規化（負値も [0,1) へ）。
    public static func shimmerPhase(at time: TimeInterval) -> Double {
        let remainder = time.truncatingRemainder(dividingBy: shimmerPeriod)
        let normalizedRemainder = remainder >= 0 ? remainder : remainder + shimmerPeriod
        return normalizedRemainder / shimmerPeriod
    }

    /// phase(0..1) を、画面外余白を含む帯中心 [−shimmerMargin, 1+shimmerMargin] へ線形写像する。
    public static func shimmerBandCenter(phase: Double) -> Double {
        let clampedPhase = min(max(phase, 0), 1)
        return clampedPhase * (1 + 2 * shimmerMargin) - shimmerMargin
    }

    /// 正規化位置 position(0=左,1=右) の明度倍率。position==phase で最大 1.0、離れるほど shimmerMinBrightness へ減衰。
    /// phase（＝帯の中心）は [0,1] 外も受け付ける。position のみ [0,1] へクランプ。
    public static func shimmerBrightness(position: Double, phase: Double) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        let distance = abs(clampedPosition - phase)
        let bandWidth = 0.22
        let normalizedDistance = distance / bandWidth
        let falloff = exp(-0.5 * normalizedDistance * normalizedDistance)
        return shimmerMinBrightness + (1 - shimmerMinBrightness) * falloff
    }
}

/// 応答生成中インジケータ。「Thinking...」イタリックのシマー + 任意の reasoning プレビュー（3行まで）。
/// accessibilityReduceMotion 有効時はアニメーションせず静的テキストを表示する。
public struct DSThinkingIndicator: View {
    let reasoningPreview: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(reasoningPreview: String? = nil) {
        self.reasoningPreview = reasoningPreview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if reduceMotion {
                staticThinkingText
            } else {
                TimelineView(.animation) { context in
                    shimmeringThinkingText(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
            if let reasoningPreview, !reasoningPreview.isEmpty {
                Text(reasoningPreview)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(3)
            }
        }
    }

    private var staticThinkingText: some View {
        Text("Thinking...")
            .font(DSFont.body.italic())
            .foregroundStyle(DSColor.textSecondary)
    }

    private func shimmeringThinkingText(at time: TimeInterval) -> some View {
        let phase = DSThinkingAnimationModel.shimmerPhase(at: time)
        // 帯中心を画面外余白まで逃がし、折返しの瞬間移動（かくつき）を不可視化する。
        let center = DSThinkingAnimationModel.shimmerBandCenter(phase: phase)
        let stops = (0...20).map { index in
            let position = Double(index) / 20
            let brightness = DSThinkingAnimationModel.shimmerBrightness(
                position: position,
                phase: center
            )
            return Gradient.Stop(
                color: DSColor.textSecondary.opacity(brightness),
                location: CGFloat(position)
            )
        }

        return Text("Thinking...")
            .font(DSFont.body.italic())
            .foregroundStyle(
                LinearGradient(
                    stops: stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

#if DEBUG
#Preview("DSThinkingIndicator") {
    VStack(alignment: .leading, spacing: DSSpacing.m) {
        DSThinkingIndicator()
        DSThinkingIndicator(reasoningPreview: "実装方針を検討中。既存 DS トークンに合わせて視覚を揃える。")
    }
    .padding(DSSpacing.l)
}
#endif
