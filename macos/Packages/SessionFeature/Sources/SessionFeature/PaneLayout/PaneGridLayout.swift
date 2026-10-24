import CoreGraphics
import AgentDomain

public struct PaneGridLayout: Equatable, Sendable {
    public static let minimumTileWidth: CGFloat = 540
    public static let minimumTileHeight: CGFloat = 440
    public static let spacing: CGFloat = 8

    public let tree: PaneTree
    public let canvasSize: CGSize

    public init(tree: PaneTree, canvasSize: CGSize) {
        self.tree = tree
        self.canvasSize = canvasSize
    }

    public static func automatic(sessions: [SessionID], viewport: CGSize) -> Self {
        var seen: Set<SessionID> = []
        let sessions = sessions.filter { seen.insert($0).inserted }
        let width = viewport.width.isFinite ? max(0, viewport.width) : 0
        let height = viewport.height.isFinite ? max(0, viewport.height) : 0
        guard !sessions.isEmpty else {
            return Self(tree: .empty, canvasSize: CGSize(width: width, height: height))
        }
        let maximumColumns = min(sessions.count, max(1, Int(min(CGFloat(sessions.count), floor((width + spacing) / (minimumTileWidth + spacing))))))
        let rows = (sessions.count + maximumColumns - 1) / maximumColumns
        let columns = (sessions.count + rows - 1) / rows
        let canvas = CGSize(width: max(width, minimumTileWidth), height: max(height, CGFloat(rows) * minimumTileHeight + CGFloat(rows - 1) * spacing))
        let rowHeight = (canvas.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        var allocator = PaneIDAllocator(reserving: nil)
        var columnNodes: [PaneNode] = []
        for column in 0..<columns {
            let indices = stride(from: column, to: sessions.count, by: columns)
            let children = indices.map { PaneNode.leaf(id: allocator.allocateLeaf(for: sessions[$0]), session: sessions[$0]) }
            var heights = Array(repeating: Double(rowHeight), count: children.count)
            heights[heights.count - 1] += Double(CGFloat(rows - children.count) * (rowHeight + spacing))
            let total = heights.reduce(0, +)
            columnNodes.append(.split(PaneSplit(id: allocator.allocateSplit(above: children[0]), axis: .vertical, children: children, weights: heights.map { $0 / total })))
        }
        let root = PaneNode.split(PaneSplit(id: allocator.allocateSplit(above: columnNodes[0]), axis: .horizontal, children: columnNodes, weights: Array(repeating: 1 / Double(columns), count: columns)))
        return Self(tree: PaneTree.make(root, fallback: .empty), canvasSize: canvas)
    }
}

extension PaneTree {
    /// 非表示の枝を別軸へ退避し、可視側の比率と分割線IDを保つ。
    public func retainingHidden(from saved: PaneTree, allSessions: [SessionID], bounds: CGSize, spacing: CGFloat) -> PaneTree {
        let hiddenIDs = Set(allSessions).subtracting(sessions)
        let hidden = saved.pruned(visible: hiddenIDs).reconciled(with: allSessions.filter { hiddenIDs.contains($0) }, bounds: bounds, spacing: spacing)
        guard let visibleRoot = root else { return hidden }
        guard let hiddenRoot = hidden.root else { return self }
        var allocator = PaneIDAllocator(reserving: visibleRoot)
        func renaming(_ node: PaneNode) -> PaneNode {
            let id = allocator.allocate(preferred: node.id.rawValue)
            switch node {
            case .leaf(_, let session): return .leaf(id: id, session: session)
            case .split(let split):
                return .split(PaneSplit(id: id, axis: split.axis, children: split.children.map(renaming), weights: split.weights))
            }
        }
        let renamed = renaming(hiddenRoot)
        let axis: PaneAxis
        if case .split(let split) = visibleRoot { axis = split.axis == .horizontal ? .vertical : .horizontal } else { axis = .vertical }
        return Self.make(.split(PaneSplit(id: allocator.allocate(preferred: "grid-hidden"), axis: axis, children: [visibleRoot, renamed], weights: [0.5, 0.5])), fallback: self)
    }
}
