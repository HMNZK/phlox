import Testing
@testable import ChatRenderKit

/// コードブロックの言語名で色分けの規則を切り替える（2026-09-26 ユーザー依頼: シェルやほかの言語にも色を付ける）。
@Suite("ChatRenderKit: 言語ごとの色分け")
struct ChatCodeLanguageTests {
    private func kinds(_ code: String, _ language: String?) -> [String: ChatCodeTokenKind] {
        Dictionary(ChatCodeTokenizer.tokens(for: code, language: language).map { ($0.text, $0.kind) }, uniquingKeysWith: { a, _ in a })
    }

    @Test("Python は # 以降がコメントで、def がキーワード")
    func pythonUsesHashCommentsAndKeywords() {
        let k = kinds("def f(): # 説明", "python")
        #expect(k["def"] == .keyword)
        #expect(k["# 説明"] == .comment)
    }

    @Test("TypeScript は単一引用符とバッククォートも文字列")
    func typeScriptQuotes() {
        let k = kinds("const a = 'x' + `y`", "ts")
        #expect(k["const"] == .keyword)
        #expect(k["'x'"] == .string)
        #expect(k["`y`"] == .string)
    }

    @Test("SQL のキーワードは大文字でも小文字でも色が付き、-- はコメント")
    func sqlIsCaseInsensitive() {
        let k = kinds("SELECT id from t -- 全件", "sql")
        #expect(k["SELECT"] == .keyword)
        #expect(k["from"] == .keyword)
        #expect(k["-- 全件"] == .comment)
    }

    @Test("bash のブロックはシェルの分類（先頭の語がコマンド）")
    func bashUsesShellTokenizer() {
        #expect(ChatCodeTokenizer.tokens(for: "git status", language: "bash") == ChatCodeTokenizer.shell("git status"))
    }

    @Test("言語名が無い・知らないときは従来どおり Swift の規則")
    func unknownLanguageFallsBackToSwift() {
        #expect(ChatCodeTokenizer.tokens(for: "let x = 1", language: nil) == ChatCodeTokenizer.swift("let x = 1"))
        #expect(ChatCodeTokenizer.tokens(for: "let x = 1", language: "brainfuck") == ChatCodeTokenizer.swift("let x = 1"))
    }

    @Test("差分でも拡張子から言語を決める（.py の # はコメント）")
    func diffPathRoutesByExtension() {
        let tokens = ChatCodeTokenizer.tokens(for: "x = 1 # 値", path: "src/app.py")
        #expect(tokens.contains(ChatCodeToken(text: "# 値", kind: .comment)))
    }

    @Test("差分の行ごとの分類でも、複数行のブロックコメントの途中の行はコメント")
    func diffLinesKeepBlockCommentAcrossLines() {
        let lines = ChatCodeTokenizer.lineTokens(for: ["/* 説明", "const は書かない", "*/", "const a = 1"], path: "a.js")
        #expect(lines.count == 4)
        #expect(lines[1] == [ChatCodeToken(text: "const は書かない", kind: .comment)])
        #expect(lines[3].first == ChatCodeToken(text: "const", kind: .keyword))
    }

    @Test("CRLF の行でも、行コメントは行末で止まる")
    func lineCommentStopsAtCRLF() {
        let tokens = ChatCodeTokenizer.tokens(for: "# 説明\r\nimport os", language: "python")
        #expect(tokens.contains(ChatCodeToken(text: "import", kind: .keyword)))
    }
}
