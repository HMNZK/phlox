#if os(macOS)
import SwiftUI

/// 左右のサイドバーの開閉枠。最終割当幅と内部スライドを分け、閉じている間は操作・読み上げの対象から外す。
/// 親の HStack に `.dsPaneLayoutBoundary()`、その外側に `.dsPaneAnimation(value:)` を付けて左右の動きを揃える。
/// `unloadsWhenClosed` なら、閉じる動きが終わった後に中身を外す（閉じている間に読み込みを走らせない）。
public struct DSSidePane<Content: View>: View {
    public enum Edge: Sendable { case leading, trailing }

    private let edge: Edge
    private let isOpen: Bool
    private let width: CGFloat
    private let unloadsWhenClosed: Bool
    private let content: Content
    @State private var showsContent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .modifier(DSPanePresentation(leading: edge == .leading, requestedOpen: isOpen,
                                     width: width + DSLayout.paneSeparatorWidth,
                                     progress: isOpen ? 1 : 0))
        .transaction(value: isOpen) { transaction in
            guard transaction[DSPaneChangeKey.self], !transaction.disablesAnimations else { return }
            transaction.animation = reduceMotion ? nil : DSAnimation.pane
            transaction[DSPaneChangeKey.self] = false
        }
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

/// 進入中は中央の割当を閉状態に保ち、スライド終点でだけ最終幅へ切り替える。
private struct DSPanePresentation: ViewModifier, Animatable {
    let leading: Bool
    let requestedOpen: Bool
    let width: CGFloat
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: (leading ? -1 : 1) * width * (1 - progress))
            .frame(width: width)
            .clipped()
            // 閉要求は即0。開要求は進行度の厳密な終点でだけ割当を返す。
            .frame(width: requestedOpen && progress == 1 ? width : 0,
                   alignment: leading ? .leading : .trailing)
            .zIndex(1)
    }
}

/// この印は開閉値が変わったtransactionにだけ付く。永続的な環境値にはしない。
struct DSPaneChangeKey: TransactionKey {
    static let defaultValue = false
}

private struct DSPaneAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : DSAnimation.pane, value: value)
            .transaction(value: value) { transaction in
                transaction[DSPaneChangeKey.self] = true
            }
    }
}

extension View {
    /// HStackの割当幅・配置に開閉の動きを継承させない。印は子ペインのスライド用に残す。
    /// 重ね表示のtransitionを外さないよう、overlayを付ける前のHStackに適用する。
    public func dsPaneLayoutBoundary() -> some View {
        transaction { transaction in
            if transaction[DSPaneChangeKey.self] { transaction.animation = nil }
        }
    }

    /// サイドバー・インスペクタの開閉に共通の動き。動きを減らす設定では動かさない。
    public func dsPaneAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(DSPaneAnimation(value: value))
    }
}
#endif
