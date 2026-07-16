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
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(DSColor.chatTextSecondary)

                Spacer(minLength: .zero)

                Button(action: copyCode) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.chatTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DSCodeBlock.copyButton")
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)

            Divider()
                .overlay(DSColor.separator)

            ScrollView(.horizontal) {
                highlightedText
                    .font(DSFont.campMono)
                    .textSelection(.enabled)
                    .padding(DSSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DSColor.chatCard)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .stroke(DSColor.border)
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
