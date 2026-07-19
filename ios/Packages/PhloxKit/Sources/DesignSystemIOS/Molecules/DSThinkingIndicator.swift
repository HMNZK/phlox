import SwiftUI

/// 点滅ドットのアニメーション位相を計算する純関数群（テスト可能にするため View から分離）。
public enum DSThinkingAnimationModel {
    /// アニメーション1周期（秒）。
    public static let period: TimeInterval = 1.2
    public static let dotCount: Int = 3

    /// dotIndex(0..<dotCount) と任意の時刻 t から不透明度を返す。値域 0.2...1.0。周期 `period`。
    /// ドット同士は位相をずらす（同一時刻に全ドットが常に同値にならない）。
    public static func opacity(dotIndex: Int, at time: TimeInterval) -> Double {
        let safeDotCount = max(dotCount, 1)
        let normalizedIndex = ((dotIndex % safeDotCount) + safeDotCount) % safeDotCount
        let cycleProgress = time.truncatingRemainder(dividingBy: period) / period
        let phase = 2 * Double.pi * (
            cycleProgress - Double(normalizedIndex) / Double(safeDotCount)
        )
        let wave = (sin(phase) + 1) / 2
        return 0.2 + 0.8 * wave
    }
}

/// 応答生成中インジケータ。「Thinking...」イタリック + 点滅3ドット + 任意の reasoning プレビュー（3行まで）。
/// accessibilityReduceMotion 有効時はアニメーションせず静的ドットを表示する。
public struct DSThinkingIndicator: View {
    let reasoningPreview: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(reasoningPreview: String? = nil) {
        self.reasoningPreview = reasoningPreview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.s) {
                Text("Thinking...")
                    .font(DSFont.body.italic())
                    .foregroundStyle(DSColor.textSecondary)
                if reduceMotion {
                    thinkingDots(at: 0)
                } else {
                    TimelineView(.animation) { context in
                        thinkingDots(at: context.date.timeIntervalSinceReferenceDate)
                    }
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

    private func thinkingDots(at time: TimeInterval) -> some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(0..<DSThinkingAnimationModel.dotCount, id: \.self) { index in
                Circle()
                    .fill(DSColor.textSecondary)
                    .frame(width: DSSpacing.xs, height: DSSpacing.xs)
                    .opacity(DSThinkingAnimationModel.opacity(dotIndex: index, at: time))
            }
        }
        .accessibilityHidden(true)
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
