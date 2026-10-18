import SwiftUI
import DesignSystem

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 言語ラベル、コピー操作、Swift シンタックスハイライトを備えたコードブロック。
public struct DSCodeBlock: View {
    private let language: String?
    private let code: String

    public init(language: String?, code: String) {
        self.language = language
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(spacing: DSSpacing.s) {
                Text(language?.isEmpty == false ? language! : "text")
                    .font(DSFont.sessionDetailTechnical)
                    .foregroundStyle(DSColor.chatTextSecondary)

                Spacer(minLength: .zero)

                Button(action: copyCode) {
                    Image(systemName: "doc.on.doc")
                        .font(DSFont.sessionDetailSubtitle.weight(.medium))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("コードをコピー")
                .accessibilityIdentifier("DSCodeBlock.copyButton")
            }
            .padding(.horizontal, DSSpacing.m)
            .frame(minHeight: DSTouch.minSize)

            Divider()
                .overlay(DSColor.separator)

            ScrollView(.horizontal) {
                highlightedText
                    .font(DSFont.sessionDetailTechnical)
                    .textSelection(.enabled)
                    .padding(DSSpacing.m)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(IOSColor.bg.code)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.border, lineWidth: 1)
        }
    }

    private var highlightedText: Text {
        let displayCode = code.isEmpty ? " " : code
        return CodeHighlighter.tokens(for: displayCode, language: language).reduce(Text("")) { result, token in
            result + Text(token.text).foregroundColor(color(for: token.kind))
        }
    }

    private func color(for kind: CodeToken.Kind) -> Color {
        switch kind {
        case .plain: DSColor.chatTextPrimary
        case .keyword: DSColor.codeSyntaxKeyword
        case .string: DSColor.codeSyntaxString
        case .comment: DSColor.codeSyntaxComment
        case .number: DSColor.codeSyntaxNumber
        }
    }

    private func copyCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
    }
}
