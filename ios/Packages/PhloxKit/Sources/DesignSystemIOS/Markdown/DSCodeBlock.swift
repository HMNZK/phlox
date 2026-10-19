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
    @ScaledMetric(relativeTo: .footnote) private var codeLineSpacing = DSSpacing.xs

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
                    Label("コードをコピー", systemImage: "doc.on.doc")
                        .font(DSFont.sessionDetailSubtitle.weight(.medium))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressFeedbackStyle())
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
                    .lineSpacing(codeLineSpacing)
                    .textSelection(.enabled)
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.bottom, DSSpacing.s + DSSpacing.xxs)
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
