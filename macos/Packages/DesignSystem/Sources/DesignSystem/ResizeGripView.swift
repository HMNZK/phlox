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
    /// 掴みしろの幅(区切り線を中心に左右へ張り出す)。配置側の offset 計算と揃える。01 E6: 見た目 1pt・当たり 8pt。
    public static let gripWidth: CGFloat = 8

    let hitWidth: CGFloat
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: () -> Void
    let onDoubleClick: (() -> Void)?

    @State private var isHovered = false
    @State private var isResizing = false

    /// - Parameter hitWidth: 当たり判定の幅。分割表示の区切りは `DSLayout.dividerHitWidth`（8pt）。
    public init(
        hitWidth: CGFloat = gripWidth,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping () -> Void,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.hitWidth = hitWidth
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onDoubleClick = onDoubleClick
    }

    public var body: some View {
        let highlighted = isHovered || isResizing
        Rectangle()
            .fill(Color.clear)
            .frame(width: hitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // 区切り線位置の accent 3pt（角丸 2）。ホバー/ドラッグ中のみ表示する。
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DSColor.accent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
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
            // 01 E6: ダブルクリックで既定の幅に戻す。
            .onTapGesture(count: 2) { onDoubleClick?() }
            .onHover { hovering in
                isHovered = hovering
            }
            .dsColumnResizeCursor()
    }
}
#endif
