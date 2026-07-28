import Foundation

/// TOML を「行の並び」として保持し、指定したキーの値だけを差し替える外科的エディタ。
///
/// 目的は `~/.codex/config.toml` の安全な部分更新である。あのファイルには
/// 数百のプロジェクト設定・コメント・手書きの並びが入っており、解析して書き戻す
/// 方式（parse → re-serialize）だと触っていない箇所まで書式が変わってしまう。
/// そこで **触った行だけを書き換え、他の行はバイト単位でそのまま残す**。
///
/// 対応範囲は Phlox が実際に必要とする範囲に絞る:
/// - 読み取り: 文字列 / 真偽値 / 整数 / 文字列配列 / 宣言済みテーブル名の列挙
/// - 書き込み: 文字列 / 真偽値 / 整数 の代入、キー削除、テーブル削除
/// 複数行にまたがる値（配列・複数行文字列）は「読み飛ばすべき塊」として正しく認識するが、
/// 書き込みでは常に1行のスカラーへ置き換える。
public struct TOMLDocument: Sendable, Equatable {
    private var lines: [String]
    private let hasTrailingNewline: Bool

    public init(text: String) {
        if text.isEmpty {
            lines = []
            hasTrailingNewline = false
            return
        }
        hasTrailingNewline = text.hasSuffix("\n")
        var split = text.components(separatedBy: "\n")
        if hasTrailingNewline { split.removeLast() }
        lines = split
    }

    public var text: String {
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
    }

    // MARK: - 読み取り

    /// 値の生テキスト（前後の空白を除いたもの）。存在しなければ nil。
    public func rawValue(at path: [String]) -> String? {
        guard let entry = index().keys.first(where: { $0.path == path }) else { return nil }
        return entry.valueText(in: lines).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func string(at path: [String]) -> String? {
        guard let raw = rawValue(at: path) else { return nil }
        return TOMLValueParser.string(from: raw)
    }

    public func bool(at path: [String]) -> Bool? {
        guard let raw = rawValue(at: path) else { return nil }
        switch raw {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    public func integer(at path: [String]) -> Int? {
        guard let raw = rawValue(at: path) else { return nil }
        return Int(raw.replacingOccurrences(of: "_", with: ""))
    }

    public func stringArray(at path: [String]) -> [String]? {
        guard let raw = rawValue(at: path) else { return nil }
        return TOMLValueParser.stringArray(from: raw)
    }

    /// `prefix` の直下に宣言されているテーブル名を、文書に現れる順で返す。
    /// 例: `["projects"]` → `["/Users/me/A", "/Users/me/B"]`
    public func subtableKeys(under prefix: [String]) -> [String] {
        index().tables.compactMap { table in
            guard table.path.count == prefix.count + 1,
                  Array(table.path.prefix(prefix.count)) == prefix else { return nil }
            return table.path.last
        }
    }

    /// 宣言されているテーブルかどうか。
    public func hasTable(_ path: [String]) -> Bool {
        index().tables.contains { $0.path == path }
    }

    // MARK: - 書き込み

    public mutating func setString(_ value: String, at path: [String]) {
        setRaw(TOMLValueParser.encodeString(value), at: path)
    }

    public mutating func setBool(_ value: Bool, at path: [String]) {
        setRaw(value ? "true" : "false", at: path)
    }

    public mutating func setInteger(_ value: Int, at path: [String]) {
        setRaw(String(value), at: path)
    }

    /// 値を生の TOML テキストとして代入する。既存キーがあればその行の値部分だけを差し替え、
    /// 無ければ所属テーブルの末尾へ1行足す（テーブルごと無ければ文書末尾に作る）。
    public mutating func setRaw(_ rawValue: String, at path: [String]) {
        guard let key = path.last else { return }
        let tablePath = Array(path.dropLast())

        if let entry = index().keys.first(where: { $0.path == path }) {
            let line = lines[entry.startLine]
            let head = String(line.prefix(entry.valueStartColumn))
            let trailing = entry.endLine == entry.startLine
                ? String(Array(line)[entry.valueEndColumn...])
                : ""
            let replacement = head + rawValue + trailing
            lines.replaceSubrange(entry.startLine...entry.endLine, with: [replacement])
            return
        }

        let newLine = "\(TOMLValueParser.encodeKey(key)) = \(rawValue)"
        if let table = index().tables.first(where: { $0.path == tablePath }) {
            lines.insert(newLine, at: insertionPoint(blockEnd: table.endLine, blockStart: table.headerLine))
        } else if tablePath.isEmpty {
            lines.insert(newLine, at: insertionPoint(blockEnd: rootBlockEnd(), blockStart: -1))
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append("[\(tablePath.map(TOMLValueParser.encodeKey).joined(separator: "."))]")
            lines.append(newLine)
        }
    }

    public mutating func removeKey(at path: [String]) {
        guard let entry = index().keys.first(where: { $0.path == path }) else { return }
        lines.removeSubrange(entry.startLine...entry.endLine)
    }

    /// テーブル見出しから次の見出し直前までを丸ごと消す（直前の空行も1つ巻き取る）。
    public mutating func removeTable(_ path: [String]) {
        guard let table = index().tables.first(where: { $0.path == path }) else { return }
        var start = table.headerLine
        if start > 0, lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            start -= 1
        }
        lines.removeSubrange(start...table.endLine)
    }

    // MARK: - 内部

    /// 新しいキー行を差し込む位置（ブロック末尾の空行より前）。
    private func insertionPoint(blockEnd: Int, blockStart: Int) -> Int {
        var insertAt = blockEnd + 1
        while insertAt - 1 > blockStart, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        return insertAt
    }

    /// ルートテーブル（最初のテーブル見出しより前）の最終行。見出しが無ければ文書末尾。
    private func rootBlockEnd() -> Int {
        if let first = index().tables.first { return first.headerLine - 1 }
        return lines.count - 1
    }

    private struct KeyEntry {
        let path: [String]
        let startLine: Int
        let endLine: Int
        /// 値テキストの開始位置（startLine 内の文字位置）。
        let valueStartColumn: Int
        /// 値テキストの終端の次の位置（endLine 内）。
        let valueEndColumn: Int

        func valueText(in lines: [String]) -> String {
            if startLine == endLine {
                let chars = Array(lines[startLine])
                guard valueStartColumn <= valueEndColumn, valueEndColumn <= chars.count else { return "" }
                return String(chars[valueStartColumn..<valueEndColumn])
            }
            var parts: [String] = [String(Array(lines[startLine])[valueStartColumn...])]
            if startLine + 1 <= endLine - 1 {
                parts.append(contentsOf: lines[(startLine + 1)...(endLine - 1)])
            }
            parts.append(String(Array(lines[endLine])[..<valueEndColumn]))
            return parts.joined(separator: "\n")
        }
    }

    private struct TableEntry {
        let path: [String]
        let headerLine: Int
        /// このテーブルに属する最後の行（次の見出しの直前）。
        let endLine: Int
    }

    private struct Index {
        let keys: [KeyEntry]
        let tables: [TableEntry]
    }

    private func index() -> Index {
        var keys: [KeyEntry] = []
        var tables: [TableEntry] = []
        var currentTable: [String] = []
        var pendingTableStart: Int?
        var pendingTablePath: [String] = []

        var i = 0
        while i < lines.count {
            let chars = Array(lines[i])
            var col = 0
            while col < chars.count, chars[col] == " " || chars[col] == "\t" { col += 1 }

            if col >= chars.count || chars[col] == "#" {
                i += 1
                continue
            }

            if chars[col] == "[" {
                if let start = pendingTableStart {
                    tables.append(TableEntry(path: pendingTablePath, headerLine: start, endLine: i - 1))
                }
                let isArrayOfTables = col + 1 < chars.count && chars[col + 1] == "["
                let headerStart = col + (isArrayOfTables ? 2 : 1)
                if let header = TOMLValueParser.keyPath(from: chars, start: headerStart, terminator: "]") {
                    currentTable = header.path
                    pendingTablePath = header.path
                    pendingTableStart = i
                }
                i += 1
                continue
            }

            guard let parsed = TOMLValueParser.keyPath(from: chars, start: col, terminator: "=") else {
                i += 1
                continue
            }
            var valueStart = parsed.end + 1
            while valueStart < chars.count, chars[valueStart] == " " || chars[valueStart] == "\t" { valueStart += 1 }
            let span = TOMLValueParser.scanValue(lines: lines, line: i, column: valueStart)
            keys.append(
                KeyEntry(
                    path: currentTable + parsed.path,
                    startLine: i,
                    endLine: span.line,
                    valueStartColumn: valueStart,
                    valueEndColumn: span.column
                )
            )
            i = span.line + 1
        }

        if let start = pendingTableStart {
            tables.append(TableEntry(path: pendingTablePath, headerLine: start, endLine: lines.count - 1))
        }
        return Index(keys: keys, tables: tables)
    }
}

/// TOML のキー・値テキストを扱う下請け。
enum TOMLValueParser {
    /// `key` / `"quoted key"` / `a.b."c"` を、終端文字（`=` か `]`）まで読む。
    static func keyPath(from chars: [Character], start: Int, terminator: Character) -> (path: [String], end: Int)? {
        var path: [String] = []
        var current = ""
        var i = start
        var sawContent = false

        while i < chars.count {
            let c = chars[i]
            if c == terminator {
                if !current.isEmpty || sawContent {
                    path.append(current)
                }
                return path.isEmpty ? nil : (path, i)
            }
            switch c {
            case " ", "\t":
                i += 1
            case ".":
                path.append(current)
                current = ""
                sawContent = false
                i += 1
            case "\"":
                guard let quoted = readQuoted(chars, from: i, quote: "\"", allowEscapes: true) else { return nil }
                current += quoted.value
                sawContent = true
                i = quoted.end
            case "'":
                guard let quoted = readQuoted(chars, from: i, quote: "'", allowEscapes: false) else { return nil }
                current += quoted.value
                sawContent = true
                i = quoted.end
            default:
                guard c.isLetter || c.isNumber || c == "_" || c == "-" else { return nil }
                current.append(c)
                sawContent = true
                i += 1
            }
        }
        return nil
    }

    private static func readQuoted(
        _ chars: [Character],
        from index: Int,
        quote: Character,
        allowEscapes: Bool
    ) -> (value: String, end: Int)? {
        var i = index + 1
        var value = ""
        while i < chars.count {
            let c = chars[i]
            if allowEscapes, c == "\\", i + 1 < chars.count {
                value.append(unescape(chars[i + 1]))
                i += 2
                continue
            }
            if c == quote { return (value, i + 1) }
            value.append(c)
            i += 1
        }
        return nil
    }

    private static func unescape(_ c: Character) -> Character {
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        default: return c
        }
    }

    /// 値の終端（複数行の配列・文字列を含む）を返す。
    static func scanValue(lines: [String], line: Int, column: Int) -> (line: Int, column: Int) {
        enum StringState { case none, basic, literal, multiBasic, multiLiteral }
        var state = StringState.none
        var depth = 0
        var i = line
        var col = column

        while i < lines.count {
            let chars = Array(lines[i])
            while col < chars.count {
                let c = chars[col]
                switch state {
                case .none:
                    if c == "#" {
                        if depth == 0 {
                            // 値の後ろのコメント。直前の空白は値に含めない。
                            var end = col
                            while end > column, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
                            return (i, end)
                        }
                        col = chars.count
                        continue
                    }
                    if c == "\"" {
                        if col + 2 < chars.count, chars[col + 1] == "\"", chars[col + 2] == "\"" {
                            state = .multiBasic
                            col += 3
                        } else {
                            state = .basic
                            col += 1
                        }
                        continue
                    }
                    if c == "'" {
                        if col + 2 < chars.count, chars[col + 1] == "'", chars[col + 2] == "'" {
                            state = .multiLiteral
                            col += 3
                        } else {
                            state = .literal
                            col += 1
                        }
                        continue
                    }
                    if c == "[" || c == "{" { depth += 1 }
                    if c == "]" || c == "}" { depth -= 1 }
                    col += 1
                case .basic:
                    if c == "\\" { col += 2; continue }
                    if c == "\"" { state = .none }
                    col += 1
                case .literal:
                    if c == "'" { state = .none }
                    col += 1
                case .multiBasic:
                    if c == "\\" { col += 2; continue }
                    if c == "\"", col + 2 < chars.count, chars[col + 1] == "\"", chars[col + 2] == "\"" {
                        state = .none
                        col += 3
                        continue
                    }
                    col += 1
                case .multiLiteral:
                    if c == "'", col + 2 < chars.count, chars[col + 1] == "'", chars[col + 2] == "'" {
                        state = .none
                        col += 3
                        continue
                    }
                    col += 1
                }
            }
            if state == .none, depth <= 0 {
                return (i, chars.count)
            }
            i += 1
            col = 0
        }
        return (lines.count - 1, Array(lines[lines.count - 1]).count)
    }

    /// `"..."` / `'...'` / 複数行文字列 から中身を取り出す。
    static func string(from raw: String) -> String? {
        let chars = Array(raw)
        guard let first = chars.first else { return nil }
        if raw.hasPrefix("\"\"\"") && raw.hasSuffix("\"\"\"") && raw.count >= 6 {
            return unescapeBasic(String(chars[3..<(chars.count - 3)]))
        }
        if raw.hasPrefix("'''") && raw.hasSuffix("'''") && raw.count >= 6 {
            return String(chars[3..<(chars.count - 3)])
        }
        if first == "\"", raw.hasSuffix("\""), raw.count >= 2 {
            return unescapeBasic(String(chars[1..<(chars.count - 1)]))
        }
        if first == "'", raw.hasSuffix("'"), raw.count >= 2 {
            return String(chars[1..<(chars.count - 1)])
        }
        return nil
    }

    private static func unescapeBasic(_ text: String) -> String {
        var result = ""
        var iterator = Array(text).makeIterator()
        while let c = iterator.next() {
            guard c == "\\", let next = iterator.next() else {
                result.append(c)
                continue
            }
            result.append(unescape(next))
        }
        return result
    }

    /// `["a", "b"]` を配列として読む（要素は文字列のみ対応）。
    static func stringArray(from raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let chars = Array(trimmed)
        var values: [String] = []
        var i = 1
        while i < chars.count - 1 {
            let c = chars[i]
            if c == "\"" || c == "'" {
                guard let quoted = readQuoted(chars, from: i, quote: c, allowEscapes: c == "\"") else { return nil }
                values.append(quoted.value)
                i = quoted.end
                continue
            }
            i += 1
        }
        return values
    }

    /// 文字列を基本文字列として書き出す。
    static func encodeString(_ value: String) -> String {
        var escaped = ""
        for c in value {
            switch c {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default: escaped.append(c)
            }
        }
        return "\"\(escaped)\""
    }

    /// キー1要素を書き出す。裸で書けない文字を含むならクォートする。
    static func encodeKey(_ key: String) -> String {
        let isBare = !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return isBare ? key : encodeString(key)
    }
}
