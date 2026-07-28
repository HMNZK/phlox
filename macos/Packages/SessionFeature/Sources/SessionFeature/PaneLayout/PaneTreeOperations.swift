import CoreGraphics
import AgentDomain

/// ペインを分割する向き（ドロップ先の辺）。
public enum PaneEdge: String, Codable, Sendable, CaseIterable {
    case leading
    case trailing
    case top
    case bottom
}

extension PaneEdge {
    var axis: PaneAxis {
        switch self {
        case .leading, .trailing: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// 新しいペインが既存ペインの手前（左/上）に入るか。
    var placesNewPaneFirst: Bool {
        switch self {
        case .leading, .top: return true
        case .trailing, .bottom: return false
        }
    }
}

/// 木の中で衝突しない `PaneID` を決定論的に払い出す。
///
/// leaf の ID はセッション UUID から決めるので、同じセッションを取り除いて入れ直しても
/// 同じ ID に戻る（分割線 ID の安定性）。候補が既に使われていれば `-2`, `-3` … を付けて避ける。
struct PaneIDAllocator {
    private var used: Set<PaneID>

    init(reserving root: PaneNode?) {
        used = []
        if let root {
            PaneIDAllocator.collect(root, into: &used)
        }
    }

    mutating func allocate(preferred: String) -> PaneID {
        var candidate = PaneID(preferred)
        var suffix = 2
        while used.contains(candidate) {
            candidate = PaneID("\(preferred)-\(suffix)")
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    mutating func allocateLeaf(for session: SessionID) -> PaneID {
        allocate(preferred: "pane-\(session.rawValue.uuidString.lowercased())")
    }

    mutating func allocateSplit(above firstChild: PaneNode) -> PaneID {
        allocate(preferred: "split-\(firstChild.id.rawValue)")
    }

    private static func collect(_ node: PaneNode, into used: inout Set<PaneID>) {
        used.insert(node.id)
        guard case .split(let split) = node else { return }
        for child in split.children {
            collect(child, into: &used)
        }
    }
}

// MARK: - 変換操作（すべて純関数。永続ツリーを書き換えない）

extension PaneTree {
    /// 可視集合で刈り込んだ実効ツリー。隠れた leaf は取り除き、兄弟が領域を吸収する。
    /// 永続ツリー自身は変えない（D4）。
    public func pruned(visible: Set<SessionID>) -> PaneTree {
        guard let root else { return self }
        return PaneTree.make(PaneTree.prune(root, visible: visible), fallback: self)
    }

    /// leaf を取り除き、兄弟が領域を吸収する。存在しなければ自身を返す。
    public func removing(_ session: SessionID) -> PaneTree {
        guard let root else { return self }
        var remaining = Set(sessions)
        guard remaining.remove(session) != nil else { return self }
        return PaneTree.make(PaneTree.prune(root, visible: remaining), fallback: self)
    }

    /// 生き残ったノードの `PaneID` は作り替えない。子が1個になった split もここでは畳まず、
    /// `init(root:)` の正規化に委ねる（畳み込みの規則を1か所に閉じ込めるため）。
    private static func prune(_ node: PaneNode, visible: Set<SessionID>) -> PaneNode? {
        switch node {
        case .leaf(_, let session):
            return visible.contains(session) ? node : nil
        case .split(let split):
            var children: [PaneNode] = []
            var weights: [Double] = []
            for (child, weight) in zip(split.children, split.weights) {
                guard let kept = prune(child, visible: visible) else { continue }
                children.append(kept)
                weights.append(weight)
            }
            guard !children.isEmpty else { return nil }
            return .split(
                PaneSplit(id: split.id, axis: split.axis, children: children, weights: weights)
            )
        }
    }

    /// 2つの leaf の位置を入れ替える。どちらかが無ければ自身を返す。
    ///
    /// leaf の `PaneID` は位置に残したままセッションだけを交換する。ID を一緒に動かすと
    /// 分割線 ID（両隣のノード ID）が入れ替わってしまい、進行中の操作が別の分割線を指す。
    public func swapping(_ a: SessionID, _ b: SessionID) -> PaneTree {
        guard let root, a != b else { return self }
        let placed = Set(sessions)
        guard placed.contains(a), placed.contains(b) else { return self }
        return PaneTree.make(PaneTree.swapSessions(root, a, b), fallback: self)
    }

    private static func swapSessions(_ node: PaneNode, _ a: SessionID, _ b: SessionID) -> PaneNode {
        switch node {
        case .leaf(let id, let session):
            if session == a { return .leaf(id: id, session: b) }
            if session == b { return .leaf(id: id, session: a) }
            return node
        case .split(let split):
            return .split(
                PaneSplit(
                    id: split.id,
                    axis: split.axis,
                    children: split.children.map { swapSessions($0, a, b) },
                    weights: split.weights
                )
            )
        }
    }

    /// target のペインを edge 方向に分割して session を差し込む。
    /// session が既に木にあるときは先に取り除いてから差し込む（move 相当）。
    public func inserting(_ session: SessionID, splitting target: SessionID, edge: PaneEdge) -> PaneTree {
        // 自分自身のペインへのドロップは何も変えない。
        guard session != target else { return self }
        let base = sessions.contains(session) ? removing(session) : self
        guard let root = base.root, base.sessions.contains(target) else { return self }

        var allocator = PaneIDAllocator(reserving: root)
        let newLeaf = PaneNode.leaf(id: allocator.allocateLeaf(for: session), session: session)
        guard
            let updated = PaneTree.insert(
                newLeaf,
                splitting: target,
                edge: edge,
                in: root,
                allocator: &allocator
            )
        else { return self }
        return PaneTree.make(updated, fallback: self)
    }

    private static func insert(
        _ newLeaf: PaneNode,
        splitting target: SessionID,
        edge: PaneEdge,
        in node: PaneNode,
        allocator: inout PaneIDAllocator
    ) -> PaneNode? {
        switch node {
        case .leaf(_, let session):
            guard session == target else { return nil }
            let children = edge.placesNewPaneFirst ? [newLeaf, node] : [node, newLeaf]
            // 既存ペインの領域を半分ずつ分け合う。親と同じ axis ならこの split は
            // `init(root:)` の平坦化で親へ吸収され、weights は積で合成される。
            return .split(
                PaneSplit(
                    id: allocator.allocateSplit(above: children[0]),
                    axis: edge.axis,
                    children: children,
                    weights: [0.5, 0.5]
                )
            )
        case .split(let split):
            for (index, child) in split.children.enumerated() {
                guard
                    let replaced = insert(
                        newLeaf,
                        splitting: target,
                        edge: edge,
                        in: child,
                        allocator: &allocator
                    )
                else { continue }
                var children = split.children
                children[index] = replaced
                return .split(
                    PaneSplit(
                        id: split.id,
                        axis: split.axis,
                        children: children,
                        weights: split.weights
                    )
                )
            }
            return nil
        }
    }

    /// 面積が最大のペインを分割して差し込む（長辺に垂直な向きで割る）。
    public func insertingIntoLargestPane(
        _ session: SessionID,
        bounds: CGSize,
        spacing: CGFloat
    ) -> PaneTree {
        let base = sessions.contains(session) ? removing(session) : self
        guard base.root != nil else {
            var allocator = PaneIDAllocator(reserving: nil)
            return PaneTree.make(
                .leaf(id: allocator.allocateLeaf(for: session), session: session),
                fallback: self
            )
        }
        let tiles = base.frames(in: bounds, spacing: spacing).tiles
        // 同面積のときは走査順で先のペインを選ぶ（`max(by:)` は最初の最大値を残す）。
        guard
            let largest = tiles.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })
        else { return self }
        // 長辺に垂直な向きで割る（横長なら左右に、縦長なら上下に）。
        let edge: PaneEdge = largest.rect.width >= largest.rect.height ? .trailing : .bottom
        return base.inserting(session, splitting: largest.session, edge: edge)
    }

    /// 分割線を動かす。`divider.leading` と `divider.trailing` の**合計取り分の中だけ**で
    /// 再配分する。間に他の子（隠れた兄弟）が挟まっていてもその weight は変えない。
    ///
    /// クランプは「2枚の合計は不変」を固定したうえで、その内側の比に対して掛ける。
    /// 全体の再正規化は行わない（他の兄弟の取り分が動いてしまうため）。
    public func settingDivider(_ divider: PaneDividerID, leadingFraction: Double) -> PaneTree {
        guard let root, leadingFraction.isFinite else { return self }
        guard let updated = PaneTree.setDivider(root, divider, leadingFraction: leadingFraction) else {
            return self
        }
        return PaneTree.make(updated, fallback: self)
    }

    private static func setDivider(
        _ node: PaneNode,
        _ divider: PaneDividerID,
        leadingFraction: Double
    ) -> PaneNode? {
        guard case .split(let split) = node else { return nil }

        if split.id == divider.split {
            return redistributing(
                split,
                leading: divider.leading,
                trailing: divider.trailing,
                leadingFraction: leadingFraction
            )
        }

        for (index, child) in split.children.enumerated() {
            guard let updated = setDivider(child, divider, leadingFraction: leadingFraction) else {
                continue
            }
            var children = split.children
            children[index] = updated
            return .split(
                PaneSplit(id: split.id, axis: split.axis, children: children, weights: split.weights)
            )
        }
        return nil
    }

    /// 実効ツリー（`pruned` 後）で隣り合っていた2ノードの境界を、この split の中で解決して動かす。
    ///
    /// **直接の子とは限らない**のが要点。`pruned` は `PaneID` を保つが、続く正規化が
    /// 「子1個の split を畳む」「親と同じ axis の入れ子を平坦化する」ため、実効ツリーで
    /// 隣接していた2つが永続ツリーでは同じ子の**部分木の中**に沈んでいることがある。
    /// 直接の子としてしか探さないと対象が見つからず、絞り込み中のドラッグが丸ごと無視される。
    ///
    /// そこで「その `PaneID` を含む部分木」で子を特定し、両方が同じ子に入っていれば
    /// その子へ降りて同じ解決を続ける。降り切った先が、2つを分けている唯一の split である。
    private static func redistributing(
        _ split: PaneSplit,
        leading: PaneID,
        trailing: PaneID,
        leadingFraction: Double
    ) -> PaneNode? {
        guard
            let leadingIndex = split.children.firstIndex(where: { $0.contains(leading) }),
            let trailingIndex = split.children.firstIndex(where: { $0.contains(trailing) })
        else { return nil }

        if leadingIndex == trailingIndex {
            guard
                case .split(let inner) = split.children[leadingIndex],
                let updated = redistributing(
                    inner,
                    leading: leading,
                    trailing: trailing,
                    leadingFraction: leadingFraction
                )
            else { return nil }
            var children = split.children
            children[leadingIndex] = updated
            return .split(
                PaneSplit(id: split.id, axis: split.axis, children: children, weights: split.weights)
            )
        }

        guard leadingIndex < trailingIndex else { return nil }

        let combined = split.weights[leadingIndex] + split.weights[trailingIndex]
        let fraction = min(
            max(leadingFraction, PaneTree.minimumDividerFraction),
            1 - PaneTree.minimumDividerFraction
        )
        var weights = split.weights
        weights[leadingIndex] = combined * fraction
        weights[trailingIndex] = combined * (1 - fraction)
        return .split(
            PaneSplit(id: split.id, axis: split.axis, children: split.children, weights: weights)
        )
    }

    /// split の子を等分に戻す。
    public func equalizing(_ split: PaneID) -> PaneTree {
        guard let root, let updated = PaneTree.equalize(root, split) else { return self }
        return PaneTree.make(updated, fallback: self)
    }

    private static func equalize(_ node: PaneNode, _ target: PaneID) -> PaneNode? {
        guard case .split(let split) = node else { return nil }

        if split.id == target {
            let share = 1.0 / Double(split.children.count)
            return .split(
                PaneSplit(
                    id: split.id,
                    axis: split.axis,
                    children: split.children,
                    weights: Array(repeating: share, count: split.children.count)
                )
            )
        }

        for (index, child) in split.children.enumerated() {
            guard let updated = equalize(child, target) else { continue }
            var children = split.children
            children[index] = updated
            return .split(
                PaneSplit(id: split.id, axis: split.axis, children: children, weights: split.weights)
            )
        }
        return nil
    }

    /// 実在セッション集合に合わせる。消えた leaf を除去し、増えた分を
    /// `insertingIntoLargestPane` で追加する。順序は `sessions` の並び順に従う。
    ///
    /// 増減が無いときは自身をそのまま返す（weights を touch しないので冪等）。
    public func reconciled(
        with sessions: [SessionID],
        bounds: CGSize,
        spacing: CGFloat
    ) -> PaneTree {
        var desired: [SessionID] = []
        var wanted: Set<SessionID> = []
        for session in sessions where wanted.insert(session).inserted {
            desired.append(session)
        }

        var tree = self
        var placed = Set(tree.sessions)
        for existing in tree.sessions where !wanted.contains(existing) {
            tree = tree.removing(existing)
            placed.remove(existing)
        }
        for session in desired where !placed.contains(session) {
            tree = tree.insertingIntoLargestPane(session, bounds: bounds, spacing: spacing)
            placed.insert(session)
        }
        return tree
    }
}
