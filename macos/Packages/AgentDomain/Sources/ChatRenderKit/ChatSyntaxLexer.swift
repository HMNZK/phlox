import Foundation

extension ChatCodeTokenizer {
    private static let keywords: Set<String> = [
        "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "do", "else", "enum", "false", "for", "func", "guard", "if", "import", "in",
        "init", "let", "nil", "private", "public", "return", "self", "static", "struct", "switch",
        "throw", "throws", "true", "try", "var", "while",
    ]

    /// 未指定・未知フェンスは dev の語彙と文字境界を保持する。
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

    public static func tokens(for code: String, syntax: ChatCodeLanguage) -> [ChatCodeToken] {
        guard syntax != .plain, shouldHighlight(code) else {
            return code.isEmpty ? [] : [ChatCodeToken(text: code, kind: .plain)]
        }
        let lexer = ChatSyntaxLexer(code, language: syntax)
        return lexer.scan()
    }
}

/// UTF-8 の境界を走査し、確定した範囲だけ文字列へ戻す。文字の正規化はしない。
private final class ChatSyntaxLexer {
    let bytes: [UInt8]
    let language: ChatCodeLanguage
    let rules: ChatSyntaxRules
    let isCSS: Bool
    let isShell: Bool
    let isCommandLanguage: Bool
    let isMarkup: Bool
    let isJSX: Bool
    let isJSON: Bool
    var index = 0
    var spans: [(Range<Int>, ChatCodeTokenKind)] = []
    var lineStart = true
    var expectsCommand = true
    var jsxDepth = 0
    var cssInBlock = false
    var cssValue = false
    var cssDeclaration = false
    var cssParentheses = 0
    var cancellationCheckpoint = 0

    init(_ code: String, language: ChatCodeLanguage) {
        bytes = Array(code.utf8)
        self.language = language
        // 全種類から一度作った表なので、対応する規則は必ず存在する。
        rules = ChatSyntaxRules.shared[language]!
        isCSS = [.css, .scss, .less].contains(language)
        isShell = language == .shell || language == .fish
        isCommandLanguage = isShell || language == .powershell
        isMarkup = [.html, .xml, .vue, .svelte, .php].contains(language)
        isJSX = language == .jsx || language == .tsx
        isJSON = [.json, .jsonc, .json5].contains(language)
    }

    func has(_ text: String, at position: Int) -> Bool {
        guard position < bytes.count, let first = text.utf8.first, bytes[position] == first else { return false }
        var cursor = position
        for expected in text.utf8 {
            guard cursor < bytes.count, bytes[cursor] == expected else { return false }
            cursor += 1
        }
        return true
    }

    func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
    func isName(_ byte: UInt8) -> Bool {
        byte >= 128 || byte >= 65 && byte <= 90 || byte >= 97 && byte <= 122 || byte == 95 || byte >= 48 && byte <= 57
    }
    func isSpace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
    func lineEnd(_ start: Int) -> Int {
        var end = start
        while end < bytes.count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
        return end
    }
    func afterLine(_ start: Int) -> Int {
        var end = lineEnd(start)
        if end < bytes.count, bytes[end] == 13 { end += 1 }
        if end < bytes.count, bytes[end] == 10 { end += 1 }
        return end
    }
    func find(_ pattern: String, from start: Int, before limit: Int? = nil) -> Int {
        let end = limit ?? bytes.count
        let length = pattern.utf8.count
        var cursor = start
        while cursor + length <= end {
            if (cursor - start) & 4095 == 0, Task.isCancelled { return end }
            if has(pattern, at: cursor) { return cursor }
            cursor += 1
        }
        return end
    }
    func emit(_ end: Int, _ kind: ChatCodeTokenKind) {
        guard end > index else { return }
        if let last = spans.last, last.1 == kind, last.0.upperBound == index {
            spans[spans.count - 1].0 = last.0.lowerBound..<end
        } else { spans.append((index..<end, kind)) }
        lineStart = bytes[end - 1] == 10 || bytes[end - 1] == 13
        index = end
    }
    func embedded(_ end: Int, _ syntax: ChatCodeLanguage) {
        guard end > index else { return }
        // 公開入口で全文のサイズ・行長を確認済み。埋め込みはその部分範囲。
        guard syntax != .plain else { emit(end, .plain); return }
        let start = index
        let code = text(start..<end)
        let lexer = ChatSyntaxLexer(code, language: syntax)
        lexer.scanSpans()
        for (range, kind) in lexer.spans {
            emit(start + range.upperBound, kind)
        }
    }
    func quotedEnd(_ start: Int, delimiter: String, escape: UInt8? = 92, doubled: Bool = false, before limit: Int? = nil) -> Int {
        let end = limit ?? bytes.count
        var cursor = start + delimiter.utf8.count
        while cursor < end {
            if has(delimiter, at: cursor) {
                let next = cursor + delimiter.utf8.count
                if doubled, has(delimiter, at: next) { cursor = next + delimiter.utf8.count; continue }
                return next
            }
            if bytes[cursor] == escape, cursor + 1 < end { cursor += 2 } else { cursor += 1 }
        }
        return end
    }

    func isTagStart() -> Bool {
        guard bytes[index] == 60, index + 1 < bytes.count else { return false }
        var next = index + 1
        if bytes[next] == 47 { next += 1 }
        guard next < bytes.count else { return false }
        let byte = bytes[next]
        if language == .tsx {
            var end = next
            while end < bytes.count, isName(bytes[end]) { end += 1 }
            if end < bytes.count, bytes[end] == 44 { return false }
            while end < bytes.count, bytes[end] == 32 || bytes[end] == 9 { end += 1 }
            if has("extends", at: end), end + 7 < bytes.count, isSpace(bytes[end + 7]) { return false }
        }
        return byte >= 65 && byte <= 90 || byte >= 97 && byte <= 122
            || byte == 95 || byte == 33 || byte == 63 || isJSX && byte == 62
    }

    /// JS/TS の値に続く < は、比較や型引数として扱う。
    func startsJSXExpression() -> Bool {
        var previous = index
        while previous > 0, isSpace(bytes[previous - 1]) { previous -= 1 }
        if previous == 0 { return true }
        if "=([{,:;?!&|>".utf8.contains(bytes[previous - 1]) { return true }
        let end = previous
        while previous > 0, isName(bytes[previous - 1]) { previous -= 1 }
        return ["return", "yield"].contains(text(previous..<end))
    }

    func startsAttribute() -> Bool {
        var previous = index
        while previous > 0, bytes[previous - 1] == 32 || bytes[previous - 1] == 9 { previous -= 1 }
        return previous == 0 || "\n\r{};".utf8.contains(bytes[previous - 1])
    }

    func scan() -> [ChatCodeToken] {
        scanSpans()
        return spans.map { ChatCodeToken(text: text($0.0), kind: $0.1) }
    }

    private func scanSpans() {
        while index < bytes.count {
            // 取消済みの計算は破棄される。残りは原文のまま返し、長い旧計算を止める。
            if index >= cancellationCheckpoint {
                if Task.isCancelled { emit(bytes.count, .plain); break }
                cancellationCheckpoint = index + 4096
            }
            if language == .csv || language == .tsv { csv(); continue }
            if language == .diff { diff(); continue }
            if language == .markdown || language == .mdx { markdown(); continue }
            if isMarkup, markup() { continue }
            if isJSX, jsxDepth > 0 {
                if bytes[index] == 123 { expression(); continue }
                if bytes[index] != 60 {
                    var end = index + 1
                    while end < bytes.count, bytes[end] != 60, bytes[end] != 123 { end += 1 }
                    emit(end, .plain); continue
                }
            }
            if isJSX, isTagStart(), jsxDepth > 0 || startsJSXExpression() {
                let start = index
                let closing = has("</", at: index)
                tag()
                if closing { jsxDepth = max(0, jsxDepth - 1) }
                else if index < 2 || !has("/>", at: index - 2), !has("<!", at: start) { jsxDepth += 1 }
                continue
            }
            if rules.usesLineRules, lineStart, lineRule() { continue }
            if lexical() { continue }
            emit(index + 1, .plain)
        }
    }

    func lexical() -> Bool {
        let start = index
        let byte = bytes[index]
        if isCSS, byte == 40 || byte == 41 {
            cssParentheses = max(0, cssParentheses + (byte == 40 ? 1 : -1))
            emit(index + 1, .plain); return true
        }
        if isCSS, "{}:;".utf8.contains(byte) {
            if byte == 123 { cssInBlock = true; cssValue = false; cssDeclaration = false }
            if byte == 125 { cssInBlock = false; cssValue = false; cssDeclaration = false }
            if byte == 58, cssInBlock || cssDeclaration { cssValue = true }
            if byte == 59 { cssValue = false; cssDeclaration = false }
            emit(index + 1, .structure); return true
        }
        for (open, close) in rules.blocks where has(open, at: index) {
            var end = index + open.utf8.count
            var depth = 1
            while end < bytes.count {
                if rules.nestedComments, has(open, at: end) { depth += 1; end += open.utf8.count }
                else if has(close, at: end) {
                    depth -= 1; end += close.utf8.count
                    if depth == 0 { break }
                } else { end += 1 }
            }
            emit(end, .comment); return true
        }
        var luaLongComment = false
        if language == .lua, has("--[", at: index) {
            var delimiter = index + 3
            while delimiter < bytes.count, bytes[delimiter] == 61 { delimiter += 1 }
            luaLongComment = delimiter < bytes.count && bytes[delimiter] == 91
        }
        if !luaLongComment {
            for delimiter in rules.lineComments where has(delimiter, at: index) {
                if isCSS, delimiter == "//", cssParentheses > 0 { continue }
                if !rules.lineCommentNeedsBoundary || index == 0 || isSpace(bytes[index - 1])
                    || isShell && "|><;&".utf8.contains(bytes[index - 1]) {
                    emit(lineEnd(index), .comment); return true
                }
            }
        }
        if language == .lua, has("[", at: index) || has("--[", at: index) {
            let comment = has("--", at: index)
            var end = index + (comment ? 3 : 1)
            while end < bytes.count, bytes[end] == 61 { end += 1 }
            if end < bytes.count, bytes[end] == 91 {
                let close = "]" + String(repeating: "=", count: end - index - (comment ? 3 : 1)) + "]"
                let match = find(close, from: end + 1)
                emit(min(bytes.count, match + close.utf8.count), comment ? .comment : .string); return true
            }
        }
        if (language == .swift && byte == 35) || (language == .rust && byte == 114) {
            var end = index + (language == .rust ? 1 : 0)
            while end < bytes.count, bytes[end] == 35 { end += 1 }
            if end < bytes.count, bytes[end] == 34 {
                let hashes = String(repeating: "#", count: end - index - (language == .rust ? 1 : 0))
                let quote = has("\"\"\"", at: end) ? "\"\"\"" : "\""
                let close = quote + hashes
                var match = find(close, from: end + quote.utf8.count)
                if language == .swift {
                    let escape = "\\" + hashes
                    while match < bytes.count, match >= escape.utf8.count,
                          has(escape, at: match - escape.utf8.count) {
                        match = find(close, from: match + quote.utf8.count)
                    }
                }
                emit(min(bytes.count, match + close.utf8.count), .string); return true
            }
        }
        if language == .nix, has("''", at: index) {
            emit(quotedEnd(index, delimiter: "''"), .string); return true
        }
        if language == .csharp, byte == 91, startsAttribute(), index + 1 < bytes.count, isName(bytes[index + 1]) {
            emit(index + 1, .structure)
            var end = index
            while end < bytes.count, isName(bytes[end]) || bytes[end] == 46 { end += 1 }
            emit(end, .attribute); return true
        }
        if rules.quotes.contains(byte), !rules.quoteNeedsBoundary || index == 0
            || isSpace(bytes[index - 1]) || "[{,:-?".utf8.contains(bytes[index - 1]) {
            if language == .rust, byte == 39, index + 1 < bytes.count, isName(bytes[index + 1]) {
                var end = index + 1
                while end < bytes.count, isName(bytes[end]) { end += 1 }
                if end == bytes.count || bytes[end] != 39 { emit(end, .plain); return true }
            }
            let quote = String(UnicodeScalar(byte))
            let delimiter = rules.triple && has(quote + quote + quote, at: index) ? quote + quote + quote : quote
            let escape: UInt8? = byte == 96 && rules.rawBackticks || byte == 39 && rules.doubledSingleQuotes ? nil : rules.escapeByte
            let end = quotedEnd(index, delimiter: delimiter, escape: escape, doubled: byte == 39 && rules.doubledSingleQuotes)
            var next = end
            while next < bytes.count, isSpace(bytes[next]) { next += 1 }
            let key = next < bytes.count && ((isJSON || language == .yaml) && bytes[next] == 58
                || language == .toml && bytes[next] == 61)
            emit(end, key ? .key : .string)
            if isShell { expectsCommand = false }
            return true
        }
        if (byte == 36 && rules.hasVariables)
            || (byte == 64 && [.perl, .less].contains(language)) || (byte == 37 && language == .perl) {
            var end = index + 1
            if end < bytes.count, language == .perl, bytes[end] == 35 { end += 1 }
            if end < bytes.count, isShell, "@*#?$!-".utf8.contains(bytes[end]) { emit(end + 1, .variable); return true }
            if end < bytes.count, bytes[end] == 123 || bytes[end] == 40 {
                let close = bytes[end] == 123 ? "}" : ")"
                end = min(bytes.count, find(close, from: end + 1) + 1)
            } else { while end < bytes.count, isName(bytes[end]) || language == .powershell && bytes[end] == 58 { end += 1 } }
            emit(end, .variable)
            if isCSS { cssDeclaration = true }
            return true
        }
        if byte == 64, rules.hasAnnotations {
            if (language == .objectiveC || language == .csharp), index + 1 < bytes.count, bytes[index + 1] == 34 {
                if language == .csharp {
                    var end = index + 2
                    while end < bytes.count {
                        if bytes[end] == 34 {
                            end += 1
                            if end < bytes.count, bytes[end] == 34 { end += 1; continue }
                            break
                        }
                        end += 1
                    }
                    emit(end, .string)
                } else { emit(quotedEnd(index + 1, delimiter: "\""), .string) }
                return true
            }
            var end = index + 1
            while end < bytes.count, isName(bytes[end]) || bytes[end] == 45
                || (language == .java || language == .kotlin) && bytes[end] == 46 { end += 1 }
            emit(end, .keyword); return true
        }
        if byte == 58, (language == .ruby || language == .elixir),
           index == 0 || bytes[index - 1] != 58, !has("::", at: index), index + 1 < bytes.count,
           bytes[index + 1] == 34 || bytes[index + 1] == 39 {
            emit(quotedEnd(index + 1, delimiter: String(UnicodeScalar(bytes[index + 1]))), .string); return true
        }
        if byte == 58, language == .ruby || language == .elixir,
           index == 0 || bytes[index - 1] != 58, !has("::", at: index),
           index + 1 < bytes.count, isName(bytes[index + 1]) {
            var end = index + 2
            while end < bytes.count, isName(bytes[end]) { end += 1 }
            emit(end, .string); return true
        }
        if byte == 92, language == .latex || language == .bibtex {
            if language == .latex, index + 1 < bytes.count, "[]()".utf8.contains(bytes[index + 1]) {
                emit(index + 2, .structure); return true
            }
            var end = index + 1
            while end < bytes.count, isName(bytes[end]) { end += 1 }
            if end == index + 1 { end = min(bytes.count, end + 1) }
            emit(end, .keyword)
            if (text(start..<end) == "\\begin" || text(start..<end) == "\\end"), index < bytes.count, bytes[index] == 123 {
                emit(min(bytes.count, find("}", from: index + 1) + 1), .section)
            }
            return true
        }
        if byte == 36, language == .latex { emit(index + (has("$$", at: index) ? 2 : 1), .structure); return true }
        if isShell, has("2>", at: index) {
            emit(index + 2, .operator); expectsCommand = true; return true
        }
        if isShell, byte == 92, index + 1 < bytes.count, bytes[index + 1] == 10 || bytes[index + 1] == 13 {
            emit(afterLine(index), .plain); return true
        }
        if isShell, byte == 91 || byte == 93 {
            emit(index + 1, .command); expectsCommand = false; return true
        }
        if isShell, !isSpace(byte), !"|><;&\"'#$-".utf8.contains(byte) {
            var end = index + 1
            while end < bytes.count, !isSpace(bytes[end]), !"|><;&\"'#$".utf8.contains(bytes[end]) { end += 1 }
            if let assignment = bytes[index..<end].firstIndex(of: 61),
               assignment > index, bytes[index..<assignment].allSatisfy({ isName($0) }) {
                emit(assignment + 1, .variable)
                while index < bytes.count, !isSpace(bytes[index]), !"|><;&".utf8.contains(bytes[index]) {
                    if bytes[index] == 34 || bytes[index] == 39 {
                        emit(quotedEnd(index, delimiter: String(UnicodeScalar(bytes[index]))), .string)
                    } else {
                        var valueEnd = index
                        while valueEnd < bytes.count, !isSpace(bytes[valueEnd]),
                              !"|><;&\"'".utf8.contains(bytes[valueEnd]) {
                            if bytes[valueEnd] == 92, valueEnd + 1 < bytes.count { valueEnd += 1 }
                            valueEnd += 1
                        }
                        emit(valueEnd, .plain)
                    }
                }
                return true
            }
            let word = text(index..<end)
            let kind: ChatCodeTokenKind
            if rules.keywords.contains(word) { kind = .keyword }
            else if expectsCommand { kind = .command; expectsCommand = false }
            else if ChatSyntaxRules.subcommands.contains(word) { kind = .subcommand }
            else { kind = .plain }
            emit(end, kind); return true
        }
        if isCSS, byte == 46 || byte == 35,
           index + 1 < bytes.count, isName(bytes[index + 1]) {
            var end = index + 2
            while end < bytes.count, isName(bytes[end]) || bytes[end] == 45 { end += 1 }
            emit(end, cssValue ? .string : .selector); return true
        }
        if byte >= 48 && byte <= 57 {
            var end = index + 1
            while end < bytes.count, isName(bytes[end]) || bytes[end] == 46 { end += 1 }
            if language == .toml, end < bytes.count, bytes[end] == 45 {
                while end < bytes.count, isName(bytes[end]) || "-:+. ".utf8.contains(bytes[end]) { end += 1 }
                emit(end, .date); return true
            }
            emit(end, language == .log && Double(text(index..<end)) == nil ? .plain : .number); return true
        }
        if isName(byte), !(byte >= 48 && byte <= 57) {
            var end = index + 1
            while end < bytes.count, isName(bytes[end])
                || ((isCSS || isCommandLanguage || rules.identifierHyphens) && bytes[end] == 45)
                || rules.identifierApostrophes && bytes[end] == 39 { end += 1 }
            let word = text(index..<end)
            var next = end
            while next < bytes.count, bytes[next] == 32 || bytes[next] == 9 { next += 1 }
            if isCSS, word.lowercased() == "url", end < bytes.count, bytes[end] == 40 {
                emit(end, .string)
                emit(index + 1, .plain)
                var stop = index
                while stop < bytes.count, bytes[stop] != 41 {
                    if bytes[stop] == 34 || bytes[stop] == 39 {
                        stop = quotedEnd(stop, delimiter: String(UnicodeScalar(bytes[stop])))
                    } else if bytes[stop] == 92, stop + 1 < bytes.count {
                        stop += 2
                    } else { stop += 1 }
                }
                emit(stop, .string)
                if index < bytes.count { emit(index + 1, .plain) }
                return true
            }
            var kind: ChatCodeTokenKind = rules.keywords.contains(rules.insensitive ? word.lowercased() : word) ? .keyword : .plain
            if language == .graphql, kind == .plain { kind = .key }
            if language == .hcl, next < bytes.count, bytes[next] == 123 { kind = .section }
            if next < bytes.count, bytes[next] == 58, [.yaml, .json5, .graphql].contains(language) { kind = .key }
            if next < bytes.count, bytes[next] == 61, rules.hasAssignmentKeys { kind = .key }
            if isCSS {
                kind = cssValue ? .string : (next < bytes.count && bytes[next] == 58 ? .property : .selector)
                if kind == .property { cssDeclaration = true }
            }
            if language == .log, ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"].contains(word) { kind = .keyword }
            if isCommandLanguage {
                if kind == .plain, expectsCommand { kind = .command; expectsCommand = false }
                else if ChatSyntaxRules.subcommands.contains(word) { kind = .subcommand }
            }
            emit(end, kind); return true
        }
        if isCommandLanguage, byte == 45 {
            var end = index + 1
            while end < bytes.count, !isSpace(bytes[end]), !"|><;&".utf8.contains(bytes[end]) { end += 1 }
            emit(end, .option); return true
        }
        if isCommandLanguage, "|><;&".utf8.contains(byte) {
            var end = index + 1
            if end < bytes.count, bytes[end] == byte { end += 1 }
            emit(end, .operator); expectsCommand = true; return true
        }
        if byte == 10 || byte == 13 { expectsCommand = true }
        return false
    }

    func lineRule() -> Bool {
        let end = lineEnd(index)
        let line = text(index..<end)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if language == .yaml, trimmed.hasPrefix("#") { return false }
        if language == .log {
            let count = line.utf8.prefix { $0 >= 48 && $0 <= 57 || "-/:.TZ+ ".utf8.contains($0) }.count
            if count >= 10 { emit(index + count, .date); return true }
        }
        if [.ini, .toml].contains(language), trimmed.hasPrefix("[") {
            var start = index
            while start < end, isSpace(bytes[start]) { start += 1 }
            emit(start, .plain)
            var close = min(end, find("]", from: index + 1, before: end) + 1)
            if close < end, bytes[close] == 93 { close += 1 }
            emit(close, .section); return true
        }
        if [.ini, .env, .properties].contains(language), !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";") {
            var separator = index
            var escaped = false
            while separator < end {
                if !escaped, bytes[separator] == 61 || language == .properties && bytes[separator] == 58 { break }
                escaped = bytes[separator] == 92 && !escaped
                separator += 1
            }
            if separator < end {
                var start = index
                while start < separator, isSpace(bytes[start]) { start += 1 }
                emit(start, .plain); emit(separator, .key); emit(separator + 1, .operator)
                var valueEnd = end
                if language == .properties {
                    while valueEnd > index, bytes[valueEnd - 1] == 92, valueEnd < bytes.count { valueEnd = lineEnd(afterLine(valueEnd)) }
                    emit(valueEnd, Double(text(index..<valueEnd)) == nil ? .string : .number)
                    return true
                }
                while index < valueEnd {
                    if bytes[index] == 35 || language == .ini && bytes[index] == 59,
                       index == 0 || isSpace(bytes[index - 1]) { emit(valueEnd, .comment) }
                    else if isSpace(bytes[index]) { emit(index + 1, .plain) }
                    else if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 36 && language == .env { _ = lexical() }
                    else {
                        var stop = index + 1
                        while stop < valueEnd, !isSpace(bytes[stop]), !(bytes[stop] == 36 && language == .env) { stop += 1 }
                        let value = text(index..<stop)
                        emit(stop, Double(value) == nil ? .string : .number)
                    }
                }
                return true
            }
        }
        if language == .ignore || language == .attributes {
            if trimmed.hasPrefix("#") { emit(end, .comment); return true }
            while index < end {
                if "!*?[]".utf8.contains(bytes[index]) { emit(index + 1, .operator) }
                else if isSpace(bytes[index]) { emit(index + 1, .plain) }
                else {
                    var next = index + 1
                    while next < end, !isSpace(bytes[next]), !"!*?[]".utf8.contains(bytes[next]) { next += 1 }
                    let attribute = language == .attributes && index > 0 && isSpace(bytes[index - 1])
                    emit(next, attribute ? .attribute : .pattern)
                }
            }
            if index == end { emit(afterLine(index), .plain) }
            return true
        }
        if language == .literateHaskell {
            if bytes[index] != 62 { emit(afterLine(index), .plain) }
            else { emit(index + 1, .structure); embedded(end, .haskell) }
            return true
        }
        if language == .makefile, bytes[index] == 9 { emit(index + 1, .plain); embedded(end, .shell); return true }
        if language == .makefile, !trimmed.hasPrefix("#"), let equal = line.firstIndex(of: "=") {
            let operatorEnd = index + line[...equal].utf8.count
            var separator = operatorEnd - 1
            if separator > index, ":?+!".utf8.contains(bytes[separator - 1]) { separator -= 1 }
            var keyEnd = separator
            while keyEnd > index, isSpace(bytes[keyEnd - 1]) { keyEnd -= 1 }
            emit(keyEnd, .key); emit(separator, .plain)
            emit(operatorEnd, .operator)
            return true
        }
        if language == .makefile, let colon = line.firstIndex(of: ":"), !trimmed.hasPrefix("#") {
            emit(index + line[..<colon].utf8.count, .section); emit(index + 1, .operator); return true
        }
        if language == .dockerfile, trimmed.uppercased().hasPrefix("RUN ") {
            var stop = end
            while stop > index, bytes[stop - 1] == 92, stop < bytes.count {
                stop = lineEnd(afterLine(stop))
            }
            let offset = line.utf8.prefix { $0 == 32 || $0 == 9 }.count
            emit(index + offset, .plain); emit(index + 3, .keyword); embedded(stop, .shell); return true
        }
        if language == .yaml, let marker = line.range(of: ":"),
           line[marker.upperBound...].trimmingCharacters(in: .whitespaces).hasPrefix("|")
            || language == .yaml && line.contains(": >") {
            let indent = line.utf8.prefix { $0 == 32 }.count
            var next = afterLine(index)
            while next < bytes.count {
                let stop = lineEnd(next)
                let following = text(next..<stop)
                let spaces = following.utf8.prefix { $0 == 32 }.count
                if !following.trimmingCharacters(in: .whitespaces).isEmpty, spaces <= indent { break }
                next = afterLine(next)
            }
            // 見出し行は通常規則、続く字下げ部分を文字列として保持する。
            let stop = afterLine(index)
            while index < stop {
                if !lexical() { emit(index + 1, .plain) }
            }
            emit(next, .string); return true
        }
        if [.c, .objectiveC, .csharp].contains(language), trimmed.hasPrefix("#") {
            var start = index
            while start < end, isSpace(bytes[start]) { start += 1 }
            emit(start, .plain)
            var stop = index + 1
            while stop < end, bytes[stop] == 32 || bytes[stop] == 9 { stop += 1 }
            while stop < end, isName(bytes[stop]) { stop += 1 }
            emit(stop, .keyword); return true
        }
        return false
    }

    func diff() {
        let end = afterLine(index)
        let kind: ChatCodeTokenKind
        if ["---", "+++", "diff ", "index ", "***"].contains(where: { has($0, at: index) }) { kind = .diffHeader }
        else if has("@@", at: index) { kind = .diffHunk }
        else if bytes[index] == 43 { kind = .diffAdded }
        else if bytes[index] == 45 { kind = .diffRemoved }
        else if bytes[index] == 92 { kind = .annotation }
        else { kind = .plain }
        emit(end, kind)
    }

    func csv() {
        let separator: UInt8 = language == .tsv ? 9 : 44
        if bytes[index] == separator { emit(index + 1, .delimiter); return }
        if bytes[index] == 10 || bytes[index] == 13 { emit(index + 1, .plain); return }
        if bytes[index] == 34 {
            var end = index + 1
            while end < bytes.count {
                if bytes[end] == 34 {
                    end += 1
                    if end < bytes.count, bytes[end] == 34 { end += 1; continue }
                    break
                }
                end += 1
            }
            emit(end, .string); return
        }
        var end = index + 1
        while end < bytes.count, bytes[end] != separator, bytes[end] != 10, bytes[end] != 13 { end += 1 }
        let field = text(index..<end).trimmingCharacters(in: .whitespaces)
        emit(end, Double(field)?.isFinite == true ? .number : .plain)
    }

    func markup() -> Bool {
        if language == .php {
            if has("<?", at: index) {
                let open = has("<?php", at: index) ? 5 : 2
                emit(index + open, .tag)
                // タグ内は PHP、外は HTML。走査の再帰を避けるため共通字句だけ使う。
                while index < bytes.count, !has("?>", at: index) {
                    if !lexical() { emit(index + 1, .plain) }
                }
                if index < bytes.count { emit(index + 2, .tag) }
                return true
            }
        }
        if has("<!--", at: index) {
            emit(min(bytes.count, find("-->", from: index + 4) + 3), .comment); return true
        }
        if has("<![CDATA[", at: index) {
            emit(min(bytes.count, find("]]>", from: index + 9) + 3), .plain); return true
        }
        if isTagStart() {
            let start = index
            let end = tag()
            if language != .xml {
                let declaration = markupDeclaration(start..<end)
                let tagName = declaration.name == "script" || declaration.name == "style" ? declaration.name : ""
                if !tagName.isEmpty {
                    var stop = index
                    let closeBytes = Array(("</" + tagName).utf8)
                    while stop < bytes.count {
                        if bytes[stop] == 60, stop + closeBytes.count <= bytes.count,
                           bytes[stop..<(stop + closeBytes.count)].map({ $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }).elementsEqual(closeBytes) { break }
                        stop += 1
                    }
                    let declarations: [String: ChatCodeLanguage] = tagName == "script"
                        ? ["js": .javascript, "javascript": .javascript, "text/javascript": .javascript,
                           "application/javascript": .javascript, "module": .javascript,
                           "ts": .typescript, "typescript": .typescript, "text/typescript": .typescript,
                           "json": .json, "application/json": .json, "text/json": .json]
                        : ["css": .css, "text/css": .css, "scss": .scss, "less": .less]
                    let declared = declaration.attributes["lang"] ?? declaration.attributes["type"]
                    embedded(stop, declared.map { declarations[$0] ?? .plain } ?? (tagName == "style" ? .css : .javascript))
                }
            }
            return true
        }
        if bytes[index] == 38 {
            let end = lineEnd(index)
            let stop = min(end, find(";", from: index + 1, before: end) + 1)
            if stop > index, stop <= bytes.count, bytes[stop - 1] == 59 { emit(stop, .structure); return true }
        }
        if language == .vue, has("{{", at: index) {
            emit(index + 2, .structure); embedded(find("}}", from: index), .javascript)
            if index < bytes.count { emit(index + 2, .structure) }; return true
        }
        if language == .svelte, bytes[index] == 123 {
            expression(); return true
        }
        // マークアップの本文をプログラムとして解釈しない。
        var end = index + 1
        while end < bytes.count, ![60, 38].contains(bytes[end]),
              !(language == .php && has("<?", at: end)),
              !(language == .vue && has("{{", at: end)),
              !(language == .svelte && bytes[end] == 123) { end += 1 }
        emit(end, .plain); return true
    }

    @discardableResult func tag() -> Int {
        if has("<!", at: index) || has("<?", at: index) {
            emit(min(bytes.count, find(">", from: index + 2) + 1), .tag); return index
        }
        var end = index + 1
        if end < bytes.count, bytes[end] == 47 { end += 1 }
        while end < bytes.count, isName(bytes[end]) || bytes[end] == 45 || bytes[end] == 58 { end += 1 }
        emit(end, .tag)
        var expectsValue = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 62 { emit(index + 1, .tag); break }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 62 { emit(index + 2, .tag); break }
            if byte == 61 { expectsValue = true; emit(index + 1, .plain); continue }
            if byte == 34 || byte == 39 { emit(quotedEnd(index, delimiter: String(UnicodeScalar(byte)), escape: nil), .string); expectsValue = false; continue }
            if byte == 123, language == .jsx || language == .tsx || language == .svelte { expression(); continue }
            if expectsValue, !isSpace(byte) {
                var next = index + 1
                while next < bytes.count, !isSpace(bytes[next]), bytes[next] != 62, !has("/>", at: next) { next += 1 }
                emit(next, .string); expectsValue = false; continue
            }
            if isName(byte) || byte == 58 || byte == 64 || byte == 35 {
                var next = index + 1
                while next < bytes.count, isName(bytes[next]) || "-:.@".utf8.contains(bytes[next]) { next += 1 }
                let name = text(index..<next)
                emit(next, name.hasPrefix("v-") || name.hasPrefix(":") || name.hasPrefix("@") || name.hasPrefix("#") ? .keyword : .attribute)
                continue
            }
            emit(index + 1, .plain)
        }
        return index
    }

    func markupDeclaration(_ range: Range<Int>) -> (name: String, attributes: [String: String]) {
        var cursor = range.lowerBound + 1
        let start = cursor
        while cursor < range.upperBound, isName(bytes[cursor]) || bytes[cursor] == 45 { cursor += 1 }
        let name = text(start..<cursor).lowercased()
        var attributes: [String: String] = [:]
        while cursor < range.upperBound {
            while cursor < range.upperBound, isSpace(bytes[cursor]) { cursor += 1 }
            let keyStart = cursor
            while cursor < range.upperBound, isName(bytes[cursor]) || bytes[cursor] == 45 { cursor += 1 }
            guard cursor > keyStart else { cursor += 1; continue }
            let key = text(keyStart..<cursor).lowercased()
            while cursor < range.upperBound, isSpace(bytes[cursor]) { cursor += 1 }
            guard cursor < range.upperBound, bytes[cursor] == 61 else { continue }
            cursor += 1
            while cursor < range.upperBound, isSpace(bytes[cursor]) { cursor += 1 }
            guard cursor < range.upperBound else { break }
            let quote = bytes[cursor] == 34 || bytes[cursor] == 39 ? bytes[cursor] : 0
            if quote != 0 { cursor += 1 }
            let valueStart = cursor
            while cursor < range.upperBound, quote == 0 ? !isSpace(bytes[cursor]) && bytes[cursor] != 62 : bytes[cursor] != quote { cursor += 1 }
            attributes[key] = text(valueStart..<cursor).lowercased()
            if quote != 0, cursor < range.upperBound { cursor += 1 }
        }
        return (name, attributes)
    }

    func expression() {
        emit(index + 1, .structure)
        let start = index
        var end = index
        var depth = 1
        while end < bytes.count {
            if bytes[end] == 34 || bytes[end] == 39 || bytes[end] == 96 {
                end = quotedEnd(end, delimiter: String(UnicodeScalar(bytes[end])))
            } else if has("/*", at: end) { end = min(bytes.count, find("*/", from: end + 2) + 2) }
            else if has("//", at: end) { end = lineEnd(end) }
            else {
                if bytes[end] == 123 { depth += 1 }
                if bytes[end] == 125 { depth -= 1; if depth == 0 { break } }
                end += 1
            }
        }
        if end > start { embedded(end, language == .tsx ? .typescript : .javascript) }
        if index < bytes.count { emit(index + 1, .structure) }
    }

    func markdown() {
        if lineStart {
            let stop = lineEnd(index)
            let line = text(index..<stop)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if bytes[index] == 91 {
                let close = find("]:", from: index + 1, before: stop)
                if close < stop {
                    emit(index + 1, .structure); emit(close, .link); emit(close + 2, .structure)
                    while index < stop, isSpace(bytes[index]) { emit(index + 1, .plain) }
                    var end = index
                    while end < stop, !isSpace(bytes[end]) { end += 1 }
                    emit(end, .link)
                    while index < stop, isSpace(bytes[index]) { emit(index + 1, .plain) }
                    if index < stop, bytes[index] == 34 || bytes[index] == 39 {
                        emit(quotedEnd(index, delimiter: String(UnicodeScalar(bytes[index])), before: stop), .string)
                    }
                    return
                }
            }
            if index == 0, trimmed == "---" {
                emit(afterLine(index), .structure)
                var close = index
                while close < bytes.count, text(close..<lineEnd(close)) != "---", text(close..<lineEnd(close)) != "..." { close = afterLine(close) }
                embedded(close, .yaml)
                if index < bytes.count { emit(afterLine(index), .structure) }
                return
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = trimmed.first == "`" ? "`" : "~"
                let count = trimmed.prefix { String($0) == marker }.count
                let name = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                emit(afterLine(index), .structure)
                var close = index
                let markerByte: UInt8 = marker == "`" ? 96 : 126
                while close < bytes.count {
                    let stop = lineEnd(close)
                    var cursor = close
                    while cursor < stop, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
                    var unicodeWhitespace = cursor < stop && (bytes[cursor] >= 128 || bytes[cursor] < 32)
                    if !unicodeWhitespace {
                        let start = cursor
                        while cursor < stop, bytes[cursor] == markerByte { cursor += 1 }
                        if cursor - start >= count {
                            while cursor < stop, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
                            if cursor == stop { break }
                            unicodeWhitespace = bytes[cursor] >= 128 || bytes[cursor] < 32
                        }
                    }
                    // 通常の空白は byte で判定し、Unicode の空白は従来の Foundation 規則を保つ。
                    if unicodeWhitespace {
                        let candidate = text(close..<stop).trimmingCharacters(in: .whitespaces)
                        let run = candidate.prefix { String($0) == marker }.count
                        if run >= count, candidate.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty { break }
                    }
                    close = afterLine(close)
                }
                embedded(close, ChatCodeLanguage.named(name) ?? .plain)
                if index < bytes.count { emit(afterLine(index), .structure) }
                return
            }
            if ["#", ">", "- ", "+ ", "* "].contains(where: { trimmed.hasPrefix($0) }) || trimmed == "---" || trimmed == "***" {
                let indentation = line.unicodeScalars.prefix { CharacterSet.whitespaces.contains($0) }
                    .reduce(0) { $0 + String($1).utf8.count }
                var end = index + indentation
                while end < stop, " #>+-*\t".utf8.contains(bytes[end]) { end += 1 }
                emit(end, .structure); return
            }
            var digit = index
            while digit < stop, bytes[digit] >= 48 && bytes[digit] <= 57 { digit += 1 }
            if digit > index, digit + 1 < stop, bytes[digit] == 46, bytes[digit + 1] == 32 { emit(digit + 1, .structure); return }
        }
        if has("<!--", at: index) { emit(min(bytes.count, find("-->", from: index + 4) + 3), .comment); return }
        if bytes[index] == 96 {
            var end = index + 1
            while end < bytes.count, bytes[end] == 96 { end += 1 }
            let fence = String(repeating: "`", count: end - index)
            emit(min(bytes.count, find(fence, from: end) + fence.utf8.count), .string); return
        }
        if has("](", at: index) {
            let end = lineEnd(index)
            emit(index + 2, .structure); emit(min(end, find(")", from: index, before: end) + 1), .link); return
        }
        if has("][", at: index) {
            let end = lineEnd(index)
            emit(index + 2, .structure)
            let close = find("]", from: index, before: end)
            emit(close, .link)
            if index < end { emit(index + 1, .structure) }
            return
        }
        if language == .mdx, bytes[index] == 60 { tag(); return }
        if "*_[]!".utf8.contains(bytes[index]) { emit(index + 1, .structure); return }
        if bytes[index] == 10 || bytes[index] == 13 { emit(index + 1, .plain); return }
        var end = index + 1
        while end < bytes.count {
            switch bytes[end] {
            case 10, 13, 96, 93, 60, 42, 95, 91, 33: break
            default: end += 1; continue
            }
            break
        }
        emit(end, .plain)
    }
}
