import SwiftUI
import AgentDomain
import DesignSystem

/// transcript 末尾の圧縮中インジケーター表示条件（View から切り出し・白箱テスト対象）。
enum CompactingIndicatorPresentation {
    static func shouldShowCompactingIndicator(isCompacting: Bool) -> Bool {
        isCompacting
    }

    /// `isAwaitingUser` は承認・回答待ち。処理中でなくても待機状態として出す。
    static func shouldShowThinkingIndicator(
        showsThinkingIndicator: Bool,
        showsProcessingIndicator: Bool,
        isCompacting: Bool,
        isAwaitingUser: Bool = false
    ) -> Bool {
        showsThinkingIndicator && (showsProcessingIndicator || isAwaitingUser) && !isCompacting
    }
}

struct CompactingIndicatorCell: View {
    let descriptor: AgentDescriptor
    @State private var isInViewport = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isInViewHierarchy = false
    /// 圧縮開始（＝このセルの出現）時刻。犬アニメの物語・ステージ進行の起点。
    /// セルは圧縮中のみ存在するため、State の初期値で1回だけ固定される。
    @State private var compactingStartedAt = Date()
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInViewport,
            scenePhase: scenePhase
        )
    }

    /// PhloxChat.dc.html の isCompacting: 角丸 10・1pt 枠のカード。上 110pt に犬のアニメ、下に文言とステージ。
    /// 視差を減らす設定では犬を止めた絵のまま出す。
    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow {
            Group {
                if reduceMotion {
                    card(scale: scale, date: compactingStartedAt, animated: false)
                } else {
                    TimelineView(ThinkingAnimationModel.timelineSchedule(isVisible: isTimelineVisible)) { context in
                        card(scale: scale, date: context.date, animated: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("会話を圧縮中"))
        }
        .onAppear {
            isInViewHierarchy = true
        }
        .onDisappear {
            isInViewHierarchy = false
        }
        .onViewportVisibilityChange { isInViewport = $0 }
    }

    private func card(scale: CGFloat, date: Date, animated: Bool) -> some View {
        VStack(spacing: 0) {
            CompactingDogSceneView(date: date, startDate: compactingStartedAt)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            HStack(spacing: 10) {
                Group {
                    if animated {
                        shimmeringCompactingText(scale: scale, date: date)
                    } else {
                        staticCompactingText(scale: scale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Self.stageText(elapsed: date.timeIntervalSince(compactingStartedAt))
                    .font(.system(size: 11 * scale))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
    }

    /// 「ステージ 3 / 6 · 砂漠」。全面踏破後のお祝いの間は「ゴール」。
    static func stageText(elapsed: TimeInterval) -> Text {
        switch CompactingDogAnimation.segment(elapsed: elapsed) {
        case .stage(let stage, _):
            let total = CompactingDogAnimation.Stage.allCases.count
            return Text("ステージ \(stage.rawValue + 1) / \(total) · \(stageName(stage))")
        case .goal:
            return Text("ゴール")
        }
    }

    private static func stageName(_ stage: CompactingDogAnimation.Stage) -> Text {
        switch stage {
        case .sea: Text("海")
        case .river: Text("川")
        case .desert: Text("砂漠")
        case .volcano: Text("火山")
        case .ice: Text("氷山")
        case .moon: Text("宇宙")
        }
    }

    private func staticCompactingText(scale: CGFloat) -> some View {
        Text("会話を圧縮しています…")
            .font(.system(size: 13 * scale).italic())
            .foregroundStyle(DSColor.chatTextSecondary)
    }

    private func shimmeringCompactingText(scale: CGFloat, date: Date) -> some View {
        let phase = ShimmerBandModel.phase(date: date)
        let center = ShimmerBandModel.bandCenter(phase: phase)
        let stops = (0...20).map { index in
            let position = Double(index) / 20
            let brightness = ShimmerBandModel.brightness(
                position: position,
                phase: center
            )
            return Gradient.Stop(
                color: DSColor.chatTextSecondary.opacity(brightness),
                location: CGFloat(position)
            )
        }

        return Text("会話を圧縮しています…")
            .font(.system(size: 13 * scale).italic())
            .foregroundStyle(
                LinearGradient(
                    stops: stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}
