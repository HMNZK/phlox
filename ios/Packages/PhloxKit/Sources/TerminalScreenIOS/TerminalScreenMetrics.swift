import CoreGraphics
import Foundation

/// Mac の端末画面をモバイルの画面幅へ収めるための算数。UIKit へ依存しないのでホストで検証できる。
///
/// 方針は「横スクロールさせない」。Mac の桁数をそのまま描くと必ず画面からはみ出し、
/// 1行読むたびに横へ振らされる。まずフォントを縮めて Mac の桁数を収めにいき、
/// 読める下限まで縮めても収まらないときは**折り返す**（桁揃えより読めることを優先する）。
public enum TerminalScreenMetrics {
    /// これ以上小さくすると読めないフォントサイズ。
    public static let minimumFontSize: CGFloat = 7
    /// 折り返してでも確保する最低桁数。極端に狭い幅で1文字ずつ折り返すのを防ぐ。
    public static let minimumColumns = 20
    /// 行数の見積もりに上乗せする余白。全角判定を外して桁を少なく数えると折り返しが1行増え、
    /// 高さが足りないと端末が先頭をスクロールで捨ててしまう。多い分は末尾の空行で済む。
    public static let safetyRows = 1

    /// Mac の桁数を画面幅へ収めるフォントサイズ。収まらないときは下限で止める（＝折り返しになる）。
    ///
    /// - Parameters:
    ///   - columns: Mac 側の端末幅（桁）。
    ///   - availableWidth: 描画に使える幅。
    ///   - preferredFontSize: 収まるならこのサイズで描く（拡大はしない）。
    ///   - cellWidthAtPreferredSize: `preferredFontSize` での1桁の幅。
    public static func fittingFontSize(
        columns: Int,
        availableWidth: CGFloat,
        preferredFontSize: CGFloat,
        cellWidthAtPreferredSize: CGFloat
    ) -> CGFloat {
        guard columns > 0, availableWidth > 0, cellWidthAtPreferredSize > 0 else {
            return preferredFontSize
        }
        let requiredWidth = CGFloat(columns) * cellWidthAtPreferredSize
        guard requiredWidth > availableWidth else { return preferredFontSize }
        let scaled = preferredFontSize * (availableWidth / requiredWidth)
        return max(minimumFontSize, min(preferredFontSize, scaled))
    }

    /// 与えられた幅に収まる桁数。
    public static func columns(availableWidth: CGFloat, cellWidth: CGFloat) -> Int {
        guard availableWidth > 0, cellWidth > 0 else { return minimumColumns }
        return max(minimumColumns, Int(availableWidth / cellWidth))
    }

    /// 折り返した結果の行数。Mac の1行が桁数を超えていれば複数行になる。
    ///
    /// エスケープを除いたプレーンテキストで数える（SGR は幅を持たない）。
    public static func wrappedRowCount(plainText: String, columns: Int) -> Int {
        let columns = max(1, columns)
        let lines = plainText.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return 1 }
        return lines.reduce(0) { total, line in
            let width = displayWidth(of: line)
            return total + max(1, Int((width + columns - 1) / columns))
        }
    }

    /// 端末上での表示幅。全角は2桁を占める。
    ///
    /// 判定は主要な全角ブロックの近似で、外したときは幅を1と数える。多めに見積もる方向に
    /// 外れても余分な空行が1行出るだけだが、少なく見積もると末尾が切れて読めなくなる。
    public static func displayWidth(of text: some StringProtocol) -> Int {
        text.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }

    private static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x2FFFD:
            return true
        default:
            return false
        }
    }
}
