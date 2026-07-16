@preconcurrency import SwiftTerm
import Foundation

/// SwiftTerm の viewport 全 cell の状態をデバッグ用に snapshot して文字列化する。
/// Vendor/SwiftTerm を改変せず、Terminal の public API (getCharData / getCharacter / cols / rows /
/// getCursorLocation) だけで完結する。
///
/// 用途: Cursor の起動時ロゴ崩れの原因切り分け (背景属性残留 / inverse 残留 / 描画 invalidation 漏れ)。
/// 通常運用では発火しない (AgentLaunchProfile.debugDump = false が既定)。
public enum TerminalDump {
    /// 1 つの cell の観測値。row/col は 0-based、viewport 内座標。
    public struct CellSnapshot: Sendable {
        public let row: Int
        public let col: Int
        public let character: Character
        public let fgDescription: String
        public let bgDescription: String
        public let styleDescription: String
    }

    /// viewport 全 cell を走査して snapshot を作る。空 cell も含める (背景属性残留を見逃さないため)。
    @MainActor
    public static func snapshot(_ terminal: Terminal) -> [CellSnapshot] {
        let cols = terminal.cols
        let rows = terminal.rows
        var result: [CellSnapshot] = []
        result.reserveCapacity(cols * rows)

        for row in 0..<rows {
            for col in 0..<cols {
                if let charData = terminal.getCharData(col: col, row: row) {
                    let character = displayCharacter(terminal.getCharacter(col: col, row: row))
                    result.append(
                        CellSnapshot(
                            row: row,
                            col: col,
                            character: character,
                            fgDescription: describe(color: charData.attribute.fg, defaultLabel: "defFG"),
                            bgDescription: describe(color: charData.attribute.bg, defaultLabel: "defBG"),
                            styleDescription: describe(style: charData.attribute.style)
                        )
                    )
                } else {
                    result.append(
                        CellSnapshot(
                            row: row,
                            col: col,
                            character: " ",
                            fgDescription: "defFG",
                            bgDescription: "defBG",
                            styleDescription: "[]"
                        )
                    )
                }
            }
        }
        return result
    }

    /// 既定の dump 出力先 (~/Library/Logs/Phlox)。
    public static var defaultOutputDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Phlox", isDirectory: true)
    }

    /// snapshot を整形して `directory` 配下の terminal-dump-{sessionLabel}-{label}.txt へ書き込む。
    /// ディレクトリは必要なら作成する。戻り値は書き込んだファイルの URL。
    @discardableResult
    public static func write(
        _ cells: [CellSnapshot],
        cols: Int,
        rows: Int,
        cursor: (x: Int, y: Int),
        sessionLabel: String,
        label: String,
        ptyWinsize: (cols: Int, rows: Int)? = nil,
        to directory: URL
    ) throws -> URL {
        let body = format(
            cells,
            cols: cols,
            rows: rows,
            cursor: cursor,
            label: label,
            ptyWinsize: ptyWinsize
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("terminal-dump-\(sessionLabel)-\(label).txt")
        try Data(body.utf8).write(to: file, options: .atomic)
        return file
    }

    /// snapshot を 1 行 1 cell 形式で文字列化する。
    /// row サマリ行 (nonBlank 数 + 行全体の SGR 風表記) を行末に挿入。
    public static func format(
        _ cells: [CellSnapshot],
        cols: Int,
        rows: Int,
        cursor: (x: Int, y: Int),
        label: String,
        ptyWinsize: (cols: Int, rows: Int)? = nil
    ) -> String {
        var lines: [String] = []
        var header = "# label=\(label) cols=\(cols) rows=\(rows) cursor=(\(cursor.x),\(cursor.y)) cells=\(cells.count)"
        if let pty = ptyWinsize {
            let mismatch = (pty.cols != cols || pty.rows != rows) ? "Y" : "N"
            header += " ptyCols=\(pty.cols) ptyRows=\(pty.rows) MISMATCH=\(mismatch)"
        }
        lines.append(header)
        lines.append("")

        for row in 0..<rows {
            var nonBlank = 0
            for col in 0..<cols {
                let index = row * cols + col
                guard index < cells.count else { continue }
                let cell = cells[index]
                if cell.character != " " {
                    nonBlank += 1
                }
                lines.append(
                    "r\(String(format: "%02d", row)) c\(String(format: "%02d", col)) " +
                    "'\(charLiteral(cell.character))' fg=\(cell.fgDescription) " +
                    "bg=\(cell.bgDescription) style=\(cell.styleDescription)"
                )
            }
            let cursorOnRow = cursor.y == row ? "Y" : "N"
            lines.append("--- row\(row) nonBlank=\(nonBlank) cursor=\(cursorOnRow)")
        }

        return lines.joined(separator: "\n")
    }

    /// NUL 文字・全ゼロスカラーを空白に正規化する。
    /// TerminalCoordinator.visibleText() と dump の出力を一致させるため、実装はここに一本化する
    /// （食い違うと dump と画面の突合による描画バグの切り分けを誤らせる）。
    static func displayCharacter(_ character: Character?) -> Character {
        guard let character else { return " " }
        if character == "\0" {
            return " "
        }
        if character.unicodeScalars.allSatisfy({ $0.value == 0 }) {
            return " "
        }
        return character
    }

    // MARK: - private helpers

    private static func charLiteral(_ character: Character) -> String {
        switch character {
        case " ": return " "
        case "'": return "\\'"
        case "\\": return "\\\\"
        default: return String(character)
        }
    }

    private static func describe(color: Attribute.Color, defaultLabel: String) -> String {
        switch color {
        case .defaultColor:
            return defaultLabel
        case .defaultInvertedColor:
            return defaultLabel == "defFG" ? "defInvFG" : "defInvBG"
        case .ansi256(let code):
            return "ansi(\(code))"
        case .trueColor(let red, let green, let blue):
            return "tc(\(red),\(green),\(blue))"
        }
    }

    private static func describe(style: CharacterStyle) -> String {
        var flags: [String] = []
        if style.contains(.inverse) { flags.append("inverse") }
        if style.contains(.bold) { flags.append("bold") }
        if style.contains(.dim) { flags.append("dim") }
        if style.contains(.underline) { flags.append("underline") }
        if style.contains(.blink) { flags.append("blink") }
        if style.contains(.invisible) { flags.append("invisible") }
        if style.contains(.italic) { flags.append("italic") }
        if style.contains(.crossedOut) { flags.append("crossedOut") }
        return "[\(flags.joined(separator: ","))]"
    }
}
