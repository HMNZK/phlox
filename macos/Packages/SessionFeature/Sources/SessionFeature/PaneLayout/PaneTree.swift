import Foundation
import AgentDomain

// グリッドの新レイアウトモデル「n 分岐の分割ツリー」の純粋な値型（D1）。
// UI・永続化・VM を含まない。Foundation / CoreGraphics 以外に依存しない
// （SwiftUI / AppKit は import しない）。

// MARK: - 基本型

/// split が子を並べる向き。
public enum PaneAxis: String, Codable, Sendable, CaseIterable {
    /// 子を左右に並べる（分割線は縦向き）。
    case horizontal
    /// 子を上下に並べる（分割線は横向き）。
    case vertical
}

/// ツリー内のノードを一意に指す ID（leaf・split の区別なく一意）。
public struct PaneID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    // JSON では素の文字列として表現する（`{"rawValue": "..."}` の入れ子を避ける）。
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 分割線の同一性。**index ではなく両隣のノード ID で表す**（D10）。
///
/// index だと、永続ツリー `[A, B, C]` から B を隠した実効ツリー `[A, C]` の `index: 0` は
/// A|C 境界を指すのに、永続ツリーの `index: 0` は A|B 境界を指す。ビューは実効ツリーの
/// 分割線 ID を VM へ渡すため、絞り込み中に分割線を動かすと別の分割線が動いてしまう。
public struct PaneDividerID: Hashable, Codable, Sendable {
    public let split: PaneID
    /// 分割線の手前側（左/上）の子ノードの ID。
    public let leading: PaneID
    /// 分割線の奥側（右/下）の子ノードの ID。
    public let trailing: PaneID

    public init(split: PaneID, leading: PaneID, trailing: PaneID) {
        self.split = split
        self.leading = leading
        self.trailing = trailing
    }
}

/// n 分岐の分割ノード。`weights` は `children` と同順・同数で、合計 1。
public struct PaneSplit: Equatable, Sendable {
    public let id: PaneID
    public let axis: PaneAxis
    public let children: [PaneNode]
    public let weights: [Double]

    public init(id: PaneID, axis: PaneAxis, children: [PaneNode], weights: [Double]) {
        self.id = id
        self.axis = axis
        self.children = children
        self.weights = weights
    }
}

public indirect enum PaneNode: Equatable, Sendable {
    /// leaf にも安定 ID を持たせる（分割線を両隣のノード ID で表すため。D10）。
    case leaf(id: PaneID, session: SessionID)
    case split(PaneSplit)

    public var id: PaneID {
        switch self {
        case .leaf(let id, _): return id
        case .split(let split): return split.id
        }
    }
}

extension PaneNode {
    /// 走査順（左→右／上→下の深さ優先）のセッション一覧。
    var sessions: [SessionID] {
        switch self {
        case .leaf(_, let session): return [session]
        case .split(let split): return split.children.flatMap(\.sessions)
        }
    }

    /// 部分木の節点数。正規化ループの停止性を保証する測度に使う。
    var nodeCount: Int {
        switch self {
        case .leaf: return 1
        case .split(let split): return split.children.reduce(1) { $0 + $1.nodeCount }
        }
    }
}

public enum PaneTreeError: Error, Equatable {
    case duplicateSession(SessionID)
    /// 子0個。子1個は「畳む」ので error ではない。
    case emptySplit(PaneID)
    case weightCountMismatch(PaneID)
    case nonPositiveWeight(PaneID)
    case duplicatePaneID(PaneID)
    case unsupportedSchemaVersion(Int)
}

// MARK: - PaneTree

public struct PaneTree: Equatable, Codable, Sendable {
    /// エンコード結果のトップレベルはオブジェクトで、このキー（Int）を必ず持つ。
    public static let schemaVersion = 1

    /// 分割線を動かすときの、**隣接2枚の合計に対する**片側の取り分の下限。
    /// 各 weight の絶対下限ではない（絶対下限にすると 21 子以上の split が
    /// 数学的に作れなくなるため。不変条件は「weight > 0」のみ）。
    public static let minimumDividerFraction: Double = 0.05

    /// weights の合計を 1.0 とみなす許容差。**これを超えてずれている場合だけ**再正規化する。
    /// 既に 1.0 とみなせるなら触らない（触ると `x / 0.9999999999999998` で値が微妙に漂い、
    /// Codable の往復や `reconciled` の再適用で `Equatable` が壊れる）。
    static let weightSumTolerance: Double = 1e-9

    /// nil = 空（セッション0件）。
    public let root: PaneNode?

    /// 正規化と不変条件の検証を行う唯一の入口。違反は throw。
    ///
    /// 順序は ①形の検証（子0個・weights 個数不一致・非正の weight）→ ②正規化
    /// （畳み込み・平坦化を収束するまで／必要なときだけ weights を再正規化）→ ③検証
    /// （重複 SessionID・重複 PaneID・正規化後も残る非正の weight）。
    /// ①を先に置くのは、weights 個数が合っていない木に対して正規化（zip・積の合成）を
    /// 走らせないため。子1個の split は拒否せず畳む（削除・刈り込みの途中で自然に生じる形）。
    public init(root: PaneNode?) throws {
        guard let root else {
            self.root = nil
            return
        }
        try PaneTree.validateShape(root)
        let normalized = PaneTree.normalizedToFixpoint(root)
        // 正規形（不変条件6）は正規化の事後条件。対応する `PaneTreeError` が無いため
        // throw ではなく assert で守り、白箱テストで固定する。
        assert(PaneTree.isNormalForm(normalized), "正規化後の木が正規形になっていない")
        try PaneTree.validateInvariants(normalized)
        self.root = normalized
    }

    /// 検証を経ずに空ツリーを作るための内部専用の入口（nil root は不変条件を自明に満たす）。
    private init(emptyTree: Void) {
        root = nil
    }

    /// 空ツリー。throw しない文脈のフォールバックに使う。
    static let empty = PaneTree(emptyTree: ())

    /// 走査順（左→右／上→下の深さ優先）のセッション一覧。
    public var sessions: [SessionID] {
        root?.sessions ?? []
    }

    /// 変換結果を必ず `init(root:)`（正規化＋検証の唯一の入口）へ通すためのヘルパー。
    /// 各操作は不変条件を破る木を作らない設計なので throw は起きないが、
    /// 万一破れたときに壊れた木を返さないよう fallback へ倒す。
    static func make(_ root: PaneNode?, fallback: PaneTree) -> PaneTree {
        (try? PaneTree(root: root)) ?? fallback
    }
}

// MARK: - 検証

extension PaneTree {
    /// 正規化の前提となる「形」を検証する。
    private static func validateShape(_ node: PaneNode) throws {
        guard case .split(let split) = node else { return }
        guard !split.children.isEmpty else { throw PaneTreeError.emptySplit(split.id) }
        guard split.weights.count == split.children.count else {
            throw PaneTreeError.weightCountMismatch(split.id)
        }
        for weight in split.weights {
            // NaN・±Inf もここで弾く（永続化データ由来の値を正規化に流さない）。
            guard weight > 0, weight.isFinite else { throw PaneTreeError.nonPositiveWeight(split.id) }
        }
        for child in split.children {
            try validateShape(child)
        }
    }

    /// 正規化後の不変条件を検証する（重複 SessionID・重複 PaneID・退化した weights）。
    private static func validateInvariants(_ node: PaneNode) throws {
        var seenSessions: Set<SessionID> = []
        var seenIDs: Set<PaneID> = []
        try walk(node, sessions: &seenSessions, ids: &seenIDs)
    }

    private static func walk(
        _ node: PaneNode,
        sessions: inout Set<SessionID>,
        ids: inout Set<PaneID>
    ) throws {
        guard ids.insert(node.id).inserted else { throw PaneTreeError.duplicatePaneID(node.id) }
        switch node {
        case .leaf(_, let session):
            guard sessions.insert(session).inserted else {
                throw PaneTreeError.duplicateSession(session)
            }
        case .split(let split):
            guard !split.children.isEmpty else { throw PaneTreeError.emptySplit(split.id) }
            guard split.weights.count == split.children.count else {
                throw PaneTreeError.weightCountMismatch(split.id)
            }
            // 再正規化が退化した（合計が ±Inf などで 0 に潰れた）ケースはここで落ちる。
            for weight in split.weights {
                guard weight > 0, weight.isFinite else {
                    throw PaneTreeError.nonPositiveWeight(split.id)
                }
            }
            for child in split.children {
                try walk(child, sessions: &sessions, ids: &ids)
            }
        }
    }

    /// 正規形か（子1個の split が無い・親と同じ axis の split が直接の子になっていない・
    /// weights の合計が 1 とみなせる）。
    static func isNormalForm(_ node: PaneNode) -> Bool {
        guard case .split(let split) = node else { return true }
        guard split.children.count >= 2 else { return false }
        guard abs(split.weights.reduce(0, +) - 1) <= weightSumTolerance else { return false }
        for child in split.children {
            if case .split(let inner) = child, inner.axis == split.axis { return false }
            guard isNormalForm(child) else { return false }
        }
        return true
    }
}

// MARK: - 正規化

extension PaneTree {
    /// 正規化を不動点まで繰り返す。
    ///
    /// **停止性**: `normalizePass` は木の節点数を決して増やさない。畳み込みは split を1つ、
    /// 平坦化も入れ子 split を1つ取り除くだけで、新しい節点は作らない（子の付け替えのみ）。
    /// よって節点数は非負整数の単調非増加列になり、「1回のパスで節点数が減らない」＝
    /// 畳み込みも平坦化も起きなかった＝不動点である。減り続ける限りループするが、
    /// 節点数は初期値から 0 未満にはならないので高々「初期節点数」回で必ず停止する。
    ///
    /// なお `normalizePass` は葉から根へ（bottom-up）適用するため、実際には1回のパスで
    /// 不動点に到達する（子を正規化してから親で平坦化・畳み込みを行うので、
    /// 「畳み込みが平坦化を誘発し、平坦化がさらに畳み込みを誘発する」連鎖が同じパスの中で
    /// 解ける）。このループはその性質に依存しない安全網で、2回目のパスで不動点を確認して抜ける。
    static func normalizedToFixpoint(_ node: PaneNode) -> PaneNode {
        var current = node
        var count = current.nodeCount
        while true {
            let next = normalizePass(current)
            let nextCount = next.nodeCount
            if nextCount >= count { return next }
            current = next
            count = nextCount
        }
    }

    /// 正規化の1パス（bottom-up）。`validateShape` を通った木にだけ適用する。
    private static func normalizePass(_ node: PaneNode) -> PaneNode {
        guard case .split(let split) = node else { return node }

        // ①子を先に正規化する。以降、子の中に「自分と同じ axis の split を直接持つ split」は無い。
        let normalizedChildren = split.children.map(normalizePass)

        // ②親と同じ axis の子 split を平坦化する（weights は積で合成）。
        // 子は①で正規化済みなので、取り込んだ孫に同 axis の split は含まれない＝1回で足りる。
        var children: [PaneNode] = []
        var weights: [Double] = []
        for (child, weight) in zip(normalizedChildren, split.weights) {
            if case .split(let inner) = child, inner.axis == split.axis {
                children.append(contentsOf: inner.children)
                weights.append(contentsOf: inner.weights.map { $0 * weight })
            } else {
                children.append(child)
                weights.append(weight)
            }
        }

        // ③子1個の split は畳む。生き残った子の PaneID は作り替えない（消えるのは split の ID だけ）。
        if children.count == 1 { return children[0] }

        return .split(
            PaneSplit(
                id: split.id,
                axis: split.axis,
                children: children,
                weights: renormalizedIfNeeded(weights)
            )
        )
    }

    /// 合計が 1.0 から `weightSumTolerance` を超えてずれている場合だけ再正規化する。
    /// 既に 1.0 とみなせるなら配列をそのまま返す（ビット単位の冪等性を保つため）。
    static func renormalizedIfNeeded(_ weights: [Double]) -> [Double] {
        let sum = weights.reduce(0, +)
        guard sum > 0, abs(sum - 1) > weightSumTolerance else { return weights }
        return weights.map { $0 / sum }
    }
}

// MARK: - Codable

extension PaneTree {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case root
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PaneTree.schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(root.map(PaneNodeRepresentation.init), forKey: .root)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == PaneTree.schemaVersion else {
            throw PaneTreeError.unsupportedSchemaVersion(version)
        }
        let representation = try container.decodeIfPresent(PaneNodeRepresentation.self, forKey: .root)
        // 復号した木も正規化・検証の唯一の入口を通す（破損データを黙って通さない）。
        try self.init(root: representation?.node)
    }
}

/// `PaneNode` の JSON 表現。`PaneNode` 自身に `Codable` を足さずに永続化の形を閉じ込める。
private enum PaneNodeRepresentation: Codable {
    case leaf(id: PaneID, session: SessionID)
    case split(id: PaneID, axis: PaneAxis, children: [PaneNodeRepresentation], weights: [Double])

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case session
        case axis
        case children
        case weights
    }

    private enum Kind: String, Codable {
        case leaf
        case split
    }

    init(_ node: PaneNode) {
        switch node {
        case .leaf(let id, let session):
            self = .leaf(id: id, session: session)
        case .split(let split):
            self = .split(
                id: split.id,
                axis: split.axis,
                children: split.children.map(PaneNodeRepresentation.init),
                weights: split.weights
            )
        }
    }

    var node: PaneNode {
        switch self {
        case .leaf(let id, let session):
            return .leaf(id: id, session: session)
        case .split(let id, let axis, let children, let weights):
            return .split(
                PaneSplit(id: id, axis: axis, children: children.map(\.node), weights: weights)
            )
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .leaf:
            self = .leaf(
                id: try container.decode(PaneID.self, forKey: .id),
                session: try container.decode(SessionID.self, forKey: .session)
            )
        case .split:
            self = .split(
                id: try container.decode(PaneID.self, forKey: .id),
                axis: try container.decode(PaneAxis.self, forKey: .axis),
                children: try container.decode([PaneNodeRepresentation].self, forKey: .children),
                weights: try container.decode([Double].self, forKey: .weights)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let id, let session):
            try container.encode(Kind.leaf, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(session, forKey: .session)
        case .split(let id, let axis, let children, let weights):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(axis, forKey: .axis)
            try container.encode(children, forKey: .children)
            try container.encode(weights, forKey: .weights)
        }
    }
}
