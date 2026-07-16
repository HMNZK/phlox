// このファイル全体は macOS 専用。`dsColumnResizeCursor()` は macOS 専用 extension に依存する。
// iOS 向け代替は作らない（YAGNI）。
#if os(macOS)
import SwiftUI

/// 縦の境界リサイズ用の掴みしろ。区切り線を中心に `gripWidth` の透明な当たり判定を持ち、
/// ホバー/ドラッグ中はアクセント色の発光バーを出して掴みしろを視認しやすくする。
/// 各インスタンスが自分の hover/drag state を持つため、複数を並べても相互に干渉しない
/// (view 単位の state を共有すると「片方をホバーすると両方光る」問題が起きるため切り出した)。
/// navigationShell 等の最前面オーバーレイとして区切り線の真上に重ねる前提。
public struct ResizeGripView: View {
    /// 掴みしろの幅(区切り線を中心に左右へ張り出す)。配置側の offset 計算と揃える。
    public static let gripWidth: CGFloat = 20

    let onChanged: (DragGesture.Value) -> Void
    let onEnded: () -> Void

    @State private var isHovered = false
    @State private var isResizing = false

    public init(
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping () -> Void
    ) {
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    public var body: some View {
        let highlighted = isHovered || isResizing
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.gripWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // 区切り線位置の発光バー(中央 3pt)。ホバー/ドラッグ中のみ表示する。
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(DSColor.accent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .shadow(color: DSColor.accent.opacity(0.9), radius: highlighted ? 5 : 0)
                    .opacity(highlighted ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: highlighted)
                    .allowsHitTesting(false)
            }
            .gesture(
                // ローカル座標だと区切り線自身の移動で translation の基準がズレてカクつくため、
                // グローバル座標で測る。
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        isResizing = true
                        onChanged(value)
                    }
                    .onEnded { _ in
                        isResizing = false
                        onEnded()
                    }
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .dsColumnResizeCursor()
    }
}
#endif
