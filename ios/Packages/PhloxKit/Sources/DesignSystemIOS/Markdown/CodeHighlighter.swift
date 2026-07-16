import Foundation

/// コードブロックの簡易シンタックスハイライタ（Phlox 本体 ChatCodeHighlighter の iOS 移植面）。
/// 連続走査ベースの軽量トークナイザで、正確なパースは狙わない（表示用途）。
/// 契約は Tests/DesignSystemIOSTests/MarkdownRenderingAcceptanceTests.swift。
public struct CodeToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        case keyword
        case string
        case comment
        case number
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum CodeHighlighter {
    private static let swiftKeywords: Set<String> = [
        "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
        "class", "continue", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if",
        "import", "in", "init", "inout", "internal", "is", "isolated", "let", "nil",
        "nonisolated", "open", "operator", "precedencegroup", "private", "protocol", "public",
        "repeat", "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
    ]

    /// code をトークン列に分割する。不変条件: 全トークンの text を連結すると元の code に一致する。
    /// 未知の language は全文 plain。
    public static func tokens(for code: String, language: String?) -> [CodeToken] {
        guard language?.lowercased() == "swift" else {
            return [CodeToken(kind: .plain, text: code)]
        }

        var tokens: [CodeToken] = []
        var index = code.startIndex

        func character(after position: String.Index) -> Character? {
            let next = code.index(after: position)
            return next < code.endIndex ? code[next] : nil
        }

        func append(_ kind: CodeToken.Kind, from start: String.Index, to end: String.Index) {
            guard start < end else { return }
            let text = String(code[start..<end])
            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1] = CodeToken(kind: kind, text: last.text + text)
            } else {
                tokens.append(CodeToken(kind: kind, text: text))
            }
        }

        while index < code.endIndex {
            let start = index

            if code[index] == "/", character(after: index) == "/" {
                index = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(.comment, from: start, to: index)
                continue
            }

            if code[index] == "/", character(after: index) == "*" {
                index = code.index(index, offsetBy: 2)
                var depth = 1
                while index < code.endIndex, depth > 0 {
                    if code[index] == "/", character(after: index) == "*" {
                        depth += 1
                        index = code.index(index, offsetBy: 2)
                    } else if code[index] == "*", character(after: index) == "/" {
                        depth -= 1
                        index = code.index(index, offsetBy: 2)
                    } else {
                        index = code.index(after: index)
                    }
                }
                append(.comment, from: start, to: index)
                continue
            }

            if code[index] == "\"" {
                index = code.index(after: index)
                var isEscaped = false
                while index < code.endIndex {
                    let character = code[index]
                    index = code.index(after: index)
                    if character == "\"", !isEscaped { break }
                    if character == "\\" {
                        isEscaped.toggle()
                    } else {
                        isEscaped = false
                    }
                }
                append(.string, from: start, to: index)
                continue
            }

            if code[index].isNumber {
                index = code.index(after: index)
                while index < code.endIndex,
                      code[index].isNumber || code[index].isLetter || code[index] == "." || code[index] == "_" {
                    index = code.index(after: index)
                }
                append(.number, from: start, to: index)
                continue
            }

            if code[index].isLetter || code[index] == "_" {
                index = code.index(after: index)
                while index < code.endIndex, code[index].isLetter || code[index].isNumber || code[index] == "_" {
                    index = code.index(after: index)
                }
                let word = String(code[start..<index])
                append(swiftKeywords.contains(word) ? .keyword : .plain, from: start, to: index)
                continue
            }

            index = code.index(after: index)
            append(.plain, from: start, to: index)
        }

        return tokens
    }
}
