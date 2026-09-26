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

    /// PhloxChat.dc.html: 右寄せの吹き出し（コード地・角丸 14・幅 78% まで）。ホバーで左に時刻とコピー。添付は本文の上。
    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = ChatUserMessagePresentation(text: text, attachments: attachments)
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 0)
            if presentation.showsText {
                HStack(spacing: 6) {
                    ChatTimestampText(timestamp: timestamp)
                    MessageCopyButton(
                        text: text,
                        accessibilityIdentifier: "ChatMessage.copyButton.user",
                        scale: scale,
                        isVisible: isHovering
                    )
                }
                .opacity(isHovering ? 1 : 0)
                .padding(.bottom, 4)
            }
            UserBubbleWidth {
                VStack(alignment: .leading, spacing: 6) {
                    if let badge = presentation.badge {
                        ChatAttachmentBadge(title: badge.title, scale: scale)
                    }
                    if presentation.showsText {
                        Text(text)
                            .font(.system(size: 13 * scale))
                            .foregroundStyle(DSColor.chatTextPrimary)
                            .chatTextSelection()
                            .lineSpacing(5 * scale)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DSColor.codeBackground)
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

/// 吹き出しを親の幅の 78% までに収める（短い発言は内容の幅のまま）。
private struct UserBubbleWidth: Layout {
    static let fraction: CGFloat = 0.78

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 * Self.fraction }, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private struct ChatAttachmentBadge: View {
    let title: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 10 * scale))
                .foregroundStyle(DSColor.textTertiary)
            Text(title)
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(DSColor.chatTextSecondary)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 22 * scale)
        .background(DSColor.windowBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .ignore)
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
        // 04 A1: ホバーの時刻とコピーは場所を取らず、本文の右下に重ねる（モックはホバー行を常設しない）。
        // 本文の枠の内側に置く。下へはみ出すと、直後の行（右寄せのターンのコストなど）と重なる。
        AvatarMessageRow {
            AgentMessageBody(text: text)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 6) {
                        ChatTimestampText(timestamp: timestamp)
                        MessageCopyButton(
                            text: text,
                            accessibilityIdentifier: "ChatMessage.copyButton.agent",
                            scale: scale,
                            isVisible: isHovering
                        )
                    }
                    .padding(.leading, 6)
                    .background(DSColor.windowBackground)
                    .opacity(isHovering ? 1 : 0)
                }
                .contentShape(Rectangle())
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
        HStack(spacing: 12) {
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
        .font(.system(size: 11 * scale))
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

    /// 「$0.42」（記号と数字の間に空白を入れない）。1 セント未満だけ 4 桁まで出す（「$0.0012」）。
    static func format(_ costUSD: Double) -> String {
        String(format: costUSD >= 0.01 || costUSD == 0 ? "$%.2f" : "$%.4f", costUSD)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// PhloxChat.dc.html の isError: 赤の淡い面と 1pt の枠、塗りの三角、見出し 12.5 と等幅の本文。時刻は出さない。
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12 * scale))
                .foregroundStyle(DSColor.attentionMark(.error))
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.heading ?? "")
                    .font(.system(size: 12.5 * scale, weight: .semibold))
                    .foregroundStyle(DSColor.attentionInk(.error))
                Text(message)
                    .font(.system(size: 12.5 * scale, design: .monospaced))
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .chatTextSelection()
                    .lineSpacing(4 * scale)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DSColor.attentionMark(.error), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
