import Foundation
import Testing
@testable import ChatRenderKit

@Suite("ChatRenderKit: ファイルのシンタックスハイライト仕様")
struct SyntaxHighlightingCoverageTests {
    struct Example: Sendable {
        let path: String
        let code: String
        let checks: [(String, ChatCodeTokenKind)]
    }

    // §3 の各種類を、色への割り当て前の字句分類で検査する。
    static let examples: [Example] = [
        .init(path: "a.swift", code: "let raw = #\"if 日本語\"# /* func */", checks: [("let", .keyword), ("#\"if 日本語\"#", .string), ("/* func */", .comment)]),
        .init(path: "a.mm", code: "#import <Foundation/Foundation.h>\n@interface Foo\nNSString *s = @\"return\";", checks: [("#import", .keyword), ("@interface", .keyword), ("@\"return\"", .string)]),
        .init(path: "a.hpp", code: "#include <stdio.h>\nint x = 42; char c = 'x'; // return", checks: [("#include", .keyword), ("int", .keyword), ("42", .number), ("'x'", .string), ("// return", .comment)]),
        .init(path: "a.java", code: "@Override public String s = \"\"\"\nclass\n\"\"\";", checks: [("@Override", .keyword), ("public", .keyword), ("\"\"\"\nclass\n\"\"\"", .string)]),
        .init(path: "a.kt", code: "@Deprecated val s = \"\"\"\nfun\n\"\"\"", checks: [("@Deprecated", .keyword), ("val", .keyword), ("\"\"\"\nfun\n\"\"\"", .string)]),
        .init(path: "a.cs", code: "[Obsolete] public string s = @\"class\ntext\";", checks: [("Obsolete", .attribute), ("public", .keyword), ("@\"class\ntext\"", .string)]),
        .init(path: "a.go", code: "func f() { s := `return\ntext`; }", checks: [("func", .keyword), ("`return\ntext`", .string)]),
        .init(path: "a.rs", code: "fn f<'a>(x: &'a str) { let s = r##\"return\"##; let c = 'x'; }", checks: [("fn", .keyword), ("let", .keyword), ("r##\"return\"##", .string), ("'x'", .string)]),
        .init(path: "a.pyw", code: "def f():\n    s = '''return\ntext''' # class", checks: [("def", .keyword), ("'''return\ntext'''", .string), ("# class", .comment)]),
        .init(path: "a.rb", code: "def f\n  :ready\nend # class", checks: [("def", .keyword), (":ready", .string), ("# class", .comment)]),
        .init(path: "a.phtml", code: "<b title=\"hello\"><?php $value = 42; echo \"if\"; ?></b>", checks: [("b", .tag), ("title", .attribute), ("<?php", .tag), ("$value", .variable), ("echo", .keyword), ("?>", .tag)]),
        .init(path: "a.pm", code: "my $value = 42; # return", checks: [("my", .keyword), ("$value", .variable), ("42", .number), ("# return", .comment)]),
        .init(path: "a.lua", code: "local x = [=[return\ntext]=] --[=[if\nthen]=]", checks: [("local", .keyword), ("[=[return\ntext]=]", .string), ("--[=[if\nthen]=]", .comment)]),
        .init(path: "a.r", code: "function(x) { TRUE } # function", checks: [("function", .keyword), ("TRUE", .keyword), ("# function", .comment)]),
        .init(path: "a.dart", code: "final s = '''return\ntext''';", checks: [("final", .keyword), ("'''return\ntext'''", .string)]),
        .init(path: "a.sc", code: "val s = \"\"\"return\ntext\"\"\"", checks: [("val", .keyword), ("\"\"\"return\ntext\"\"\"", .string)]),
        .init(path: "a.exs", code: "def f do\n  :ready\n  \"\"\"\nreturn\n\"\"\"\nend", checks: [("def", .keyword), (":ready", .string), ("\"\"\"\nreturn\n\"\"\"", .string)]),
        .init(path: "a.hs", code: "module Main where\n{- if\nthen -}\nx = \"hello\" -- let", checks: [("module", .keyword), ("{- if\nthen -}", .comment), ("-- let", .comment)]),
        .init(path: "a.lhs", code: "説明のみ\n> module Main where\n", checks: [("説明のみ", .plain), ("module", .keyword), ("where", .keyword)]),
        .init(path: "a.mjs", code: "const s = `if ${returnValue}`; // class", checks: [("const", .keyword), ("`if ${returnValue}`", .string), ("// class", .comment)]),
        .init(path: "a.cts", code: "interface Shape { value: number }", checks: [("interface", .keyword), ("number", .keyword)]),
        .init(path: "a.jsx", code: "const x = <Box title=\"if\">{true && {value: \"}\"}.value}</Box>;", checks: [("const", .keyword), ("Box", .tag), ("title", .attribute), ("\"if\"", .string), ("true", .keyword), ("\"}\"", .string)]),
        .init(path: "a.tsx", code: "const x = <Box size={42}>{false}</Box>;", checks: [("Box", .tag), ("size", .attribute), ("42", .number), ("false", .keyword)]),
        .init(path: "a.sh", code: "if git --version; then echo $HOME; fi # if", checks: [("if", .keyword), ("git", .command), ("--version", .option), ("$HOME", .variable), ("# if", .comment)]),
        .init(path: "a.fish", code: "function greet\nset name $USER\nend", checks: [("function", .keyword), ("set", .keyword), ("$USER", .variable), ("end", .keyword)]),
        .init(path: "a.ps1", code: "if ($true) { Get-Item $HOME } <# return\n#>", checks: [("if", .keyword), ("Get-Item", .command), ("$HOME", .variable), ("<# return\n#>", .comment)]),
        .init(path: "a.sql", code: "select id FROM users -- SELECT", checks: [("select", .keyword), ("FROM", .keyword), ("-- SELECT", .comment)]),
        .init(path: "a.gql", code: "query Get($id: ID!) { user(id: $id) { name } }\n\"\"\"query\ntext\"\"\"", checks: [("query", .keyword), ("$id", .variable), ("user", .key), ("name", .key), ("\"\"\"query\ntext\"\"\"", .string)]),
        .init(path: "a.json", code: "{\"key\": true, \"count\": 42, \"empty\": null}", checks: [("\"key\"", .key), ("true", .keyword), ("42", .number), ("null", .keyword)]),
        .init(path: "a.jsonc", code: "{\"key\": 42 /* true */} // null", checks: [("\"key\"", .key), ("/* true */", .comment), ("// null", .comment)]),
        .init(path: "a.json5", code: "{key: 'true', count: 42} // null", checks: [("key", .key), ("'true'", .string), ("42", .number), ("// null", .comment)]),
        .init(path: "a.yml", code: "message: |\n  true\n  # text\ncount: 42\n", checks: [("message", .key), ("  true\n  # text\n", .string), ("count", .key), ("42", .number)]),
        .init(path: "a.toml", code: "[server]\ntime = 2026-10-04T12:00:00Z\nmessage = \"\"\"true\ntext\"\"\" # false", checks: [("[server]", .section), ("time", .key), ("2026-10-04T12:00:00Z", .date), ("\"\"\"true\ntext\"\"\"", .string), ("# false", .comment)]),
        .init(path: "a.conf", code: "[server]\nport=42\n; true", checks: [("[server]", .section), ("port", .key), ("; true", .comment)]),
        .init(path: ".env.production", code: "NAME=${HOME}\nCOUNT=42 # true", checks: [("NAME", .key), ("=", .operator), ("${HOME}", .variable), ("# true", .comment)]),
        .init(path: "a.properties", code: "message=hello\\\n  world\ncount=42\n# true", checks: [("message", .key), ("hello\\\n  world", .string), ("# true", .comment)]),
        .init(path: "a.svg", code: "<?xml version=\"1.0\"?><svg width=\"42\">&amp;<![CDATA[if true]]><!-- return --></svg>", checks: [("svg", .tag), ("width", .attribute), ("\"42\"", .string), ("if true", .plain), ("<!-- return -->", .comment)]),
        .init(path: "Dockerfile", code: "FROM swift\nRUN echo $HOME --help # if", checks: [("FROM", .keyword), ("RUN", .keyword), ("echo", .command), ("$HOME", .variable), ("--help", .option)]),
        .init(path: "Makefile", code: "build:\n\techo $(HOME) # if", checks: [("build", .section), ("echo", .command), ("$(HOME)", .variable), ("# if", .comment)]),
        .init(path: "CMakeLists.txt", code: "set(NAME \"hello\") # if", checks: [("set", .keyword), ("\"hello\"", .string), ("# if", .comment)]),
        .init(path: ".gitignore", code: "# true\n!build/*.swift", checks: [("# true", .comment), ("!", .operator), ("*", .operator), ("build/", .pattern)]),
        .init(path: ".gitattributes", code: "*.swift text eol=lf", checks: [("*", .operator), (".swift", .pattern), ("text", .attribute), ("eol", .attribute)]),
        .init(path: "a.htm", code: "<div title=\"if\">&amp;<!-- class --></div><script>const x = 42;</script>", checks: [("div", .tag), ("title", .attribute), ("\"if\"", .string), ("<!-- class -->", .comment), ("const", .keyword), ("42", .number)]),
        .init(path: "a.md", code: "# Title\n[link](https://example.test) `if true`\n```swift\nlet x = 42\n```", checks: [("#", .structure), ("https://example.test", .link), ("`if true`", .string), ("let", .keyword), ("42", .number)]),
        .init(path: "a.mdx", code: "<Box title=\"if\">{const value = 42}</Box>", checks: [("Box", .tag), ("title", .attribute), ("const value = 42", .plain)]),
        .init(path: "a.css", code: "@media screen { .box { color: red; width: 42px; } } /* if */", checks: [("@media", .keyword), (".box", .selector), ("color", .property), ("42px", .number), ("/* if */", .comment)]),
        .init(path: "a.scss", code: "$accent: red; .box { color: $accent; }", checks: [("$accent", .variable), ("red", .string), (".box", .selector), ("color", .property)]),
        .init(path: "a.less", code: "@color: red; .box { color: @color; }", checks: [("@color", .variable), ("red", .string), (".box", .selector)]),
        .init(path: "a.vue", code: "<template><div v-if=\"ok\">{{ true }}</div></template><script lang=\"ts\">interface Shape {}</script><style lang=\"scss\">$color: red;</style>", checks: [("div", .tag), ("v-if", .keyword), ("true", .keyword), ("interface", .keyword), ("$color", .variable)]),
        .init(path: "a.svelte", code: "<div>{true}</div><script>const x = 42;</script><style>.box { color: red; }</style>", checks: [("div", .tag), ("true", .keyword), ("const", .keyword), ("color", .property)]),
        .init(path: "a.csv", code: "name,42,\"a\n\"\"b\"\n", checks: [(",", .delimiter), ("42", .number), ("\"a\n\"\"b\"", .string)]),
        .init(path: "a.tsv", code: "name\t42\ttext42", checks: [("\t", .delimiter), ("42", .number), ("text42", .plain)]),
        .init(path: "a.log", code: "2026-10-04 12:00:00 ERROR \"if\" 42 information ERRORLESS", checks: [("2026-10-04 12:00:00", .date), ("ERROR", .keyword), ("\"if\"", .string), ("42", .number), ("ERRORLESS", .plain)]),
        .init(path: "a.patch", code: "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-let x = 1\n+let x = 2\n\\ No newline at end of file", checks: [("--- a/file", .diffHeader), ("+++ b/file", .diffHeader), ("@@ -1 +1 @@", .diffHunk), ("-let x = 1", .diffRemoved), ("+let x = 2", .diffAdded), ("\\ No newline at end of file", .annotation)]),
        .init(path: "a.proto", code: "message User { string name = 1; } // if", checks: [("message", .keyword), ("string", .keyword), ("1", .number), ("// if", .comment)]),
        .init(path: "a.tfvars", code: "resource \"aws_instance\" \"example\" { count = 42 } # if", checks: [("resource", .keyword), ("\"aws_instance\"", .string), ("count", .key), ("42", .number)]),
        .init(path: "a.nix", code: "let name = ''if\ntext''; in { value = 42; }", checks: [("let", .keyword), ("''if\ntext''", .string), ("value", .key)]),
        .init(path: "a.sty", code: "\\begin{equation} $42$ \\end{equation} % if", checks: [("\\begin", .keyword), ("equation", .section), ("$", .structure), ("42", .number), ("% if", .comment)]),
        .init(path: "a.bib", code: "@article{sample, title=\"if\", year=2026}", checks: [("@article", .keyword), ("title", .key), ("\"if\"", .string), ("2026", .number)]),
        .init(path: "a.txt", code: "let x = 42 // comment", checks: [("let x = 42 // comment", .plain)]),
    ]

    @Test("§3 の代表例と構造分類、原文の UTF-8 一致", arguments: examples)
    func representativeExamples(_ example: Example) {
        let tokens = ChatCodeTokenizer.tokens(for: example.code, path: example.path)
        #expect(Array(tokens.map(\.text).joined().utf8) == Array(example.code.utf8))
        for (text, kind) in example.checks {
            expectClassification(text, kind: kind, code: example.code, tokens: tokens)
        }
    }

    private func expectClassification(_ text: String, kind: ChatCodeTokenKind, code: String, tokens: [ChatCodeToken], sourceLocation: SourceLocation = #_sourceLocation) {
        let range = (code as NSString).range(of: text)
        #expect(range.location != NSNotFound, sourceLocation: sourceLocation)
        guard range.location != NSNotFound else { return }
        var offset = 0
        for token in tokens {
            let tokenRange = NSRange(location: offset, length: token.text.utf16.count)
            if NSIntersectionRange(range, tokenRange).length > 0 {
                #expect(token.kind == kind, "対象: \(text)、字句: \(token.text)", sourceLocation: sourceLocation)
            }
            offset += tokenRange.length
        }
    }

    @Test("§2 の名前・拡張子・shebang の優先順位と大小文字")
    func detectionPrecedence() {
        let cases: [(String, String, ChatCodeLanguage)] = [
            ("a/.env.swift", "#!/bin/bash", .env), ("Dockerfile", "#!/bin/python3", .dockerfile),
            ("Containerfile", "", .dockerfile), ("Makefile", "", .makefile), ("makefile", "", .makefile), ("GNUmakefile", "", .makefile),
            (".gitignore", "", .ignore), (".dockerignore", "", .ignore), (".ignore", "", .ignore), (".gitattributes", "", .attributes),
            (".editorconfig", "", .ini), ("CMakeLists.txt", "", .cmake), (".env", "", .env), (".env.local", "", .env),
            ("dockerfile", "", .plain), ("MAKEFILE", "", .plain), (".ENV", "", .plain), ("Dockerfile.dev", "", .dockerfile),
            ("Containerfile.dev", "", .dockerfile), ("a.SWIFT", "#!/bin/bash", .swift), ("a.h", "", .c), ("a.m", "", .objectiveC),
            ("a.pl", "", .perl), ("a.ts", "", .typescript), ("a.unknown", "let x = 42", .plain), ("", "", .plain),
            ("a.txt", "#!/bin/bash", .plain), ("a.unknown", "#!/usr/bin/env -S python3.12 -u\n", .python),
            ("script", "#!/usr/local/bin/python3.13\n", .python), ("script", "#!/usr/bin/env nodejs\n", .javascript),
            ("script", "#!/usr/bin/env pwsh\n", .powershell), ("script", "#!/bin/unknown\n", .plain),
            ("script", "text\n#!/bin/bash", .plain), ("script", "#!/bin/pythonista", .plain),
            ("a.javascript", "const x = 42", .plain), ("a.python", "def f(): pass", .plain),
            ("a.shell", "echo hello", .plain), ("a.terraform", "resource {}", .plain),
        ]
        for (path, code, language) in cases {
            #expect(ChatCodeTokenizer.language(for: path, code: code) == language, "判定対象: \(path)")
        }
    }

    @Test("フェンス別名は同じ規則を使い、未知フェンスの従来互換を保つ")
    func fenceAliasesAndFallback() {
        let aliases = [("python", "py"), ("typescript", "ts"), ("javascript", "js"), ("objective-c", "objc"), ("c++", "cpp"), ("yaml", "yml"), ("powershell", "pwsh"), ("graphql", "gql"), ("terraform", "hcl")]
        for (a, b) in aliases {
            #expect(ChatCodeTokenizer.tokens(for: "if x = 42 # comment", language: a) == ChatCodeTokenizer.tokens(for: "if x = 42 # comment", language: b))
        }
        #expect(ChatCodeTokenizer.tokens(for: "let x = 42", language: "unknown") == ChatCodeTokenizer.swift("let x = 42"))
        #expect(ChatCodeTokenizer.tokens(for: "let x = 42", language: nil) == ChatCodeTokenizer.swift("let x = 42"))
    }

    @Test("未知フェンスの数値互換を保ち、ファイルと明示した Swift は進数を分類する")
    func legacyAndFileNumberClassification() {
        let legacy = [ChatCodeToken(text: "0", kind: .number), ChatCodeToken(text: "xFF", kind: .plain)]
        let modern = [ChatCodeToken(text: "0xFF", kind: .number)]
        #expect(ChatCodeTokenizer.swift("0xFF") == legacy)
        #expect(ChatCodeTokenizer.tokens(for: "0xFF", language: nil) == legacy)
        #expect(ChatCodeTokenizer.tokens(for: "0xFF", language: "unknown") == legacy)
        #expect(ChatCodeTokenizer.tokens(for: "0xFF", path: "a.swift") == modern)
        #expect(ChatCodeTokenizer.tokens(for: "0xFF", language: "swift") == modern)
    }

    @Test("§3 に列挙した拡張子と §2 の実行名を判定する")
    func extensionAndShebangCoverage() {
        let groups: [(ChatCodeLanguage, String)] = [
            (.swift, "swift"), (.objectiveC, "m mm"), (.c, "c h cc cpp cxx hpp hh hxx"),
            (.java, "java"), (.kotlin, "kt kts"), (.csharp, "cs"), (.go, "go"), (.rust, "rs"),
            (.python, "py pyw"), (.ruby, "rb"), (.php, "php phtml"), (.perl, "pl pm"), (.lua, "lua"),
            (.r, "r"), (.dart, "dart"), (.scala, "scala sc"), (.elixir, "ex exs"), (.haskell, "hs"), (.literateHaskell, "lhs"),
            (.javascript, "js mjs cjs"), (.typescript, "ts mts cts"), (.jsx, "jsx"), (.tsx, "tsx"),
            (.shell, "sh bash zsh"), (.fish, "fish"), (.powershell, "ps1 psm1 psd1"), (.sql, "sql"), (.graphql, "graphql gql"),
            (.json, "json"), (.jsonc, "jsonc"), (.json5, "json5"), (.yaml, "yaml yml"), (.toml, "toml"),
            (.ini, "ini cfg conf"), (.env, "env"), (.properties, "properties"), (.xml, "plist xml svg xsd xsl xslt"),
            (.dockerfile, "dockerfile containerfile"), (.makefile, "mk make"), (.cmake, "cmake"),
            (.html, "html htm"), (.markdown, "md markdown"), (.mdx, "mdx"), (.css, "css"), (.scss, "scss"), (.less, "less"),
            (.vue, "vue"), (.svelte, "svelte"), (.csv, "csv"), (.tsv, "tsv"), (.log, "log"), (.diff, "diff patch"),
            (.protobuf, "proto"), (.hcl, "tf tfvars hcl"), (.nix, "nix"), (.latex, "tex sty cls"), (.bibtex, "bib"), (.plain, "txt text"),
        ]
        for (language, extensions) in groups {
            for ext in extensions.split(separator: " ") {
                #expect(ChatCodeTokenizer.language(for: "a.\(ext)", code: "#!/bin/bash") == language)
            }
        }
        let executables: [(String, ChatCodeLanguage)] = [
            ("sh", .shell), ("bash", .shell), ("zsh", .shell), ("fish", .fish), ("python", .python), ("python3", .python),
            ("python3.12", .python), ("ruby", .ruby), ("perl", .perl), ("php", .php), ("lua", .lua),
            ("node", .javascript), ("nodejs", .javascript), ("pwsh", .powershell), ("powershell", .powershell),
        ]
        for (executable, language) in executables {
            #expect(ChatCodeTokenizer.language(for: "script", code: "#!/usr/local/bin/\(executable)\n") == language)
            #expect(ChatCodeTokenizer.language(for: "script", code: "#!/usr/bin/env \(executable)\n") == language)
            #expect(ChatCodeTokenizer.language(for: "script", code: "#!/usr/bin/env -S \(executable) -u\n") == language)
        }
    }

    @Test("文字列・コメント内と識別子の一部をキーワードにしない")
    func suppressesInnerKeywords() {
        let cases = [("a.swift", "let letter = \"if let\" /* return let */"), ("a.py", "def define():\n x = 'if def' # return def"), ("a.js", "const constant = `if const`; // return const")]
        for (path, code) in cases {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            let keywords = tokens.filter { $0.kind == .keyword }.map(\.text)
            #expect(keywords.count == 1)
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
        }
        let json = ChatCodeTokenizer.tokens(for: "// true\n/* null */", path: "a.json")
        #expect(!json.contains { $0.kind == .comment })
        let rust = ChatCodeTokenizer.tokens(for: "fn f<'a>(x: &'a str) {}", path: "a.rs")
        #expect(!rust.contains { $0.kind == .string })
    }

    @Test("未閉鎖・Unicode・CRLF・CR を原文のまま返す")
    func incompleteAndUnicode() {
        let cases = [("a.swift", "/* let 👩🏽‍💻 e\u{301}\r\nreturn\r"), ("a.py", "'''def 日本語\r\nx\r"), ("a.rs", "r##\"fn 👩‍💻\r\nx"), ("a.lua", "--[=[local\r\nx"), ("a.csv", "\"a\r\n\"\"b\rc"), ("a.html", "<!-- const\r\n日本語"), ("a.md", "```swift\r\nlet x = \"👩‍💻\"\r\n")]
        for (path, code) in cases {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
            #expect(!tokens.contains { $0.text.isEmpty })
        }
        for example in Self.examples {
            #expect(ChatCodeTokenizer.tokens(for: "", path: example.path).isEmpty)
        }
        let code = "// comment\rlet x = 42\r\nlet y = 43"
        #expect(ChatCodeTokenizer.tokens(for: code, path: "a.swift").filter { $0.kind == .keyword && $0.text == "let" }.count == 2)
    }

    @Test("未閉鎖の複数行コメント・文字列は末尾まで分類を維持する")
    func incompleteClassification() {
        let cases: [(String, String, ChatCodeTokenKind)] = [
            ("a.swift", "/* let\r\nreturn", .comment), ("a.swift", "#\"if\r\nlet", .string),
            ("a.py", "'''def\nreturn", .string), ("a.lua", "--[=[local\nthen", .comment),
            ("a.lua", "[=[local\nthen", .string), ("a.html", "<!-- const\nif", .comment),
            ("a.rs", "r##\"fn\nlet", .string), ("a.cs", "@\"class\nreturn", .string),
        ]
        for (path, code, kind) in cases {
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            #expect(tokens == [ChatCodeToken(text: code, kind: kind)])
        }
    }

    @Test("複数行のフェンス・文字列は行表示に分けても分類と原文を保つ")
    func lineRenderingKeepsEmbeddedState() {
        let lines = ["```python", "value = '''def", "return 👩‍💻 e\u{301}", "'''", "```", "text"]
        let tokens = ChatCodeTokenizer.lineTokens(for: lines, path: "a.md")
        #expect(tokens.map { $0.map(\.text).joined() } == lines)
        #expect(tokens[2] == [ChatCodeToken(text: lines[2], kind: .string)])
        #expect(tokens[5] == [ChatCodeToken(text: "text", kind: .plain)])
    }

    @Test("長行は UTF-16 で 10,000 を境界とし、CRLF と CR で区切る")
    func longLineBoundary() {
        #expect(ChatCodeTokenizer.shouldHighlight(String(repeating: "a", count: 10_000)))
        #expect(!ChatCodeTokenizer.shouldHighlight(String(repeating: "a", count: 10_001)))
        #expect(ChatCodeTokenizer.shouldHighlight(String(repeating: "😀", count: 5_000)))
        #expect(!ChatCodeTokenizer.shouldHighlight(String(repeating: "😀", count: 5_001)))
        #expect(ChatCodeTokenizer.shouldHighlight(String(repeating: "a", count: 10_000) + "\r\n" + String(repeating: "b", count: 10_000)))
        #expect(ChatCodeTokenizer.shouldHighlight(String(repeating: "a", count: 10_000) + "\r" + String(repeating: "b", count: 10_000)))
    }

    @Test("埋め込み領域は開始宣言で切り替わり、未知宣言を推測しない")
    func embeddedRegionSwitches() {
        let code = "<script type=\"application/json\">{\"value\":42}</script><script type=\"unknown\">const value = 42</script><style>.box { color: red; }</style>"
        let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.html")
        expectClassification("\"value\"", kind: .key, code: code, tokens: tokens)
        expectClassification("const value = 42", kind: .plain, code: code, tokens: tokens)
        expectClassification("color", kind: .property, code: code, tokens: tokens)
        let markdown = "---\nname: true\n---\n```unknown\nlet value = 42\n```\n```\nconst x = 42\n```"
        let mdTokens = ChatCodeTokenizer.tokens(for: markdown, path: "a.md")
        expectClassification("name", kind: .key, code: markdown, tokens: mdTokens)
        expectClassification("let value = 42", kind: .plain, code: markdown, tokens: mdTokens)
        expectClassification("const x = 42", kind: .plain, code: markdown, tokens: mdTokens)
        #expect(Array(mdTokens.map(\.text).joined().utf8) == Array(markdown.utf8))
    }

    @Test("文字列の終了境界、宣言・フェンス・ログの反例")
    func lexicalBoundaryCounterexamples() {
        let cases: [Example] = [
            .init(path: "a.rs", code: "let a = '\\n'; let b = '\\u{1F600}';", checks: [("'\\n'", .string), ("'\\u{1F600}'", .string)]),
            .init(path: "a.rs", code: "' ' '-' '(' '😀'", checks: [("' '", .string), ("'-'", .string), ("'('", .string), ("'😀'", .string)]),
            .init(path: "a.rs", code: "&'a str &'static str", checks: [("'a", .plain), ("'static", .plain)]),
            .init(path: "a.swift", code: "let s = #\"escaped \\#\" quote\"#", checks: [("#\"escaped \\#\" quote\"#", .string)]),
            .init(path: "a.swift", code: "let s = #\"escaped \\#\"# quote\"#; let n=1", checks: [("#\"escaped \\#\"# quote\"#", .string), ("1", .number)]),
            .init(path: "a.php", code: "<?php $s = \"?>\"; echo 1; ?> <div>text</div>", checks: [("\"?>\"", .string), ("echo", .keyword), ("1", .number), ("text", .plain)]),
            .init(path: "a.html", code: "<script type='not-json'>const x = 42</script><script lang='not-typescript'>interface Shape {}</script>", checks: [("const x = 42", .plain), ("interface Shape {}", .plain)]),
            .init(path: "a.html", code: "<script lang = 'ts'>interface Shape {}</script><scripture>const x = 42</scripture>", checks: [("interface", .keyword), ("const x = 42", .plain)]),
            .init(path: "a.html", code: "<div width=42 title=hello>text</div>", checks: [("42", .string), ("hello", .string)]),
            .init(path: "a.md", code: "```python\n```still-code\nreturn 42\n```\ntext", checks: [("return", .keyword), ("42", .number), ("text", .plain)]),
            .init(path: "a.log", code: "INFO // if return\nERRORLESS text", checks: [("// if return", .plain), ("ERRORLESS", .plain)]),
            .init(path: "a.tex", code: "\\[42\\] \\(43\\)", checks: [("\\[", .structure), ("\\]", .structure), ("\\(", .structure), ("\\)", .structure)]),
            .init(path: "a.jsx", code: "const x = <Box value={{ nested: { text: \"}\" }, /* } */ valid: true }} />;", checks: [("Box", .tag), ("value", .attribute), ("\"}\"", .string), ("/* } */", .comment), ("true", .keyword)]),
            .init(path: "a.c", code: "#define MESSAGE \"hello\" // if", checks: [("#define", .keyword), ("\"hello\"", .string), ("// if", .comment)]),
            .init(path: "a.html", code: #"<div path="C:\">text</div>"#, checks: [(#""C:\""#, .string), ("text", .plain)]),
            .init(path: "a.lua", code: "--[not a long comment] local x=1", checks: [("--[not a long comment] local x=1", .comment)]),
            .init(path: "a.toml", code: "[section] # note\n\"title\" = \"hello\"", checks: [("[section]", .section), ("# note", .comment), ("\"title\"", .key)]),
            .init(path: "a.ini", code: "[section] # note", checks: [("[section]", .section), ("# note", .comment)]),
            .init(path: "a.yaml", code: "\"title\": true", checks: [("\"title\"", .key), ("true", .keyword)]),
            .init(path: "a.pl", code: "my %hash = ();", checks: [("my", .keyword), ("%hash", .variable)]),
            .init(path: "a.java", code: "@pkg.Annotation public class Foo {}", checks: [("@pkg.Annotation", .keyword)]),
            .init(path: "a.kt", code: "@pkg.Annotation class Foo", checks: [("@pkg.Annotation", .keyword)]),
            .init(path: "Dockerfile", code: "from alpine\ncopy . /app", checks: [("from", .keyword), ("copy", .keyword)]),
            .init(path: "a.yaml", code: "# ignored: |\n  next: true", checks: [("# ignored: |", .comment), ("next", .key), ("true", .keyword)]),
        ]
        for example in cases {
            let tokens = ChatCodeTokenizer.tokens(for: example.code, path: example.path)
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(example.code.utf8))
            for (text, kind) in example.checks {
                expectClassification(text, kind: kind, code: example.code, tokens: tokens)
            }
        }
    }

    @Test("Markdown の本文をまとめても Unicode と改行後の構造を保つ")
    func markdownPlainRunsPreserveStructure() {
        for newline in ["\n", "\r\n", "\r"] {
            let prose = "日本語 👩🏽‍💻 e\u{301} の本文"
            let code = prose + newline + "# Heading" + newline + "**emphasis** [link](https://example.test) `let x = 1`"
            let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.md")
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
            let checks: [(String, ChatCodeTokenKind)] = [(prose, .plain), ("#", .structure), ("*", .structure), ("[", .structure), ("https://example.test", .link), ("`let x = 1`", .string)]
            for (text, kind) in checks {
                expectClassification(text, kind: kind, code: code, tokens: tokens)
            }
        }
    }

    @Test("Markdown フェンスの終端は ASCII と Unicode の空白および長い区切りを保つ")
    func markdownFenceClosingWhitespace() {
        let cases = [
            ("```python", " \t``` \t"), ("```python", "`````"), ("~~~python", "\t~~~~ \t"),
            ("```python", "\u{00A0}```\u{00A0}"), ("```python", "\u{2003}```\u{2003}"),
            ("```python", " \t```\u{2003}"), ("```python", "\u{00A0}``` \t"),
        ]
        for (opening, closing) in cases {
            let code = opening + "\r\ndef value(): pass\r\n" + closing + "\r\nreturn 外側 👩‍💻"
            let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.md")
            #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
            expectClassification("def", kind: .keyword, code: code, tokens: tokens)
            expectClassification(closing, kind: .structure, code: code, tokens: tokens)
            expectClassification("return 外側 👩‍💻", kind: .plain, code: code, tokens: tokens)
        }
        let code = "```python\n```still-code\nreturn 42\n```\nclass 外側"
        let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.md")
        #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
        expectClassification("return", kind: .keyword, code: code, tokens: tokens)
        expectClassification("class 外側", kind: .plain, code: code, tokens: tokens)
    }

    @Test("Unicode 空白から始まる Markdown 構造は走査が進み原文を保つ")
    func markdownUnicodeIndentation() {
        let structures = [("# Heading", "#"), ("> Quote", ">"), ("- item", "-"), ("+ item", "+"), ("* item", "*"), ("---", "---"), ("***", "***")]
        for indent in ["\u{00A0}", "\u{2003}"] {
            for (line, marker) in structures {
                let code = indent + line + "\n本文"
                let tokens = ChatCodeTokenizer.tokens(for: code, path: "a.md")
                #expect(Array(tokens.map(\.text).joined().utf8) == Array(code.utf8))
                expectClassification(marker, kind: .structure, code: code, tokens: tokens)
                expectClassification("本文", kind: .plain, code: code, tokens: tokens)
            }
        }
    }
}
