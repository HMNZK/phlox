import SwiftUI
import AgentDomain

/// チャットメッセージバブル（カンプ⑦ 質問への回答）。
/// エージェントは左寄せ・無背景、ユーザーは右寄せ・`DSColor.userBubble` 淡面（macOS 揃え）。
public struct DSChatBubble: View {
    public enum Role: Sendable {
        case agent
        case user
    }
    /// バブル角丸（カンプカード 14px）。
    static let cornerRadius = DSRadius.card
    /// エージェントアバター（カンプ⑦）。
    static let agentAvatarSize: CGFloat = DSCampAgentBadge.chatAvatarSize
    static let agentAvatarCornerRadius: CGFloat = DSCampAgentBadge.chatAvatarCornerRadius

    /// 長押し contextMenu でコピーを提供する（task-5 契約）。
    public static let providesLongPressCopy = true
    /// 常時表示のコピーボタンは提供しない（task-5 契約）。
    public static let providesAlwaysVisibleCopyButton = false

    let role: Role
    let message: String
    let attachmentImageCount: Int?
    let agentKind: AgentKind?
    let maxBubbleWidth: CGFloat?
    let copyText: String?

    public init(
        role: Role,
        message: String,
        attachmentImageCount: Int? = nil,
        agentKind: AgentKind? = nil,
        maxBubbleWidth: CGFloat? = nil,
        copyText: String? = nil
    ) {
        self.role = role
        self.message = message
        self.attachmentImageCount = attachmentImageCount
        self.agentKind = agentKind
        self.maxBubbleWidth = maxBubbleWidth
        self.copyText = copyText
    }

    public static func attachmentBadgeText(count: Int) -> String {
        count <= 1 ? "画像" : "画像 ×\(count)"
    }

    /// ブランドグラデ背景は廃止（macOS 揃え · task-2）。
    static func usesBrandGradient(for role: Role) -> Bool {
        false
    }

    /// バブル背景色（テスト用契約 · Task2AcceptanceTests）。nil = 無背景。
    /// body の実描画もこの関数を単一の正として使う。
    static func backgroundColor(for role: Role) -> Color? {
        role == .user ? DSColor.userBubble : nil
    }

    /// 発話者に応じた水平配置。
    static func horizontalAlignment(for role: Role) -> HorizontalAlignment {
        role == .agent ? .leading : .trailing
    }

    /// ユーザーバブル内テキスト色（`userBubble` 淡面上 · macOS 揃え）。
    static let userMessageForeground = DSColor.textPrimary

    static func accessibilitySpeakerLabel(for role: Role) -> String {
        role == .agent ? "エージェント" : "あなた"
    }

    public var body: some View {
        switch role {
        case .agent:
            HStack(alignment: .top, spacing: DSSpacing.s) {
                if let agentKind {
                    DSAgentAvatar(kind: agentKind, size: Self.agentAvatarSize)
                }
                messageBubble
                    .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                Spacer(minLength: DSSpacing.xl)
            }
        case .user:
            // 画像添付バッジはバブル内ではなくバブルの外（下）に分離して表示する（macOS 揃え）。
            HStack(alignment: .top, spacing: DSSpacing.s) {
                Spacer(minLength: DSSpacing.xl)
                VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                    if !message.isEmpty {
                        messageBubble
                            .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
                    }
                    if let count = attachmentImageCount, count > 0 {
                        attachmentBadge(count: count)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var messageBubble: some View {
        Group {
            if role == .agent, let agentKind {
                agentMessageContent(message, highlightColor: DSColor.campAgentColor(for: agentKind))
            } else {
                userMessageContent
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background {
            if let color = Self.backgroundColor(for: role) {
                bubbleShape.fill(color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(userAccessibilityLabel))
        .chatMessageCopyContextMenu(copyText: copyText)
    }

    @ViewBuilder
    private var userMessageContent: some View {
        Text(message)
            .font(DSFont.body)
            .foregroundStyle(Self.userMessageForeground)
    }

    /// バブルの外（下・右寄せ）に置く画像添付バッジ（カプセル型チップ · macOS 揃え）。
    private func attachmentBadge(count: Int) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "photo")
            Text(Self.attachmentBadgeText(count: count))
        }
        .font(DSFont.caption)
        .foregroundStyle(DSColor.textSecondary)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(Capsule().fill(DSColor.userBubble))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Self.attachmentBadgeText(count: count)))
    }

    private var userAccessibilityLabel: String {
        "\(Self.accessibilitySpeakerLabel(for: role)): \(message)"
    }

    @ViewBuilder
    private func agentMessageContent(_ text: String, highlightColor: Color) -> some View {
        let marker = "/approvals"
        if let range = text.range(of: marker) {
            let before = String(text[..<range.lowerBound])
            let after = String(text[range.upperBound...])
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                if !before.isEmpty {
                    DSMarkdownText(before)
                }
                Text(marker)
                    .font(DSFont.campMono)
                    .foregroundStyle(highlightColor)
                if !after.isEmpty {
                    DSMarkdownText(after)
                }
            }
        } else {
            DSMarkdownText(text)
        }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }
}

#if DEBUG
#Preview("DSChatBubble") {
    VStack(spacing: DSSpacing.m) {
        DSChatBubble(
            role: .agent,
            message: "POST /send で回答を送ってください。対象は /approvals エンドポイントです。"
        )
        DSChatBubble(role: .user, message: "はい、承認して進めてください。")
    }
    .padding(DSSpacing.l)
}
#endif
