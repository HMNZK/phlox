import CoreGraphics

/// 上部トップバー（使用量メーター含む操作系オーバーレイ）に対する本文上余白の決定（task-2）。
/// オーバーレイは前面に浮くだけで高さを予約しないため、本文側が実測高から余白を確保する。
///
/// 契約（tasks/task-2.md / AcceptanceTopBarInsetTests）:
/// - `contentTopInset` = max(32, ceil(measuredOverlayHeight) + 8)。
///   32 は従来の固定余白（DSSpacing.xxl）を下限として維持、8 は DSSpacing.s の余裕。
public enum TopBarInsetPolicy {
    public static func contentTopInset(measuredOverlayHeight: CGFloat) -> CGFloat {
        max(32, ceil(measuredOverlayHeight) + 8)
    }
}
