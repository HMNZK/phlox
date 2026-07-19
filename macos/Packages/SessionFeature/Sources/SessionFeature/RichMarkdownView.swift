import SwiftUI
import DesignSystem
import MarkdownUI

#if canImport(AppKit)
import AppKit
#endif

public struct RichMarkdownView: View {
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
    private let markdown: String

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public init(streaming markdown: String) {
        self.markdown = markdown
    }

    @MainActor private static var themes: [String: Theme] = [:]

    public var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Markdown(markdown)
            .markdownTheme(Self.theme(for: themeID, scale: scale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction(handler: openChatMarkdownLink))
    }

    @MainActor
    static func theme(for themeID: String, scale: CGFloat) -> Theme {
        let cacheKey = themeCacheKey(themeID: themeID, scale: scale)
        if let theme = themes[cacheKey] {
            return theme
        }
        let theme = chatMarkdownTheme(scale: scale)
        themes[cacheKey] = theme
        return theme
    }

    static func themeCacheKey(themeID: String, scale: CGFloat) -> String {
        "\(themeID):\(scale)"
    }
}

@MainActor
private func chatMarkdownTheme(scale: CGFloat) -> Theme {
    Theme()
        .text {
            ForegroundColor(DSColor.chatTextPrimary)
            FontSize(ChatTypography.bodyFontSize(scale: scale))
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(ChatTypography.codeFontSize(scale: scale))
            ForegroundColor(DSColor.chatAccent)
            BackgroundColor(DSColor.fillSubtle)
        }
        .link {
            ForegroundColor(DSColor.chatAccent)
        }
        // NOTE: 箇条書きの項目が折り返すと、折り返し行の縦高さが確保されず次項目と重なって潰れる
        // （MarkdownUI v2.4.1 の ListItemView は Label{content} icon:{marker} 構成で、項目 content に
        // 縦サイズ確保が無い）。list 項目に限定して縦サイズを固定し、全行分の高さを確保する。
        // .listItem は list 項目にのみ適用され table セル（.table/.tableCell）へは波及しないため、
        // .fixedSize による表レイアウト非収束＝ADR 0045 の CPU 暴走とは無関係。
        .listItem { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: DSSpacing.m)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(ChatTypography.heading1FontSize(scale: scale))
                    ForegroundColor(DSColor.chatTextPrimary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: DSSpacing.s, bottom: DSSpacing.s)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(ChatTypography.heading2FontSize(scale: scale))
                    ForegroundColor(DSColor.chatTextPrimary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: DSSpacing.s, bottom: DSSpacing.xs)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(ChatTypography.heading3FontSize(scale: scale))
                    ForegroundColor(DSColor.chatTextPrimary)
                }
        }
        .blockquote { configuration in
            configuration.label
                .padding(.leading, DSSpacing.l)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSRadius.s)
                        .fill(DSColor.chatAccent.opacity(0.6))
                        .frame(width: 3)
                }
                .markdownTextStyle {
                    ForegroundColor(DSColor.chatTextSecondary)
                }
                .markdownMargin(top: DSSpacing.s, bottom: DSSpacing.s)
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DSSpacing.s) {
                    Text(configuration.language?.isEmpty == false ? configuration.language! : "code")
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                    Spacer(minLength: 0)
                    Button {
                        copyToPasteboard(configuration.content)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(ChatScaledFont.captionStrong(scale: scale))
                            .foregroundStyle(DSColor.chatTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy code")
                }
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)

                Divider()
                    .overlay(DSColor.separator)

                highlightedCode(configuration.content, language: configuration.language)
                    .font(ChatScaledFont.mono(scale: scale))
                    .padding(DSSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(DSColor.chatCard)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .stroke(DSColor.border, lineWidth: 1)
            )
            .markdownMargin(top: DSSpacing.s, bottom: DSSpacing.s)
        }
        // NOTE: 表本体・セルに .fixedSize(horizontal: false, vertical: true) を付けない。
        // MarkdownUI 標準テーマ（GitHub 等）は付けているが、Phlox のチャット文脈
        // （ScrollView + LazyVStack + 可変幅）では表のレイアウトが収束しなくなり、
        // リサイズ・アクティベーション起点で main thread が 100% 固着する
        // （2026-07-07 CPU 暴走。ADR 0045 / delivery/0024-teamview-cpu-fix-worklog.md）。
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(
                    TableBorderStyle(color: DSColor.border, width: 1)
                )
                .markdownTableBackgroundStyle(
                    .alternatingRows(
                        DSColor.fillSubtle,
                        Color.clear,
                        header: DSColor.fillSelected
                    )
                )
                .markdownMargin(top: DSSpacing.s, bottom: DSSpacing.s)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    FontSize(ChatTypography.bodyFontSize(scale: scale))
                    ForegroundColor(DSColor.chatTextPrimary)
                    BackgroundColor(nil)
                }
                .padding(.vertical, DSSpacing.xs * scale)
                .padding(.horizontal, DSSpacing.s * scale)
        }
}

// トランスクリプト行内に「非同期に自身のサイズを変える View」を置かない（駆動源#2・2026-07-05 実機確定）。
// CodeText 等はハイライト完了で行高が変わり LazyVStack の anchor translation → 行の破棄/再実体化が自励発振する。
@ViewBuilder
private func highlightedCode(_ content: String, language _: String?) -> some View {
    let code = content.isEmpty ? " " : content
    Text(ChatCodeHighlighter.highlight(code))
}

#if canImport(AppKit)
private func openChatMarkdownLink(_ url: URL) -> OpenURLAction.Result {
    NSWorkspace.shared.open(url)
    return .handled
}
#else
private func openChatMarkdownLink(_: URL) -> OpenURLAction.Result {
    .systemAction
}
#endif

#if canImport(AppKit)
private func copyToPasteboard(_ content: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content, forType: .string)
}
#else
private func copyToPasteboard(_: String) {}
#endif
