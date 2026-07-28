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
}
