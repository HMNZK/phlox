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

/// アゴラタイムライン末尾の Thinking インジケータ行（アイコン＋セッション名＋アニメーション）。
struct AgoraThinkingIndicatorRow: View {
    let source: TeamTimelineSource
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    /// タイムラインの取り込み済みメッセージから活動状態を導出する（チャットの Thinking セルと同じ規則）。
    /// タイムラインは実行中セッションだけを流すため、常に実行中として扱う。
    static func activityState(source: TeamTimelineSource) -> AgentActivityState {
        let items: [ChatItem] = source.messages.compactMap { message in
            guard case .chatItem(let item) = message.content else { return nil }
            return item
        }
        return ChatRecap.deriveActivityState(transcript: items, status: .running)
    }

    var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let state = Self.activityState(source: source)
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
                ThinkingOrbView(state: state, size: .inline)
                ShimmerTextView(
                    text: state.orbLabel,
                    font: .system(size: ChatTypography.bodyFontSize(scale: scale)),
                    pointSize: ChatTypography.bodyFontSize(scale: scale),
                    color: DSColor.chatTextPrimary
                )
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(source.displayName): \(state.orbLabel)")
    }
}
