import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// シーム契約テスト: 分割線ドラッグの確定値が、そのままレイアウトへ適用できること。
// PaneDividerDragMachine（task-2）／PaneTree.settingDivider（task-1）／
// PaneLayoutView の配線（task-4）が共有する境界。task-2・task-4 の verify で再実走する。
// PM が著す不変の契約（実装役は編集禁止。ハーネスの欠陥は PM に報告して承認を得てから修理）。
//
// 契約の骨子:
// - ドラッグ中に確定は起きない（性能防壁。ADR 0116）。
// - マウスアップで確定した比率を settingDivider に渡すと、ゴーストが示した位置に
//   実際の分割線が来る（見た目と結果が一致する）。
// - 隣接2枚以外のペインは動かない。

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

/// ドラッグ1回ぶんをまるごと回して、確定後の木を返す。
private func performDrag(
    on tree: PaneTree,
    dividerAt index: Int,
    bounds: CGSize,
    spacing: CGFloat,
    minimumPaneExtent: CGFloat,
    translation: CGFloat,
    intermediateSteps: Int = 5
) throws -> (updated: PaneTree, ghostPosition: CGFloat, frame: PaneDividerFrame) {
    let frames = tree.frames(in: bounds, spacing: spacing)
    let frame = frames.dividers[index]

    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: minimumPaneExtent)
    for step in 1...max(1, intermediateSteps) {
        let partial = translation * CGFloat(step) / CGFloat(max(1, intermediateSteps))
        let output = machine.changed(translation: partial)
        if case .commit = output {
            Issue.record("ドラッグ中に確定が発生した（ADR 0116 の性能防壁が破れている）")
        }
    }
    let ghostPosition = try #require(machine.ghost?.position, "ドラッグ中はゴーストが存在する")

    guard case .commit(let divider, let fraction) = machine.ended(translation: translation) else {
        Issue.record("ended が確定値を返さなかった")
        return (tree, ghostPosition, frame)
    }
    #expect(divider == frame.id, "確定した分割線 ID が掴んだものと一致する")
    return (tree.settingDivider(divider, leadingFraction: fraction), ghostPosition, frame)
}

// MARK: - 見た目（ゴースト）と結果（実レイアウト）が一致する

@Test
func commit_movesDividerToWhereTheGhostWas_horizontal() throws {
    let bounds = CGSize(width: 1000, height: 800)
    let tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.5]
    ))

    for translation in [-200.0, -40.0, 40.0, 200.0] {
        let result = try performDrag(
            on: tree, dividerAt: 0, bounds: bounds, spacing: 8,
            minimumPaneExtent: 200, translation: CGFloat(translation)
        )
        let after = result.updated.frames(in: bounds, spacing: 8)
        let newDivider = try #require(after.dividers.first)
        expectClose(newDivider.gapRect.midX, result.ghostPosition, 1.0,
                    "translation=\(translation): 確定後の分割線がゴーストの位置に来る")
    }
}

@Test
func commit_movesDividerToWhereTheGhostWas_vertical() throws {
    let bounds = CGSize(width: 900, height: 700)
    let tree = try PaneTree(root: split(
        "S", .vertical, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.5]
    ))

    for translation in [-150.0, 150.0] {
        let result = try performDrag(
            on: tree, dividerAt: 0, bounds: bounds, spacing: 8,
            minimumPaneExtent: 120, translation: CGFloat(translation)
        )
        let after = result.updated.frames(in: bounds, spacing: 8)
        let newDivider = try #require(after.dividers.first)
        expectClose(newDivider.gapRect.midY, result.ghostPosition, 1.0,
                    "translation=\(translation): 確定後の分割線がゴーストの位置に来る")
    }
}

@Test
func commit_inThreeWaySplit_movesOnlyTheGrabbedBoundary() throws {
    let bounds = CGSize(width: 1200, height: 600)
    let spacing: CGFloat = 8
    let ids = (1...3).map(sid)
    let tree = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [1.0 / 3, 1.0 / 3, 1.0 / 3]
    ))
    let before = tree.frames(in: bounds, spacing: spacing)
    let cBefore = try #require(before.tiles.first(where: { $0.session == ids[2] })?.rect)

    // 1本目（A|B）を掴んで動かす。C の矩形は変わらないはず。
    let result = try performDrag(
        on: tree, dividerAt: 0, bounds: bounds, spacing: spacing,
        minimumPaneExtent: 100, translation: 120
    )
    let after = result.updated.frames(in: bounds, spacing: spacing)
    let cAfter = try #require(after.tiles.first(where: { $0.session == ids[2] })?.rect)

    expectClose(cAfter.minX, cBefore.minX, 0.5, "C の左端は動かない")
    expectClose(cAfter.width, cBefore.width, 0.5, "C の幅は動かない")

    let firstDividerAfter = try #require(after.dividers.first)
    expectClose(firstDividerAfter.gapRect.midX, result.ghostPosition, 1.0,
                "掴んだ分割線はゴーストの位置に来る")
}

// MARK: - 隠れたペインを跨いだドラッグ（D4 / D10 の統合）

@Test
func commit_onPrunedTree_appliesToPersistedTreeWithoutDisturbingHiddenPane() throws {
    let bounds = CGSize(width: 1200, height: 600)
    let spacing: CGFloat = 8
    let ids = (1...3).map(sid)
    // 永続ツリー: A(0.2) | B(0.3) | C(0.5)。B を絞り込みで隠す。
    let persisted = try PaneTree(root: split(
        "S", .horizontal,
        [leaf("A", ids[0]), leaf("B", ids[1]), leaf("C", ids[2])],
        [0.2, 0.3, 0.5]
    ))
    let effective = persisted.pruned(visible: [ids[0], ids[2]])

    // 実効ツリー（A|C の1本）を掴んでドラッグする。
    let effectiveFrames = effective.frames(in: bounds, spacing: spacing)
    let frame = try #require(effectiveFrames.dividers.first)
    #expect(frame.id.leading == pid("A"))
    #expect(frame.id.trailing == pid("C"), "実効ツリーの分割線は A|C を指す")

    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: 100)
    machine.changed(translation: 150)
    let ghostPosition = try #require(machine.ghost?.position, "確定前はゴーストが存在する")
    guard case .commit(let divider, let fraction) = machine.ended(translation: 150) else {
        Issue.record("ended が確定値を返さなかった"); return
    }

    // ビューは実効ツリーの ID を VM へ渡す。VM は永続ツリーへ適用する。
    let updatedPersisted = persisted.settingDivider(divider, leadingFraction: fraction)

    #expect(updatedPersisted.sessions == ids, "隠れたセッションは永続ツリーに残る")
    guard case .split(let s) = try #require(updatedPersisted.root) else {
        Issue.record("root が split でない"); return
    }
    expectClose(s.weights[1], 0.3, 1e-9, "隠れた B の取り分はビット単位で不変")
    expectClose(s.weights[0] + s.weights[2], 0.7, 1e-9, "A と C の合計は不変")
    #expect(s.weights[0] > 0.2, "A は広がった")

    // 再描画した実効ツリーで、分割線がゴーストの位置に来ている。
    let redrawn = updatedPersisted.pruned(visible: [ids[0], ids[2]])
        .frames(in: bounds, spacing: spacing)
    let newDivider = try #require(redrawn.dividers.first)
    expectClose(newDivider.gapRect.midX, ghostPosition, 1.0,
                "確定後の分割線がゴーストの位置に来る（隠れたペインを跨いでも）")
}

// MARK: - 連続ドラッグの安定性

@Test
func repeatedDrags_convergeAndNeverCommitMidDrag() throws {
    let bounds = CGSize(width: 1000, height: 800)
    var tree = try PaneTree(root: split(
        "S", .horizontal, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.5]
    ))

    for round in 0..<10 {
        let translation: CGFloat = round.isMultiple(of: 2) ? 60 : -35
        let result = try performDrag(
            on: tree, dividerAt: 0, bounds: bounds, spacing: 8,
            minimumPaneExtent: 200, translation: translation, intermediateSteps: 8
        )
        tree = result.updated
        let frames = tree.frames(in: bounds, spacing: 8)
        for tileFrame in frames.tiles {
            #expect(tileFrame.rect.width >= 0, "round \(round): 幅が負にならない")
            #expect(tileFrame.rect.maxX <= bounds.width + 0.5, "round \(round): はみ出さない")
        }
    }
    #expect(tree.sessions.count == 2)
}
