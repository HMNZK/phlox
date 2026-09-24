import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

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
    @State private var isHovering = false
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
            VStack(alignment: .trailing, spacing: TranscriptTypography.metadataGap) {
                VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
                    VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
                        if presentation.showsText {
                            Text(text)
                                .font(ChatScaledFont.body(scale: scale))
                                .foregroundStyle(DSColor.chatTextPrimary)
                                .chatTextSelection()
                                .lineSpacing(TranscriptTypography.textLineSpacing)
                        }
                        if let badge = presentation.badge {
                            ChatAttachmentBadge(title: badge.title, scale: scale)
                        }
                    }
                    .padding(.horizontal, TranscriptTypography.cardHorizontalInset)
                    .padding(.vertical, TranscriptTypography.cardVerticalInset)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                            .fill(DSColor.userBubble)
                    )
                    if presentation.showsText {
                        HStack(spacing: DSSpacing.xs) {
                            MessageCopyButton(
                                text: text,
                                accessibilityIdentifier: "ChatMessage.copyButton.user",
                                scale: scale,
                                isVisible: isHovering
                            )
                            ChatTimestampText(timestamp: timestamp)
                                .opacity(isHovering ? 1 : 0)
                        }
                    }
                }
                .onHover { isHovering = $0 }
                .animation(.easeInOut(duration: 0.12), value: isHovering)
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
    @State private var isHovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        AvatarMessageRow {
            VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
                AgentMessageBody(text: text)
                HStack(spacing: DSSpacing.xs) {
                    MessageCopyButton(
                        text: text,
                        accessibilityIdentifier: "ChatMessage.copyButton.agent",
                        scale: scale,
                        isVisible: isHovering
                    )
                    ChatTimestampText(timestamp: timestamp)
                        .opacity(isHovering ? 1 : 0)
                }
            }
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }
}

struct TurnCostCell: View {
    let costUSD: Double?
    let timestamp: Date
    /// トークン内訳とコンテキスト使用率（04）。無い値は出さない。
    var usage: TurnUsage? = nil
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        HStack(spacing: DSSpacing.m) {
            Spacer(minLength: 72)
            if let costUSD {
                Text(Self.format(costUSD))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .accessibilityLabel(UIWording.turnCostAccessibility(amountText: Self.format(costUSD), languageCode: languageCode))
            }
            if let tokens = Self.tokenText(usage) {
                tokens
            }
            if let percent = Self.contextPercent(usage) {
                Text("コンテキスト \(percent)%")
            }
        }
        .font(ChatScaledFont.caption(scale: scale))
        .monospacedDigit()
        .foregroundStyle(DSColor.textTertiary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ChatMessage.turnCost")
    }

    /// 「入力 18.2k · 出力 1.9k · キャッシュ読込 142k」。
    static func tokenText(_ usage: TurnUsage?) -> Text? {
        guard let usage else { return nil }
        let parts: [Text] = [
            usage.inputTokens.map { Text("入力 \(compact($0))") },
            usage.outputTokens.map { Text("出力 \(compact($0))") },
            usage.cacheReadTokens.map { Text("キャッシュ読込 \(compact($0))") },
        ].compactMap { $0 }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(verbatim: " · ") + $1 }
    }

    static func contextPercent(_ usage: TurnUsage?) -> Int? {
        guard let used = usage?.contextUsedTokens, let window = usage?.contextWindowTokens, window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }

    /// 1,900 → 1.9k、142,000 → 142k、1,200,000 → 1.2M。
    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<100_000: return String(format: "%.1fk", Double(count) / 1_000)
        case ..<1_000_000: return "\(count / 1_000)k"
        default: return String(format: "%.1fM", Double(count) / 1_000_000)
        }
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
    var bodyColor: Color /* default primary */ = DSColor.chatTextPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
            ForEach(Array(ChatMessageRenderCache.markdownBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let markdown):
                    RichMarkdownView(markdown, bodyColor: bodyColor)
                        .chatTextSelection()
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
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.error(
            message: message,
            heading: UIWording.text(.errorHeading, languageCode: languageCode)
        )
        VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
            Label(presentation.heading ?? "", systemImage: "exclamationmark.triangle")
                .font(ChatScaledFont.captionStrong(scale: scale))
                .foregroundStyle(DSColor.statusError)
            Text(message)
                .font(ChatScaledFont.body(scale: scale))
                .foregroundStyle(DSColor.chatTextPrimary)
                .chatTextSelection()
                .lineSpacing(TranscriptTypography.textLineSpacing)
            ChatTimestampText(timestamp: timestamp)
        }
        .padding(.horizontal, TranscriptTypography.cardHorizontalInset)
        .padding(.vertical, TranscriptTypography.cardVerticalInset)
        .frame(maxWidth: 720, alignment: .leading)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.attentionMark(.error), lineWidth: 1)
        )
    }
}
