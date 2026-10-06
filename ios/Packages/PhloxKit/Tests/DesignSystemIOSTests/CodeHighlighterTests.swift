import ChatRenderKit
import SwiftUI
import Testing
@testable import DesignSystemIOS

struct CodeHighlighterTests {
    @Test("文字列内のキーワードとコメント記号は string のまま")
    func stringTakesPriority() {
        let code = #"let value = "return // not a comment""#
        let tokens = CodeHighlighter.tokens(for: code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
        #expect(tokens.contains(CodeToken(kind: .string, text: #""return // not a comment""#)))
        #expect(!tokens.contains { $0.kind == .comment })
        #expect(!tokens.contains(CodeToken(kind: .keyword, text: "return")))
    }

    @Test("コメント内の文字列と数値は comment のまま")
    func commentTakesPriority() {
        let code = "// \"return 42\"\nlet answer = 7"
        let tokens = CodeHighlighter.tokens(for: code, language: "SWIFT")
        #expect(tokens.map(\.text).joined() == code)
        #expect(tokens.first == CodeToken(kind: .comment, text: "// \"return 42\""))
        #expect(tokens.contains(CodeToken(kind: .number, text: "7")))
    }

    @Test("エスケープ引用符と未終端文字列でも連結不変条件を保つ")
    func escapedAndUnterminatedStringsPreserveSource() {
        let samples = [
            #"let a = \"a\\\"b\"; return a"#,
            #"let broken = \"return 123"#,
            "\"\"\n// tail",
        ]
        for code in samples {
            #expect(CodeHighlighter.tokens(for: code, language: "swift").map(\.text).joined() == code)
        }
    }

    @Test("複合したランダム風入力で範囲が重ならず欠落しない")
    func mixedInputsPreserveEveryCharacter() {
        let fragments = ["func", " ", "f_2", "()", " {\n", "// \"x\" 99", "\n", "let", " n=0x2A ", #"\"if\\n\""#, "\nreturn n\n}"]
        let code = fragments.joined()
        let tokens = CodeHighlighter.tokens(for: code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
        #expect(tokens.allSatisfy { !$0.text.isEmpty })
    }

    @Test("nil 言語は全文 plain")
    func nilLanguageIsPlain() {
        let code = "let x = 42"
        #expect(CodeHighlighter.tokens(for: code, language: nil) == [.init(kind: .plain, text: code)])
    }
}

/// 共有トークン列（ChatRenderKit）を iOS のテーマ色へ対応付ける入口。
struct CodeHighlighterSharedTokenTests {
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

    @Test("共有トークナイザの出力を色付き文字列にしても、文字は 1 つも増減しない")
    func attributedPreservesCharacters() {
        let tokens = ChatCodeTokenizer.shell("swift test --package-path $HOME && echo ok")
        let attributed = CodeHighlighter.attributed(tokens: tokens)
        #expect(String(attributed.characters) == "swift test --package-path $HOME && echo ok")
    }

    @Test("シェル入口は原文を保つ（表示用のインデントを混ぜない）", arguments: [
        "swift build \\\n  --configuration release",
        "Read /tmp/a.txt",
        "",
    ])
    func shellEntryPreservesSource(_ command: String) {
        #expect(String(CodeHighlighter.shell(command).characters) == command)
    }

    @Test("diff 入口は原文を保ち、未対応拡張子でも落ちない", arguments: [
        ("let x = 1", "a.swift"),
        ("plain text", "notes.txt"),
        ("", "empty.swift"),
    ])
    func diffEntryPreservesSource(_ code: String, _ path: String) {
        #expect(String(CodeHighlighter.diff(code, path: path).characters) == code)
    }

    private func color(for text: String, in attributed: AttributedString) -> Color? {
        attributed.runs.first { run in
            String(attributed[run.range].characters).contains(text)
        }?.foregroundColor
    }
}
