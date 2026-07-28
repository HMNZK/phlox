import CoreGraphics

// 分割線ドラッグの純粋な状態機械（D2 のゴースト方式）。
//
// ADR 0116 が実測で確定している——タイル幅が毎フレーム変わると transcript 全件が CoreText で
// 再 typeset され、メインスレッドが 470〜643ms 固まる。この型は「ドラッグ中はレイアウトを
// 確定しない」を機械的に担保する唯一の関所であり、確定値（比率）は `ended` からしか出てこない。
//
// 型による防壁:
//  - `PaneDividerGhost` は**比率を一切持たない**。持っているのは bounds 座標系の絶対位置だけで、
//    `PaneTree.settingDivider(_:leadingFraction:)` に渡せる値が構造的に取り出せない。
//    したがって `.preview` を受け取った呼び出し側は、たとえ誤用したくてもレイアウトを更新できない。
//  - 確定値を運ぶ `Output.commit` は `ended` の中でしか構築しない（`begin` / `changed` は
//    `.preview` か `.idle` のみを返す）。
//
// UI 非依存（Foundation / CoreGraphics のみ。SwiftUI / AppKit は import しない）。

/// ドラッグ中に描くゴースト線の情報。**レイアウトの確定値ではない**。
///
/// この型から比率を復元できないのは意図的な設計（上のコメント参照）。描画に必要な最小限だけを持つ。
public struct PaneDividerGhost: Equatable, Sendable {
    public let divider: PaneDividerID
    public let axis: PaneAxis
    /// ゴースト線の中心の**軸方向の絶対位置**（bounds 座標系, points）。クランプ済み。
    public let position: CGFloat
    /// 軸に直交する方向の描画範囲（gapRect から引き継ぐ）。
    public let crossOrigin: CGFloat
    public let crossExtent: CGFloat
}

public struct PaneDividerDragMachine: Equatable, Sendable {
    public enum Output: Equatable, Sendable {
        case idle
        /// ドラッグ中。ゴーストだけを動かす。**この値からレイアウトを更新してはならない。**
        case preview(PaneDividerGhost)
        /// ドラッグ終了時に一度だけ発生する確定値。
        case commit(PaneDividerID, leadingFraction: Double)
    }

    /// `begin` で固定されるドラッグの基準。全プロパティが `let` で、`begin` 以外に代入する経路が
    /// 無いので「ドラッグ中に基準が動く」（不変条件3）は型として起こらない。`changed` は
    /// これを読んでゴーストを作り直すだけで、基準の作り直し（rebase）を行わない。
    private struct Anchor: Equatable, Sendable {
        let divider: PaneDividerID
        let axis: PaneAxis
        /// 隣接2枚が占める領域の軸方向の始点（bounds 座標系）。
        let segmentOrigin: CGFloat
        /// 隣接2枚の**タイル部分だけ**の軸方向の合計長。2枚の間の spacing は含まないので、
        /// `segmentExtent * fraction` がそのまま leading 側のペイン長になる（spacing を引かない）。
        let segmentExtent: CGFloat
        /// 掴んだ時点の、**隣接2枚の合計に対する** leading の取り分。
        let initialLeadingFraction: Double
        /// 軸方向のペイン最小長（points）。
        let minimumPaneExtent: CGFloat
        /// 隙間の軸方向の太さ。ゴーストの中心を隙間の中心に合わせるために使う。
        let gapThickness: CGFloat
        let crossOrigin: CGFloat
        let crossExtent: CGFloat

        init(frame: PaneDividerFrame, minimumPaneExtent: CGFloat) {
            divider = frame.id
            axis = frame.axis
            segmentOrigin = frame.segmentOrigin
            segmentExtent = frame.segmentExtent
            initialLeadingFraction = frame.leadingFraction
            self.minimumPaneExtent = max(0, minimumPaneExtent)
            switch frame.axis {
            case .horizontal:
                gapThickness = frame.gapRect.width
                crossOrigin = frame.gapRect.minY
                crossExtent = frame.gapRect.height
            case .vertical:
                gapThickness = frame.gapRect.height
                crossOrigin = frame.gapRect.minX
                crossExtent = frame.gapRect.width
            }
        }

        /// 開始点からの累積移動量 → クランプ済みの leading 比率。
        ///
        /// クランプは2段:
        ///  ① 両側のペイン長が `minimumPaneExtent` 以上（points → 比率へは
        ///     `minimumPaneExtent / segmentExtent` で変換する。**split 全体ではなく隣接2枚の合計**が
        ///     分母であることが要）。
        ///  ② `[PaneTree.minimumDividerFraction, 1 - PaneTree.minimumDividerFraction]`
        ///     （task-1 の `settingDivider` 側のクランプと矛盾しないように、ここでも同じ範囲へ収める）。
        /// 2つの区間は必ず 0.5 を含むので交わりが空になることはない。
        func leadingFraction(translation: CGFloat) -> Double {
            // 隣接2枚が両方とも最小長を取れないなら、どちらにも寄せず等分に倒す。
            // `segmentExtent <= 0`（レイアウト確定前の 0 サイズなど）もここに入るため、以降で 0 除算は起きない。
            guard segmentExtent > 0, segmentExtent >= minimumPaneExtent * 2 else { return 0.5 }

            let minimumFraction = Double(minimumPaneExtent / segmentExtent)
            let lower = max(minimumFraction, PaneTree.minimumDividerFraction)
            let upper = min(1 - minimumFraction, 1 - PaneTree.minimumDividerFraction)

            let raw = initialLeadingFraction + Double(translation) / Double(segmentExtent)
            // NaN は比較が全て false になりクランプをすり抜けるので、明示的に等分へ倒す。
            guard !raw.isNaN else { return 0.5 }
            return min(max(raw, lower), upper)
        }

        /// ゴーストの位置も**クランプ後の比率**から作る（指と一緒に無限に飛ばない）。
        /// `leadingFraction(translation:)` を共有するので、preview と commit がずれる余地が無い。
        func ghost(translation: CGFloat) -> PaneDividerGhost {
            PaneDividerGhost(
                divider: divider,
                axis: axis,
                position: segmentOrigin
                    + segmentExtent * CGFloat(leadingFraction(translation: translation))
                    + gapThickness / 2,
                crossOrigin: crossOrigin,
                crossExtent: crossExtent
            )
        }
    }

    private var anchor: Anchor?

    public private(set) var ghost: PaneDividerGhost?

    public init() {}

    /// ドラッグ開始。frame は task-1 の `PaneDividerFrame`。
    /// minimumPaneExtent は軸方向のペイン最小長（points）。
    @discardableResult
    public mutating func begin(_ frame: PaneDividerFrame, minimumPaneExtent: CGFloat) -> Output {
        let anchor = Anchor(frame: frame, minimumPaneExtent: minimumPaneExtent)
        let ghost = anchor.ghost(translation: 0)
        self.anchor = anchor
        self.ghost = ghost
        return .preview(ghost)
    }

    /// ドラッグ中。translation は開始点からの軸方向の移動量（points）。
    /// **必ず .preview か .idle を返す。.commit は返さない。**
    @discardableResult
    public mutating func changed(translation: CGFloat) -> Output {
        guard let anchor else { return .idle }
        let ghost = anchor.ghost(translation: translation)
        self.ghost = ghost
        return .preview(ghost)
    }

    /// ドラッグ終了。直前の preview と同じ比率で **一度だけ** .commit を返し、状態を空にする。
    ///
    /// `DragGesture.onEnded` は `onChanged` の最終値と同じとは限らない値を渡すため、
    /// 受け取った translation で計算し直す（同じ translation なら preview と一致する）。
    @discardableResult
    public mutating func ended(translation: CGFloat) -> Output {
        guard let anchor else { return .idle }
        let fraction = anchor.leadingFraction(translation: translation)
        self.anchor = nil
        ghost = nil
        return .commit(anchor.divider, leadingFraction: fraction)
    }

    /// 中断（Esc・ドラッグキャンセル）。.idle を返し、確定しない。
    @discardableResult
    public mutating func cancelled() -> Output {
        anchor = nil
        ghost = nil
        return .idle
    }
}
