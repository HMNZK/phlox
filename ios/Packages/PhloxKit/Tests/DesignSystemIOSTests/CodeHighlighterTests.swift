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
