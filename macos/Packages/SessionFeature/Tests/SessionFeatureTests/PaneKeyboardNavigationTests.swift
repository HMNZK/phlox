import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// 06 キーボード: ⌥⌘⇧＋矢印の相手と、⌃⌥＋矢印で動かす分割線。

private func sid(_ n: Int) -> SessionID {
    let hex = String(format: "%012x", n)
    return SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(hex)")!)
}

private func leaf(_ name: String, _ session: SessionID) -> PaneNode {
    .leaf(id: PaneID(name), session: session)
}

private func split(_ name: String, _ axis: PaneAxis, _ children: [PaneNode], _ weights: [Double]) -> PaneNode {
    .split(PaneSplit(id: PaneID(name), axis: axis, children: children, weights: weights))
}

/// 左に A、右を上下に B / C。
private func sample() throws -> PaneTree {
    try PaneTree(root: split("root", .horizontal, [
        leaf("A", sid(1)),
        split("right", .vertical, [leaf("B", sid(2)), leaf("C", sid(3))], [0.5, 0.5]),
    ], [0.5, 0.5]))
}

@Test func neighbor_picksTheTileTouchingThatSide() throws {
    let tree = try sample()
    #expect(tree.neighbor(of: sid(2), toward: .down) == sid(3))
    #expect(tree.neighbor(of: sid(3), toward: .up) == sid(2))
    #expect(tree.neighbor(of: sid(2), toward: .left) == sid(1))
    #expect(tree.neighbor(of: sid(1), toward: .left) == nil)
    #expect(tree.neighbor(of: sid(2), toward: .up) == nil)
}

@Test func nudgedDivider_picksTheLineOnTheTilesEdge() throws {
    let tree = try sample()
    let bounds = CGSize(width: 1000, height: 800)
    // A の右の線を右へ（+5%）。保存ツリーでは 0.5 → 0.55。
    let right = try #require(tree.nudgedDivider(of: sid(1), toward: .right))
    #expect(right.id.split == PaneID("root"))
    #expect(right.delta == 0.05)
    let moved = tree.nudgingDivider(right.id, by: right.delta)
    #expect(moved.frames(in: bounds, spacing: 0).tiles.first { $0.session == sid(1) }?.rect.width == 550)
    // B は右の辺に線が無いので、左の辺の線を左へ。
    #expect(tree.nudgedDivider(of: sid(2), toward: .left)?.delta == -0.05)
    // B の下の線（B / C の間）を上へ。
    #expect(tree.nudgedDivider(of: sid(2), toward: .up)?.id.split == PaneID("right"))
    // A には上下の線が無い。
    #expect(tree.nudgedDivider(of: sid(1), toward: .down) == nil)
}

@Test func nudgingDivider_startsFromTheStoredFractionWhenTheDisplayTreeIsFlattened() throws {
    // 保存ツリー: 左右に [A | (B | H)]。H を隠すと表示は [A | B] に平坦化される。
    let stored = try PaneTree(root: split("root", .horizontal, [
        leaf("A", sid(1)),
        split("inner", .horizontal, [leaf("B", sid(2)), leaf("H", sid(9))], [0.5, 0.5]),
    ], [0.3, 0.7]))
    let shown = stored.pruned(visible: [sid(1), sid(2)])
    let bounds = CGSize(width: 1000, height: 800)
    let nudged = try #require(shown.nudgedDivider(of: sid(1), toward: .right))
    let moved = stored.nudgingDivider(nudged.id, by: nudged.delta)
    let before = shown.frames(in: bounds, spacing: 0).tiles.first { $0.session == sid(1) }!.rect.width
    let after = moved.pruned(visible: [sid(1), sid(2)]).frames(in: bounds, spacing: 0).tiles.first { $0.session == sid(1) }!.rect.width
    // → で A は必ず広がる（向きが逆にならない）。
    #expect(after > before)
}
