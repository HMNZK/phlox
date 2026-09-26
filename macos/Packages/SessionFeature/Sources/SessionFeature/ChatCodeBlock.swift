import AppKit
import SwiftUI
import ChatRenderKit
import DesignSystem

struct CodeBlockView: View {
    let language: String?
    let code: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        // PhloxChat.dc.html: コード地・枠なし・角丸 8。28pt の見出し（言語は素の等幅 11・右に文字だけの「コピー」）＋区切り線。
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(language?.isEmpty == false ? language! : UIWording.text(.missingCodeBlockLanguage, languageCode: languageCode))
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(DSColor.chatTextSecondary)
                Spacer(minLength: 0)
                Button(action: copyCode) {
                    Text(UIWording.text(.copyAction, languageCode: languageCode))
                        .font(.system(size: 11 * scale))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.chatTextSecondary)
                .help(UIWording.text(.copyCodeHelp, languageCode: languageCode))
                .accessibilityIdentifier("CodeBlock.copyButton")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 28 * scale)
            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)

            ScrollView(.horizontal) {
                Text(ChatCodeHighlighter.highlight(code.isEmpty ? " " : code, language: language))
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .lineSpacing(7 * scale)
                    .chatTextSelection()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

public enum ChatCodeHighlighter {
    /// 内容同一性をキーにメモ化した窓口（P2）。同一内容の再ハイライトは走らない。
    /// キャッシュは非観測ストレージ（static NSCache）なので body から呼んでも @Observable state を書かない。
    public static func highlight(_ code: String) -> AttributedString {
        ChatMessageRenderCache.highlightedCode(code)
    }

    /// コードブロックの言語名で分類を切り替える窓口。言語名が無い・知らないときは `highlight(_:)` と同じ。
    public static func highlight(_ code: String, language: String?) -> AttributedString {
        ChatMessageRenderCache.highlightedCode(code, language: language)
    }

    /// diff 本文用のトークン分類。分類規則は ChatRenderKit に委譲する。
    public static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        ChatCodeTokenizer.tokens(for: code, path: path)
    }

    static func highlight(tokens: [ChatCodeToken]) -> AttributedString {
        var output = AttributedString()
        for token in tokens {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    static func computeShellHighlight(_ command: String) -> AttributedString {
        var output = AttributedString()
        for token in ChatCodeTokenizer.shell(command) {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    /// 純粋なハイライト計算。非トークン文字は同色 run にまとめて1回だけ append する
    /// （1文字ずつの連結を廃止 = P2）。AttributedString は隣接同属性 run を凝集するため、
    /// 出力は旧・1文字連結版と完全同値（属性境界＝色切替点は1文字もズレない）。
    static func computeHighlight(_ code: String) -> AttributedString {
        var output = AttributedString()
        for token in ChatCodeTokenizer.swift(code) {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    static func computeHighlight(_ code: String, language: String) -> AttributedString {
        var output = AttributedString()
        for token in ChatCodeTokenizer.tokens(for: code, language: language) {
            append(token.text, color: color(for: token.kind), to: &output)
        }
        return output
    }

    private static func append(_ string: String, color: Color, to output: inout AttributedString) {
        var chunk = AttributedString(string)
        chunk.foregroundColor = color
        output += chunk
    }

    // 既存テスト用の窓口。分類規則は共有トークナイザへ委譲する。
    static let tokenizeShell: @Sendable (String) -> [ChatCodeToken] = ChatCodeTokenizer.shell

    private static func color(for kind: ChatCodeTokenKind) -> Color {
        switch kind {
        case .keyword: DSColor.codeSyntaxKeyword
        case .string: DSColor.codeSyntaxString
        case .number: DSColor.codeSyntaxNumber
        case .comment: DSColor.codeSyntaxComment
        case .plain: DSColor.chatTextPrimary
        case .command: DSColor.codeSyntaxKeyword
        case .subcommand: DSColor.codeSyntaxNumber
        case .variable: DSColor.codeSyntaxString
        case .operator: DSColor.codeSyntaxKeyword
        case .option: DSColor.codeSyntaxNumber
        }
    }
}

public typealias ChatCodeTokenKind = ChatRenderKit.ChatCodeTokenKind
public typealias ChatCodeToken = ChatRenderKit.ChatCodeToken
