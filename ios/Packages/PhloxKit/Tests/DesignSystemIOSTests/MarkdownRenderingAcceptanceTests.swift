import Foundation
import Testing
@testable import DesignSystemIOS

/// task-5 受け入れテスト（PM 著・実装役は編集禁止）。
/// チャットのマークダウン描画パリティ（Phlox 本体 ChatCodeBlock / RichMarkdownView 相当）の
/// 純関数コア: フェンス分割（MarkdownBlockParser）とシンタックスハイライト（CodeHighlighter）。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
struct MarkdownBlockParserAcceptanceTests {
    @Test("フェンス付きコードブロックを言語ラベル付きで分割する")
    func splitsFencedCodeBlock() {
        let text = "before\n```swift\nlet x = 1\n```\nafter"
        let blocks = MarkdownBlockParser.blocks(from: text)
        #expect(blocks == [
            .paragraph("before"),
            .code(language: "swift", content: "let x = 1"),
            .paragraph("after"),
        ])
    }

    @Test("言語指定なしのフェンスは language nil")
    func fenceWithoutLanguage() {
        let blocks = MarkdownBlockParser.blocks(from: "```\nplain code\n```")
        #expect(blocks == [.code(language: nil, content: "plain code")])
    }

    @Test("閉じられていないフェンスは末尾までコードとして扱う")
    func unterminatedFence() {
        let blocks = MarkdownBlockParser.blocks(from: "```py\nprint(1)\nprint(2)")
        #expect(blocks == [.code(language: "py", content: "print(1)\nprint(2)")])
    }

    @Test("フェンスが無い本文は単一段落")
    func plainTextIsSingleParagraph() {
        #expect(MarkdownBlockParser.blocks(from: "こんにちは **世界**")
                == [.paragraph("こんにちは **世界**")])
    }

    @Test("複数のコードブロックを順序どおり分割する")
    func multipleFences() {
        let text = "A\n```swift\nlet a = 1\n```\nB\n```sh\nls -la\n```\nC"
        let blocks = MarkdownBlockParser.blocks(from: text)
        #expect(blocks == [
            .paragraph("A"),
            .code(language: "swift", content: "let a = 1"),
            .paragraph("B"),
            .code(language: "sh", content: "ls -la"),
            .paragraph("C"),
        ])
    }
}

struct CodeHighlighterAcceptanceTests {
    @Test("不変条件: トークンの text 連結は元のコードに一致する")
    func tokensConcatenateToOriginal() {
        let code = "func greet(name: String) -> String {\n    // あいさつ\n    return \"Hello, \\(name)\" // 42\n}"
        let tokens = CodeHighlighter.tokens(for: code, language: "swift")
        #expect(tokens.map(\.text).joined() == code)
    }

    @Test("swift のキーワードを keyword として分類する")
    func classifiesSwiftKeywords() {
        let tokens = CodeHighlighter.tokens(for: "func foo() { return 1 }", language: "swift")
        #expect(tokens.contains(CodeToken(kind: .keyword, text: "func")))
        #expect(tokens.contains(CodeToken(kind: .keyword, text: "return")))
    }

    @Test("文字列リテラルを string として分類する")
    func classifiesStringLiterals() {
        let tokens = CodeHighlighter.tokens(for: #"let s = "hello""#, language: "swift")
        #expect(tokens.contains(CodeToken(kind: .string, text: #""hello""#)))
    }

    @Test("行コメントを comment として分類する")
    func classifiesLineComments() {
        let tokens = CodeHighlighter.tokens(for: "let x = 1 // note", language: "swift")
        #expect(tokens.contains(CodeToken(kind: .comment, text: "// note")))
    }

    @Test("数値リテラルを number として分類する")
    func classifiesNumbers() {
        let tokens = CodeHighlighter.tokens(for: "let x = 42", language: "swift")
        #expect(tokens.contains(CodeToken(kind: .number, text: "42")))
    }

    @Test("未知の言語は全文 plain の単一トークン")
    func unknownLanguageIsPlain() {
        let code = "SELECT * FROM users;"
        let tokens = CodeHighlighter.tokens(for: code, language: "cobol-2026")
        #expect(tokens == [CodeToken(kind: .plain, text: code)])
    }
}
