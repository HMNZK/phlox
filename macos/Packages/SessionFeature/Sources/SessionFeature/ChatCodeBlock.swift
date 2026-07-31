import AppKit
import SwiftUI
import ChatRenderKit
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

public enum ChatCodeHighlighter {
    /// 内容同一性をキーにメモ化した窓口（P2）。同一内容の再ハイライトは走らない。
    /// キャッシュは非観測ストレージ（static NSCache）なので body から呼んでも @Observable state を書かない。
    public static func highlight(_ code: String) -> AttributedString {
        ChatMessageRenderCache.highlightedCode(code)
    }

    /// diff 本文用のトークン分類。分類規則は ChatRenderKit に委譲する。
    public static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        ChatCodeTokenizer.tokens(for: code, path: path)
    }

    static func computeDiffHighlight(_ code: String, path: String) -> AttributedString {
        var output = AttributedString()
        for token in ChatCodeTokenizer.tokens(for: code, path: path) {
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
