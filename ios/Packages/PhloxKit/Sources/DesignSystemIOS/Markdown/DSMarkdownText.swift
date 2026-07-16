import SwiftUI
import DesignSystem
import MarkdownUI

/// チャット本文の Markdown とフェンス付きコードを描画する View。
public struct DSMarkdownText: View {
    private let content: String

    public init(_ content: String) {
        self.content = content
    }

    public var body: some View {
        let blocks = MarkdownBlockParser.blocks(from: content)
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(markdown):
                    Markdown(markdown)
                        .markdownTheme(Self.theme)
                        .font(DSFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .code(language, code):
                    DSCodeBlock(language: language, code: code)
                }
            }
        }
    }

    private static let theme = Theme()
        .text {
            ForegroundColor(DSColor.chatTextPrimary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            ForegroundColor(DSColor.chatAccent)
            BackgroundColor(DSColor.fillSubtle)
        }
        .link {
            ForegroundColor(DSColor.chatAccent)
        }
}
