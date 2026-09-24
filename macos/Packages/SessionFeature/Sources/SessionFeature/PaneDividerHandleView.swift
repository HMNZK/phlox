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
        // 発光バーの表示にだけ使う。カーソル形状は下のモディファイアが受け持つ。
        .onHover { hovering in
            isHovering = hovering
        }
        .paneDividerResizeCursor(axis: divider.axis)
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
            // 動かし先は 2pt の破線（元の位置の 3pt の棒と見分ける。PhloxGrid の S9）。
            PaneDividerGhostLine(isVertical: ghost.axis == .horizontal)
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(
                    width: ghost.axis == .horizontal ? 2 : ghost.crossExtent,
                    height: ghost.axis == .vertical ? 2 : ghost.crossExtent
                )
                .offset(
                    x: (ghost.axis == .horizontal ? ghost.position : crossCenter) - divider.rect.midX,
                    y: (ghost.axis == .vertical ? ghost.position : crossCenter) - divider.rect.midY
                )
                .allowsHitTesting(false)
            ghostLabel(ghost)
                .fixedSize()
                // 左上を線の脇に合わせる（ZStack の中心揃えのまま、はみ出させて置く）。
                .frame(width: 0, height: 0, alignment: .topLeading)
                .offset(
                    x: (ghost.axis == .horizontal ? ghost.position + 10 : crossCenter) - divider.rect.midX,
                    y: (ghost.axis == .vertical ? ghost.position + 10 : crossCenter) - divider.rect.midY
                )
                .allowsHitTesting(false)
        }
    }

    /// S9「⟷ 62% · 718pt ／ 最小 240 × 160pt ／ ダブルクリックで等分」。離すまでは確定しない。
    private func ghostLabel(_ ghost: PaneDividerGhost) -> some View {
        let gap = divider.axis == .horizontal ? divider.gapRect.width : divider.gapRect.height
        let leading = max(0, ghost.position - gap / 2 - divider.segmentOrigin)
        let percent = divider.segmentExtent > 0 ? Int((leading / divider.segmentExtent * 100).rounded()) : 0
        let arrow = divider.axis == .horizontal ? "⟷" : "↕"
        return Text("\(arrow) \(percent)% · \(Int(leading.rounded()))pt ／ 最小 \(Int(PaneLayoutView.minimumPaneWidth)) × \(Int(PaneLayoutView.minimumPaneHeight))pt ／ ダブルクリックで等分")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 6))
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

}

private extension View {
    /// 分割線の向きに合わせたリサイズカーソル。
    ///
    /// macOS 15+ は SwiftUI 管理の `.pointerStyle` を使う。`.onHover` の中で `NSCursor.push/pop` を
    /// 呼ぶ素直な実装は、mouseMoved のたびに arrow へ戻されてカーソルが定着しないという既知不具合が
    /// あり、このリポジトリでは既に `DesignSystem/Interaction.swift`（15〜35 行目）で同じ対処が
    /// 取られている。左右方向はその `dsColumnResizeCursor()` をそのまま使う。
    @ViewBuilder
    func paneDividerResizeCursor(axis: PaneAxis) -> some View {
        switch axis {
        case .horizontal:
            dsColumnResizeCursor()
        case .vertical:
            modifier(PaneRowResizeCursorModifier())
        }
    }
}

/// 上下リサイズ用。`DesignSystem` に同等のヘルパー（`dsRowResizeCursor()`）がまだ無いため、
/// `dsColumnResizeCursor()` と**同じ形**でここに置く（macOS 15+ は `.pointerStyle(.rowResize)`、
/// 14 は `NSCursor.resizeUpDown` の push/pop へフォールバック）。
/// 恒久的には `DesignSystem/Interaction.swift` へ移すのが筋だが、そこは本タスクの変更範囲外。
private struct PaneRowResizeCursorModifier: ViewModifier {
    @State private var isHovering = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.rowResize)
        } else {
            content
                .onHover { hovering in
                    // push / pop の対応が崩れると祖先のカーソルまで戻してしまうため、
                    // 状態が実際に変わったときだけ操作する。
                    guard hovering != isHovering else { return }
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                // ホバー中にレイアウトが変わってこのハンドルが消えると、カーソルが残る。
                .onDisappear {
                    if isHovering {
                        isHovering = false
                        NSCursor.pop()
                    }
                }
        }
    }
}

/// ゴーストの破線。枠の中心を通る 1 本の線。
private struct PaneDividerGhostLine: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
