import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// 受け入れテスト: 絞り込み（pruned）で木の形が変わっても、実効ツリーで掴んだ分割線が
// 永続ツリーの正しい境界へ適用されること。
//
// `pruned(visible:)` は生き残ったノードの `PaneID` を保つが、正規化（`init(root:)`）が
//   ①子1個になった split を畳む（collapse）
//   ②親と同じ axis の子 split を平坦化する（flatten）
// ため、実効ツリーで隣り合う2ノードが、永続ツリーでは**同じ split の直接の子とは限らない**。
// 既存の契約テスト（ContractPaneDividerCommitTests）が押さえているのは「隠れた兄弟が
// 同じ split に挟まっている」場合だけで、深さが変わる①②は覆われていなかった。
//
// 症状: 11 セッション中 2 件だけ表示する絞り込み状態でグリッドの分割線をドラッグしても
// 何も起きない（`settingDivider` が対象を見つけられず同一の木を返し、
// `DashboardViewModel.handlePaneLayoutAction` の `guard updated != paneLayout` で捨てられる）。

// MARK: - ハーネス

private func sid(_ n: Int) -> SessionID {
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

/// 実効ツリーの分割線を1本ドラッグし、確定値を**永続ツリー**へ適用した結果を返す。
private func dragOnEffectiveTree(
    persisted: PaneTree,
    visible: Set<SessionID>,
    dividerAt index: Int,
    bounds: CGSize,
    spacing: CGFloat,
    minimumPaneExtent: CGFloat,
    translation: CGFloat
) throws -> (updated: PaneTree, ghostPosition: CGFloat, divider: PaneDividerID) {
    let effective = persisted.pruned(visible: visible)
    let frames = effective.frames(in: bounds, spacing: spacing)
    let frame = try #require(
        frames.dividers.indices.contains(index) ? frames.dividers[index] : nil,
        "実効ツリーに分割線が \(index + 1) 本以上ある"
    )

    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: minimumPaneExtent)
    machine.changed(translation: translation)
    let ghostPosition = try #require(machine.ghost?.position, "ドラッグ中はゴーストが存在する")

    guard case .commit(let divider, let fraction) = machine.ended(translation: translation) else {
        Issue.record("ended が確定値を返さなかった")
        return (persisted, ghostPosition, frame.id)
    }
    return (
        persisted.settingDivider(divider, leadingFraction: fraction),
        ghostPosition,
        divider
    )
}

private func weights(of tree: PaneTree, splitNamed name: String) throws -> [Double] {
    func find(_ node: PaneNode) -> PaneSplit? {
        guard case .split(let split) = node else { return nil }
        if split.id == pid(name) { return split }
        for child in split.children {
            if let found = find(child) { return found }
        }
        return nil
    }
    let root = try #require(tree.root)
    return try #require(find(root), "split \(name) が木に存在する").weights
}

// MARK: - ①畳み込み: 隠れた兄弟によって split が畳まれ、深さが変わる

@Test
func drag_whenHiddenSiblingCollapsesSplit_movesPersistedBoundary() throws {
    let bounds = CGSize(width: 1000, height: 800)
    let spacing: CGFloat = 8
    let ids = (1...3).map(sid)
    // 永続: S(横) [ A , Q(縦)[ B , C ] ]。C を隠すと Q は子1個になり B へ畳まれ、
    // 実効ツリーは S[A, B] になる（B は永続ツリーでは S の直接の子ではない）。
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), split("Q", .vertical, [leaf("B", ids[1]), leaf("C", ids[2])], [0.5, 0.5])],
        [0.5, 0.5]
    ))

    let result = try dragOnEffectiveTree(
        persisted: persisted,
        visible: [ids[0], ids[1]],
        dividerAt: 0,
        bounds: bounds,
        spacing: spacing,
        minimumPaneExtent: 100,
        translation: 120
    )

    #expect(result.divider.leading == pid("A"))
    #expect(result.divider.trailing == pid("B"), "実効ツリーの分割線は A|B を指す")

    let updatedRoot = try weights(of: result.updated, splitNamed: "S")
    #expect(updatedRoot[0] > 0.5, "A は広がる（右へ 120pt 動かしたので）")
    expectClose(updatedRoot[0] + updatedRoot[1], 1.0, 1e-9, "S の合計は不変")
    expectClose(try weights(of: result.updated, splitNamed: "Q")[0], 0.5, 1e-9,
                "隠れた C を含む Q の内部比率は不変")
    #expect(result.updated.sessions == ids, "隠れたセッションは永続ツリーに残る")

    let redrawn = result.updated
        .pruned(visible: [ids[0], ids[1]])
        .frames(in: bounds, spacing: spacing)
    let newDivider = try #require(redrawn.dividers.first)
    expectClose(newDivider.gapRect.midX, result.ghostPosition, 1.0,
                "確定後の分割線がゴーストの位置に来る")
}

// MARK: - ②平坦化: 畳み込みで同 axis の入れ子ができ、実効ツリーで平坦化される

@Test
func drag_whenPruningFlattensSameAxisNesting_movesInnermostBoundary() throws {
    let bounds = CGSize(width: 1200, height: 600)
    let spacing: CGFloat = 8
    let ids = (1...4).map(sid)
    // 永続: S(横)[ A , Q(縦)[ B , R(横)[ C , D ] ] ]。
    // B を隠すと Q は R へ畳まれ、S(横) の直下に R(横) が来て平坦化され、
    // 実効ツリーは S[A, C, D]（C|D は永続ツリーでは R の子）になる。
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [
            leaf("A", ids[0]),
            split(
                "Q", .vertical,
                [leaf("B", ids[1]), split("R", .horizontal, [leaf("C", ids[2]), leaf("D", ids[3])], [0.5, 0.5])],
                [0.5, 0.5]
            ),
        ],
        [0.4, 0.6]
    ))

    let result = try dragOnEffectiveTree(
        persisted: persisted,
        visible: [ids[0], ids[2], ids[3]],
        dividerAt: 1,
        bounds: bounds,
        spacing: spacing,
        minimumPaneExtent: 100,
        translation: 90
    )

    #expect(result.divider.leading == pid("C"))
    #expect(result.divider.trailing == pid("D"), "実効ツリーの2本目の分割線は C|D を指す")

    let innermost = try weights(of: result.updated, splitNamed: "R")
    #expect(innermost[0] > 0.5, "C は広がる")
    expectClose(innermost[0] + innermost[1], 1.0, 1e-9, "R の合計は不変")
    expectClose(try weights(of: result.updated, splitNamed: "S")[0], 0.4, 1e-9, "S の比率は不変")
    expectClose(try weights(of: result.updated, splitNamed: "Q")[0], 0.5, 1e-9,
                "隠れた B を含む Q の比率は不変")
    #expect(result.updated.sessions == ids, "隠れたセッションは永続ツリーに残る")

    let redrawn = result.updated
        .pruned(visible: [ids[0], ids[2], ids[3]])
        .frames(in: bounds, spacing: spacing)
    let newDivider = try #require(redrawn.dividers.indices.contains(1) ? redrawn.dividers[1] : nil)
    expectClose(newDivider.gapRect.midX, result.ghostPosition, 1.0,
                "確定後の分割線がゴーストの位置に来る")
}
