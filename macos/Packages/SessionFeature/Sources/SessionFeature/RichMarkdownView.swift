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
    private let bodyColor: Color
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    public init(_ markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {
        self.markdown = TranscriptMarkdownPresentation.prepare(markdown)
        self.bodyColor = bodyColor
    }

    public init(streaming markdown: String, bodyColor: Color = DSColor.chatTextPrimary) {
        self.markdown = TranscriptMarkdownPresentation.prepare(markdown)
        self.bodyColor = bodyColor
    }

    @MainActor private static var themes: [String: Theme] = [:]

    public var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Markdown(markdown)
            .markdownTheme(Self.theme(for: themeID, scale: scale, languageCode: languageCode, bodyColor: bodyColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction(handler: openChatMarkdownLink))
    }

    @MainActor
    static func theme(for themeID: String, scale: CGFloat, languageCode: String = "", bodyColor: Color = DSColor.chatTextPrimary) -> Theme {
        let cacheKey = themeCacheKey(themeID: themeID, scale: scale, bodyColor: bodyColor, languageCode: languageCode)
        if let theme = themes[cacheKey] {
            return theme
        }
        let theme = chatMarkdownTheme(scale: scale, languageCode: languageCode, bodyColor: bodyColor)
        themes[cacheKey] = theme
        return theme
    }

    static func themeCacheKey(themeID: String, scale: CGFloat, bodyColor: Color = DSColor.chatTextPrimary, languageCode: String = "") -> String {
        let role = bodyColor == DSColor.chatTextSecondary ? "secondary" : "primary"
        return "\(themeID):\(scale):\(languageCode):\(role)"
    }
}

@MainActor
private func chatMarkdownTheme(scale: CGFloat, languageCode: String, bodyColor: Color) -> Theme {
    Theme()
        .text {
            ForegroundColor(bodyColor)
            FontSize(ChatTypography.bodyFontSize(scale: scale))
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(ChatTypography.codeFontSize(scale: scale))
            // 04 A1: 色は注意の 4 状態だけ。インラインのコードは本文色＋淡い地で区別する。
            ForegroundColor(bodyColor)
            BackgroundColor(DSColor.fillSubtle)
        }
        .link {
            ForegroundColor(DSColor.accentInk)
        }
        // NOTE: 箇条書きの項目が折り返すと、折り返し行の縦高さが確保されず次項目と重なって潰れる
        // （MarkdownUI v2.4.1 の ListItemView は Label{content} icon:{marker} 構成で、項目 content に
        // 縦サイズ確保が無い）。list 項目に限定して縦サイズを固定し、全行分の高さを確保する。
        // .listItem は list 項目にのみ適用され table セル（.table/.tableCell）へは波及しないため、
        // .fixedSize による表レイアウト非収束＝ADR 0045 の CPU 暴走とは無関係。
        .listItem { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(bottom: TranscriptTypography.withinAnswer)
        }
        // Chat Screen.dc.html: 「•」はアクセント色の太字・本文との間 8。
        .bulletedListMarker { _ in
            Text(verbatim: "•")
                .fontWeight(.bold)
                .foregroundStyle(DSColor.chatAccent)
                .relativeFrame(minWidth: .em(1), alignment: .leading)
        }
        // MarkdownUI の空テーマは段落・見出しの label に縦サイズ確保を付けない。そのまま
        // selectable な Text を幅制約下へ置くと、描画が折り返しても親が 1 行高のままになり、
        // 次のブロックへ重なり得る。非表ブロックだけに固定し、折り返した全行の高さを親へ返す。
        // 表へは波及させない（ADR 0045）。
        // Chat Screen.dc.html の rich(): 段落の文字は自前で強調する（MarkdownUI は語ごとの色を持てない）。
        // 段落の間隔・箇条書きの並びは MarkdownUI のまま。
        // 画像を含む段落は Text で描けないので MarkdownUI のまま（強調はしない）。
        .paragraph { configuration in
            let markdown = configuration.content.renderMarkdown()
            Group {
                if markdown.contains("![") {
                    configuration.label
                } else {
                    Text(ChatProseText.attributed(markdown: markdown, scale: scale))
                        .font(.system(size: ChatTypography.bodyFontSize(scale: scale)))
                        .foregroundStyle(bodyColor)
                        .tint(DSColor.accentInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // 13pt・行の高さ 1.7（PhloxChat.dc.html）。
            .lineSpacing(6 * scale)
            .markdownMargin(bottom: TranscriptTypography.withinAnswer)
        }
        .heading1 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: 0, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(ChatTypography.heading1FontSize(scale: scale))
                    ForegroundColor(bodyColor)
                }
        }
        .heading2 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: TranscriptTypography.betweenAnswers, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(ChatTypography.heading2FontSize(scale: scale))
                    ForegroundColor(bodyColor)
                }
        }
        .heading3 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: TranscriptTypography.withinAnswer, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(ChatTypography.heading3FontSize(scale: scale))
                    ForegroundColor(bodyColor)
                }
        }
        .heading4 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: TranscriptTypography.withinAnswer, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(TranscriptTypography.pointSize(for: .heading4, scale: scale))
                    ForegroundColor(bodyColor)
                }
        }
        .heading5 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: TranscriptTypography.withinAnswer, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(TranscriptTypography.pointSize(for: .heading5, scale: scale))
                    ForegroundColor(bodyColor)
                }
        }
        .heading6 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                // Chat Screen.dc.html: 見出しの下に区切り線。
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
                .markdownMargin(top: TranscriptTypography.withinAnswer, bottom: TranscriptTypography.withinAnswer)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(TranscriptTypography.pointSize(for: .heading6, scale: scale))
                    ForegroundColor(bodyColor)
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
                    Text(configuration.language?.isEmpty == false ? configuration.language! : UIWording.text(.missingMarkdownLanguage, languageCode: languageCode))
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                    Spacer(minLength: 0)
                    Button {
                        copyToPasteboard(configuration.content)
                    } label: {
                        Label(UIWording.text(.copyAction, languageCode: languageCode), systemImage: "doc.on.doc")
                            .font(ChatScaledFont.captionStrong(scale: scale))
                            .foregroundStyle(DSColor.chatTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(UIWording.text(.copyCodeHelp, languageCode: languageCode))
                }
                .padding(.horizontal, TranscriptTypography.cardHorizontalInset)
                .padding(.vertical, TranscriptTypography.cardVerticalInset)

                Divider()
                    .overlay(DSColor.separator)

                highlightedCode(configuration.content, language: configuration.language)
                    .font(ChatScaledFont.mono(scale: scale))
                    .padding(TranscriptTypography.codeContentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chatTextSelection()
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
                    ForegroundColor(bodyColor)
                    BackgroundColor(nil)
                }
                .padding(.vertical, DSSpacing.xs * scale)
                .padding(.horizontal, DSSpacing.s * scale)
        }
}

// トランスクリプト行内に「非同期に自身のサイズを変える View」を置かない（駆動源#2・2026-07-05 実機確定）。
// CodeText 等はハイライト完了で行高が変わり LazyVStack の anchor translation → 行の破棄/再実体化が自励発振する。
@ViewBuilder
private func highlightedCode(_ content: String, language: String?) -> some View {
    let code = content.isEmpty ? " " : content
    Text(ChatCodeHighlighter.highlight(code, language: language))
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
