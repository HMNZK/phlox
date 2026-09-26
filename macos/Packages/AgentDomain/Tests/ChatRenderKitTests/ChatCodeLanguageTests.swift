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

    @Test("Python の \"\"\" で囲んだ複数行の文字列は、途中の行まで文字列")
    func pythonTripleQuotedStringSpansLines() {
        let lines = ChatCodeTokenizer.lineTokens(for: ["x = \"\"\"a", "say \"hi\" def", "\"\"\" # c"], path: "s.py")
        #expect(lines[1] == [ChatCodeToken(text: "say \"hi\" def", kind: .string)])
        #expect(lines[2].last == ChatCodeToken(text: "# c", kind: .comment))
    }

    @Test("Python の三重引用符は、エスケープされた引用符では閉じない")
    func pythonTripleQuoteIgnoresEscapedQuote() {
        let tokens = ChatCodeTokenizer.tokens(for: "\"\"\"a\\\"\"\"b\"\"\" def", language: "python")
        #expect(tokens.first == ChatCodeToken(text: "\"\"\"a\\\"\"\"b\"\"\"", kind: .string))
        #expect(tokens.last == ChatCodeToken(text: "def", kind: .keyword))
    }

    @Test("行に単独の CR や U+2028 があっても、行と色の対応がずれない")
    func lineTokensKeepLinesWithEmbeddedLineBreaks() {
        let lines = ["a\rb", "x\u{2028}y", "c\r", "def"]
        let result = ChatCodeTokenizer.lineTokens(for: lines, path: "s.py")
        #expect(result.map { $0.map(\.text).joined() } == lines)
        #expect(result[3] == [ChatCodeToken(text: "def", kind: .keyword)])
    }

    @Test("swift は型・. で始まる名前・呼び出しを分ける（見本の tok）")
    func swiftSplitsTypesMembersAndCalls() {
        let k = kinds("func expireOverdue(at now: Date) { pending[i].state = .expired }", "swift")
        #expect(k["func"] == .keyword)
        #expect(k["expireOverdue"] == .call)
        #expect(k["Date"] == .type)
        #expect(k[".state"] == .member)
        #expect(k[".expired"] == .member)
    }

    @Test("言語名なしと JSON は、名前を分けない")
    func noLanguageAndJSONKeepNamesPlain() {
        #expect(ChatCodeTokenizer.tokens(for: "let d = Date()", language: nil).contains { $0.kind == .type } == false)
        #expect(ChatCodeTokenizer.tokens(for: "{\"a\": Foo}", language: "json").contains { $0.kind == .type } == false)
    }

    @Test("R は呼び出しを分け、Dockerfile は大文字の命令を型にしない")
    func rRefinesButDockerfileDoesNot() {
        #expect(kinds("x <- calculate(1)", "r")["calculate"] == .call)
        #expect(ChatCodeTokenizer.tokens(for: "FROM swift", language: "dockerfile").contains { $0.kind == .type } == false)
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
