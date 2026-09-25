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

    /// 左上から数えたタイルの並び（行の上から、同じ行は左から）。⌘1–9 と見出しの番号が読む。
    /// ウィンドウの大きさに左右されないよう、固定の大きさ・余白 0 で数える。
    public func readingOrder() -> [SessionID] {
        frames(in: CGSize(width: 1600, height: 1000), spacing: 0).tiles
            .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
            .map(\.session)
    }

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
    /// 隣接する子の隙間も `(edge[i+1] + gap*(i+1)) - (edge[i+1] + gap*i) = gap` で一定。
    ///
    /// **退化ケース**（隙間の総和が領域に収まらない。`GeometryReader` がレイアウト確定前に
    /// 0 を返す・極端に細い領域に多数ペインがある）では、`content` を 0 に切り上げるだけでは
    /// 座標側の `spacing * index` が積み上がって後続タイルが領域の外へ出る。実効の隙間を
    /// `min(spacing, length / (子の数 - 1))` へ縮めることで、タイルも隙間も領域内に収める。
    /// 隙間が収まるときは実効の隙間が `spacing` とビット単位で一致するため、通常時の挙動は変わらない。
    private static func childRects(_ split: PaneSplit, in rect: CGRect, spacing: CGFloat) -> [CGRect] {
        let count = split.children.count
        let length = max(0, split.axis == .horizontal ? rect.width : rect.height)
        // 実効の隙間。領域に収まる限り `spacing` そのもの。
        let gap = count > 1 ? max(0, min(spacing, length / CGFloat(count - 1))) : 0
        // タイルに配れる長さ（隙間を除いた分）。退化ケースでは 0 になる。
        let content = max(0, length - gap * CGFloat(count - 1))
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
            let start = edges[index] + gap * CGFloat(index)
            let end = edges[index + 1] + gap * CGFloat(index)
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

/// 06 キーボード: ⌥⌘⇧＋矢印（隣と入れ替え）と ⌃⌥＋矢印（分割線を動かす）の向き。
public enum PaneDirection: Sendable, CaseIterable {
    case left, right, up, down
}

extension PaneTree {
    /// その向きで接しているタイルのうち、接している長さが一番長いもの（⌥⌘⇧＋矢印の相手）。
    public func neighbor(of session: SessionID, toward direction: PaneDirection) -> SessionID? {
        let tiles = frames(in: Self.keyboardBounds, spacing: 0).tiles
        guard let me = tiles.first(where: { $0.session == session })?.rect else { return nil }
        let candidates: [(SessionID, CGFloat)] = tiles.compactMap { tile in
            let r = tile.rect
            guard tile.session != session else { return nil }
            let touches: Bool
            let shared: CGFloat
            switch direction {
            case .left: touches = Self.near(r.maxX, me.minX); shared = Self.overlap(r.minY, r.maxY, me.minY, me.maxY)
            case .right: touches = Self.near(r.minX, me.maxX); shared = Self.overlap(r.minY, r.maxY, me.minY, me.maxY)
            case .up: touches = Self.near(r.maxY, me.minY); shared = Self.overlap(r.minX, r.maxX, me.minX, me.maxX)
            case .down: touches = Self.near(r.minY, me.maxY); shared = Self.overlap(r.minX, r.maxX, me.minX, me.maxX)
            }
            return touches && shared > 0 ? (tile.session, shared) : nil
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    /// ⌃⌥＋矢印で動かす分割線と、動かす量（隣り合う 2 枚の合計に対する取り分の差）。
    /// タイルの右（下）の辺の線を優先し、無ければ左（上）の辺の線。1 回で 5%。
    /// 最小の大きさの判定は、保存ツリーへ当てた結果で呼び出し元が行う（表示と保存で取り分の基準が違うため）。
    public func nudgedDivider(of session: SessionID, toward direction: PaneDirection) -> (id: PaneDividerID, delta: Double)? {
        let layout = frames(in: Self.keyboardBounds, spacing: 0)
        guard let me = layout.tiles.first(where: { $0.session == session })?.rect else { return nil }
        let isHorizontal = direction == .left || direction == .right
        let lines = layout.dividers.filter { $0.axis == (isHorizontal ? .horizontal : .vertical) }
        func touching(_ edge: CGFloat) -> PaneDividerFrame? {
            lines.first { line in
                isHorizontal
                    ? Self.near(line.gapRect.midX, edge) && Self.overlap(line.gapRect.minY, line.gapRect.maxY, me.minY, me.maxY) > 0
                    : Self.near(line.gapRect.midY, edge) && Self.overlap(line.gapRect.minX, line.gapRect.maxX, me.minX, me.maxX) > 0
            }
        }
        guard let line = touching(isHorizontal ? me.maxX : me.maxY) ?? touching(isHorizontal ? me.minX : me.minY) else { return nil }
        return (line.id, (direction == .right || direction == .down) ? 0.05 : -0.05)
    }

    private static let keyboardBounds = CGSize(width: 1600, height: 1000)
    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }
    private static func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        max(0, min(a1, b1) - max(a0, b0))
    }
}
