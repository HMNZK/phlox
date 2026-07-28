import CoreGraphics
import AgentDomain

// 分割ツリー → 矩形。タイル矩形は隙間を含まない（現行 `sessionGridCellFrames` と同じ流儀）。

public struct PaneTileFrame: Equatable, Sendable {
    public let session: SessionID
    public let rect: CGRect

    public init(session: SessionID, rect: CGRect) {
        self.session = session
        self.rect = rect
    }
}

public struct PaneDividerFrame: Equatable, Sendable {
    public let id: PaneDividerID
    public let axis: PaneAxis
    /// 掴む領域。spacing が `dividerHitThickness` より細いときは、隙間の中心を保ったまま
    /// `dividerHitThickness` まで太らせる（掴めなくならないように）。
    public let rect: CGRect
    /// 実際の隙間（軸方向の太さ = spacing）。ゴースト線を描く基準に使う。
    public let gapRect: CGRect
    /// 隣接2枚の**タイル部分だけ**の軸方向の合計長（points）。2枚の間の spacing は含まない。
    public let segmentExtent: CGFloat
    /// 隣接2枚が占める領域の、軸方向の始点（bounds 座標系, points）。
    public let segmentOrigin: CGFloat
    /// **隣接2枚の合計に対する** leading 側の取り分（0〜1）。split 全体に対する比ではない。
    public let leadingFraction: Double

    public init(
        id: PaneDividerID,
        axis: PaneAxis,
        rect: CGRect,
        gapRect: CGRect,
        segmentExtent: CGFloat,
        segmentOrigin: CGFloat,
        leadingFraction: Double
    ) {
        self.id = id
        self.axis = axis
        self.rect = rect
        self.gapRect = gapRect
        self.segmentExtent = segmentExtent
        self.segmentOrigin = segmentOrigin
        self.leadingFraction = leadingFraction
    }
}

public struct PaneLayoutFrames: Equatable, Sendable {
    public let tiles: [PaneTileFrame]
    public let dividers: [PaneDividerFrame]

    public init(tiles: [PaneTileFrame], dividers: [PaneDividerFrame]) {
        self.tiles = tiles
        self.dividers = dividers
    }
}

extension PaneTree {
    /// 掴む領域の最低太さ（points）。spacing がこれより細くても分割線を掴めるようにする。
    public static let dividerHitThickness: CGFloat = 8

    /// タイル矩形と分割線矩形を同時に算出する。`tiles` の順序は `sessions` の走査順と一致する。
    public func frames(in bounds: CGSize, spacing: CGFloat) -> PaneLayoutFrames {
        guard let root else { return PaneLayoutFrames(tiles: [], dividers: []) }
        var tiles: [PaneTileFrame] = []
        var dividers: [PaneDividerFrame] = []
        PaneTree.layout(
            root,
            in: CGRect(origin: .zero, size: bounds),
            spacing: spacing,
            tiles: &tiles,
            dividers: &dividers
        )
        return PaneLayoutFrames(tiles: tiles, dividers: dividers)
    }

    private static func layout(
        _ node: PaneNode,
        in rect: CGRect,
        spacing: CGFloat,
        tiles: inout [PaneTileFrame],
        dividers: inout [PaneDividerFrame]
    ) {
        switch node {
        case .leaf(_, let session):
            tiles.append(PaneTileFrame(session: session, rect: rect))
        case .split(let split):
            let slices = childRects(split, in: rect, spacing: spacing)
            for index in 0..<(slices.count - 1) {
                dividers.append(
                    dividerFrame(
                        split: split,
                        index: index,
                        leadingRect: slices[index],
                        trailingRect: slices[index + 1],
                        in: rect
                    )
                )
            }
            // 子の順に降りるので、tiles は深さ優先の走査順（= `sessions` の順）で積まれる。
            for (child, childRect) in zip(split.children, slices) {
                layout(child, in: childRect, spacing: spacing, tiles: &tiles, dividers: &dividers)
            }
        }
    }

    /// 子の矩形を **累積座標 → 差分** で求める。
    ///
    /// 各子に独立して `length * weight` を適用すると丸め誤差が積もり、最後の子の端が領域の端と
    /// 1px ずれる（隙間・はみ出しとして目視される）。累積境界 `edge[i] = content * Σ_{j<i} w_j`
    /// を先に出し、`extent[i] = edge[i+1] - edge[i]` を取ると、末尾の境界を `content` に
    /// 固定できるので「最後の子の端 == 領域の端」が定義から厳密に成り立つ。
    /// 隣接する子の隙間も `(edge[i+1] + spacing*(i+1)) - (edge[i+1] + spacing*i) = spacing` で一定。
    private static func childRects(_ split: PaneSplit, in rect: CGRect, spacing: CGFloat) -> [CGRect] {
        let count = split.children.count
        let length = split.axis == .horizontal ? rect.width : rect.height
        // タイルに配れる長さ（隙間を除いた分）。領域より隙間の総和が大きい退化ケースでは 0。
        let content = max(0, length - spacing * CGFloat(count - 1))
        // 不変条件より weights は全て正なので total > 0。
        let total = split.weights.reduce(0, +)

        var edges: [CGFloat] = [0]
        edges.reserveCapacity(count + 1)
        var running = 0.0
        for index in 0..<count {
            running += split.weights[index]
            // 末尾は端に厳密に一致させる（誤差を最後の子へ吸わせない）。
            edges.append(index == count - 1 ? content : content * CGFloat(running / total))
        }

        return (0..<count).map { index in
            let start = edges[index] + spacing * CGFloat(index)
            let end = edges[index + 1] + spacing * CGFloat(index)
            switch split.axis {
            case .horizontal:
                return CGRect(x: rect.minX + start, y: rect.minY, width: end - start, height: rect.height)
            case .vertical:
                return CGRect(x: rect.minX, y: rect.minY + start, width: rect.width, height: end - start)
            }
        }
    }

    private static func dividerFrame(
        split: PaneSplit,
        index: Int,
        leadingRect: CGRect,
        trailingRect: CGRect,
        in rect: CGRect
    ) -> PaneDividerFrame {
        let id = PaneDividerID(
            split: split.id,
            leading: split.children[index].id,
            trailing: split.children[index + 1].id
        )

        let gapRect: CGRect
        let segmentExtent: CGFloat
        let segmentOrigin: CGFloat
        let leadingExtent: CGFloat
        switch split.axis {
        case .horizontal:
            gapRect = CGRect(
                x: leadingRect.maxX,
                y: rect.minY,
                width: trailingRect.minX - leadingRect.maxX,
                height: rect.height
            )
            leadingExtent = leadingRect.width
            segmentExtent = leadingRect.width + trailingRect.width
            segmentOrigin = leadingRect.minX
        case .vertical:
            gapRect = CGRect(
                x: rect.minX,
                y: leadingRect.maxY,
                width: rect.width,
                height: trailingRect.minY - leadingRect.maxY
            )
            leadingExtent = leadingRect.height
            segmentExtent = leadingRect.height + trailingRect.height
            segmentOrigin = leadingRect.minY
        }

        // 掴む領域は隙間の中心を保ったまま最低 `dividerHitThickness` まで太らせる。
        let hitRect: CGRect
        switch split.axis {
        case .horizontal:
            let thickness = max(gapRect.width, dividerHitThickness)
            hitRect = CGRect(
                x: gapRect.midX - thickness / 2,
                y: gapRect.minY,
                width: thickness,
                height: gapRect.height
            )
        case .vertical:
            let thickness = max(gapRect.height, dividerHitThickness)
            hitRect = CGRect(
                x: gapRect.minX,
                y: gapRect.midY - thickness / 2,
                width: gapRect.width,
                height: thickness
            )
        }

        return PaneDividerFrame(
            id: id,
            axis: split.axis,
            rect: hitRect,
            gapRect: gapRect,
            segmentExtent: segmentExtent,
            segmentOrigin: segmentOrigin,
            leadingFraction: segmentExtent > 0 ? Double(leadingExtent / segmentExtent) : 0.5
        )
    }
}
