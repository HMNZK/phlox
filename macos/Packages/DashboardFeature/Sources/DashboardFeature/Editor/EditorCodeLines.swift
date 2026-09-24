import Foundation

/// 変更の子タブの右側に出す 1 行（07 D2）。差分は行番号・記号・行全体の色で、内容は行番号つきで出す。
struct EditorCodeLine: Equatable {
    enum Kind: Equatable {
        case context
        case added
        case removed
        /// `@@ -a,b +c,d @@` の塊の見出し。
        case hunk
    }

    let number: Int?
    let text: String
    let kind: Kind
}

enum EditorCodeLines {
    /// git の unified diff を行に分ける。ファイルの見出し（diff --git・index・--- / +++ など）は出さない。
    /// 行番号は、追加と前後の行は新しいファイルの番号、削除は古いファイルの番号。
    static func diff(_ text: String) -> [EditorCodeLine] {
        var lines: [EditorCodeLine] = []
        var oldLine = 0
        var newLine = 0
        var inHunk = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                let (old, new) = hunkStarts(line)
                oldLine = old
                newLine = new
                inHunk = true
                lines.append(EditorCodeLine(number: nil, text: line, kind: .hunk))
                continue
            }
            guard inHunk else { continue }
            if line.hasPrefix("+") {
                lines.append(EditorCodeLine(number: newLine, text: String(line.dropFirst()), kind: .added))
                newLine += 1
            } else if line.hasPrefix("-") {
                lines.append(EditorCodeLine(number: oldLine, text: String(line.dropFirst()), kind: .removed))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                lines.append(EditorCodeLine(number: newLine, text: String(line.dropFirst()), kind: .context))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                // 「\ No newline at end of file」は番号なしで残す。
                lines.append(EditorCodeLine(number: nil, text: line, kind: .context))
            } else if line.hasPrefix("diff --git") {
                inHunk = false
            }
        }
        // 権限だけの変更・名前の変更など塊の無い差分は、git の見出しをそのまま出す（空の欄にしない）。
        if lines.isEmpty {
            return text.split(separator: "\n").map { EditorCodeLine(number: nil, text: String($0), kind: .context) }
        }
        return lines
    }

    /// ファイルの内容を 1 から番号を振った行にする。
    static func content(_ text: String) -> [EditorCodeLine] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines.enumerated().map { EditorCodeLine(number: $0.offset + 1, text: $0.element, kind: .context) }
    }

    /// 先頭 `limit` 行より後ろに残る、塊の数と（見出しを除いた）行の数。
    static func remainder(of lines: [EditorCodeLine], after limit: Int) -> (hunks: Int, lines: Int) {
        guard lines.count > limit else { return (0, 0) }
        let rest = lines[limit...]
        var hunks = rest.filter { $0.kind == .hunk }.count
        if let first = rest.first, first.kind != .hunk, lines[..<limit].contains(where: { $0.kind == .hunk }) {
            hunks += 1
        }
        return (hunks, rest.filter { $0.kind != .hunk }.count)
    }

    private static func hunkStarts(_ header: String) -> (old: Int, new: Int) {
        // "@@ -12,7 +12,9 @@ func …"
        let parts = header.split(separator: " ")
        func start(_ prefix: Character) -> Int {
            guard let part = parts.first(where: { $0.first == prefix }) else { return 1 }
            return Int(part.dropFirst().split(separator: ",").first ?? "") ?? 1
        }
        return (start("-"), start("+"))
    }
}
