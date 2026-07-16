import CoreGraphics

/// iOS タッチターゲットのトークン。生値 `44` の直書きを排除する。
public enum DSTouch {
    /// HIG が定める最小タッチターゲット（44×44pt）。全インタラクティブ部品の下限。
    public static let minSize: CGFloat = 44
    /// 行などタップ領域を広げる際の最小行高。
    public static let rowMinHeight: CGFloat = 56
}
