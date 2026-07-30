import SwiftUI
import DesignSystem

enum DisclosureCardPalette {
    static func title(isToolCall: Bool) -> Color {
        isToolCall ? DSColor.chatToolCallText : DSColor.chatTextPrimary
    }

    static func subtitle(isToolCall: Bool) -> Color {
        isToolCall ? DSColor.chatToolCallText : DSColor.chatTextSecondary
    }
}

struct AvatarMessageRow<Content: View>: View {
    let timestamp: Date
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ChatTimestampText(timestamp: timestamp)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatTimestampText: View {
    let timestamp: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        if timestamp != .distantPast {
            Text(Self.formatter.string(from: timestamp))
                .font(ChatScaledFont.caption(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .monospacedDigit()
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

struct DisclosureCard<Content: View>: View {
    @Binding var isExpanded: Bool
    let title: String
    let subtitle: String?
    let timestamp: Date
    let isToolCall: Bool
    let isTimelineVisible: Bool
    let liveTitle: ((Date) -> String)?
    @ViewBuilder let content: Content
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(
        isExpanded: Binding<Bool>,
        title: String,
        subtitle: String?,
        timestamp: Date,
        isToolCall: Bool = false,
        isTimelineVisible: Bool = true,
        liveTitle: ((Date) -> String)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        _isExpanded = isExpanded
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.isToolCall = isToolCall
        self.isTimelineVisible = isTimelineVisible
        self.liveTitle = liveTitle
        self.content = content()
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: DSSpacing.s) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    titleText(scale: scale)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(ChatScaledFont.caption(scale: scale))
                            .foregroundStyle(DisclosureCardPalette.subtitle(isToolCall: isToolCall))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DSSpacing.s)
                ChatTimestampText(timestamp: timestamp)
            }
        }
        .disclosureGroupStyle(DisclosureCardStyle())
        .padding(.vertical, DSSpacing.xs)
    }

    @ViewBuilder
    private func titleText(scale: CGFloat) -> some View {
        if let liveTitle {
            TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                Text(liveTitle(context.date))
                    .font(ChatScaledFont.captionStrong(scale: scale))
                    .foregroundStyle(DisclosureCardPalette.title(isToolCall: isToolCall))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(title)
                .font(ChatScaledFont.captionStrong(scale: scale))
                .foregroundStyle(DisclosureCardPalette.title(isToolCall: isToolCall))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DisclosureCardStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.system(size: DSIconSize.s, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "展開中" : "折りたたみ中")
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
