import Foundation
import Testing
@testable import ChatRenderKit

@Suite("シンタックスレビューの回帰")
struct SyntaxReviewRegressionTests {
    @Test func shellAssignmentPrefixKeepsCommandPosition() {
        for (code, command, value) in [("SWIFT_TEST_OUTPUT=full bash run.sh", "bash", "full"),
                                      ("FOO=\"a b\" cmd -x", "cmd", "\"a b\"")] {
            let tokens = ChatCodeTokenizer.shell(code)
            #expect(tokens.contains(ChatCodeToken(text: command, kind: .command)), "\(code)")
            #expect(!tokens.contains { $0.kind == .command && $0.text == value }, "\(code)")
            #expect(tokens.map(\.text).joined() == code)
        }
    }

    @Test func unknownLongFencesKeepLegacyHighlighting() {
        let code = "let value = \"" + String(repeating: "x", count: 10_001) + "\"; print(Value())"
        for language: String? in [nil, "", "unknown"] {
            let tokens = ChatCodeTokenizer.tokens(for: code, language: language)
            #expect(tokens == ChatCodeTokenizer.swift(code))
            #expect(tokens.contains(ChatCodeToken(text: "let", kind: .keyword)))
        }
        #expect(ChatCodeTokenizer.tokens(for: code, language: "swift") == [.init(text: code, kind: .plain)])
    }

    @Test func regressionsFoundInReview() {
        for code in ["it's a test\nlet x = 1", "cp src/* dst/\nlet x = 1"] {
            let tokens = ChatCodeTokenizer.tokens(for: code, language: nil)
            #expect(tokens.contains(ChatCodeToken(text: "let", kind: .keyword)))
            #expect(!tokens.contains { $0.kind == .string || $0.kind == .comment })
        }
        for (path, code) in [("a.tsx", "const [a, b] = useState<number>(0);\nconst z = 2;"),
                             ("a.jsx", "for (let i=0;i<10;i++) {}\nconst y = 1;")] {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            #expect(!tokens.contains { $0.kind == .tag })
            #expect(tokens.contains(ChatCodeToken(text: "const", kind: .keyword)))
        }
        for path in ["a.css", "a.scss", "a.less"] {
            let tokens = ChatCodeTokenizer.tokens(for: "a { background: url(https://x/y.png); color: red; }", path: path)
            #expect(!tokens.contains { $0.kind == .comment })
            #expect(tokens.contains(ChatCodeToken(text: "color", kind: .property)))
        }
        #expect(ChatCodeTokenizer.shell("ls;# note").contains(ChatCodeToken(text: "# note", kind: .comment)))
    }

    // dev の ChatCodeTokenizer.swift から採取した代表出力。未知・未指定は同じ互換経路。
    @Test func unspecifiedAndUnknownFencesMatchDev() {
        let examples: [(String, [ChatCodeToken])] = [
            ("it's a test\nlet x = 1", [.init(text: "it's a test\n", kind: .plain), .init(text: "let", kind: .keyword), .init(text: " x = ", kind: .plain), .init(text: "1", kind: .number)]),
            ("cp src/* dst/\nlet x = 1", [.init(text: "cp src/* dst/\n", kind: .plain), .init(text: "let", kind: .keyword), .init(text: " x = ", kind: .plain), .init(text: "1", kind: .number)]),
            ("associatedtype T; let x = 0xFF // func", [.init(text: "associatedtype T; ", kind: .plain), .init(text: "let", kind: .keyword), .init(text: " x = ", kind: .plain), .init(text: "0", kind: .number), .init(text: "xFF ", kind: .plain), .init(text: "// func", kind: .comment)]),
            ("let s = #\"if\"#; await f()", [.init(text: "let", kind: .keyword), .init(text: " s = #", kind: .plain), .init(text: "\"if\"", kind: .string), .init(text: "#; ", kind: .plain), .init(text: "await", kind: .keyword), .init(text: " f()", kind: .plain)]),
        ]
        for (code, expected) in examples {
            for language: String? in [nil, "", "unknown"] {
                #expect(ChatCodeTokenizer.tokens(for: code, language: language) == expected)
            }
        }
        #expect(ChatCodeTokenizer.shell("cmd 2>&1") == [
            .init(text: "cmd", kind: .command), .init(text: " ", kind: .plain),
            .init(text: "2>&", kind: .operator), .init(text: "1", kind: .command)
        ])
    }

    @Test func languageSpecificBoundariesPreserveLaterTokens() {
        let examples: [(String, String, [(String, ChatCodeTokenKind)])] = [
            ("a.log", "INFO can't connect\nERROR failed", [("can't", .plain), ("ERROR", .keyword)]),
            ("a.tex", "Don't\n\\section{A}", [("Don't", .plain), ("\\section", .keyword)]),
            ("a.bib", "@article{a, title={Don't}, year=2026}", [("Don't", .plain), ("year", .key)]),
            ("a.yaml", "description: it's fine\nuser-name: 'it''s true'\nname: x", [("it's fine", .plain), ("user-name", .key), ("'it''s true'", .string), ("name", .key)]),
            ("a.hs", "x = foldl' f 0 xs\nmodule Main where", [("foldl'", .plain), ("module", .keyword)]),
            ("a.ps1", #"$x = 'C:\'; $y = "C:\"; Write-Host $x"#, [(#"'C:\'"#, .string), (#""C:\""#, .string), ("Write-Host", .command)]),
            ("a.js", #"const x = `if \` return`; const y = 1;"#, [(#"`if \` return`"#, .string), ("1", .number)]),
            ("a.rb", "Foo::Bar; :ready", [("::Bar", .plain), (":ready", .string)]),
            ("a.cs", "var x = items[count];\n[Obsolete] public class A {}", [("count", .plain), ("Obsolete", .attribute)]),
            ("Makefile", "CC := gcc\nall: main\n\t$(CXX) main.c", [("CC", .key), (":=", .operator), ("all", .section)]),
            ("Dockerfile", "RUN echo first && \\\n    printf '%s' next\nCOPY . /app", [("echo", .command), ("printf", .command), ("COPY", .keyword)]),
            ("a.html", "<p>a < b and a<10</p><div>ok</div>", [("a < b and a<10", .plain), ("div", .tag)]),
            ("a.csv", "nan,inf,-inf,1e3,-2.5,+4", [("nan", .plain), ("inf", .plain), ("-inf", .plain), ("1e3", .number), ("-2.5", .number), ("+4", .number)]),
            ("a.sh", "ROOT=/tmp bash run.sh; if [ -d \"$ROOT\" ]; then echo yes; fi", [("ROOT=", .variable), ("/tmp ", .plain), ("bash", .command), ("[", .command), ("]", .command), ("echo", .command)]),
            ("a.md", "[inline](https://a) [reference][id]\n[id]: https://a \"title\"", [("https://a", .link), ("id", .link), ("\"title\"", .string)]),
        ]
        for (path, code, checks) in examples {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
            for (part, kind) in checks {
                let range = (code as NSString).range(of: part, options: .backwards)
                var offset = 0
                for token in tokens {
                    let tokenRange = NSRange(location: offset, length: token.text.utf16.count)
                    if NSIntersectionRange(range, tokenRange).length > 0 {
                        #expect(token.kind == kind, "\(path): \(part) → \(token)")
                    }
                    offset = NSMaxRange(tokenRange)
                }
            }
        }
    }

    @Test func lineLocalScansStayLinear() {
        let html = String(repeating: "<p>R&D Q&A text</p>\n", count: 50_000)
        let toml = String(repeating: "  [1, 2, 3\n", count: 90_000)
        for (path, code) in [("a.html", html), ("a.toml", toml)] {
            let elapsed = ContinuousClock().measure { _ = ChatCodeTokenizer.tokens(for: code, path: path) }
            #expect(elapsed < .seconds(2), "\(path): \(elapsed)")
        }
    }

    @Test func jsxTagsAndTypeParametersUseExpressionContext() {
        let cases = [
            "const f = <T,>(value: T) => value; const x = <Box />;",
            "const f = <T extends object>(value: T) => value; const x = <Box />;",
            "const x = useState<number>(0); const view = <Box />;",
            "const x = value < limit; const view = <Box />;",
        ]
        for code in cases {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.tsx")
            #expect(tokens.contains { $0.kind == .tag && $0.text.contains("Box") })
            #expect(!tokens.contains { $0.kind == .tag && ($0.text.contains("T") || $0.text.contains("number") || $0.text.contains("limit")) })
            #expect(tokens.contains(ChatCodeToken(text: "const", kind: .keyword)))
            #expect(tokens.map(\.text).joined() == code)
        }
    }
}
