@preconcurrency import Foundation
@preconcurrency import SwiftTerm

/// SwiftTerm の可視画面を SGR（色・装飾）付きテキストへ書き出す。
///
/// `TerminalCoordinator.visibleText()` は色と装飾を落としたプレーンテキストで、
/// 「端末画面のスクリーンショット」としては情報が欠けている。ここで書き出した文字列を
/// 別の端末エミュレータへ feed し直すと、同じ桁数で同じ見た目を再現できる。
/// モバイルはこれを受け取って SwiftTerm で描画する。
public enum AnsiScreenEncoder {
    /// 1回の応答へ載せる最大行数。SwiftTerm の既定スクロールバックは 500 行なので通常は
    /// これに届かない。設定が変わっても転送量と受け手の描画コストが青天井にならないための上限。
    public static let defaultMaxRows = 4000

    /// **スクロールバックを含むバッファ全体**を SGR 付きテキストへ書き出す。
    ///
    /// viewport だけを送ると、受け手は「Mac に今映っている画面」しか持てず、自分では
    /// 1行も遡れない（→ ADR 0127）。受け手が独立にスクロールできるよう履歴ごと渡す。
    ///
    /// - 属性が変わる境界でだけ SGR を挿入する（cell ごとに出すと数十倍に膨らむ）。
    /// - 行末の「既定属性の空白」は落とす。背景色の付いた空白は見た目に出るので残す。
    /// - 先頭と末尾の空行は落とす（バッファは未使用行を空行として持っている）。
    @MainActor
    public static func encode(_ terminal: Terminal, maxRows: Int = defaultMaxRows) -> String {
        let rows = terminal.scrollInvariantRowRange
        let start = max(rows.lowerBound, rows.upperBound - max(1, maxRows))
        var lines: [String] = []
        lines.reserveCapacity(rows.upperBound - start)

        for row in start..<rows.upperBound {
            lines.append(encodeRow(terminal, row: row))
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func encodeRow(_ terminal: Terminal, row: Int) -> String {
        guard let line = terminal.getScrollInvariantLine(row: row) else { return "" }
        var cells: [(character: Character, attribute: Attribute)] = []
        cells.reserveCapacity(terminal.cols)

        // 桁数を変えた後のスクロールバックは行ごとに長さが違う。短い方に合わせて読む。
        for col in 0..<min(terminal.cols, line.count) {
            let data = line[col]
            // 全角文字は2 cell を占め、続く cell は width 0 のダミー。ここで足すと1桁ずれる。
            if data.width == 0 { continue }
            cells.append((TerminalDump.displayCharacter(data.getCharacter()), data.attribute))
        }

        while let last = cells.last, isInvisibleFiller(last) {
            cells.removeLast()
        }
        guard !cells.isEmpty else { return "" }

        var result = ""
        var applied: Attribute?
        for cell in cells {
            if applied != cell.attribute {
                result += sgr(for: cell.attribute)
                applied = cell.attribute
            }
            result.append(cell.character)
        }
        return result + "\u{1b}[0m"
    }

    /// 落としても見た目が変わらない cell か。行末の詰め物を落として転送量を減らすために使う。
    /// 背景色・反転・下線が付いた空白は「見えている」ので落とさない。
    private static func isInvisibleFiller(_ cell: (character: Character, attribute: Attribute)) -> Bool {
        guard cell.character == " " else { return false }
        switch cell.attribute.bg {
        case .defaultColor, .defaultInvertedColor:
            break
        case .ansi256, .trueColor:
            return false
        }
        let style = cell.attribute.style
        return !style.contains(.inverse) && !style.contains(.underline)
    }

    /// 属性1つ分の SGR シーケンス。必ず 0（リセット）から積み直すので、直前の状態に依存しない。
    static func sgr(for attribute: Attribute) -> String {
        var codes = ["0"]
        let style = attribute.style
        if style.contains(.bold) { codes.append("1") }
        if style.contains(.dim) { codes.append("2") }
        if style.contains(.italic) { codes.append("3") }
        if style.contains(.underline) { codes.append("4") }
        if style.contains(.blink) { codes.append("5") }
        if style.contains(.inverse) { codes.append("7") }
        if style.contains(.invisible) { codes.append("8") }
        if style.contains(.crossedOut) { codes.append("9") }
        codes += colorCodes(attribute.fg, isForeground: true)
        codes += colorCodes(attribute.bg, isForeground: false)
        return "\u{1b}[" + codes.joined(separator: ";") + "m"
    }

    /// 既定色は「指定しない」で表す。受け手のテーマの既定色がそのまま効く。
    private static func colorCodes(_ color: Attribute.Color, isForeground: Bool) -> [String] {
        switch color {
        case .defaultColor, .defaultInvertedColor:
            return []
        case .ansi256(let code) where code < 8:
            return ["\(Int(code) + (isForeground ? 30 : 40))"]
        case .ansi256(let code) where code < 16:
            return ["\(Int(code) - 8 + (isForeground ? 90 : 100))"]
        case .ansi256(let code):
            return [isForeground ? "38" : "48", "5", "\(code)"]
        case .trueColor(let red, let green, let blue):
            return [isForeground ? "38" : "48", "2", "\(red)", "\(green)", "\(blue)"]
        }
    }
}
