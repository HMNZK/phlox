import CoreGraphics

/// 「履歴から再開」カード（`ChatHistoryStartView`）の配置制約（task-1）。
/// フローティング composer（実測高 `composerHeight`）とカードが重ならないための純関数。
///
/// 契約（tasks/task-1.md / AcceptanceChatHistoryLayoutTests）:
/// - `maxCardHeight` = availableHeight − composerHeight − 56（外側余白 24×2 ＋隙間 8）を
///   [120, 360] にクランプ（360 は現行カードの上限を継承、120 は操作可能な下限）。
/// - `bottomInset` = composerHeight（カードのセンタリング領域を composer の上に制限する）。
enum ChatHistoryStartLayout {
    static let minCardHeight: CGFloat = 120
    static let maxCardHeightCap: CGFloat = 360
    /// 外側余白（24×2）＋カードと composer の隙間（8）。
    static let verticalReserve: CGFloat = 56

    static func maxCardHeight(availableHeight: CGFloat, composerHeight: CGFloat) -> CGFloat {
        let raw = availableHeight - composerHeight - verticalReserve
        return min(max(raw, minCardHeight), maxCardHeightCap)
    }

    static func bottomInset(composerHeight: CGFloat) -> CGFloat {
        composerHeight
    }
}
