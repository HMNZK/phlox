import Foundation

/// ファイル判定と字句規則で共有する種類。色や表示属性は保持しない。
public enum ChatCodeLanguage: CaseIterable, Hashable, Sendable {
    case plain, swift, objectiveC, c, java, kotlin, csharp, go, rust, python, ruby, php
    case perl, lua, r, dart, scala, elixir, haskell, literateHaskell
    case javascript, typescript, jsx, tsx, shell, fish, powershell, sql, graphql
    case json, jsonc, json5, yaml, toml, ini, env, properties, xml
    case dockerfile, makefile, cmake, ignore, attributes, html, markdown, mdx
    case css, scss, less, vue, svelte, csv, tsv, log, diff, protobuf, hcl, nix, latex, bibtex

    static let aliases: [String: ChatCodeLanguage] = {
        let groups: [(ChatCodeLanguage, String)] = [
            (.plain, "txt text plain plaintext"), (.swift, "swift"),
            (.objectiveC, "m mm objc objective-c objective-c++"), (.c, "c h cc cpp cxx hpp hh hxx c++"),
            (.java, "java"), (.kotlin, "kotlin kt kts"), (.csharp, "cs csharp c#"),
            (.go, "go golang"), (.rust, "rust rs"), (.python, "python py pyw"), (.ruby, "ruby rb"),
            (.php, "php phtml"), (.perl, "perl pl pm"), (.lua, "lua"), (.r, "r"), (.dart, "dart"),
            (.scala, "scala sc"), (.elixir, "elixir ex exs"), (.haskell, "haskell hs"), (.literateHaskell, "lhs"),
            (.javascript, "javascript js mjs cjs node nodejs"), (.typescript, "typescript ts mts cts"),
            (.jsx, "jsx"), (.tsx, "tsx"), (.shell, "sh bash zsh shell console shellscript terminal"),
            (.fish, "fish"), (.powershell, "powershell pwsh ps1 psm1 psd1"),
            (.sql, "sql sqlite postgresql mysql"), (.graphql, "graphql gql"),
            (.json, "json"), (.jsonc, "jsonc"), (.json5, "json5"), (.yaml, "yaml yml"), (.toml, "toml"),
            (.ini, "ini cfg conf editorconfig"), (.env, "env"), (.properties, "properties"),
            (.xml, "xml plist svg xsd xsl xslt"), (.dockerfile, "dockerfile containerfile"),
            (.makefile, "makefile make mk"), (.cmake, "cmake"), (.ignore, "gitignore dockerignore ignore"),
            (.attributes, "gitattributes"), (.html, "html htm"), (.markdown, "md markdown"), (.mdx, "mdx"),
            (.css, "css"), (.scss, "scss"), (.less, "less"), (.vue, "vue"), (.svelte, "svelte"),
            (.csv, "csv"), (.tsv, "tsv"), (.log, "log"), (.diff, "diff patch"),
            (.protobuf, "proto protobuf"), (.hcl, "tf tfvars hcl terraform"), (.nix, "nix"),
            (.latex, "tex sty cls latex"), (.bibtex, "bib bibtex"),
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { kind, words in
            words.split(separator: " ").map { (String($0), kind) }
        })
    }()

    public static func named(_ name: String) -> Self? { aliases[name.lowercased()] }

    // フェンス専用の呼び名を除き、拡張子も別名表から導く。
    static let extensions = Set(aliases.keys).subtracting(
        "plain plaintext objc objective-c objective-c++ c++ kotlin csharp c# golang rust python ruby perl elixir haskell javascript node nodejs typescript shell console shellscript terminal powershell pwsh sqlite postgresql mysql editorconfig makefile gitignore dockerignore ignore gitattributes protobuf terraform latex bibtex"
            .split(separator: " ").map(String.init)
    )

    var refinesIdentifiers: Bool {
        switch self {
        case .swift, .objectiveC, .c, .java, .kotlin, .csharp, .go, .rust, .python, .ruby, .php,
             .perl, .lua, .r, .dart, .scala, .elixir, .haskell, .javascript, .typescript, .jsx, .tsx:
            true
        default: false
        }
    }
}

extension ChatCodeTokenizer {
    /// 名前 → 拡張子 → shebang の順。本文からの言語推測は行わない。
    public static func language(for path: String, code: String) -> ChatCodeLanguage {
        let name = (path as NSString).lastPathComponent
        if name == ".env" || name.hasPrefix(".env.") { return .env }
        let names: [String: ChatCodeLanguage] = [
            "Dockerfile": .dockerfile, "Containerfile": .dockerfile,
            "Makefile": .makefile, "makefile": .makefile, "GNUmakefile": .makefile,
            ".gitignore": .ignore, ".dockerignore": .ignore, ".ignore": .ignore,
            ".gitattributes": .attributes, ".editorconfig": .ini, "CMakeLists.txt": .cmake,
        ]
        if let kind = names[name] { return kind }
        let ext = (name as NSString).pathExtension.lowercased()
        let lower = name.lowercased()
        if lower.hasPrefix("dockerfile.") || lower.hasPrefix("containerfile.") { return .dockerfile }
        if ChatCodeLanguage.extensions.contains(ext), let kind = ChatCodeLanguage.named(ext) { return kind }
        let first = code.prefix { !$0.isNewline }
        guard first.hasPrefix("#!") else { return .plain }
        var words = first.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return .plain }
        var executable = (words.removeFirst() as NSString).lastPathComponent
        if executable == "env" {
            while let word = words.first, word.hasPrefix("-") || word.contains("=") { words.removeFirst() }
            guard let word = words.first else { return .plain }
            executable = (word as NSString).lastPathComponent
        }
        if executable.hasPrefix("python"), executable.dropFirst(6).allSatisfy({ $0.isNumber || $0 == "." }) {
            return .python
        }
        let executables: Set<String> = ["sh", "bash", "zsh", "fish", "ruby", "perl", "php", "lua", "node", "nodejs", "pwsh", "powershell"]
        return executables.contains(executable) ? ChatCodeLanguage.named(executable) ?? .plain : .plain
    }

    public static let maximumLineUTF16Length = 10_000

    public static func shouldHighlight(_ code: String) -> Bool {
        guard code.utf8.count <= 1_000_000 else { return false }
        var length = 0
        // UTF-8 の先頭バイトだけを数え、4 バイトの scalar は UTF-16 の 2 単位として扱う。
        for byte in code.utf8 {
            if byte == 10 || byte == 13 { length = 0 }
            else if byte < 128 || byte >= 192 && byte < 240 { length += 1 }
            else if byte >= 240 { length += 2 }
            if length > maximumLineUTF16Length { return false }
        }
        return true
    }
}
