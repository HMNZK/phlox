import AppKit
import SwiftUI
import DesignSystem
import MarkdownUI

/// ファイルは原文の書式だけを描画し、会話の文字倍率や自動強調を適用しない。
@MainActor
func fileMarkdownTheme(hoveredLink: URL?) -> Theme {
    Theme()
        .text { ForegroundColor(DSColor.textPrimary); FontSize(13) }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(11)
            BackgroundColor(DSColor.fillSubtle)
        }
        .link { ForegroundColor(DSColor.accentInk) }
        .paragraph { configuration in
            Group {
                if configuration.content.renderMarkdown().contains("![") {
                    configuration.label
                } else {
                    fileMarkdownText(configuration.content, hoveredLink: hoveredLink)
                }
            }
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
                .markdownMargin(top: 0, bottom: 0)
        }
        .heading1 { configuration in
            fileMarkdownText(configuration.content, hoveredLink: hoveredLink, headingLevel: 1, size: 24, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
                .markdownMargin(top: 0, bottom: 0)
        }
        .heading2 { configuration in
            fileMarkdownText(configuration.content, hoveredLink: hoveredLink, headingLevel: 2, size: 16, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .markdownMargin(top: 0, bottom: 0)
        }
        .heading3 { configuration in
            configuration.label.markdownTextStyle { FontSize(14); FontWeight(.semibold) }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 6, bottom: 0)
        }
        .listItem { configuration in
            configuration.label.fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .bulletedListMarker { _ in
            Text(verbatim: "•").foregroundStyle(DSColor.textTertiary)
                .frame(width: 12, alignment: .leading)
        }
        .blockquote { configuration in
            configuration.label.padding(.leading, DSSpacing.m)
                .overlay(alignment: .leading) { Rectangle().fill(DSColor.border).frame(width: 3) }
                .markdownTextStyle { ForegroundColor(DSColor.textSecondary) }
        }
        .codeBlock { configuration in
            Text(configuration.content.hasSuffix("\n") ? String(configuration.content.dropLast()) : configuration.content)
                .font(DSFont.monoCaption)
                .lineSpacing(6)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: DSRadius.m))
                .markdownMargin(top: 0, bottom: 0)
        }
        .table { configuration in
            FileMarkdownTable {
                configuration.label
                .markdownTableBorderStyle(TableBorderStyle(.horizontalBorders, color: DSColor.border))
                .markdownTableBackgroundStyle(.alternatingRows(.clear, .clear, header: DSColor.cardBackground))
            }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.m).stroke(DSColor.border, lineWidth: 1))
                .markdownMargin(top: 0, bottom: 0)
        }
        .tableCell { configuration in
            FileMarkdownTableCell(configuration: configuration) {
                configuration.label
                .markdownTextStyle {
                    FontSize(configuration.column == 0 ? 11 : 12)
                    if configuration.column == 0 { FontFamilyVariant(.monospaced) }
                    if configuration.row == 0 { FontWeight(.semibold) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
}

private struct FileMarkdownColumnWidths: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private struct FileMarkdownAllocatedWidths: EnvironmentKey {
    static let defaultValue: [Int: CGFloat] = [:]
}

private extension EnvironmentValues {
    var fileMarkdownColumnWidths: [Int: CGFloat] {
        get { self[FileMarkdownAllocatedWidths.self] }
        set { self[FileMarkdownAllocatedWidths.self] = newValue }
    }
}

/// MarkdownUI の表を使い、列の自然幅の比で余った幅を配分する。
private struct FileMarkdownTable<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var width: CGFloat = 0
    @State private var naturalWidths: [Int: CGFloat] = [:]

    var body: some View {
        content()
            .environment(\.fileMarkdownColumnWidths, allocatedWidths)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onPreferenceChange(FileMarkdownColumnWidths.self) { naturalWidths = $0 }
    }

    private var allocatedWidths: [Int: CGFloat] {
        let total = naturalWidths.values.reduce(0, +)
        guard width > 0, total > 0 else { return [:] }
        // MarkdownUI Grid の外側と列の間には、それぞれ 1pt の枠がある。
        let available = max(0, width - CGFloat(naturalWidths.count + 1))
        return naturalWidths.mapValues { available * $0 / total }
    }
}

private struct FileMarkdownTableCell<Content: View>: View {
    let configuration: TableCellConfiguration
    @ViewBuilder var content: () -> Content
    @Environment(\.fileMarkdownColumnWidths) private var widths

    var body: some View {
        content()
            .frame(width: widths[configuration.column], alignment: .leading)
            .preference(key: FileMarkdownColumnWidths.self,
                        value: [configuration.column: naturalWidth])
    }

    private var naturalWidth: CGFloat {
        let weight: NSFont.Weight = configuration.row == 0 ? .semibold : .regular
        let font = configuration.column == 0
            ? NSFont.monospacedSystemFont(ofSize: 11, weight: weight)
            : NSFont.systemFont(ofSize: 12, weight: weight)
        return (configuration.content.renderPlainText() as NSString).size(withAttributes: [.font: font]).width + 20
    }
}

@MainActor
private func fileMarkdownText(_ content: MarkdownContent, hoveredLink: URL?, headingLevel: Int = 0,
                              size: CGFloat = 13, weight: NSFont.Weight = .regular) -> some View {
    var markdown = content.renderMarkdown().trimmingCharacters(in: .newlines)
    let prefix = String(repeating: "#", count: headingLevel) + " "
    if headingLevel > 0, markdown.hasPrefix(prefix) { markdown.removeFirst(prefix.count) }
    let text = fileMarkdownAttributed(markdown, hoveredLink: hoveredLink)
    return Text(text)
        .font(.system(size: size, weight: weight == .bold ? .bold : weight == .semibold ? .semibold : .regular))
        .foregroundStyle(DSColor.textPrimary)
        .tint(DSColor.accentInk)
        .modifier(ChatLinkCursorModifier(text: text, scale: 1, fontSize: size, fontWeight: weight,
                                        lineSpacing: headingLevel > 0 ? 0 : 6))
}

func fileMarkdownAttributed(_ markdown: String, hoveredLink: URL?) -> AttributedString {
    var text = (try? AttributedString(markdown: markdown,
                                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(markdown)
    for run in text.runs {
        if let link = run.link {
            text[run.range].foregroundColor = DSColor.accentInk
            if link == hoveredLink { text[run.range].underlineStyle = .single }
        }
        if run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = DSFont.monoCaption
            text[run.range].backgroundColor = DSColor.fillSubtle
        }
    }
    return text
}
