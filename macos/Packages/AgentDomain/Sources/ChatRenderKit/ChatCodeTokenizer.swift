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
    case tag, attribute, key, section, structure, link, pattern, selector, property, date, delimiter
    case diffAdded, diffRemoved, diffHeader, diffHunk, annotation
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
    /// 名前・拡張子・shebang で種類を決める。未知の種類は本文色に戻す。
    public static func tokens(for code: String, path: String) -> [ChatCodeToken] {
        tokens(for: code, syntax: language(for: path, code: code))
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
        guard let syntax = ChatCodeLanguage.named(name) else { return swift(code) }
        guard shouldHighlight(code) else {
            return code.isEmpty ? [] : [ChatCodeToken(text: code, kind: .plain)]
        }
        let tokens = self.tokens(for: code, syntax: syntax)
        return refinesIdentifiers(language: name) ? refiningIdentifiers(tokens) : tokens
    }

    /// 見本どおりの細かい色分け（型・メンバー・呼び出し・太字のキーワード）をする言語か。
    public static func refinesIdentifiers(language: String?) -> Bool {
        ChatCodeLanguage.named(language ?? "")?.refinesIdentifiers ?? false
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

    public static func shell(_ code: String) -> [ChatCodeToken] {
        tokens(for: code, syntax: .shell)
    }
}
