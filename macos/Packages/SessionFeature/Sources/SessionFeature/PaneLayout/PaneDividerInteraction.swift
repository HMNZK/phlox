import CoreGraphics

// DragGesture と `PaneDividerDragMachine` の間の薄いアダプタ。UI 非依存（CoreGraphics のみ）。
//
// ADR 0116 の性能防壁（ドラッグ中はレイアウトを確定しない）を **ビューの書き方に依存させない**
// ための型。`changed` は戻り値の型としては `PaneLayoutAction?` を返すが、実装は必ず nil を返す。
// ビューは「戻り値が非 nil のときだけ onLayoutAction を呼ぶ」と一様に書けばよく、
// ドラッグ中に確定させる経路を（誤って書こうとしても）作れない。
//
// もう1つの役割は軸の取り出し。SwiftUI の DragGesture が渡す translation は2次元だが、
// 分割線は片方の軸しか動かない。どちらの成分を使うか・軸ごとの最小ペイン長のどちらを使うかを
// ここに閉じ込め、ビューには軸の分岐を書かせない。
public struct PaneDividerInteraction: Equatable, Sendable {
    /// 左右分割（分割線は縦）のときに使う最小ペイン長。幅を制限する。
    private let minimumPaneWidth: CGFloat
    /// 上下分割（分割線は横）のときに使う最小ペイン長。高さを制限する。
    private let minimumPaneHeight: CGFloat
    private var machine = PaneDividerDragMachine()

    public init(minimumPaneWidth: CGFloat, minimumPaneHeight: CGFloat) {
        self.minimumPaneWidth = minimumPaneWidth
        self.minimumPaneHeight = minimumPaneHeight
    }

    /// ドラッグ中に描くゴースト。状態機械の値をそのまま見せる（写しを持つと両者がずれうるため）。
    public var ghost: PaneDividerGhost? { machine.ghost }

    /// ドラッグ開始。常に nil を返す。
    @discardableResult
    public mutating func began(_ frame: PaneDividerFrame) -> PaneLayoutAction? {
        machine.begin(frame, minimumPaneExtent: minimumPaneExtent(for: frame.axis))
        return nil
    }

    /// ドラッグ中。**常に nil を返す**（契約）。ゴーストだけが動く。
    @discardableResult
    public mutating func changed(_ frame: PaneDividerFrame, translation: CGSize) -> PaneLayoutAction? {
        // 状態機械の戻り値（.preview）は意図的に捨てる。ここから確定値は決して出さない。
        machine.changed(translation: axisComponent(of: translation, axis: frame.axis))
        return nil
    }

    /// ドラッグ終了。確定できるときだけ `.setDivider` を返す。
    /// 中断後・未開始のときは状態機械が `.idle` を返すので nil になる。
    @discardableResult
    public mutating func ended(_ frame: PaneDividerFrame, translation: CGSize) -> PaneLayoutAction? {
        guard case .commit(let divider, let fraction) = machine.ended(
            translation: axisComponent(of: translation, axis: frame.axis)
        ) else { return nil }
        return .setDivider(divider, leadingFraction: fraction)
    }

    /// 中断。nil を返し、ゴーストを消す。
    @discardableResult
    public mutating func cancelled() -> PaneLayoutAction? {
        machine.cancelled()
        return nil
    }

    /// 分割線のダブルクリック。掴んでいるかに依らず、その split を等分に戻す操作を返す。
    public func equalize(_ frame: PaneDividerFrame) -> PaneLayoutAction {
        .equalize(frame.id.split)
    }

    /// 軸ごとの最小ペイン長。横並び（.horizontal）は幅が、縦並び（.vertical）は高さが縮む。
    private func minimumPaneExtent(for axis: PaneAxis) -> CGFloat {
        switch axis {
        case .horizontal: return minimumPaneWidth
        case .vertical: return minimumPaneHeight
        }
    }

    /// 分割線が動ける軸の成分だけを取り出す（横分割は width、縦分割は height）。
    private func axisComponent(of translation: CGSize, axis: PaneAxis) -> CGFloat {
        switch axis {
        case .horizontal: return translation.width
        case .vertical: return translation.height
        }
    }
}
