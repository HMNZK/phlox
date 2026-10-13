#if os(macOS)
import SwiftUI

/// 左右のサイドバーの開閉枠。幅を 0 まで縮めて端から出し入れし、閉じている間は操作・読み上げの対象から外す。
/// 動きは親で `.dsPaneAnimation(value:)` を付けて揃える（左右で動きを変えない。2026-10-13 ユーザー指示）。
/// `unloadsWhenClosed` なら、閉じる動きが終わった後に中身を外す（閉じている間に読み込みを走らせない）。
public struct DSSidePane<Content: View>: View {
    public enum Edge: Sendable { case leading, trailing }

    private let edge: Edge
    private let isOpen: Bool
    private let width: CGFloat
    private let unloadsWhenClosed: Bool
    private let content: Content
    @State private var showsContent: Bool

    public init(edge: Edge, isOpen: Bool, width: CGFloat, unloadsWhenClosed: Bool = false, @ViewBuilder content: () -> Content) {
        self.edge = edge
        self.isOpen = isOpen
        self.width = width
        self.unloadsWhenClosed = unloadsWhenClosed
        self.content = content()
        _showsContent = State(initialValue: isOpen || !unloadsWhenClosed)
    }

    public var body: some View {
        HStack(spacing: 0) {
            if edge == .trailing { separator }
            Group { if showsContent || isOpen { content } }.frame(width: width)
            if edge == .leading { separator }
        }
        // 中央側の端を固定して縮めるので、画面の外側へ滑って消える。
        .frame(width: isOpen ? width + DSLayout.paneSeparatorWidth : 0, alignment: edge == .leading ? .trailing : .leading)
        .clipped()
        .disabled(!isOpen)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .task(id: isOpen) {
            guard unloadsWhenClosed else { return }
            if isOpen { showsContent = true; return }
            // ponytail: 閉じる動き（DSAnimation.pane の 0.18 秒）より長く待ってから外す。動きの長さを変えたらここも見直す。
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { showsContent = false }
        }
    }

    private var separator: some View {
        Rectangle().fill(DSColor.separator).frame(width: DSLayout.paneSeparatorWidth)
    }
}

private struct DSPaneAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : DSAnimation.pane, value: value)
    }
}

extension View {
    /// サイドバー・インスペクタの開閉に共通の動き。動きを減らす設定では動かさない。
    public func dsPaneAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(DSPaneAnimation(value: value))
    }
}
#endif
