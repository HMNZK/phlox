import CoreGraphics
import AgentDomain

/// 1クリックで到達できるレイアウトの雛形。
public enum PaneLayoutPreset: String, Codable, Sendable, CaseIterable {
    /// 自動整列（⌈√N⌉ 列の等分）。
    case balanced
    /// 1枚（先頭のみ。残りは balanced で下に足す）。
    case single
    case columns2
    case columns3
    case rows2
    case rows3
    case grid2x2
    /// 左1枚＋右を上下に積む。
    case mainLeftStackRight
    /// 上1枚＋下を左右に並べる。
    case mainTopStackBottom

    public var displayName: String {
        switch self {
        case .balanced: return "自動整列"
        case .single: return "1枚"
        case .columns2: return "2列"
        case .columns3: return "3列"
        case .rows2: return "2段"
        case .rows3: return "3段"
        case .grid2x2: return "2×2"
        case .mainLeftStackRight: return "左1枚＋右に2枚"
        case .mainTopStackBottom: return "上1枚＋下に2枚"
        }
    }

    /// `sessions` の並び順を尊重して木を作る。セッション数がプリセットの想定より多いときは、
    /// 余りを最大ペインの分割で足す（レイアウトから溢れさせない）。
    public func tree(for sessions: [SessionID]) -> PaneTree {
        var unique: [SessionID] = []
        var seen: Set<SessionID> = []
        for session in sessions where seen.insert(session).inserted {
            unique.append(session)
        }
        guard !unique.isEmpty else { return .empty }

        let capacity = min(unique.count, self.capacity(for: unique.count))
        let placed = Array(unique[..<capacity])
        let overflow = Array(unique[capacity...])

        var allocator = PaneIDAllocator(reserving: nil)
        let root = node(for: placed, allocator: &allocator)
        var tree = PaneTree.make(root, fallback: .empty)
        for session in overflow {
            tree = tree.insertingIntoLargestPane(
                session,
                bounds: PaneLayoutPreset.nominalBounds,
                spacing: 0
            )
        }
        return tree
    }

    /// 余りを最大ペインへ足すときに使う仮の領域。プリセット生成にはビューの実寸が無いので、
    /// 典型的なウィンドウに近い 16:10 の比だけを使う（分割の向きの判断にしか効かない）。
    private static let nominalBounds = CGSize(width: 1600, height: 1000)

    /// このプリセットが素の形で受け止めるセッション数。
    private func capacity(for count: Int) -> Int {
        switch self {
        case .balanced, .single, .mainLeftStackRight, .mainTopStackBottom: return count
        case .columns2, .rows2: return 2
        case .columns3, .rows3: return 3
        case .grid2x2: return 4
        }
    }

    private func node(for sessions: [SessionID], allocator: inout PaneIDAllocator) -> PaneNode {
        switch self {
        case .balanced:
            return balancedNode(sessions, allocator: &allocator)
        case .single:
            let main = makeLeaf(sessions[0], allocator: &allocator)
            guard sessions.count > 1 else { return main }
            let rest = balancedNode(Array(sessions.dropFirst()), allocator: &allocator)
            return makeSplit(.vertical, [main, rest], allocator: &allocator)
        case .columns2, .columns3:
            let cells = leaves(sessions, allocator: &allocator)
            return makeSplit(.horizontal, cells, allocator: &allocator)
        case .rows2, .rows3:
            let cells = leaves(sessions, allocator: &allocator)
            return makeSplit(.vertical, cells, allocator: &allocator)
        case .grid2x2:
            var rows: [PaneNode] = []
            for chunk in chunked(sessions, by: 2) {
                let cells = leaves(chunk, allocator: &allocator)
                rows.append(makeSplit(.horizontal, cells, allocator: &allocator))
            }
            return makeSplit(.vertical, rows, allocator: &allocator)
        case .mainLeftStackRight:
            return mainPlusStack(sessions, mainAxis: .horizontal, allocator: &allocator)
        case .mainTopStackBottom:
            return mainPlusStack(sessions, mainAxis: .vertical, allocator: &allocator)
        }
    }

    /// 先頭1枚＋残りを反対の向きに並べる（「左1枚＋右上下」「上1枚＋下左右」）。
    private func mainPlusStack(
        _ sessions: [SessionID],
        mainAxis: PaneAxis,
        allocator: inout PaneIDAllocator
    ) -> PaneNode {
        let main = makeLeaf(sessions[0], allocator: &allocator)
        guard sessions.count > 1 else { return main }
        let stackAxis: PaneAxis = mainAxis == .horizontal ? .vertical : .horizontal
        let cells = leaves(Array(sessions.dropFirst()), allocator: &allocator)
        let stack = makeSplit(stackAxis, cells, allocator: &allocator)
        return makeSplit(mainAxis, [main, stack], allocator: &allocator)
    }

    /// ⌈√N⌉ 列で等分に並べる（現行の auto モードと同じ列数の決め方）。
    private func balancedNode(_ sessions: [SessionID], allocator: inout PaneIDAllocator) -> PaneNode {
        let columns = max(1, Int(Double(sessions.count).squareRoot().rounded(.up)))
        var rows: [PaneNode] = []
        for chunk in chunked(sessions, by: columns) {
            let cells = leaves(chunk, allocator: &allocator)
            rows.append(makeSplit(.horizontal, cells, allocator: &allocator))
        }
        return makeSplit(.vertical, rows, allocator: &allocator)
    }

    private func leaves(_ sessions: [SessionID], allocator: inout PaneIDAllocator) -> [PaneNode] {
        var nodes: [PaneNode] = []
        for session in sessions {
            nodes.append(makeLeaf(session, allocator: &allocator))
        }
        return nodes
    }

    private func makeLeaf(_ session: SessionID, allocator: inout PaneIDAllocator) -> PaneNode {
        .leaf(id: allocator.allocateLeaf(for: session), session: session)
    }

    /// 等分の split。子が1個なら split を作らずその子を返す（正規形を最初から満たす）。
    private func makeSplit(
        _ axis: PaneAxis,
        _ children: [PaneNode],
        allocator: inout PaneIDAllocator
    ) -> PaneNode {
        guard children.count > 1 else { return children[0] }
        let share = 1.0 / Double(children.count)
        return .split(
            PaneSplit(
                id: allocator.allocateSplit(above: children[0]),
                axis: axis,
                children: children,
                weights: Array(repeating: share, count: children.count)
            )
        )
    }

    private func chunked(_ sessions: [SessionID], by size: Int) -> [[SessionID]] {
        guard size > 0 else { return [sessions] }
        return stride(from: 0, to: sessions.count, by: size).map { start in
            Array(sessions[start..<min(start + size, sessions.count)])
        }
    }
}
