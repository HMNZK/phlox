import Foundation

/// Mac から受け取った端末画面のスナップショット。
///
/// `cols` が入っているときだけ「Mac の端末をそのまま描き直せる ANSI（SGR 付き）」で、
/// それ以外は従来どおり色を落としたプレーンテキスト。端末を持たない構造化セッションでは
/// Mac 側が後者へ落とすため、受け手はこの区別で描画方法を選ぶ。
public struct TerminalScreen: Sendable, Equatable {
    /// 画面本文。ANSI のときは SGR エスケープを含む。
    public let text: String
    /// Mac 側の端末幅（桁）。この桁数より狭く描くと折り返し位置がずれる。
    public let cols: Int?

    public init(text: String, cols: Int?) {
        self.text = text
        self.cols = cols
    }

    /// 端末として描き直せるか。桁数が分からないものは折り返しを再現できないので false。
    public var isANSI: Bool { cols != nil }

    public static let empty = TerminalScreen(text: "", cols: nil)

    /// エスケープシーケンスを取り除いた本文。行数の判定・空判定・読み上げに使う。
    public var plainText: String { Self.strippingEscapes(from: text) }

    /// CSI（`ESC [ … 終端文字`）を丸ごと落とす。SGR だけを狙い撃ちにすると、
    /// 将来カーソル移動などが混ざったときに生の記号が本文へ漏れる。
    static func strippingEscapes(from text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.startIndex

        while iterator < text.endIndex {
            let character = text[iterator]
            guard character == "\u{1B}" else {
                result.append(character)
                iterator = text.index(after: iterator)
                continue
            }
            let afterEscape = text.index(after: iterator)
            guard afterEscape < text.endIndex, text[afterEscape] == "[" else {
                // CSI ではない（単独 ESC 等）。読める文字ではないので落とす。
                iterator = afterEscape
                continue
            }
            var scan = text.index(after: afterEscape)
            while scan < text.endIndex, !text[scan].isLetter {
                scan = text.index(after: scan)
            }
            iterator = scan < text.endIndex ? text.index(after: scan) : text.endIndex
        }
        return result
    }
}
