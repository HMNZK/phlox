import SwiftUI
import DesignSystem
import SessionFeature

/// レイアウトプリセットを1クリックで選ぶメニュー。選択はコールバックで外へ出し、
/// 永続化・状態更新は呼び出し側（VM の `handlePaneLayoutAction(.applyPreset(_:))`）に任せる。
struct PaneLayoutPresetMenu: View {
    /// 表示順。ビューはこの配列を描くだけで、並びの決定はここに閉じる。
    static let items: [PaneLayoutPreset] = [
        .balanced,
        .single,
        .columns2,
        .columns3,
        .rows2,
        .rows3,
        .grid2x2,
        .mainLeftStackRight,
        .mainTopStackBottom
    ]

    let onSelect: (PaneLayoutPreset) -> Void

    init(onSelect: @escaping (PaneLayoutPreset) -> Void) {
        self.onSelect = onSelect
    }

    var body: some View {
        Menu {
            ForEach(Self.items, id: \.self) { preset in
                Button(preset.displayName) {
                    onSelect(preset)
                }
            }
        } label: {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
        .help("レイアウトを選択")
    }
}
