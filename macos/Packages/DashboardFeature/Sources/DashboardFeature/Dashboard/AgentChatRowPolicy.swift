import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// エージェントビューの行表示の純ロジック（R1/R2）。
public enum AgentChatRowPolicy {
    /// 発言者ヘッダ（エージェントアイコン＋その右のセッション名）を出すか。
    /// ユーザー発言（右寄せ吹き出し）にはヘッダを出さない。それ以外（エージェント発言・
    /// reasoning・コマンド実行・端末テキスト等）には出す。
    public static func showsSpeakerHeader(for content: TeamTimelineContent) -> Bool {
        switch content {
        case .chatItem(.userMessage):
            false
        case .chatItem, .terminalText:
            true
        }
    }

    /// アゴラ専用の左寄せバブルで本文を包む agentMessage か。
    public static func usesAgentMessageBubble(for content: TeamTimelineContent) -> Bool {
        if case .chatItem(.agentMessage) = content { return true }
        return false
    }
}

/// アゴラ討論タイムライン向けのエージェント発言バブル（左寄せ・ユーザーバブルと対称）。
struct AgoraAgentMessageBubble: View {
    let text: String
    let timestamp: Date

    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                RichMarkdownView(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                            .fill(DSColor.userBubble)
                    )
                if timestamp != .distantPast {
                    Text(Self.timestampFormatter.string(from: timestamp))
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            Spacer(minLength: 72)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// アゴラ Thinking 行のドットアニメーション（SessionFeature の ThinkingAnimationModel と同型の位相）。
private enum AgoraThinkingDotsAnimation {
    static let period: TimeInterval = 2.4

    struct DotState: Equatable {
        var opacity: Double
        var scale: Double
        var yOffset: Double
    }

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

private struct AgoraThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    private static let dotCount = 3

    private var shouldAnimate: Bool {
        !reduceMotion && controlActiveState == .key
    }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    staticDots(date: context.date)
                }
            } else {
                staticDots(date: nil)
            }
        }
    }

    private func staticDots(date: Date?) -> some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                let state = dotState(for: index, date: date)
                Circle()
                    .fill(DSColor.chatTextSecondary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(state.scale)
                    .offset(y: state.yOffset)
                    .opacity(state.opacity)
            }
        }
        .frame(width: 20, height: 8, alignment: .center)
        .accessibilityHidden(true)
    }

    private func dotState(for index: Int, date: Date?) -> AgoraThinkingDotsAnimation.DotState {
        guard let date else {
            return .init(opacity: 0.55, scale: 1, yOffset: 0)
        }
        return AgoraThinkingDotsAnimation.dotState(
            index: index,
            dotCount: Self.dotCount,
            date: date
        )
    }
}

/// アゴラタイムライン末尾の Thinking インジケータ行（アイコン＋セッション名＋アニメーション）。
struct AgoraThinkingIndicatorRow: View {
    let source: TeamTimelineSource
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                AgentBrandIcon(descriptor: source.agentDescriptor, size: 16)
                Text(source.displayName)
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(source.agentDescriptor.displayName)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: DSSpacing.s) {
                Text("Thinking...")
                    .font(.system(size: ChatTypography.bodyFontSize(scale: scale)).italic())
                    .foregroundStyle(DSColor.chatTextSecondary)
                AgoraThinkingDots()
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(source.displayName) が考え中")
    }
}
