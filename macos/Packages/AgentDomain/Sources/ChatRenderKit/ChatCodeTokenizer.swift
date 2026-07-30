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

    /// 拡張子で言語を決める。Swift 以外は plain にフォールバックする。
    public static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        guard path.lowercased().hasSuffix(".swift") else {
            return code.isEmpty ? [] : [ChatCodeToken(text: code, kind: .plain)]
        }
        return swift(code)
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
