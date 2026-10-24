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

    /// 今のレイアウトの名前（表示言語で引いたもの）と、そのあと手で崩したか（06「（調整済み）」）。
    let currentName: String
    let isAdjusted: Bool
    let onSelect: (PaneLayoutPreset) -> Void
    let onAutomatic: () -> Void
    let onUndoAutomatic: () -> Void
    let canUndoAutomatic: Bool
    @Environment(\.locale) private var locale

    init(currentName: String = "", isAdjusted: Bool = false, canUndoAutomatic: Bool = false, onAutomatic: @escaping () -> Void = {}, onUndoAutomatic: @escaping () -> Void = {}, onSelect: @escaping (PaneLayoutPreset) -> Void) {
        self.currentName = currentName
        self.isAdjusted = isAdjusted
        self.onSelect = onSelect
        self.onAutomatic = onAutomatic
        self.onUndoAutomatic = onUndoAutomatic
        self.canUndoAutomatic = canUndoAutomatic
    }

    var body: some View {
        Menu {
            Button("自動整列に戻す", action: onAutomatic)
                .accessibilityIdentifier("grid-layout-automatic")
            Button("直前のカスタムに戻す", action: onUndoAutomatic)
                .disabled(!canUndoAutomatic)
                .accessibilityIdentifier("grid-layout-restore-custom")
            Divider()
            ForEach(Self.items, id: \.self) { preset in
                Button(AppLocalizedString.string(preset.displayName, locale: locale)) {
                    onSelect(preset)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("レイアウト: \(isAdjusted ? String(format: AppLocalizedString.string("%@（調整済み）", locale: locale), currentName) : currentName)")
                Text(verbatim: "▾").font(.system(size: 9)).opacity(0.7)
            }
            .font(DSFont.auxiliary)
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("grid-layout-menu")
        .help("レイアウトを選択")
    }
}
