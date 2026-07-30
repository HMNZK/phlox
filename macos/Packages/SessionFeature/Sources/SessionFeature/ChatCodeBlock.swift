import AppKit
import SwiftUI
import DesignSystem

struct CodeBlockView: View {
    let language: String?
    let code: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.s) {
                Text(language?.isEmpty == false ? language! : "text")
                    .font(ChatScaledFont.captionStrong(scale: scale))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.xs)
                    .background(DSColor.chatElevated, in: Capsule())
                Spacer(minLength: 0)
                Button(action: copyCode) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(ChatScaledFont.captionStrong(scale: scale))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.chatTextSecondary)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, DSSpacing.xs)
                .background(DSColor.fillSubtle, in: Capsule())
                .help("Copy code")
                .accessibilityIdentifier("CodeBlock.copyButton")
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.top, DSSpacing.m)
            .padding(.bottom, DSSpacing.s)

            ScrollView(.horizontal) {
                Text(ChatCodeHighlighter.highlight(code.isEmpty ? " " : code))
                    .font(ChatScaledFont.mono(scale: scale))
                    .chatTextSelection()
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.bottom, DSSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DSColor.chatCard, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.border, lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

enum ChatCodeHighlighter {
    private static let keywords: Set<String> = [
        "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "do", "else", "enum", "false", "for", "func", "guard", "if", "import", "in",
        "init", "let", "nil", "private", "public", "return", "self", "static", "struct", "switch",
        "throw", "throws", "true", "try", "var", "while",
    ]

    /// 内容同一性をキーにメモ化した窓口（P2）。同一内容の再ハイライトは走らない。
    /// キャッシュは非観測ストレージ（static NSCache）なので body から呼んでも @Observable state を書かない。
    static func highlight(_ code: String) -> AttributedString {
        ChatMessageRenderCache.highlightedCode(code)
    }

    /// diff 本文用のトークン分類。未対応拡張子は装飾せず plain にフォールバックする。
    static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        guard path.lowercased().hasSuffix(".swift") else {
            return code.isEmpty ? [] : [ChatCodeToken(text: code, kind: .plain)]
        }
        return tokenizeSwift(code)
    }

    static func computeDiffHighlight(_ code: String, path: String) -> AttributedString {
        var output = AttributedString()
        for token in tokens(for: code, path: path) {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    /// 純粋なハイライト計算。非トークン文字は同色 run にまとめて1回だけ append する
    /// （1文字ずつの連結を廃止 = P2）。AttributedString は隣接同属性 run を凝集するため、
    /// 出力は旧・1文字連結版と完全同値（属性境界＝色切替点は1文字もズレない）。
    static func computeHighlight(_ code: String) -> AttributedString {
        var output = AttributedString()
        for token in tokenizeSwift(code) {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    private static func append(_ string: String, color: Color, to output: inout AttributedString) {
        var chunk = AttributedString(string)
        chunk.foregroundColor = color
        output += chunk
    }

    private static func tokenizeSwift(_ code: String) -> [ChatCodeToken] {
        var tokens: [ChatCodeToken] = []
        var index = code.startIndex

        func append(_ text: String, _ kind: ChatCodeTokenKind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(ChatCodeToken(text: text, kind: kind))
            }
        }

        while index < code.endIndex {
            if code[index] == "/", code.index(after: index) < code.endIndex, code[code.index(after: index)] == "/" {
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(String(code[index..<end]), .comment)
                index = end
                continue
            }
            if code[index] == "\"" {
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let character = code[end]
                    if character == "\"" && !escaped {
                        end = code.index(after: end)
                        break
                    }
                    escaped = character == "\\" && !escaped
                    end = code.index(after: end)
                }
                append(String(code[index..<end]), .string)
                index = end
                continue
            }
            if code[index].isNumber {
                let end = code[index...].firstIndex { !$0.isNumber && $0 != "." } ?? code.endIndex
                append(String(code[index..<end]), .number)
                index = end
                continue
            }
            if code[index].isLetter || code[index] == "_" {
                let end = code[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? code.endIndex
                let word = String(code[index..<end])
                append(word, keywords.contains(word) ? .keyword : .plain)
                index = end
                continue
            }
            append(String(code[index]), .plain)
            index = code.index(after: index)
        }
        return tokens
    }

    private static func color(for kind: ChatCodeTokenKind) -> Color {
        switch kind {
        case .keyword: DSColor.codeSyntaxKeyword
        case .string: DSColor.codeSyntaxString
        case .number: DSColor.codeSyntaxNumber
        case .comment: DSColor.codeSyntaxComment
        case .plain: DSColor.chatTextPrimary
        }
    }
}

enum ChatCodeTokenKind: Equatable, Sendable {
    case keyword
    case string
    case number
    case comment
    case plain
}

struct ChatCodeToken: Equatable, Sendable {
    var text: String
    let kind: ChatCodeTokenKind
}
