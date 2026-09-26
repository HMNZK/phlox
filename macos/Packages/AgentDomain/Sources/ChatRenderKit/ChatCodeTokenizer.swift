import Foundation

public enum ChatCodeTokenKind: Equatable, Sendable {
    case keyword
    case string
    case number
    case comment
    case plain
    case command
    case subcommand
    case variable
    case `operator`
    case option
    /// 大文字で始まる名前（型）。
    case type
    /// `.expired` のような `.` で始まる名前。
    case member
    /// 直後が `(` の名前（関数の呼び出し）。
    case call
}

public struct ChatCodeToken: Equatable, Sendable {
    public var text: String
    public let kind: ChatCodeTokenKind

    public init(text: String, kind: ChatCodeTokenKind) {
        self.text = text
        self.kind = kind
    }
}

public enum ChatCodeTokenizer {
    private static let keywords: Set<String> = [
        "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "do", "else", "enum", "false", "for", "func", "guard", "if", "import", "in",
        "init", "let", "nil", "private", "public", "return", "self", "static", "struct", "switch",
        "throw", "throws", "true", "try", "var", "while",
    ]

    /// 拡張子で言語を決める。知らない拡張子は plain にフォールバックする。
    public static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "swift" || Language(name: ext) != nil else {
            return code.isEmpty ? [] : [ChatCodeToken(text: code, kind: .plain)]
        }
        // 差分・変更タブは従来の分類のまま（型・メンバー・呼び出しは分けない。2026-09-26 ユーザー判断）。
        return baseTokens(for: code, language: ext)
    }

    /// 差分のように行ごとに描くときの窓口。行をつないでまとめて分けてから行へ戻すので、
    /// 複数行にまたがるブロックコメントや文字列の途中の行も正しく分類される。
    /// 戻すときは各行の長さ（Unicode scalar 数）で区切る。改行らしい文字（行内の CR・U+2028 や、
    /// CR で終わる行と区切りの LF が 1 文字にまとまる CRLF）で区切ると、行との対応がずれるため。
    public static func lineTokens(for lines: [String], path: String) -> [[ChatCodeToken]] {
        var result: [[ChatCodeToken]] = Array(repeating: [], count: lines.count)
        guard !lines.isEmpty else { return result }
        var line = 0
        var remaining = lines[0].unicodeScalars.count
        for token in tokens(for: lines.joined(separator: "\n"), path: path) {
            var piece = String.UnicodeScalarView()
            for scalar in token.text.unicodeScalars {
                guard remaining == 0 else {
                    piece.append(scalar)
                    remaining -= 1
                    continue
                }
                // 行の終わりに来た。この scalar は行をつないだ区切りの LF。
                if !piece.isEmpty { result[line].append(ChatCodeToken(text: String(piece), kind: token.kind)) }
                piece = String.UnicodeScalarView()
                line += 1
                remaining = lines[line].unicodeScalars.count
            }
            if !piece.isEmpty { result[line].append(ChatCodeToken(text: String(piece), kind: token.kind)) }
        }
        return result
    }

    /// コードブロックの窓口。言語名が swift のときと表にある言語は、残りの名前を型・メンバー・呼び出しに
    /// 分ける（Chat Screen.dc.html の見本）。言語名が無い・知らないときは従来どおり（`swift(_:)` のまま）。
    public static func tokens(for code: String, language: String?) -> [ChatCodeToken] {
        let name = language?.lowercased() ?? ""
        let tokens = baseTokens(for: code, language: name)
        return refinesIdentifiers(language: name) ? refiningIdentifiers(tokens) : tokens
    }

    /// 見本どおりの細かい色分け（型・メンバー・呼び出し・太字のキーワード）をする言語か。
    public static func refinesIdentifiers(language: String?) -> Bool {
        let name = language?.lowercased() ?? ""
        switch Language(name: name) {
        case .rules(let rules): return rules.identifiers
        case .shell: return false
        case nil: return name == "swift"
        }
    }

    /// 言語ごとの基本の分類（キーワード・文字列・数値・コメント）。
    static func baseTokens(for code: String, language name: String) -> [ChatCodeToken] {
        switch Language(name: name) {
        case .shell: shell(code)
        case .rules(let rules): generic(code, rules: rules)
        case nil: swift(code)
        }
    }

    /// 本文色の部分から、型（大文字で始まる名前）・`.` で始まる名前・呼び出し（直後が `(`）を切り出す。
    static func refiningIdentifiers(_ tokens: [ChatCodeToken]) -> [ChatCodeToken] {
        var output: [ChatCodeToken] = []
        func append(_ text: String, _ kind: ChatCodeTokenKind) {
            guard !text.isEmpty else { return }
            if output.last?.kind == kind {
                output[output.count - 1].text += text
            } else {
                output.append(ChatCodeToken(text: text, kind: kind))
            }
        }
        func isNameCharacter(_ character: Character) -> Bool {
            character.isASCII && (character.isLetter || character.isNumber || character == "_")
        }
        for token in tokens {
            guard token.kind == .plain else {
                append(token.text, token.kind)
                continue
            }
            let text = token.text
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                let next = text.index(after: index)
                if character == ".", next < text.endIndex, text[next].isASCII, text[next].isLowercase {
                    let end = text[next...].firstIndex { !isNameCharacter($0) } ?? text.endIndex
                    append(String(text[index..<end]), .member)
                    index = end
                    continue
                }
                let startsName = character.isASCII && (character.isLetter || character == "_")
                if startsName, index == text.startIndex || !isNameCharacter(text[text.index(before: index)]) {
                    let end = text[index...].firstIndex { !isNameCharacter($0) } ?? text.endIndex
                    let kind: ChatCodeTokenKind = character.isUppercase ? .type
                        : end < text.endIndex && text[end] == "(" ? .call : .plain
                    append(String(text[index..<end]), kind)
                    index = end
                    continue
                }
                append(String(character), .plain)
                index = next
            }
        }
        return output
    }

    /// 言語ごとの分類規則。色は 4 種類（キーワード・文字列・数値・コメント）のまま。
    struct Rules {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComment = false
        var quotes: Set<Character> = ["\"", "'"]
        /// SQL のように大文字・小文字を区別しない言語。
        var caseInsensitive = false
        /// Python の `"""` / `'''` のように、引用符 3 つで囲む複数行の文字列。
        var tripleQuotes = false
        /// 型・メンバー・呼び出しを分けるか（JSON・YAML・SQL のような名前の区別が無い言語では分けない）。
        var identifiers = true
    }

    enum Language {
        case shell
        case rules(Rules)

        // ponytail: 主要な言語だけの小さな表。足りない言語は Swift の規則で色分けされる。
        init?(name: String) {
            switch name {
            case "sh", "bash", "zsh", "shell", "console", "fish", "shellscript", "terminal":
                self = .shell
            case "python", "py":
                self = .rules(Rules(keywords: [
                    "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
                    "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is",
                    "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "self", "True", "try",
                    "while", "with", "yield",
                ], lineComments: ["#"], tripleQuotes: true))
            case "javascript", "js", "jsx", "mjs", "cjs", "typescript", "ts", "tsx":
                self = .rules(Rules(keywords: [
                    "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete",
                    "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if",
                    "import", "in", "instanceof", "interface", "let", "new", "null", "of", "return", "static",
                    "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var",
                    "void", "while", "yield",
                ], lineComments: ["//"], blockComment: true, quotes: ["\"", "'", "`"]))
            case "go", "golang":
                self = .rules(Rules(keywords: [
                    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
                    "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package",
                    "range", "return", "select", "struct", "switch", "true", "type", "var",
                ], lineComments: ["//"], blockComment: true, quotes: ["\"", "'", "`"]))
            case "rust", "rs":
                self = .rules(Rules(keywords: [
                    "as", "async", "await", "break", "const", "continue", "crate", "else", "enum", "false", "fn",
                    "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                    "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
                    "use", "where", "while",
                ], lineComments: ["//"], blockComment: true, quotes: ["\""]))
            case "ruby", "rb":
                self = .rules(Rules(keywords: [
                    "begin", "class", "def", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in",
                    "module", "next", "nil", "not", "or", "and", "rescue", "return", "require", "self", "super",
                    "then", "true", "unless", "until", "when", "while", "yield",
                ], lineComments: ["#"]))
            case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "m", "java", "kotlin", "kt",
                 "kts", "cs", "csharp", "c#", "dart", "scala":
                self = .rules(Rules(keywords: [
                    "abstract", "auto", "bool", "break", "case", "catch", "char", "class", "const", "continue",
                    "default", "do", "double", "else", "enum", "extends", "false", "final", "float", "for", "fun",
                    "if", "implements", "import", "int", "interface", "long", "namespace", "new", "null",
                    "nullptr", "object", "override", "package", "private", "protected", "public", "return",
                    "short", "static", "struct", "super", "switch", "this", "throw", "true", "try", "typedef",
                    "val", "var", "void", "when", "while",
                ], lineComments: ["//"], blockComment: true))
            case "json", "jsonc", "json5":
                self = .rules(Rules(keywords: ["true", "false", "null"], lineComments: ["//"], quotes: ["\""], identifiers: false))
            // 設定・ビルド記述は大文字の名前が型ではない（FROM・CC など）ので細かく分けない。
            case "yaml", "yml", "toml", "ini", "dockerfile", "makefile", "make", "cmake":
                self = .rules(Rules(keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"], identifiers: false))
            case "r", "perl", "pl":
                self = .rules(Rules(keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"]))
            case "sql", "sqlite", "postgresql", "mysql":
                self = .rules(Rules(keywords: [
                    "select", "from", "where", "insert", "into", "update", "delete", "create", "table", "drop",
                    "alter", "and", "or", "not", "null", "join", "left", "right", "inner", "outer", "on", "group",
                    "by", "order", "limit", "values", "set", "as", "distinct", "having", "union", "index",
                    "primary", "key", "references", "default", "is", "in", "like", "case", "when", "then", "else",
                    "end", "true", "false",
                ], lineComments: ["--"], blockComment: true, quotes: ["'", "\""], caseInsensitive: true, identifiers: false))
            default:
                return nil
            }
        }
    }

    static func generic(_ code: String, rules: Rules) -> [ChatCodeToken] {
        var tokens: [ChatCodeToken] = []
        var index = code.startIndex

        func append(_ text: String, _ kind: ChatCodeTokenKind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(ChatCodeToken(text: text, kind: kind))
            }
        }

        while index < code.endIndex {
            let rest = code[index...]
            if rules.blockComment, rest.hasPrefix("/*") {
                let end = rest.range(of: "*/").map(\.upperBound) ?? code.endIndex
                append(String(code[index..<end]), .comment)
                index = end
                continue
            }
            if rules.lineComments.contains(where: { rest.hasPrefix($0) }) {
                // CRLF は 1 つの Character（"\r\n"）なので、"\n" との一致ではなく改行かどうかで探す。
                let end = rest.firstIndex(where: \.isNewline) ?? code.endIndex
                append(String(code[index..<end]), .comment)
                index = end
                continue
            }
            if rules.tripleQuotes, let quote = rest.first, rules.quotes.contains(quote) {
                let fence = String(repeating: quote, count: 3)
                if rest.hasPrefix(fence) {
                    // 閉じは、バックスラッシュでエスケープされていない最初の三重引用符。
                    var end = code.index(index, offsetBy: 3)
                    while end < code.endIndex, !code[end...].hasPrefix(fence) {
                        let next = code.index(after: end)
                        end = code[end] == "\\" && next < code.endIndex ? code.index(after: next) : next
                    }
                    end = end < code.endIndex ? code.index(end, offsetBy: 3) : code.endIndex
                    append(String(code[index..<end]), .string)
                    index = end
                    continue
                }
            }
            let character = code[index]
            if rules.quotes.contains(character) {
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let current = code[end]
                    end = code.index(after: end)
                    if current == character && !escaped { break }
                    escaped = current == "\\" && !escaped
                }
                append(String(code[index..<end]), .string)
                index = end
                continue
            }
            if character.isNumber {
                let end = rest.firstIndex { !$0.isNumber && $0 != "." } ?? code.endIndex
                append(String(code[index..<end]), .number)
                index = end
                continue
            }
            if character.isLetter || character == "_" {
                let end = rest.firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? code.endIndex
                let word = String(code[index..<end])
                let isKeyword = rules.keywords.contains(rules.caseInsensitive ? word.lowercased() : word)
                append(word, isKeyword ? .keyword : .plain)
                index = end
                continue
            }
            append(String(character), .plain)
            index = code.index(after: index)
        }
        return tokens
    }

    public static func swift(_ code: String) -> [ChatCodeToken] {
        var tokens: [ChatCodeToken] = []
        var index = code.startIndex

        func append(_ text: String, _ kind: ChatCodeTokenKind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(ChatCodeToken(text: text, kind: kind))
            }
        }

        while index < code.endIndex {
            if code[index] == "/", code.index(after: index) < code.endIndex, code[code.index(after: index)] == "/" {
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(String(code[index..<end]), .comment)
                index = end
                continue
            }
            if code[index] == "\"" {
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let character = code[end]
                    if character == "\"" && !escaped {
                        end = code.index(after: end)
                        break
                    }
                    escaped = character == "\\" && !escaped
                    end = code.index(after: end)
                }
                append(String(code[index..<end]), .string)
                index = end
                continue
            }
            if code[index].isNumber {
                let end = code[index...].firstIndex { !$0.isNumber && $0 != "." } ?? code.endIndex
                append(String(code[index..<end]), .number)
                index = end
                continue
            }
            if code[index].isLetter || code[index] == "_" {
                let end = code[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? code.endIndex
                let word = String(code[index..<end])
                append(word, keywords.contains(word) ? .keyword : .plain)
                index = end
                continue
            }
            append(String(code[index]), .plain)
            index = code.index(after: index)
        }
        return tokens
    }

    public static func shell(_ command: String) -> [ChatCodeToken] {
        var tokens: [ChatCodeToken] = []
        var index = command.startIndex
        var expectsCommand = true

        func append(_ text: String, _ kind: ChatCodeTokenKind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(ChatCodeToken(text: text, kind: kind))
            }
        }

        func advanceWord(from start: String.Index) -> String.Index {
            command[start...].firstIndex { $0.isWhitespace || "|><;&\"'#$".contains($0) } ?? command.endIndex
        }

        while index < command.endIndex {
            let character = command[index]
            if character.isWhitespace {
                let end = command[index...].firstIndex(where: { !$0.isWhitespace }) ?? command.endIndex
                append(String(command[index..<end]), .plain)
                if command[index..<end].contains("\n") {
                    expectsCommand = true
                }
                index = end
                continue
            }
            let isCommentBoundary = index == command.startIndex
                || command[command.index(before: index)].isWhitespace
                || "|><;&".contains(command[command.index(before: index)])
            if character == "#", isCommentBoundary {
                let end = command[index...].firstIndex(of: "\n") ?? command.endIndex
                append(String(command[index..<end]), .comment)
                index = end
                expectsCommand = true
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                var end = command.index(after: index)
                var escaped = false
                while end < command.endIndex {
                    let current = command[end]
                    if current == quote && !escaped {
                        end = command.index(after: end)
                        break
                    }
                    escaped = current == "\\" && !escaped
                    end = command.index(after: end)
                }
                append(String(command[index..<end]), .string)
                index = end
                expectsCommand = false
                continue
            }
            if character == "$" {
                let afterDollar = command.index(after: index)
                if afterDollar < command.endIndex, command[afterDollar] == "{" {
                    let end = command[afterDollar...].firstIndex(of: "}").map { command.index(after: $0) } ?? command.endIndex
                    append(String(command[index..<end]), .variable)
                    index = end
                    continue
                }
                let end = command[afterDollar...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? command.endIndex
                if end > afterDollar {
                    append(String(command[index..<end]), .variable)
                    index = end
                    continue
                }
            }
            let remaining = command[index...]
            if let op = [">>", "&&", "||", "2>", "|", ">", "<", ";", "&"].first(where: { remaining.hasPrefix($0) }) {
                let end = command.index(index, offsetBy: op.count)
                append(op, .operator)
                index = end
                expectsCommand = true
                continue
            }
            let end = advanceWord(from: index)
            guard end > index else {
                append(String(character), .plain)
                index = command.index(after: index)
                continue
            }
            let word = String(command[index..<end])
            if word.hasPrefix("-") {
                append(word, .option)
            } else if expectsCommand {
                append(word, .command)
                expectsCommand = false
            } else if ["add", "branch", "checkout", "clone", "commit", "diff", "log", "push", "status", "test"].contains(word) {
                append(word, .subcommand)
            } else {
                append(word, .plain)
            }
            index = end
        }
        return tokens
    }
}
