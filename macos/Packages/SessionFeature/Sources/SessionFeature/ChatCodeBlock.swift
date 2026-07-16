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
                    .textSelection(.enabled)
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

    /// 純粋なハイライト計算。非トークン文字は同色 run にまとめて1回だけ append する
    /// （1文字ずつの連結を廃止 = P2）。AttributedString は隣接同属性 run を凝集するため、
    /// 出力は旧・1文字連結版と完全同値（属性境界＝色切替点は1文字もズレない）。
    static func computeHighlight(_ code: String) -> AttributedString {
        var output = AttributedString()
        var index = code.startIndex
        var plainStart: String.Index?

        func flushPlain(before boundary: String.Index) {
            guard let start = plainStart else { return }
            append(String(code[start..<boundary]), color: DSColor.chatTextPrimary, to: &output)
            plainStart = nil
        }

        while index < code.endIndex {
            if code[index] == "/", code.index(after: index) < code.endIndex, code[code.index(after: index)] == "/" {
                flushPlain(before: index)
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(String(code[index..<end]), color: DSColor.codeSyntaxComment, to: &output)
                index = end
                continue
            }

            if code[index] == "\"" {
                flushPlain(before: index)
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let character = code[end]
                    if character == "\"" && !escaped {
                        end = code.index(after: end)
                        break
                    }
                    escaped = character == "\\" && !escaped
                    if character != "\\" {
                        escaped = false
                    }
                    end = code.index(after: end)
                }
                append(String(code[index..<end]), color: DSColor.codeSyntaxString, to: &output)
                index = end
                continue
            }

            if code[index].isNumber {
                flushPlain(before: index)
                let end = code[index...].firstIndex { !$0.isNumber && $0 != "." } ?? code.endIndex
                append(String(code[index..<end]), color: DSColor.codeSyntaxNumber, to: &output)
                index = end
                continue
            }

            if code[index].isLetter || code[index] == "_" {
                flushPlain(before: index)
                let end = code[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? code.endIndex
                let word = String(code[index..<end])
                append(word, color: keywords.contains(word) ? DSColor.codeSyntaxKeyword : DSColor.chatTextPrimary, to: &output)
                index = end
                continue
            }

            // 非トークン文字（空白・演算子・記号）: run を切らず貯めて同色でまとめて出す。
            if plainStart == nil { plainStart = index }
            index = code.index(after: index)
        }

        flushPlain(before: code.endIndex)
        return output
    }

    private static func append(_ string: String, color: Color, to output: inout AttributedString) {
        var chunk = AttributedString(string)
        chunk.foregroundColor = color
        output += chunk
    }
}
