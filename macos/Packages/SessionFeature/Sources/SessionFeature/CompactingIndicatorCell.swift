import SwiftUI
import AgentDomain
import DesignSystem

/// transcript 末尾の圧縮中インジケーター表示条件（View から切り出し・白箱テスト対象）。
enum CompactingIndicatorPresentation {
    static func shouldShowCompactingIndicator(isCompacting: Bool) -> Bool {
        isCompacting
    }

    static func shouldShowThinkingIndicator(
        showsThinkingIndicator: Bool,
        showsProcessingIndicator: Bool,
        isCompacting: Bool
    ) -> Bool {
        showsThinkingIndicator && showsProcessingIndicator && !isCompacting
    }
}

struct CompactingIndicatorCell: View {
    let descriptor: AgentDescriptor
    /// transcript 最下部が viewport 内にあるか。スクロール位置のイベントから親が渡す。
    var isInTranscriptViewport = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isInViewHierarchy = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInTranscriptViewport,
            isSceneActive: scenePhase == .active
        )
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow(descriptor: descriptor, timestamp: .distantPast) {
            Group {
                if reduceMotion {
                    staticCompactingText(scale: scale)
                } else {
                    TimelineView(ThinkingAnimationModel.timelineSchedule(isVisible: isTimelineVisible)) { context in
                        shimmeringCompactingText(scale: scale, date: context.date)
                    }
                }
            }
            .padding(.vertical, DSSpacing.xs)
        }
        .onAppear {
            isInViewHierarchy = true
        }
        .onDisappear {
            isInViewHierarchy = false
        }
    }

    private func staticCompactingText(scale: CGFloat) -> some View {
        Text("会話履歴を圧縮中…")
            .font(ChatScaledFont.body(scale: scale).italic())
            .foregroundStyle(DSColor.chatTextSecondary)
    }

    private func shimmeringCompactingText(scale: CGFloat, date: Date) -> some View {
        let phase = ThinkingAnimationModel.shimmerPhase(date: date)
        let center = ThinkingAnimationModel.shimmerBandCenter(phase: phase)
        let stops = (0...20).map { index in
            let position = Double(index) / 20
            let brightness = ThinkingAnimationModel.shimmerBrightness(
                position: position,
                phase: center
            )
            return Gradient.Stop(
                color: DSColor.chatTextSecondary.opacity(brightness),
                location: CGFloat(position)
            )
        }

        return Text("会話履歴を圧縮中…")
            .font(ChatScaledFont.body(scale: scale).italic())
            .foregroundStyle(
                LinearGradient(
                    stops: stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}
