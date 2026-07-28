import Foundation

/// 1つの装飾で続く文字の塊。
public struct AnsiRun: Sendable, Equatable {
    public let text: String
    public let style: AnsiStyle

    public init(text: String, style: AnsiStyle) {
        self.text = text
        self.style = style
    }
}

/// SGR で表せる装飾。色はパレット解決済みの RGB で持つ。
public struct AnsiStyle: Sendable, Equatable {
    public var foreground: TerminalScreenPalette.Channel?
    public var background: TerminalScreenPalette.Channel?
    public var isBold = false
    public var isDim = false
    public var isItalic = false
    public var isUnderlined = false
    public var isStruckThrough = false
    public var isInverse = false

    public init() {}
}

/// Mac が配信する端末画面（SGR 付きテキスト）を、装飾ごとの塊へ分解する。
///
/// Mac 側 `AnsiScreenEncoder` が書き出すのは **SGR と本文と改行だけ**で、カーソル移動も
/// 画面消去もスクロールも含まない。つまり受け手に端末エミュレータ（＝固定行数の格子と
/// スクロールバック）は要らない。ここで装飾付きの文字列へ直せば描画はただのテキストになり、
/// 高さは中身が決める。格子に収まらない行が黙ってスクロールバックへ消える事故が原理的に起きない。
public enum AnsiTextParser {
    /// 1行ぶんの塊の並び。空行は空配列。
    public typealias Line = [AnsiRun]

    /// 行ごと・装飾ごとの塊へ分解する。本文は1文字も落とさない。
    ///
    /// 行で分けるのは、受け手が1行ずつ遅延描画できるようにするため。数千行の履歴を
    /// 1つのテキストとして組むと、画面外まで含めて毎回組み直すことになる。
    /// 装飾は行をまたいで持ち越す（端末の SGR は改行では戻らない）。
    public static func lines(of text: String, palette: TerminalScreenPalette) -> [Line] {
        guard !text.isEmpty else { return [] }
        var lines: [Line] = []
        var current: Line = []
        var style = AnsiStyle()
        var pending = ""
        var index = text.startIndex

        func flush() {
            guard !pending.isEmpty else { return }
            current.append(AnsiRun(text: pending, style: style))
            pending = ""
        }

        func endLine() {
            flush()
            lines.append(current)
            current = []
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "\n" {
                endLine()
                index = text.index(after: index)
                continue
            }
            guard character == "\u{1B}" else {
                pending.append(character)
                index = text.index(after: index)
                continue
            }
            let afterEscape = text.index(after: index)
            guard afterEscape < text.endIndex, text[afterEscape] == "[" else {
                // CSI 以外（単独 ESC・OSC 等）は描ける文字を持たないので落とす。
                index = afterEscape
                continue
            }
            let parametersStart = text.index(after: afterEscape)
            var scan = parametersStart
            while scan < text.endIndex, !text[scan].isLetter {
                scan = text.index(after: scan)
            }
            guard scan < text.endIndex else { break }
            if text[scan] == "m" {
                flush()
                style = applying(parameters: text[parametersStart..<scan], to: style, palette: palette)
            }
            // SGR 以外の CSI（カーソル表示切替など）は装飾でも本文でもないので読み飛ばす。
            index = text.index(after: scan)
        }
        endLine()
        return lines
    }

    private static func applying(
        parameters: Substring,
        to style: AnsiStyle,
        palette: TerminalScreenPalette
    ) -> AnsiStyle {
        // `?` 付きは私的パラメータで SGR ではない。装飾として解釈すると色が化ける。
        guard !parameters.contains("?") else { return style }
        let codes = parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        // `ESC[m` は `ESC[0m` と同じ（リセット）。
        guard !codes.isEmpty else { return AnsiStyle() }

        var style = style
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = AnsiStyle()
            case 1: style.isBold = true
            case 2: style.isDim = true
            case 3: style.isItalic = true
            case 4: style.isUnderlined = true
            case 7: style.isInverse = true
            case 9: style.isStruckThrough = true
            case 22:
                style.isBold = false
                style.isDim = false
            case 23: style.isItalic = false
            case 24: style.isUnderlined = false
            case 27: style.isInverse = false
            case 29: style.isStruckThrough = false
            case 30...37: style.foreground = palette.ansi[code - 30]
            case 39: style.foreground = nil
            case 40...47: style.background = palette.ansi[code - 40]
            case 49: style.background = nil
            case 90...97: style.foreground = palette.ansi[code - 90 + 8]
            case 100...107: style.background = palette.ansi[code - 100 + 8]
            case 38, 48:
                let extended = extendedColor(codes, from: index + 1, palette: palette)
                if code == 38 {
                    style.foreground = extended.color
                } else {
                    style.background = extended.color
                }
                index += extended.consumed
            default:
                // 未知の SGR は無視する（本文へ生の数字を漏らさない）。
                break
            }
            index += 1
        }
        return style
    }

    /// `38;5;n` / `38;2;r;g;b` 形式の色。消費したパラメータ数も返す。
    private static func extendedColor(
        _ codes: [Int],
        from index: Int,
        palette: TerminalScreenPalette
    ) -> (color: TerminalScreenPalette.Channel?, consumed: Int) {
        guard index < codes.count else { return (nil, 0) }
        switch codes[index] {
        case 5:
            guard index + 1 < codes.count else { return (nil, codes.count - index) }
            return (xterm256(codes[index + 1], palette: palette), 2)
        case 2:
            guard index + 3 < codes.count else { return (nil, codes.count - index) }
            return (
                TerminalScreenPalette.Channel(
                    channelValue(codes[index + 1]),
                    channelValue(codes[index + 2]),
                    channelValue(codes[index + 3])
                ),
                4
            )
        default:
            return (nil, 1)
        }
    }

    /// xterm 256 色。0〜15 はパレット、16〜231 は 6×6×6 の色立方体、232〜255 は無彩色の階段。
    static func xterm256(_ code: Int, palette: TerminalScreenPalette) -> TerminalScreenPalette.Channel? {
        switch code {
        case 0..<16:
            return palette.ansi[code]
        case 16..<232:
            let offset = code - 16
            let levels = [0, 95, 135, 175, 215, 255]
            return TerminalScreenPalette.Channel(
                levels[offset / 36],
                levels[(offset % 36) / 6],
                levels[offset % 6]
            )
        case 232..<256:
            let value = 8 + (code - 232) * 10
            return TerminalScreenPalette.Channel(value, value, value)
        default:
            return nil
        }
    }

    private static func channelValue(_ value: Int) -> Int {
        min(255, max(0, value))
    }
}
