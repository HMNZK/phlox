import SwiftUI
import Testing
import ChatRenderKit
@testable import DesignSystemIOS

@Suite("DSChatCodeCard 白箱")
@MainActor
struct DSChatCodeCardWhiteboxTests {
    @Test("カードの寸法は iOS のカードトークンへ委譲する")
    func metricsUseMobileTokens() {
        let card = DSChatCodeCard {
            Text("Bash")
        } content: {
            Text("$ swift test")
        }

        _ = card.body
        #expect(DSChatCodeCardMetrics.cornerRadius == DSRadius.card)
        #expect(DSChatCodeCardMetrics.borderWidth == 1)
    }

    @Test("共有トークン種別を iOS のテーマ色へ対応付ける")
    func sharedTokenKindsUseThemeColors() {
        let tokens = [
            ChatCodeToken(text: "command", kind: .command),
            ChatCodeToken(text: "|", kind: .operator),
            ChatCodeToken(text: "subcommand", kind: .subcommand),
            ChatCodeToken(text: " ", kind: .plain),
            ChatCodeToken(text: "$HOME", kind: .variable),
            ChatCodeToken(text: " ", kind: .plain),
            ChatCodeToken(text: "42", kind: .number),
            ChatCodeToken(text: " ", kind: .plain),
            ChatCodeToken(text: "--option", kind: .option),
            ChatCodeToken(text: " ", kind: .plain),
            ChatCodeToken(text: "# note", kind: .comment),
            ChatCodeToken(text: " ", kind: .plain),
            ChatCodeToken(text: "\"text\"", kind: .string),
        ]

        let attributed = CodeHighlighter.attributed(tokens: tokens)

        #expect(String(attributed.characters) == tokens.map(\.text).joined())
        #expect(color(for: "command", in: attributed) == DSColor.codeSyntaxKeyword)
        #expect(color(for: "|", in: attributed) == DSColor.codeSyntaxKeyword)
        #expect(color(for: "subcommand", in: attributed) == DSColor.codeSyntaxNumber)
        #expect(color(for: "$HOME", in: attributed) == DSColor.codeSyntaxString)
        #expect(color(for: "42", in: attributed) == DSColor.codeSyntaxNumber)
        #expect(color(for: "--option", in: attributed) == DSColor.codeSyntaxNumber)
        #expect(color(for: "# note", in: attributed) == DSColor.codeSyntaxComment)
        #expect(color(for: "\"text\"", in: attributed) == DSColor.codeSyntaxString)
        #expect(color(for: " ", in: attributed) == DSColor.chatTextPrimary)
    }

    @Test("shell と diff の入口は共有トークナイザへ委譲する")
    func specializedEntriesPreserveSource() {
        let shell = "swift test --package-path $HOME"
        let diff = "let value = 1"

        #expect(String(CodeHighlighter.shell(shell).characters) == shell)
        #expect(String(CodeHighlighter.diff(diff, path: "Example.swift").characters) == diff)
        #expect(String(CodeHighlighter.diff(diff, path: "notes.txt").characters) == diff)
    }

    private func color(for text: String, in attributed: AttributedString) -> Color? {
        attributed.runs.first { run in
            String(attributed[run.range].characters).contains(text)
        }?.foregroundColor
    }
}
