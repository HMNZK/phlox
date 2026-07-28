import AppKit
import SwiftUI
import DesignSystem

/// 分割線の掴みしろ1本ぶん。ドラッグでゴーストを動かし、マウスアップで1回だけ確定する。
///
/// **`PaneLayoutView` の ZStack の最後の要素として置く前提**（`.overlay` では置かない）。
/// `.pty` タイルの中身は SwiftTerm の `NSView` で、AppKit のビューは SwiftUI のオーバーレイより
/// 前面に出るため、`.overlay` で重ねた掴みしろはタイルの境界でホバーもドラッグも受け取れない
/// （`DashboardView` の `ResizeGripView` が同じ理由で最前面のオーバーレイに置かれている）。
///
/// ドラッグ中に変わる状態を**この葉ビューの中だけ**に閉じ込めてあるのが要点（ADR 0116）。
/// ゴーストの位置は `PaneDividerInteraction`（= `@State`）にしか無いので、再評価されるのは
/// この 8pt 幅のビューだけで、タイルの body もタイルの矩形もドラッグ中は一切動かない。
struct PaneDividerHandleView: View {
    /// 掴みしろに出す発光バーの太さ（`ResizeGripView` と同じ手触りに揃える）。
    private static let barThickness: CGFloat = 3

    let divider: PaneDividerFrame
    let onLayoutAction: (PaneLayoutAction) -> Void

    @State private var interaction: PaneDividerInteraction
    @State private var isHovering = false
    @State private var isDragging = false

    init(
        divider: PaneDividerFrame,
        minimumPaneWidth: CGFloat,
        minimumPaneHeight: CGFloat,
        onLayoutAction: @escaping (PaneLayoutAction) -> Void
    ) {
        self.divider = divider
        self.onLayoutAction = onLayoutAction
        _interaction = State(
            initialValue: PaneDividerInteraction(
                minimumPaneWidth: minimumPaneWidth,
                minimumPaneHeight: minimumPaneHeight
            )
        )
    }

    var body: some View {
        ZStack {
            // 掴みしろ本体。透明でも contentShape でヒット領域を確保する。
            Rectangle()
                .fill(Color.clear)
            bar
            ghostBar
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        // ダブルクリックで等分に戻す。minimumDistance: 1 のドラッグとは競合しない。
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onLayoutAction(interaction.equalize(divider)) }
        )
        .onHover { hovering in
            // push / pop の対応が崩れると祖先のカーソルまで戻してしまうため、
            // 状態が実際に変わったときだけ操作する。
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                resizeCursor.push()
            } else {
                NSCursor.pop()
            }
        }
        // ホバー中にレイアウトが変わってこのハンドルが消えると、カーソルがリサイズのまま残る。
        .onDisappear {
            if isHovering {
                isHovering = false
                NSCursor.pop()
            }
        }
        .accessibilityLabel("分割線")
    }

    /// 掴めることを示す発光バー（隙間の中心）。ホバー中とドラッグ中だけ出す。
    private var bar: some View {
        let isHighlighted = isHovering || isDragging
        return RoundedRectangle(cornerRadius: Self.barThickness / 2, style: .continuous)
            .fill(DSColor.accent)
            .frame(
                width: divider.axis == .horizontal ? Self.barThickness : nil,
                height: divider.axis == .vertical ? Self.barThickness : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isHighlighted ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHighlighted)
            .allowsHitTesting(false)
    }

    /// ドラッグ中のゴースト。**これだけがドラッグ中に動く**（タイルの矩形は動かない）。
    @ViewBuilder
    private var ghostBar: some View {
        if let ghost = interaction.ghost {
            // ゴーストは bounds 座標系の絶対位置を持つので、掴みしろの中心との差分へ直す。
            let crossCenter = ghost.crossOrigin + ghost.crossExtent / 2
            RoundedRectangle(cornerRadius: Self.barThickness / 2, style: .continuous)
                .fill(DSColor.accent.opacity(0.7))
                .frame(
                    width: ghost.axis == .horizontal ? Self.barThickness : ghost.crossExtent,
                    height: ghost.axis == .vertical ? Self.barThickness : ghost.crossExtent
                )
                .offset(
                    x: (ghost.axis == .horizontal ? ghost.position : crossCenter) - divider.rect.midX,
                    y: (ghost.axis == .vertical ? ghost.position : crossCenter) - divider.rect.midY
                )
                .allowsHitTesting(false)
        }
    }

    private var dragGesture: some Gesture {
        // ADR 0116: onChanged では **onLayoutAction を呼ばない**（レイアウトを確定しない）。
        // 確定値は onEnded で PaneDividerInteraction が返したときだけ流す。
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if interaction.ghost == nil {
                    interaction.began(divider)
                    isDragging = true
                }
                interaction.changed(divider, translation: value.translation)
            }
            .onEnded { value in
                isDragging = false
                if let action = interaction.ended(divider, translation: value.translation) {
                    onLayoutAction(action)
                }
            }
    }

    private var resizeCursor: NSCursor {
        switch divider.axis {
        case .horizontal: return .resizeLeftRight
        case .vertical: return .resizeUpDown
        }
    }
}
