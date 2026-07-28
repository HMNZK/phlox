import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-1（分割ツリーの純粋モデル）の受け入れテスト。PM が著す不変の契約
// （実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を
// 得たうえでハーネス部分に限り修理してよい）。
//
// 契約の骨子（tasks/task-1.md）:
// - PaneTree は n 分岐の分割ツリー。PaneTree.init(root:) が唯一の検証・正規化の入口。
// - 分割線は index ではなく「両隣のノード ID」で識別する（D10）。
// - frames() のタイル矩形は隙間を含まない。最外周は bounds に接し、隣接間隔はちょうど spacing。
// - pruned() は永続ツリーを変えず、生き残ったノードの PaneID を作り替えない。

// MARK: - テストハーネス

private func sid(_ n: Int) -> SessionID {
    // 決定論的な SessionID。下位バイトだけを変える。
    let hex = String(format: "%012x", n)
    return SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(hex)")!)
}

private func pid(_ name: String) -> PaneID { PaneID(name) }

private func leaf(_ name: String, _ session: SessionID) -> PaneNode {
    .leaf(id: pid(name), session: session)
}

private func split(
    _ name: String,
    _ axis: PaneAxis,
    _ children: [PaneNode],
    _ weights: [Double]
) -> PaneNode {
    .split(PaneSplit(id: pid(name), axis: axis, children: children, weights: weights))
}

private func tile(_ frames: PaneLayoutFrames, _ session: SessionID) -> CGRect? {
    frames.tiles.first(where: { $0.session == session })?.rect
}

private func expectClose<T: BinaryFloatingPoint>(
    _ actual: T,
    _ expected: T,
    _ tolerance: T,
    _ label: String
) {
    #expect(
        abs(actual - expected) <= tolerance,
        "\(label): expected \(expected) ± \(tolerance), got \(actual)"
    )
}

private func expectRect(_ actual: CGRect?, _ expected: CGRect, _ label: String) {
    guard let actual else {
        Issue.record("\(label): タイルが見つからない")
        return
    }
    expectClose(actual.minX, expected.minX, 0.5, "\(label).minX")
    expectClose(actual.minY, expected.minY, 0.5, "\(label).minY")
    expectClose(actual.width, expected.width, 0.5, "\(label).width")
    expectClose(actual.height, expected.height, 0.5, "\(label).height")
}

// MARK: - S1: ユーザー要望のレイアウトを表現できる

@Test
func mainLeftStackRightPreset_producesLeftHalfPlusTwoStackedOnRight() throws {
    let (a, b, c) = (sid(1), sid(2), sid(3))
    let tree = PaneLayoutPreset.mainLeftStackRight.tree(for: [a, b, c])
    let frames = tree.frames(in: CGSize(width: 1000, height: 800), spacing: 8)

    #expect(frames.tiles.count == 3)
    // 左半分が1枚（幅 = (1000 - 8) / 2 = 496、高さは全高）
    expectRect(tile(frames, a), CGRect(x: 0, y: 0, width: 496, height: 800), "左ペイン")
    // 右半分を上下に2枚（高さ = (800 - 8) / 2 = 396）
    expectRect(tile(frames, b), CGRect(x: 504, y: 0, width: 496, height: 396), "右上ペイン")
    expectRect(tile(frames, c), CGRect(x: 504, y: 404, width: 496, height: 396), "右下ペイン")
    // 分割線は縦1本＋横1本
    #expect(frames.dividers.count == 2)
    #expect(frames.dividers.filter { $0.axis == .horizontal }.count == 1)
    #expect(frames.dividers.filter { $0.axis == .vertical }.count == 1)
}

@Test
func mainTopStackBottomPreset_producesTopHalfPlusTwoSideBySide() throws {
    let (a, b, c) = (sid(1), sid(2), sid(3))
    let tree = PaneLayoutPreset.mainTopStackBottom.tree(for: [a, b, c])
    let frames = tree.frames(in: CGSize(width: 1000, height: 800), spacing: 8)

    expectRect(tile(frames, a), CGRect(x: 0, y: 0, width: 1000, height: 396), "上ペイン")
    expectRect(tile(frames, b), CGRect(x: 0, y: 404, width: 496, height: 396), "下左ペイン")
    expectRect(tile(frames, c), CGRect(x: 504, y: 404, width: 496, height: 396), "下右ペイン")
}

@Test
func everyPreset_placesAllSessionsWithoutLoss() {
    let sessions = (1...5).map(sid)
    for preset in PaneLayoutPreset.allCases {
        let tree = preset.tree(for: sessions)
        #expect(
            Set(tree.sessions) == Set(sessions),
            "\(preset.rawValue): 全セッションが配置されること（溢れさせない）"
        )
        let frames = tree.frames(in: CGSize(width: 1200, height: 900), spacing: 8)
        #expect(frames.tiles.count == sessions.count, "\(preset.rawValue): タイル数")
    }
}

@Test
func preset_withEmptySessions_producesEmptyTree() {
    for preset in PaneLayoutPreset.allCases {
        let tree = preset.tree(for: [])
        #expect(tree.root == nil, "\(preset.rawValue): 空集合なら空ツリー")
        #expect(tree.frames(in: CGSize(width: 800, height: 600), spacing: 8).tiles.isEmpty)
    }
}

@Test
func preset_displayNameIsNonEmpty() {
    for preset in PaneLayoutPreset.allCases {
        #expect(!preset.displayName.isEmpty, "\(preset.rawValue): 表示名が空でない")
    }
}

// MARK: - 矩形計算の埋め尽くし契約（誤差を蓄積しない）

@Test
func frames_singleLeaf_fillsBoundsExactly() throws {
    let tree = try PaneTree(root: leaf("L", sid(1)))
    let frames = tree.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    expectRect(tile(frames, sid(1)), CGRect(x: 0, y: 0, width: 1000, height: 800), "単一ペイン")
    #expect(frames.dividers.isEmpty)
}

@Test
func frames_threeColumnsWithIndivisibleBounds_touchBoundsEdgesAndKeepExactSpacing() throws {
    // 1001 は 3 で割り切れない。累積座標→差分で計算していないと端が合わない。
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [1.0 / 3, 1.0 / 3, 1.0 / 3]
    ))
    let bounds = CGSize(width: 1001, height: 777)
    let frames = tree.frames(in: bounds, spacing: 8)
    let rects = ids.compactMap { tile(frames, $0) }
    #expect(rects.count == 3)

    expectClose(rects[0].minX, 0, 0.5, "左端が bounds に接する")
    expectClose(rects[2].maxX, bounds.width, 0.5, "右端が bounds に接する")
    for rect in rects {
        expectClose(rect.minY, 0, 0.5, "上端")
        expectClose(rect.height, bounds.height, 0.5, "高さは全高")
    }
    expectClose(rects[1].minX - rects[0].maxX, 8, 0.5, "1本目の隙間がちょうど spacing")
    expectClose(rects[2].minX - rects[1].maxX, 8, 0.5, "2本目の隙間がちょうど spacing")
}

@Test
func frames_nestedTree_touchesAllFourBoundsEdges() throws {
    let ids = (1...4).map(sid)
    let tree = try PaneTree(root: split(
        "root", .horizontal,
        [
            leaf("A", ids[0]),
            split("R", .vertical, [leaf("B", ids[1]), leaf("C", ids[2]), leaf("D", ids[3])], [0.2, 0.3, 0.5]),
        ],
        [0.37, 0.63]
    ))
    let bounds = CGSize(width: 999, height: 701)
    let frames = tree.frames(in: bounds, spacing: 6)
    let all = frames.tiles.map(\.rect)

    expectClose(all.map(\.minX).min()!, 0, 0.5, "左端")
    expectClose(all.map(\.maxX).max()!, bounds.width, 0.5, "右端")
    expectClose(all.map(\.minY).min()!, 0, 0.5, "上端")
    expectClose(all.map(\.maxY).max()!, bounds.height, 0.5, "下端")

    // タイル同士が重ならない
    for i in all.indices {
        for j in all.indices where j > i {
            #expect(!all[i].intersects(all[j].insetBy(dx: 0.5, dy: 0.5)), "タイル \(i) と \(j) が重ならない")
        }
    }
}

@Test
func frames_tileOrderMatchesSessionTraversalOrder() throws {
    let ids = (1...4).map(sid)
    let tree = try PaneTree(root: split(
        "root", .horizontal,
        [
            split("L", .vertical, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]),
            split("R", .vertical, [leaf("C", ids[2]), leaf("D", ids[3])], [0.5, 0.5]),
        ],
        [0.5, 0.5]
    ))
    #expect(tree.sessions == ids)
    let frames = tree.frames(in: CGSize(width: 800, height: 600), spacing: 8)
    #expect(frames.tiles.map(\.session) == tree.sessions, "描画順が決定的で走査順と一致する")
}

// MARK: - 分割線フレームの契約（task-2 が使う値）

@Test
func dividerFrame_segmentExtentExcludesSpacing() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    let frames = tree.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    let divider = try #require(frames.dividers.first)

    #expect(divider.axis == .horizontal)
    #expect(divider.id.split == pid("S"))
    #expect(divider.id.leading == pid("A"))
    #expect(divider.id.trailing == pid("B"))
    // 2枚のタイル部分だけの合計（1000 - 8 = 992）。spacing を含まない。
    expectClose(divider.segmentExtent, 992, 0.5, "segmentExtent")
    expectClose(divider.segmentOrigin, 0, 0.5, "segmentOrigin")
    expectClose(divider.leadingFraction, 0.5, 0.001, "leadingFraction")
    // 隙間の実体は spacing 幅
    expectClose(divider.gapRect.width, 8, 0.5, "gapRect の太さ = spacing")
    expectClose(divider.gapRect.minX, 496, 0.5, "gapRect の位置")
    // 掴む領域は最低 dividerHitThickness まで太る
    #expect(divider.rect.width >= PaneTree.dividerHitThickness - 0.001)
    expectClose(divider.rect.midX, divider.gapRect.midX, 0.5, "掴む領域は隙間の中心を保つ")
}

@Test
func dividerFrame_thinSpacing_stillHasGrabbableThickness() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "S", .vertical, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    let frames = tree.frames(in: CGSize(width: 600, height: 400), spacing: 1)
    let divider = try #require(frames.dividers.first)
    #expect(divider.axis == .vertical)
    expectClose(divider.gapRect.height, 1, 0.5, "隙間の実体は spacing のまま")
    #expect(divider.rect.height >= PaneTree.dividerHitThickness - 0.001, "掴む領域は太らせる")
}

@Test
func dividerFrame_segmentValuesReflectUnevenWeights() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    // 幅 1000, spacing 10 → 隙間2本で content = 980。A=196, B=294, C=490
    let frames = tree.frames(in: CGSize(width: 1000, height: 500), spacing: 10)
    #expect(frames.dividers.count == 2)

    let first = try #require(frames.dividers.first(where: { $0.id.leading == pid("A") }))
    #expect(first.id.trailing == pid("B"))
    expectClose(first.segmentExtent, 196 + 294, 1.0, "A+B のタイル部分の合計")
    expectClose(first.segmentOrigin, 0, 0.5, "A の左端から始まる")
    expectClose(first.leadingFraction, 196.0 / 490.0, 0.01, "隣接2枚の合計に対する A の取り分")

    let second = try #require(frames.dividers.first(where: { $0.id.leading == pid("B") }))
    #expect(second.id.trailing == pid("C"))
    expectClose(second.segmentExtent, 294 + 490, 1.0, "B+C のタイル部分の合計")
    expectClose(second.segmentOrigin, 196 + 10, 1.0, "B の左端から始まる")
}

// MARK: - 不変条件の検証（init で throw する）

@Test
func init_rejectsEmptySplit() {
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split("S", .horizontal, [], []))
    }
}

@Test
func init_collapsesSplitWithSingleChild() throws {
    // 子1個の split は「拒否」ではなく「畳む」（正規化）。
    // 削除・刈り込みの途中で自然に生じる形なので、init が受理して正規形へ直す。
    let tree = try PaneTree(root: split("S", .horizontal, [leaf("A", sid(1))], [1.0]))
    guard case .leaf(let id, let session) = try #require(tree.root) else {
        Issue.record("root が leaf でない（子1個の split が畳まれていない）"); return
    }
    #expect(id == pid("A"), "生き残ったノードの PaneID は作り替えない")
    #expect(session == sid(1))
}

@Test
func init_rejectsWeightCountMismatch() {
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.3, 0.2]
        ))
    }
}

@Test
func init_rejectsNonPositiveWeight() {
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [1.0, 0.0]
        ))
    }
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [1.5, -0.5]
        ))
    }
}

@Test
func init_rejectsDuplicateSession() {
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(1))], [0.5, 0.5]
        ))
    }
}

@Test
func init_rejectsDuplicatePaneID() {
    // leaf と split の区別なく PaneID は一意でなければならない。
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "S", .horizontal, [leaf("dup", sid(1)), leaf("dup", sid(2))], [0.5, 0.5]
        ))
    }
    #expect(throws: PaneTreeError.self) {
        _ = try PaneTree(root: split(
            "X", .horizontal,
            [leaf("A", sid(1)), split("X", .vertical, [leaf("B", sid(2)), leaf("C", sid(3))], [0.5, 0.5])],
            [0.5, 0.5]
        ))
    }
}

@Test
func init_normalizesWeightsToSumOne() throws {
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [3.0, 1.0]
    ))
    guard case .split(let s) = try #require(tree.root) else {
        Issue.record("root が split でない"); return
    }
    expectClose(CGFloat(s.weights.reduce(0, +)), 1.0, 0.000_001, "weights の合計")
    expectClose(CGFloat(s.weights[0]), 0.75, 0.000_001, "比率は保たれる")
}

@Test
func init_doesNotImposeGlobalMinimumWeight_soManyChildrenAreAllowed() throws {
    // 各 weight に一律下限 0.05 を課すと 21 子以上が作れなくなる。課していないことを固定する。
    let ids = (1...30).map(sid)
    let children = ids.enumerated().map { leaf("L\($0.offset)", $0.element) }
    let tree = try PaneTree(root: split(
        "S", .horizontal, children, Array(repeating: 1.0, count: 30)
    ))
    #expect(tree.sessions.count == 30)
    #expect(tree.frames(in: CGSize(width: 2000, height: 800), spacing: 4).tiles.count == 30)
}

// MARK: - 正規形（平坦化・畳み込みが収束するまで繰り返される）

@Test
func init_flattensNestedSplitWithSameAxis() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "outer", .horizontal,
        [
            leaf("A", ids[0]),
            split("inner", .horizontal, [leaf("B", ids[1]), leaf("C", ids[2])], [0.5, 0.5]),
        ],
        [0.5, 0.5]
    ))
    guard case .split(let s) = try #require(tree.root) else {
        Issue.record("root が split でない"); return
    }
    #expect(s.children.count == 3, "同軸の入れ子が平坦化される")
    // weights は積で合成される: [0.5, 0.5*0.5, 0.5*0.5]
    expectClose(CGFloat(s.weights[0]), 0.5, 0.000_001, "A の取り分は保たれる")
    expectClose(CGFloat(s.weights[1]), 0.25, 0.000_001, "B の取り分は積で合成される")
    expectClose(CGFloat(s.weights[2]), 0.25, 0.000_001, "C の取り分は積で合成される")
}

@Test
func init_flatteningAndCollapsingConvergeTogether() throws {
    // 畳み込みが平坦化を誘発し、平坦化がさらに畳み込みを誘発する形。1回では収束しない。
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "outer", .horizontal,
        [
            leaf("A", ids[0]),
            // 子1個の split（畳まれる）→ その中身が同軸 split（平坦化される）
            split("mid", .vertical, [
                split("inner", .horizontal, [leaf("B", ids[1])], [1.0]),
            ], [1.0]),
        ],
        [0.6, 0.4]
    ))
    guard case .split(let s) = try #require(tree.root) else {
        Issue.record("root が split でない"); return
    }
    #expect(s.axis == .horizontal)
    #expect(s.children.count == 2, "収束後は A と B の2枚")
    #expect(tree.sessions == ids)
}

// MARK: - pruned（実効ツリー）: 永続ツリーを変えず ID を保つ

@Test
func pruned_removesHiddenLeavesAndSiblingsAbsorbSpace() throws {
    let ids = (1...3).map(sid)
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    let effective = persisted.pruned(visible: [ids[0], ids[2]])

    #expect(effective.sessions == [ids[0], ids[2]])
    #expect(persisted.sessions == ids, "永続ツリーは変わらない（純粋）")

    guard case .split(let s) = try #require(effective.root) else {
        Issue.record("root が split でない"); return
    }
    expectClose(CGFloat(s.weights.reduce(0, +)), 1.0, 0.000_001, "再正規化される")
    expectClose(CGFloat(s.weights[0]), 0.2 / 0.7, 0.000_001, "残った兄弟の相対比は保たれる")
}

@Test
func pruned_keepsPaneIDsOfSurvivingNodes() throws {
    let ids = (1...3).map(sid)
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    let effective = persisted.pruned(visible: [ids[0], ids[2]])
    let frames = effective.frames(in: CGSize(width: 1000, height: 600), spacing: 8)
    let divider = try #require(frames.dividers.first)

    // ここが D10 の中核。index ベースだと A|B を指してしまう。
    #expect(divider.id.split == pid("S"))
    #expect(divider.id.leading == pid("A"))
    #expect(divider.id.trailing == pid("C"), "刈り込み後の分割線は A|C を指す")
}

@Test
func pruned_collapsesSplitWhenOnlyOneChildRemains() throws {
    let ids = (1...3).map(sid)
    let persisted = try PaneTree(root: split(
        "root", .horizontal,
        [
            leaf("A", ids[0]),
            split("R", .vertical, [leaf("B", ids[1]), leaf("C", ids[2])], [0.5, 0.5]),
        ],
        [0.5, 0.5]
    ))
    let effective = persisted.pruned(visible: [ids[0], ids[1]])
    let frames = effective.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    #expect(frames.tiles.count == 2)
    expectRect(tile(frames, ids[0]), CGRect(x: 0, y: 0, width: 496, height: 800), "A は左半分のまま")
    expectRect(tile(frames, ids[1]), CGRect(x: 504, y: 0, width: 496, height: 800), "B が右半分を吸収")
}

@Test
func pruned_withEmptyVisibleSet_producesEmptyTree() throws {
    let ids = (1...2).map(sid)
    let persisted = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    #expect(persisted.pruned(visible: []).root == nil)
}

// MARK: - settingDivider（隠れた兄弟を跨いでも正しく動く）

@Test
func settingDivider_redistributesOnlyBetweenTheTwoNamedChildren() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    let divider = PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("B"))
    let updated = tree.settingDivider(divider, leadingFraction: 0.8)

    guard case .split(let s) = try #require(updated.root) else {
        Issue.record("root が split でない"); return
    }
    // A + B = 0.5 を 0.8 : 0.2 に配分。C は動かない。
    expectClose(CGFloat(s.weights[0]), 0.4, 0.000_001, "A")
    expectClose(CGFloat(s.weights[1]), 0.1, 0.000_001, "B")
    expectClose(CGFloat(s.weights[2]), 0.5, 0.000_001, "C は不変")
}

@Test
func settingDivider_acrossHiddenSibling_leavesHiddenChildUntouched() throws {
    // D4/D10 の中核: 絞り込みで B を隠した状態で A|C の分割線を動かす。
    let ids = (1...3).map(sid)
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    let divider = PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("C"))
    let updated = persisted.settingDivider(divider, leadingFraction: 0.5)

    guard case .split(let s) = try #require(updated.root) else {
        Issue.record("root が split でない"); return
    }
    // A + C = 0.7 を 0.35 : 0.35 に。B の 0.3 は変わらない。
    expectClose(CGFloat(s.weights[0]), 0.35, 0.000_001, "A")
    expectClose(CGFloat(s.weights[1]), 0.3, 0.000_001, "隠れた B の取り分は不変")
    expectClose(CGFloat(s.weights[2]), 0.35, 0.000_001, "C")
    #expect(updated.sessions == ids, "隠れたセッションは木に残る")
}

@Test
func settingDivider_clampsToMinimumDividerFraction() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    let divider = PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("B"))

    for requested in [-1.0, 0.0, 0.001] {
        guard case .split(let s) = try #require(tree.settingDivider(divider, leadingFraction: requested).root) else {
            Issue.record("root が split でない"); return
        }
        expectClose(CGFloat(s.weights[0]), CGFloat(PaneTree.minimumDividerFraction), 0.000_001,
                    "下限クランプ (requested=\(requested))")
    }
    for requested in [1.0, 2.0, 0.999] {
        guard case .split(let s) = try #require(tree.settingDivider(divider, leadingFraction: requested).root) else {
            Issue.record("root が split でない"); return
        }
        expectClose(CGFloat(s.weights[0]), CGFloat(1 - PaneTree.minimumDividerFraction), 0.000_001,
                    "上限クランプ (requested=\(requested))")
    }
}

@Test
func settingDivider_withUnknownIDs_returnsSelfUnchanged() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    #expect(tree.settingDivider(PaneDividerID(split: pid("nope"), leading: pid("A"), trailing: pid("B")),
                               leadingFraction: 0.9) == tree)
    #expect(tree.settingDivider(PaneDividerID(split: pid("S"), leading: pid("A"), trailing: pid("nope")),
                               leadingFraction: 0.9) == tree)
}

// MARK: - equalizing

@Test
func equalizing_resetsChildrenToEqualShares() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    guard case .split(let s) = try #require(tree.equalizing(pid("S")).root) else {
        Issue.record("root が split でない"); return
    }
    for weight in s.weights {
        expectClose(CGFloat(weight), 1.0 / 3.0, 0.000_001, "等分")
    }
}

// MARK: - removing / swapping / inserting

@Test
func removing_letsSiblingAbsorbTheSpace() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "root", .horizontal,
        [
            leaf("A", ids[0]),
            split("R", .vertical, [leaf("B", ids[1]), leaf("C", ids[2])], [0.5, 0.5]),
        ],
        [0.5, 0.5]
    ))
    let updated = tree.removing(ids[2])
    #expect(updated.sessions == [ids[0], ids[1]])
    let frames = updated.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    expectRect(tile(frames, ids[1]), CGRect(x: 504, y: 0, width: 496, height: 800), "B が右半分全部を吸収")
}

@Test
func removing_lastSession_producesEmptyTree() throws {
    let tree = try PaneTree(root: leaf("A", sid(1)))
    #expect(tree.removing(sid(1)).root == nil)
}

@Test
func removing_unknownSession_returnsSelfUnchanged() throws {
    let tree = try PaneTree(root: leaf("A", sid(1)))
    #expect(tree.removing(sid(99)) == tree)
}

@Test
func swapping_exchangesTwoLeavesInPlace() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "root", .horizontal,
        [
            leaf("A", ids[0]),
            split("R", .vertical, [leaf("B", ids[1]), leaf("C", ids[2])], [0.7, 0.3]),
        ],
        [0.5, 0.5]
    ))
    let before = tree.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    let updated = tree.swapping(ids[0], ids[2])
    let after = updated.frames(in: CGSize(width: 1000, height: 800), spacing: 8)

    #expect(tile(after, ids[2]) == tile(before, ids[0]), "C が A の位置へ")
    #expect(tile(after, ids[0]) == tile(before, ids[2]), "A が C の位置へ")
    #expect(tile(after, ids[1]) == tile(before, ids[1]), "B は動かない")
}

@Test
func swapping_withUnknownSession_returnsSelfUnchanged() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    #expect(tree.swapping(ids[0], sid(99)) == tree)
}

@Test
func inserting_splitsTargetPaneInTheRequestedDirection() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: leaf("A", ids[0]))
    let updated = tree.inserting(ids[1], splitting: ids[0], edge: .bottom)
    let frames = updated.frames(in: CGSize(width: 1000, height: 800), spacing: 8)

    expectRect(tile(frames, ids[0]), CGRect(x: 0, y: 0, width: 1000, height: 396), "既存が上")
    expectRect(tile(frames, ids[1]), CGRect(x: 0, y: 404, width: 1000, height: 396), "新規が下")
}

@Test
func inserting_atLeadingEdge_putsNewSessionBeforeTarget() throws {
    let ids = (1...2).map(sid)
    let tree = try PaneTree(root: leaf("A", ids[0]))
    let updated = tree.inserting(ids[1], splitting: ids[0], edge: .leading)
    let frames = updated.frames(in: CGSize(width: 1000, height: 800), spacing: 8)

    expectRect(tile(frames, ids[1]), CGRect(x: 0, y: 0, width: 496, height: 800), "新規が左")
    expectRect(tile(frames, ids[0]), CGRect(x: 504, y: 0, width: 496, height: 800), "既存が右")
}

@Test
func inserting_alreadyPlacedSession_movesItInsteadOfDuplicating() throws {
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [1.0 / 3, 1.0 / 3, 1.0 / 3]
    ))
    let updated = tree.inserting(ids[2], splitting: ids[0], edge: .top)
    #expect(Set(updated.sessions) == Set(ids), "重複しない")
    #expect(updated.sessions.count == 3)
    let frames = updated.frames(in: CGSize(width: 1000, height: 800), spacing: 8)
    let cRect = try #require(tile(frames, ids[2]))
    let aRect = try #require(tile(frames, ids[0]))
    #expect(cRect.minY < aRect.minY, "C は A の上に来る")
}

// MARK: - reconciled（セッションの増減に追随）

@Test
func reconciled_removesGoneSessionsAndAddsNewOnes() throws {
    let ids = (1...4).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.5, 0.5]
    ))
    let bounds = CGSize(width: 1600, height: 1000)
    let updated = tree.reconciled(with: [ids[0], ids[2], ids[3]], bounds: bounds, spacing: 8)

    #expect(Set(updated.sessions) == Set([ids[0], ids[2], ids[3]]))
    #expect(updated.frames(in: bounds, spacing: 8).tiles.count == 3)
}

@Test
func reconciled_isIdempotent() throws {
    let ids = (1...3).map(sid)
    let bounds = CGSize(width: 1600, height: 1000)
    let tree = PaneLayoutPreset.balanced.tree(for: ids)
    let once = tree.reconciled(with: ids, bounds: bounds, spacing: 8)
    let twice = once.reconciled(with: ids, bounds: bounds, spacing: 8)
    #expect(once == twice, "同じ集合で2回 reconcile しても変わらない")
    #expect(once == tree, "変化が無いなら木も変わらない")
}

@Test
func reconciled_withEmptySessions_producesEmptyTree() throws {
    let ids = (1...2).map(sid)
    let tree = PaneLayoutPreset.balanced.tree(for: ids)
    #expect(tree.reconciled(with: [], bounds: CGSize(width: 800, height: 600), spacing: 8).root == nil)
}

@Test
func reconciled_fromEmptyTree_placesAllSessions() throws {
    let ids = (1...5).map(sid)
    let empty = try PaneTree(root: nil)
    let updated = empty.reconciled(with: ids, bounds: CGSize(width: 1600, height: 1000), spacing: 8)
    #expect(Set(updated.sessions) == Set(ids))
}

@Test
func reconciled_addingSession_splitsTheLargestPane() throws {
    let ids = (1...3).map(sid)
    // A が広く（0.8）、B が狭い（0.2）。新規は A 側に入るべき。
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", ids[0]), leaf("B", ids[1])], [0.8, 0.2]
    ))
    let bounds = CGSize(width: 1600, height: 1000)
    let updated = tree.reconciled(with: ids, bounds: bounds, spacing: 8)
    let frames = updated.frames(in: bounds, spacing: 8)

    let aRect = try #require(tile(frames, ids[0]))
    let bRect = try #require(tile(frames, ids[1]))
    let newRect = try #require(tile(frames, ids[2]))
    #expect(newRect.width < bounds.width, "新規ペインが配置されている")
    #expect(abs(bRect.width - 0.2 * (bounds.width - 8)) < 2.0, "狭い方の B は分割されていない")
    #expect(aRect.width < 0.8 * (bounds.width - 8), "広い方の A が分割された")
}
