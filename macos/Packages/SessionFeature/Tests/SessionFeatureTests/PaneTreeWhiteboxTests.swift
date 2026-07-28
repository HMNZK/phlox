import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-1 の白箱テスト。受け入れテスト（AcceptancePaneTreeTests / ContractPaneTreeCodableTests）が
// 固定した契約に対し、**名指しされた正しさハザード**を狙い撃ちで潰す:
//
//  H1 矩形計算の誤差蓄積 → 乱択の木・多子・入れ子で「端が bounds に一致・隙間はちょうど spacing」を
//     許容差 1e-9 で検査する（受け入れテストの 0.5pt より 8 桁厳しい）。
//  H2 正規化の収束 → 畳み込みが平坦化を、平坦化が畳み込みを誘発する形を作り、不動点に達するか。
//  H3 weights 再正規化の冪等性 → 合計が 1 とみなせるときに触っていないことをビット単位で検査する。
//  H4 PaneID の安定性 → 刈り込み・削除・正規化で生き残ったノードの ID が作り替わらないこと。
//  H5 settingDivider の局所性 → 名指しされた2枚以外の weight がビット単位で不変であること。
//  最後に、乱択の操作列を長く回して不変条件が壊れないことを確認する。

@Suite("Whitebox: PaneTree（task-1 の正しさハザード）")
struct PaneTreeWhiteboxTests {

    // MARK: - ハーネス

    private func sid(_ n: Int) -> SessionID {
        let hex = String(format: "%012x", n)
        return SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(hex)")!)
    }

    private func pid(_ name: String) -> PaneID { PaneID(name) }

    private func leaf(_ name: String, _ session: SessionID) -> PaneNode {
        .leaf(id: PaneID(name), session: session)
    }

    private func split(
        _ name: String,
        _ axis: PaneAxis,
        _ children: [PaneNode],
        _ weights: [Double]
    ) -> PaneNode {
        .split(PaneSplit(id: PaneID(name), axis: axis, children: children, weights: weights))
    }

    /// 決定論的な擬似乱数（SplitMix64）。テストの再現性のため std の乱数を使わない。
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
    }

    /// 乱択の木。子数 2〜4・軸ランダム・weights は正の乱数（合計は 1 でない）。
    private func randomNode(
        _ rng: inout SeededGenerator,
        leaves: ArraySlice<Int>,
        counter: inout Int
    ) -> PaneNode {
        guard leaves.count > 1 else {
            let index = leaves.first!
            return leaf("L\(index)", sid(index))
        }
        let groupCount = Int.random(in: 2...min(4, leaves.count), using: &rng)
        var groups: [ArraySlice<Int>] = []
        var remaining = leaves
        for group in 0..<groupCount {
            let take = group == groupCount - 1
                ? remaining.count
                : Int.random(in: 1...(remaining.count - (groupCount - group - 1)), using: &rng)
            groups.append(remaining.prefix(take))
            remaining = remaining.dropFirst(take)
        }
        counter += 1
        let id = "S\(counter)"
        var children: [PaneNode] = []
        var weights: [Double] = []
        for group in groups {
            children.append(randomNode(&rng, leaves: group, counter: &counter))
            weights.append(Double.random(in: 0.05...3.0, using: &rng))
        }
        let axis: PaneAxis = Bool.random(using: &rng) ? .horizontal : .vertical
        return split(id, axis, children, weights)
    }

    /// 木の構造（内部 API）と `frames` の出力だけを突き合わせて埋め尽くしを検査する。
    ///
    /// 各 split について「子の外接矩形が軸方向に順に並び、両端が親に一致し、隣接間隔が
    /// ちょうど実効の隙間」を再帰的に確かめる。矩形計算を各子への独立な掛け算や丸めで
    /// 実装していると、深い木・多子ほど端がずれてここで落ちる。
    ///
    /// 実効の隙間は `min(spacing, 親の軸方向の長さ / (子の数 - 1))`。隙間が領域に収まる通常時は
    /// `spacing` に一致し、収まらない退化ケースでは縮む（縮めないとタイルが領域の外へ出る）。
    /// あわせて全タイルが bounds の内側にあることも確かめる。
    private func expectExactTiling(
        _ tree: PaneTree,
        bounds: CGSize,
        spacing: CGFloat,
        tolerance: CGFloat = 1e-9,
        _ label: String
    ) {
        let frames = tree.frames(in: bounds, spacing: spacing)
        var rectBySession: [SessionID: CGRect] = [:]
        for tile in frames.tiles { rectBySession[tile.session] = tile.rect }
        guard let root = tree.root else {
            #expect(frames.tiles.isEmpty, "\(label): 空ツリーはタイルを持たない")
            return
        }
        #expect(frames.tiles.map(\.session) == tree.sessions, "\(label): タイル順が走査順と一致")

        for tile in frames.tiles {
            #expect(tile.rect.minX >= -tolerance, "\(label): タイルが左へはみ出す（\(tile.rect)）")
            #expect(tile.rect.minY >= -tolerance, "\(label): タイルが上へはみ出す（\(tile.rect)）")
            #expect(tile.rect.maxX <= bounds.width + tolerance, "\(label): タイルが右へはみ出す（\(tile.rect)）")
            #expect(tile.rect.maxY <= bounds.height + tolerance, "\(label): タイルが下へはみ出す（\(tile.rect)）")
            #expect(tile.rect.width >= 0 && tile.rect.height >= 0, "\(label): 負のサイズ（\(tile.rect)）")
        }
        for divider in frames.dividers {
            #expect(divider.gapRect.minX >= -tolerance, "\(label): 隙間が左へはみ出す（\(divider.gapRect)）")
            #expect(divider.gapRect.minY >= -tolerance, "\(label): 隙間が上へはみ出す（\(divider.gapRect)）")
            #expect(divider.gapRect.maxX <= bounds.width + tolerance, "\(label): 隙間が右へはみ出す")
            #expect(divider.gapRect.maxY <= bounds.height + tolerance, "\(label): 隙間が下へはみ出す")
            #expect(divider.segmentExtent >= 0, "\(label): segmentExtent が負")
        }

        // 零サイズのタイルを落とさないよう `CGRect.union` は使わず min/max で外接矩形を作る。
        func boundingBox(_ node: PaneNode) -> CGRect {
            let rects = node.sessions.compactMap { rectBySession[$0] }
            guard !rects.isEmpty else { return .null }
            let minX = rects.map(\.minX).min()!
            let minY = rects.map(\.minY).min()!
            let maxX = rects.map(\.maxX).max()!
            let maxY = rects.map(\.maxY).max()!
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        func check(_ node: PaneNode, _ rect: CGRect) {
            guard case .split(let node) = node else { return }
            let boxes = node.children.map(boundingBox)
            let isHorizontal = node.axis == .horizontal
            let starts = boxes.map { isHorizontal ? $0.minX : $0.minY }
            let ends = boxes.map { isHorizontal ? $0.maxX : $0.maxY }
            let parentStart = isHorizontal ? rect.minX : rect.minY
            let parentEnd = isHorizontal ? rect.maxX : rect.maxY

            #expect(abs(starts[0] - parentStart) <= tolerance,
                    "\(label): split \(node.id) の先頭が親の端に接する（\(starts[0]) vs \(parentStart)）")
            #expect(abs(ends[ends.count - 1] - parentEnd) <= tolerance,
                    "\(label): split \(node.id) の末尾が親の端に接する（\(ends[ends.count - 1]) vs \(parentEnd)）")
            // 通常時は spacing。隙間が領域に収まらない退化ケースだけ縮む。
            let expectedGap = max(0, min(spacing, max(0, parentEnd - parentStart) / CGFloat(boxes.count - 1)))
            for index in 0..<(boxes.count - 1) {
                let gap = starts[index + 1] - ends[index]
                #expect(abs(gap - expectedGap) <= tolerance,
                        "\(label): split \(node.id) の \(index) 番目の隙間が実効 spacing と一致（\(gap) vs \(expectedGap)）")
            }
            for (index, box) in boxes.enumerated() {
                // 直交方向は親の幅（高さ）をそのまま受け継ぐ。
                if isHorizontal {
                    #expect(abs(box.minY - rect.minY) <= tolerance, "\(label): \(node.id)[\(index)] の上端")
                    #expect(abs(box.maxY - rect.maxY) <= tolerance, "\(label): \(node.id)[\(index)] の下端")
                } else {
                    #expect(abs(box.minX - rect.minX) <= tolerance, "\(label): \(node.id)[\(index)] の左端")
                    #expect(abs(box.maxX - rect.maxX) <= tolerance, "\(label): \(node.id)[\(index)] の右端")
                }
            }
            for (child, box) in zip(node.children, boxes) { check(child, box) }
        }

        check(root, CGRect(origin: .zero, size: bounds))
    }

    /// 木の中の PaneID / SessionID を集める（重複検査用）。
    private func identifiers(_ node: PaneNode) -> (ids: [PaneID], sessions: [SessionID]) {
        switch node {
        case .leaf(let id, let session):
            return ([id], [session])
        case .split(let split):
            var ids = [split.id]
            var sessions: [SessionID] = []
            for child in split.children {
                let nested = identifiers(child)
                ids.append(contentsOf: nested.ids)
                sessions.append(contentsOf: nested.sessions)
            }
            return (ids, sessions)
        }
    }

    private func leafIDBySession(_ tree: PaneTree) -> [SessionID: PaneID] {
        var map: [SessionID: PaneID] = [:]
        func walk(_ node: PaneNode) {
            switch node {
            case .leaf(let id, let session): map[session] = id
            case .split(let split): split.children.forEach(walk)
            }
        }
        if let root = tree.root { walk(root) }
        return map
    }

    /// 不変条件が保たれているか（重複なし・weights 正で合計 1・正規形）。
    private func expectInvariants(_ tree: PaneTree, _ label: String) {
        guard let root = tree.root else { return }
        let found = identifiers(root)
        #expect(Set(found.ids).count == found.ids.count, "\(label): PaneID が重複しない")
        #expect(Set(found.sessions).count == found.sessions.count, "\(label): SessionID が重複しない")
        #expect(PaneTree.isNormalForm(root), "\(label): 正規形（子1個・同軸の入れ子が無い／合計 1）")

        func walk(_ node: PaneNode) {
            guard case .split(let split) = node else { return }
            #expect(split.children.count >= 2, "\(label): split \(split.id) の子は2個以上")
            #expect(split.weights.count == split.children.count, "\(label): weights 個数")
            for weight in split.weights {
                #expect(weight > 0, "\(label): split \(split.id) の weight が正")
            }
            #expect(abs(split.weights.reduce(0, +) - 1) <= 1e-9,
                    "\(label): split \(split.id) の weights 合計が 1（\(split.weights.reduce(0, +))）")
            split.children.forEach(walk)
        }
        walk(root)
    }

    // MARK: - H1: 矩形計算は累積座標→差分（誤差を蓄積しない）

    @Test("多子の split でも端が bounds に一致し、隙間はちょうど spacing（許容 1e-9）")
    func whitebox_frames_manyChildrenWithIndivisibleWeights_doNotAccumulateError() throws {
        // 3・7・13・50 分割 × 割り切れない bounds。丸め（floor/round）実装なら端が px 単位でずれる。
        for count in [3, 7, 13, 50] {
            let ids = (0..<count).map(sid)
            let children = (0..<count).map { leaf("L\($0)", ids[$0]) }
            let weights = (0..<count).map { _ in 1.0 / Double(count) }
            let tree = try PaneTree(root: split("S", .horizontal, children, weights))
            for bounds in [CGSize(width: 1001, height: 777), CGSize(width: 1279.5, height: 801.25)] {
                for spacing in [CGFloat(0), 1, 8, 8.5] {
                    expectExactTiling(tree, bounds: bounds, spacing: spacing, "\(count)分割 \(bounds) sp=\(spacing)")
                }
            }
        }
    }

    @Test("乱択の入れ子ツリーでも埋め尽くしが厳密に成り立つ")
    func whitebox_frames_randomNestedTrees_tileExactly() throws {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        for trial in 0..<60 {
            let leafCount = Int.random(in: 1...12, using: &rng)
            var counter = 0
            let node = randomNode(&rng, leaves: Array(0..<leafCount)[...], counter: &counter)
            let tree = try PaneTree(root: node)
            expectInvariants(tree, "trial \(trial)")
            let bounds = CGSize(
                width: CGFloat.random(in: 300...2400, using: &rng),
                height: CGFloat.random(in: 200...1600, using: &rng)
            )
            let spacing = [CGFloat(0), 1, 4, 8, 12.5].randomElement(using: &rng)!
            expectExactTiling(tree, bounds: bounds, spacing: spacing, "trial \(trial)")
        }
    }

    @Test("隙間が収まらない領域では実効の隙間が縮み、タイルが領域から出ない")
    func whitebox_frames_degenerateSpacing_shrinksGapsInsteadOfOverflowing() throws {
        // 退化ケースの境界を総当たりで踏む。spacing*(n-1) が length を超える／ちょうど一致する／
        // 下回る（通常時）を、横分割・縦分割の両方で確認する。
        for count in [2, 3, 4, 7] {
            let ids = (1...count).map(sid)
            let children = (0..<count).map { leaf("L\($0)", ids[$0]) }
            let weights = (0..<count).map { Double($0 + 1) }
            for axis in PaneAxis.allCases {
                let tree = try PaneTree(root: split("S", axis, children, weights))
                for spacing in [CGFloat(0), 1, 8, 40] {
                    // length は「隙間の総和よりずっと小さい」から「余裕がある」まで動かす。
                    for length in [CGFloat(0), 1, spacing * CGFloat(count - 1), 500] {
                        let bounds = axis == .horizontal
                            ? CGSize(width: length, height: 50)
                            : CGSize(width: 50, height: length)
                        let label = "count=\(count) axis=\(axis) sp=\(spacing) len=\(length)"
                        expectExactTiling(tree, bounds: bounds, spacing: spacing, label)

                        let frames = tree.frames(in: bounds, spacing: spacing)
                        #expect(frames.tiles.count == count, "\(label): タイル数は変わらない")
                        let expectedGap = min(spacing, length / CGFloat(count - 1))
                        for divider in frames.dividers {
                            let thickness = axis == .horizontal ? divider.gapRect.width : divider.gapRect.height
                            #expect(abs(thickness - expectedGap) <= 1e-9,
                                    "\(label): 実効の隙間 = min(spacing, length/(n-1))（\(thickness)）")
                        }
                        // 末尾は退化ケースでも領域の端にちょうど接する。
                        let far = axis == .horizontal
                            ? frames.tiles.map(\.rect.maxX).max()!
                            : frames.tiles.map(\.rect.maxY).max()!
                        #expect(abs(far - length) <= 1e-9, "\(label): 末尾が領域の端に接する（\(far)）")
                    }
                }
            }
        }
    }

    @Test("極端に狭い領域の入れ子ツリーでもタイルが領域から出ない")
    func whitebox_frames_tinyBoundsWithDeepTree_staysInsideBounds() throws {
        var rng = SeededGenerator(seed: 0x5EED)
        for trial in 0..<20 {
            let leafCount = Int.random(in: 4...12, using: &rng)
            var counter = 0
            let tree = try PaneTree(root: randomNode(&rng, leaves: Array(0..<leafCount)[...], counter: &counter))
            for bounds in [CGSize(width: 0, height: 0), CGSize(width: 12, height: 9), CGSize(width: 40, height: 3)] {
                expectExactTiling(tree, bounds: bounds, spacing: 8, "trial \(trial) \(bounds)")
            }
        }
    }

    @Test("タイルは重ならない（乱択の木）")
    func whitebox_frames_randomTrees_tilesDoNotOverlap() throws {
        var rng = SeededGenerator(seed: 42)
        for trial in 0..<30 {
            let leafCount = Int.random(in: 2...10, using: &rng)
            var counter = 0
            let tree = try PaneTree(root: randomNode(&rng, leaves: Array(0..<leafCount)[...], counter: &counter))
            let rects = tree.frames(in: CGSize(width: 1400, height: 900), spacing: 6).tiles.map(\.rect)
            for i in rects.indices {
                for j in rects.indices where j > i {
                    #expect(!rects[i].intersects(rects[j].insetBy(dx: 0.001, dy: 0.001)),
                            "trial \(trial): タイル \(i) と \(j) が重なる")
                }
            }
        }
    }

    @Test("分割線の segment 値がタイル実測と一致する（spacing を含まない）")
    func whitebox_dividerFrames_matchMeasuredTiles() throws {
        var rng = SeededGenerator(seed: 7)
        for trial in 0..<20 {
            let leafCount = Int.random(in: 2...9, using: &rng)
            var counter = 0
            let tree = try PaneTree(root: randomNode(&rng, leaves: Array(0..<leafCount)[...], counter: &counter))
            let bounds = CGSize(width: 1600, height: 1000)
            let spacing: CGFloat = 8
            let frames = tree.frames(in: bounds, spacing: spacing)
            for divider in frames.dividers {
                #expect(divider.leadingFraction > 0 && divider.leadingFraction < 1,
                        "trial \(trial): leadingFraction が開区間 (0,1)")
                let gapThickness = divider.axis == .horizontal ? divider.gapRect.width : divider.gapRect.height
                #expect(abs(gapThickness - spacing) <= 1e-9, "trial \(trial): gapRect の太さ = spacing")
                let hitThickness = divider.axis == .horizontal ? divider.rect.width : divider.rect.height
                #expect(hitThickness >= PaneTree.dividerHitThickness - 1e-9, "trial \(trial): 掴む領域の太さ")
                // segmentOrigin + segmentExtent + spacing = 隣接2枚の領域の終端
                let segmentEnd = divider.segmentOrigin + divider.segmentExtent + spacing
                let gapEnd = divider.axis == .horizontal ? divider.gapRect.maxX : divider.gapRect.maxY
                #expect(segmentEnd > gapEnd, "trial \(trial): 終端は隙間の先にある")
            }
        }
    }

    // MARK: - H2: 正規化は収束するまで繰り返す

    @Test("単子 split の長い連鎖は1枚の leaf まで畳まれ、leaf の ID は変わらない")
    func whitebox_normalization_longSingleChildChain_collapsesToLeaf() throws {
        var node = leaf("target", sid(1))
        for depth in 0..<12 {
            node = split("wrap\(depth)", depth.isMultiple(of: 2) ? .horizontal : .vertical, [node], [1.0])
        }
        let tree = try PaneTree(root: node)
        guard case .leaf(let id, let session) = try #require(tree.root) else {
            Issue.record("leaf まで畳まれていない"); return
        }
        #expect(id == pid("target"), "生き残った leaf の PaneID を作り替えない")
        #expect(session == sid(1))
    }

    @Test("畳み込み→平坦化→畳み込みの連鎖が不動点まで解ける")
    func whitebox_normalization_collapseInducesFlattenInducesCollapse() throws {
        // root(h) ─ M(h, 子1個) ─ N(h) ─ [B, C]
        // 素直な1回のトップダウン処理だと M を畳んだ後の N（root と同軸）が残る。
        let inner = split("N", .horizontal, [leaf("B", sid(2)), leaf("C", sid(3))], [0.25, 0.75])
        let mid = split("M", .horizontal, [inner], [1.0])
        let tree = try PaneTree(root: split("root", .horizontal, [leaf("A", sid(1)), mid], [0.4, 0.6]))

        guard case .split(let root) = try #require(tree.root) else {
            Issue.record("root が split でない"); return
        }
        #expect(root.children.count == 3, "A・B・C の3枚まで平坦化される")
        #expect(root.children.map(\.id) == [pid("A"), pid("B"), pid("C")])
        guard root.children.count == 3 else { return }
        #expect(abs(root.weights[0] - 0.4) < 1e-12, "A の取り分")
        #expect(abs(root.weights[1] - 0.6 * 0.25) < 1e-12, "B は積で合成される")
        #expect(abs(root.weights[2] - 0.6 * 0.75) < 1e-12, "C は積で合成される")
        expectInvariants(tree, "cascade")
    }

    @Test("多段の入れ子（同軸 split の連鎖）が1本に平坦化される")
    func whitebox_normalization_deepSameAxisChain_flattensCompletely() throws {
        // h[ L0, h[ L1, h[ L2, h[ L3, ... ] ] ] ] を8段。
        var node = leaf("L7", sid(7))
        for index in stride(from: 6, through: 0, by: -1) {
            node = split("S\(index)", .horizontal, [leaf("L\(index)", sid(index)), node], [0.5, 0.5])
        }
        let tree = try PaneTree(root: node)
        guard case .split(let root) = try #require(tree.root) else {
            Issue.record("root が split でない"); return
        }
        #expect(root.children.count == 8, "8枚が同一 split の直下に並ぶ")
        #expect(root.children.allSatisfy { if case .leaf = $0 { return true } else { return false } })
        guard root.children.count == 8 else { return }
        #expect(abs(root.weights.reduce(0, +) - 1) <= 1e-9)
        // 取り分は 1/2, 1/4, ... , 1/128, 1/128
        #expect(abs(root.weights[0] - 0.5) < 1e-12)
        #expect(abs(root.weights[6] - root.weights[7]) < 1e-15, "末尾2枚は同じ取り分")
        expectInvariants(tree, "deep chain")
    }

    @Test("正規化は不動点: 正規化済みの木をもう一度 init に通しても完全に同じ")
    func whitebox_normalization_isFixpoint() throws {
        var rng = SeededGenerator(seed: 2024)
        for trial in 0..<40 {
            let leafCount = Int.random(in: 1...10, using: &rng)
            var counter = 0
            let tree = try PaneTree(root: randomNode(&rng, leaves: Array(0..<leafCount)[...], counter: &counter))
            let again = try PaneTree(root: tree.root)
            #expect(again == tree, "trial \(trial): 再正規化で木が変化しない（weights の漂いも無い）")
        }
    }

    // MARK: - H3: weights の再正規化は「1.0 からずれている場合だけ」

    @Test("合計が 1 とみなせる weights はビット単位で温存される")
    func whitebox_init_keepsWeightsBitwiseWhenSumIsCloseEnoughToOne() throws {
        // 6等分は合計が 0.9999999999999999 になり、1.0 とはビット単位で一致しない。
        // それでも 1e-9 以内なので「触らない」のが契約。
        let sixths = Array(repeating: 1.0 / 6, count: 6)
        #expect(sixths.reduce(0, +) != 1.0, "前提: 6等分の合計はビット単位では 1.0 にならない")
        let drifted = sixths.map { $0 / sixths.reduce(0, +) }
        #expect(drifted != sixths, "前提: 無条件に再正規化すると値が変わる")

        let tree = try PaneTree(root: split(
            "S", .horizontal,
            (0..<6).map { leaf("L\($0)", sid($0 + 1)) },
            sixths
        ))
        guard case .split(let root) = try #require(tree.root) else {
            Issue.record("root が split でない"); return
        }
        #expect(root.weights == sixths, "1e-9 以内なら触らない（触ると往復・再適用で漂う）")
    }

    @Test("合計が明確にずれていれば再正規化する（比は保つ）")
    func whitebox_init_renormalizesWhenSumIsClearlyOff() throws {
        let tree = try PaneTree(root: split(
            "S", .vertical, [leaf("A", sid(1)), leaf("B", sid(2))], [2.0, 6.0]
        ))
        guard case .split(let root) = try #require(tree.root) else {
            Issue.record("root が split でない"); return
        }
        #expect(abs(root.weights[0] - 0.25) < 1e-15)
        #expect(abs(root.weights[1] - 0.75) < 1e-15)
    }

    @Test("Codable の往復を重ねても木が漂わない")
    func whitebox_codable_repeatedRoundTripsAreBitwiseStable() throws {
        let ids = (1...5).map(sid)
        var tree = PaneLayoutPreset.mainLeftStackRight.tree(for: ids)
        tree = tree.settingDivider(
            try #require(tree.frames(in: CGSize(width: 1600, height: 1000), spacing: 8).dividers.first).id,
            leadingFraction: 0.371
        )
        var current = tree
        for cycle in 0..<8 {
            let data = try JSONEncoder().encode(current)
            current = try JSONDecoder().decode(PaneTree.self, from: data)
            #expect(current == tree, "\(cycle) 周目の往復で木が変化した")
        }
    }

    @Test("reconciled を繰り返しても木が漂わない")
    func whitebox_reconciled_repeatedApplicationIsBitwiseStable() throws {
        let ids = (1...6).map(sid)
        let bounds = CGSize(width: 1600, height: 1000)
        let tree = PaneLayoutPreset.balanced.tree(for: ids)
        var current = tree
        for round in 0..<20 {
            current = current.reconciled(with: ids, bounds: bounds, spacing: 8)
            #expect(current == tree, "\(round) 回目の reconcile で木が変化した")
        }
    }

    @Test("settingDivider は同じ値の再適用で漂わない")
    func whitebox_settingDivider_reapplyingSameFractionIsStable() throws {
        let ids = (1...4).map(sid)
        let tree = try PaneTree(root: split(
            "S", .horizontal,
            ids.enumerated().map { leaf("L\($0.offset)", $0.element) },
            [0.31, 0.19, 0.23, 0.27]
        ))
        let divider = PaneDividerID(split: pid("S"), leading: pid("L1"), trailing: pid("L2"))
        let once = tree.settingDivider(divider, leadingFraction: 0.6180339887)
        var current = once
        for round in 0..<10 {
            current = current.settingDivider(divider, leadingFraction: 0.6180339887)
            #expect(current == once, "\(round) 回目の再適用で木が変化した")
        }
    }

    // MARK: - H4: PaneID の安定性

    @Test("刈り込みで生き残った leaf の PaneID は常に永続ツリーと同じ")
    func whitebox_pruned_allSubsets_keepSurvivingPaneIDs() throws {
        let ids = (1...5).map(sid)
        let persisted = try PaneTree(root: split(
            "root", .horizontal,
            [
                leaf("A", ids[0]),
                split("mid", .vertical, [
                    leaf("B", ids[1]),
                    split("deep", .horizontal, [leaf("C", ids[2]), leaf("D", ids[3])], [0.4, 0.6]),
                ], [0.3, 0.7]),
                leaf("E", ids[4]),
            ],
            [0.2, 0.5, 0.3]
        ))
        let persistedIDs = leafIDBySession(persisted)
        let originalIDs = Set(identifiers(try #require(persisted.root)).ids)

        for mask in 0..<32 {
            let visible = Set(ids.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
            let effective = persisted.pruned(visible: visible)
            #expect(persisted.sessions == ids, "mask \(mask): 永続ツリーは変わらない（純粋）")
            #expect(Set(effective.sessions) == visible, "mask \(mask): 可視集合そのものが残る")
            for (session, id) in leafIDBySession(effective) {
                #expect(id == persistedIDs[session], "mask \(mask): \(session) の leaf ID が作り替えられた")
            }
            if let root = effective.root {
                #expect(Set(identifiers(root).ids).isSubset(of: originalIDs),
                        "mask \(mask): 新しい PaneID が生えていない（消えるのは畳まれた split の ID だけ）")
                expectInvariants(effective, "mask \(mask)")
            }
        }
    }

    @Test("removing でも生き残ったノードの PaneID は変わらない")
    func whitebox_removing_keepsSurvivingPaneIDs() throws {
        let ids = (1...4).map(sid)
        var tree = try PaneTree(root: split(
            "root", .vertical,
            [
                split("top", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]),
                split("bottom", .horizontal, [leaf("C", ids[2]), leaf("D", ids[3])], [0.5, 0.5]),
            ],
            [0.5, 0.5]
        ))
        let original = leafIDBySession(tree)
        for removed in ids.dropLast() {
            tree = tree.removing(removed)
            for (session, id) in leafIDBySession(tree) {
                #expect(id == original[session], "\(session) の leaf ID が \(removed) の削除で作り替えられた")
            }
            expectInvariants(tree, "removing \(removed)")
        }
        #expect(tree.sessions == [ids[3]])
    }

    @Test("同じセッションを取り除いて入れ直すと同じ leaf ID に戻る")
    func whitebox_insertion_reusesDeterministicLeafID() throws {
        let ids = (1...3).map(sid)
        let bounds = CGSize(width: 1600, height: 1000)
        let tree = PaneLayoutPreset.balanced.tree(for: ids)
        let before = leafIDBySession(tree)
        let cycled = tree.removing(ids[1]).insertingIntoLargestPane(ids[1], bounds: bounds, spacing: 8)
        #expect(leafIDBySession(cycled)[ids[1]] == before[ids[1]], "leaf ID はセッションから決まる")
    }

    // MARK: - H5: settingDivider は隣接2枚の合計の中だけで再配分する

    @Test("間に挟まる子の weight はビット単位で不変（隠れた兄弟を跨ぐ操作）")
    func whitebox_settingDivider_leavesInBetweenWeightsBitwiseUntouched() throws {
        let ids = (1...6).map(sid)
        let weights = [0.11, 0.07, 0.23, 0.31, 0.13, 0.15]
        let tree = try PaneTree(root: split(
            "S", .horizontal,
            ids.enumerated().map { leaf("L\($0.offset)", $0.element) },
            weights
        ))
        guard case .split(let before) = try #require(tree.root) else {
            Issue.record("root が split でない"); return
        }

        for fraction in [0.05, 0.2, 0.5, 0.73, 0.95] {
            let updated = tree.settingDivider(
                PaneDividerID(split: pid("S"), leading: pid("L0"), trailing: pid("L5")),
                leadingFraction: fraction
            )
            guard case .split(let after) = try #require(updated.root) else {
                Issue.record("root が split でない"); return
            }
            for index in 1...4 {
                #expect(after.weights[index] == before.weights[index],
                        "fraction=\(fraction): 間の子 \(index) の weight がビット単位で変わった")
            }
            let combinedBefore = before.weights[0] + before.weights[5]
            let combinedAfter = after.weights[0] + after.weights[5]
            #expect(abs(combinedAfter - combinedBefore) <= 1e-15, "fraction=\(fraction): 2枚の合計は不変")
            #expect(abs(after.weights[0] / combinedAfter - fraction) <= 1e-12,
                    "fraction=\(fraction): 合計に対する比が指定どおり（全体の再正規化を挟んでいない）")
        }
    }

    @Test("クランプは合計に対する比に効き、合計自体は動かさない")
    func whitebox_settingDivider_clampAppliesToTheLocalShareOnly() throws {
        let ids = (1...3).map(sid)
        let tree = try PaneTree(root: split(
            "S", .vertical,
            [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
            [0.6, 0.3, 0.1]
        ))
        let divider = PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("B"))
        for requested in [-5.0, 0.0, 0.01, 0.99, 1.0, 12.0] {
            guard case .split(let after) = try #require(tree.settingDivider(divider, leadingFraction: requested).root) else {
                Issue.record("root が split でない"); return
            }
            let combined = after.weights[0] + after.weights[1]
            #expect(abs(combined - 0.9) <= 1e-15, "requested=\(requested): A+B の合計は 0.9 のまま")
            #expect(after.weights[2] == 0.1, "requested=\(requested): C は不変")
            let share = after.weights[0] / combined
            #expect(share >= PaneTree.minimumDividerFraction - 1e-12, "requested=\(requested): 下限クランプ")
            #expect(share <= 1 - PaneTree.minimumDividerFraction + 1e-12, "requested=\(requested): 上限クランプ")
        }
    }

    @Test("非有限の leadingFraction は木を壊さない")
    func whitebox_settingDivider_nonFiniteFractionIsIgnored() throws {
        let ids = (1...2).map(sid)
        let tree = try PaneTree(root: split(
            "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
        ))
        let divider = PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("B"))
        #expect(tree.settingDivider(divider, leadingFraction: .nan) == tree)
        #expect(tree.settingDivider(divider, leadingFraction: .infinity) == tree)
    }

    // MARK: - 不変条件違反の検出（正規化で黙って通していないか）

    @Test("入れ子の空 split・weights 個数不一致も検出する")
    func whitebox_init_rejectsViolationsNestedDeepInTheTree() {
        #expect(throws: PaneTreeError.self) {
            _ = try PaneTree(root: self.split(
                "root", .horizontal,
                [
                    self.leaf("A", self.sid(1)),
                    self.split("mid", .vertical, [self.split("empty", .horizontal, [], [])], [1.0]),
                ],
                [0.5, 0.5]
            ))
        }
        #expect(throws: PaneTreeError.self) {
            _ = try PaneTree(root: self.split(
                "root", .horizontal,
                [
                    self.leaf("A", self.sid(1)),
                    self.split("mid", .vertical, [self.leaf("B", self.sid(2)), self.leaf("C", self.sid(3))], [1.0]),
                ],
                [0.5, 0.5]
            ))
        }
    }

    @Test("NaN・無限大の weight を拒否する")
    func whitebox_init_rejectsNonFiniteWeights() {
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(throws: PaneTreeError.self) {
                _ = try PaneTree(root: self.split(
                    "S", .horizontal, [self.leaf("A", self.sid(1)), self.leaf("B", self.sid(2))], [bad, 0.5]
                ))
            }
        }
    }

    // MARK: - 乱択の操作列（不変条件が壊れないこと）

    @Test("乱択の操作列 300 回でも不変条件と埋め尽くしが保たれる")
    func whitebox_randomOperationSequence_preservesInvariants() throws {
        var rng = SeededGenerator(seed: 0xDECAF)
        let pool = (1...9).map(sid)
        let bounds = CGSize(width: 1533, height: 921)
        let spacing: CGFloat = 7
        var tree = PaneLayoutPreset.balanced.tree(for: Array(pool.prefix(4)))

        for step in 0..<300 {
            let label = "step \(step)"
            switch Int.random(in: 0..<6, using: &rng) {
            case 0:
                tree = tree.insertingIntoLargestPane(pool.randomElement(using: &rng)!, bounds: bounds, spacing: spacing)
            case 1:
                tree = tree.removing(pool.randomElement(using: &rng)!)
            case 2:
                let frames = tree.frames(in: bounds, spacing: spacing)
                if let divider = frames.dividers.randomElement(using: &rng) {
                    tree = tree.settingDivider(divider.id, leadingFraction: Double.random(in: -0.2...1.2, using: &rng))
                }
            case 3:
                if let a = tree.sessions.randomElement(using: &rng), let b = tree.sessions.randomElement(using: &rng) {
                    tree = tree.swapping(a, b)
                }
            case 4:
                if let target = tree.sessions.randomElement(using: &rng) {
                    let edge = PaneEdge.allCases.randomElement(using: &rng)!
                    tree = tree.inserting(pool.randomElement(using: &rng)!, splitting: target, edge: edge)
                }
            default:
                let visible = Set(tree.sessions.filter { _ in Bool.random(using: &rng) })
                let effective = tree.pruned(visible: visible)
                expectInvariants(effective, "\(label) (pruned)")
                expectExactTiling(effective, bounds: bounds, spacing: spacing, "\(label) (pruned)")
            }

            expectInvariants(tree, label)
            expectExactTiling(tree, bounds: bounds, spacing: spacing, label)
            #expect(tree.frames(in: bounds, spacing: spacing).tiles.count == tree.sessions.count, "\(label): タイル数")
            #expect(Set(tree.sessions).isSubset(of: Set(pool)), "\(label): 知らないセッションが生えない")
        }
    }

    // MARK: - スコープの契約（純粋な値型）

    @Test("PaneLayout/ の実装は SwiftUI・AppKit を import しない")
    func whitebox_paneLayoutSources_areFreeOfUIFrameworks() throws {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SessionFeature/PaneLayout")
        let files = try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count == 5, "PaneLayout/ のファイル数")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("import SwiftUI"), "\(file.lastPathComponent) が SwiftUI を import している")
            #expect(!text.contains("import AppKit"), "\(file.lastPathComponent) が AppKit を import している")
        }
    }
}
