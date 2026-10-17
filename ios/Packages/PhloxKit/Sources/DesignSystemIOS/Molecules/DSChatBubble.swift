import SwiftUI
import AgentDomain

/// チャットメッセージバブル（カンプ⑦ 質問への回答）。
/// エージェントは左寄せ・無背景、ユーザーは右寄せ・raised 面。
public struct DSChatBubble: View {
    public enum Role: Sendable {
        case agent
        case user
    }
    /// バブル角丸（カンプカード 14px）。
    static let cornerRadius = DSRadius.card
    /// エージェントアバター（カンプ⑦）。
    static let agentLogoSize: CGFloat = 28

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

    /// バブル背景色（テスト用契約 · DSChatBubbleStyleTests）。nil = 無背景。
    /// body の実描画もこの関数を単一の正として使う。
    static func backgroundColor(for role: Role) -> Color? {
        role == .user ? IOSColor.bg.raised : nil
    }

    /// 発話者に応じた水平配置。
    static func horizontalAlignment(for role: Role) -> HorizontalAlignment {
        role == .agent ? .leading : .trailing
    }

    /// ユーザーバブル内テキスト色（`userBubble` 淡面上 · macOS 揃え）。
    static var userMessageForeground: Color { IOSColor.text.primary }

    static func highlightColor(for role: Role) -> Color? {
        role == .agent ? IOSColor.text.secondary : nil
    }

    static func accessibilitySpeakerLabel(for role: Role, agentKind: AgentKind? = nil) -> String {
        if role == .agent, let agentKind {
            return AgentRegistry.descriptor(for: agentKind).displayName
        }
        return role == .agent ? "エージェント" : "あなた"
    }

    public var body: some View {
        switch role {
        case .agent:
            HStack(alignment: .top, spacing: DSSpacing.s) {
                if let agentKind {
                    DSAgentBrandIcon(kind: agentKind, size: Self.agentLogoSize)
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
            if role == .agent {
                agentMessageContent(message, highlightColor: Self.highlightColor(for: role) ?? IOSColor.text.secondary)
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
        .background(Capsule().fill(IOSColor.bg.raised))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Self.attachmentBadgeText(count: count)))
    }

    private var userAccessibilityLabel: String {
        "\(Self.accessibilitySpeakerLabel(for: role, agentKind: agentKind)): \(message)"
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
