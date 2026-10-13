#if os(macOS)
import SwiftUI

// 選択肢の一覧を出すポップアップ共通の見た目（ADR 0190）。

public extension View {
    /// 一覧ポップアップの行の強調。ホバーとキーボードの選択で同じ `selectionFill`。文字色は変えない。
    func dsPopupRowHighlight(_ isHighlighted: Bool) -> some View {
        background(
            isHighlighted ? DSColor.selectionFill : .clear,
            in: RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
        )
    }

    /// 自前で浮かせる一覧ポップアップの外枠（面・0.5pt の縁・影）。システムの `.popover` に載せるものは原則面だけ塗る（例外は ADR 0190）。
    func dsPopupSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.attention, style: .continuous)
        return background(DSColor.popoverBackground, in: shape)
            .overlay(shape.strokeBorder(DSColor.popoverEdge, lineWidth: 0.5))
            .dsShadow(.popover)
    }
}
#endif
