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
        return tokens(for: code, language: ext)
    }

    /// 差分のように行ごとに描くときの窓口。行をつないでまとめて分けてから行へ戻すので、
    /// 複数行にまたがるブロックコメントや文字列の途中の行も正しく分類される。
    public static func lineTokens(for lines: [String], path: String) -> [[ChatCodeToken]] {
        var result: [[ChatCodeToken]] = [[]]
        for token in tokens(for: lines.joined(separator: "\n"), path: path) {
            var piece = ""
            for character in token.text {
                if character.isNewline {
                    if !piece.isEmpty { result[result.count - 1].append(ChatCodeToken(text: piece, kind: token.kind)) }
                    piece = ""
                    result.append([])
                } else {
                    piece.append(character)
                }
            }
            if !piece.isEmpty { result[result.count - 1].append(ChatCodeToken(text: piece, kind: token.kind)) }
        }
        // 末尾の空行ぶんを行数に合わせる（空の入力でも行数は保つ）。
        while result.count < lines.count { result.append([]) }
        return Array(result.prefix(lines.count))
    }

    /// コードブロックの言語名（```python の python）で分類を切り替える。
    /// 言語名が無い・知らない・Swift のときは従来どおり Swift の規則で分ける。
    public static func tokens(for code: String, language: String?) -> [ChatCodeToken] {
        switch Language(name: language?.lowercased() ?? "") {
        case .shell: shell(code)
        case .rules(let rules): generic(code, rules: rules)
        case nil: swift(code)
        }
    }

    /// 言語ごとの分類規則。色は 4 種類（キーワード・文字列・数値・コメント）のまま。
    struct Rules {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComment = false
        var quotes: Set<Character> = ["\"", "'"]
        /// SQL のように大文字・小文字を区別しない言語。
        var caseInsensitive = false
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
                ], lineComments: ["#"]))
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
                self = .rules(Rules(keywords: ["true", "false", "null"], lineComments: ["//"], quotes: ["\""]))
            case "yaml", "yml", "toml", "ini", "dockerfile", "makefile", "make", "cmake", "r", "perl", "pl":
                self = .rules(Rules(keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"]))
            case "sql", "sqlite", "postgresql", "mysql":
                self = .rules(Rules(keywords: [
                    "select", "from", "where", "insert", "into", "update", "delete", "create", "table", "drop",
                    "alter", "and", "or", "not", "null", "join", "left", "right", "inner", "outer", "on", "group",
                    "by", "order", "limit", "values", "set", "as", "distinct", "having", "union", "index",
                    "primary", "key", "references", "default", "is", "in", "like", "case", "when", "then", "else",
                    "end", "true", "false",
                ], lineComments: ["--"], blockComment: true, quotes: ["'", "\""], caseInsensitive: true))
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
