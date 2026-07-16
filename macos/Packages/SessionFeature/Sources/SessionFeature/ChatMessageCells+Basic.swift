import SwiftUI
import AgentDomain
import DesignSystem

struct ChatUserMessagePresentation: Equatable {
    let showsText: Bool
    let badge: ChatAttachmentBadgePresentation?

    init(text: String, attachments: [ChatUserAttachment]) {
        showsText = !text.isEmpty
        badge = ChatAttachmentBadgePresentation(attachments: attachments)
    }
}

struct ChatAttachmentBadgePresentation: Equatable {
    let title: String

    init?(attachments: [ChatUserAttachment]) {
        guard let first = attachments.first else { return nil }
        let baseName: String
        if let filename = first.filename?.trimmingCharacters(in: .whitespacesAndNewlines), !filename.isEmpty {
            baseName = filename
        } else {
            baseName = "画像"
        }
        if attachments.count > 1 {
            title = "\(baseName) ×\(attachments.count)"
        } else {
            title = baseName
        }
    }
}

struct UserMessageCell: View {
    let text: String
    let timestamp: Date
    let attachments: [ChatUserAttachment]
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(text: String, timestamp: Date, attachments: [ChatUserAttachment] = []) {
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = ChatUserMessagePresentation(text: text, attachments: attachments)
        HStack(alignment: .bottom) {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        if presentation.showsText {
                            Text(text)
                                .font(ChatScaledFont.body(scale: scale))
                                .foregroundStyle(DSColor.chatTextPrimary)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                        }
                        if let badge = presentation.badge {
                            ChatAttachmentBadge(title: badge.title, scale: scale)
                        }
                    }
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                            .fill(DSColor.userBubble)
                    )
                    if presentation.showsText {
                        MessageCopyButton(
                            text: text,
                            accessibilityIdentifier: "ChatMessage.copyButton.user",
                            scale: scale
                        )
                    }
                }
                ChatTimestampText(timestamp: timestamp)
            }
            .frame(maxWidth: 560, alignment: .trailing)
        }
    }
}

private struct ChatAttachmentBadge: View {
    let title: String
    let scale: CGFloat

    var body: some View {
        Label(title, systemImage: "photo")
            .font(ChatScaledFont.captionStrong(scale: scale))
            .foregroundStyle(DSColor.chatTextPrimary)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(DSColor.chatTextPrimary.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DSColor.chatTextPrimary.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel("添付画像 \(title)")
    }
}

struct AgentMessageCell: View {
    let text: String
    let timestamp: Date
    let descriptor: AgentDescriptor
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow(descriptor: descriptor, timestamp: timestamp) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                AgentMessageBody(text: text)
                MessageCopyButton(
                    text: text,
                    accessibilityIdentifier: "ChatMessage.copyButton.agent",
                    scale: scale
                )
            }
        }
    }
}

struct TurnCostCell: View {
    let costUSD: Double
    let timestamp: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack {
            Spacer(minLength: 72)
            Text(Self.format(costUSD))
                .font(.system(size: 9 * scale, weight: .regular, design: .monospaced))
                .foregroundStyle(DSColor.chatTextSecondary.opacity(0.7))
                .accessibilityLabel("Turn cost \(Self.format(costUSD))")
        }
        .frame(maxWidth: 720, alignment: .trailing)
        .accessibilityIdentifier("ChatMessage.turnCost")
    }

    private static let costFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    private static func format(_ costUSD: Double) -> String {
        costFormatter.string(from: NSNumber(value: costUSD)) ?? String(format: "$%.4f", costUSD)
    }
}

struct AgentMessageBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            ForEach(Array(ChatMessageRenderCache.markdownBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let markdown):
                    RichMarkdownView(markdown)
                        .textSelection(.enabled)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

struct ErrorMessageCell: View {
    let message: String
    let timestamp: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Label("Error", systemImage: "exclamationmark.triangle")
                .font(ChatScaledFont.captionStrong(scale: scale))
                .foregroundStyle(DSColor.statusError)
            Text(message)
                .font(ChatScaledFont.body(scale: scale))
                .foregroundStyle(DSColor.chatTextPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
            ChatTimestampText(timestamp: timestamp)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .frame(maxWidth: 720, alignment: .leading)
        .background(DSColor.statusError.opacity(0.14), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.statusError.opacity(0.35), lineWidth: 1)
        )
    }
}
