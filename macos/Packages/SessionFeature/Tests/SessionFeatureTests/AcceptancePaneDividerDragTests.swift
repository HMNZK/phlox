import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-2（分割線ドラッグの状態機械）の受け入れテスト。PM が著す不変の契約
// （実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を
// 得たうえでハーネス部分に限り修理してよい）。
//
// 契約の中核は「ドラッグ中はレイアウトを確定しない」。これは ADR 0116 の実測ハング
// （タイル幅が毎フレーム変わると CoreText 再 typeset でメインスレッドが 470〜643ms 固まる）を
// 構造的に防ぐ唯一の関所であり、changed から .commit が出ないことを列挙的に固定する。

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

/// 実際の PaneTree から分割線フレームを取り出す（task-1 の出力をそのまま使うことで、
/// 2つのタスクの境界がずれていないことも同時に検査する）。
private func dividerFrame(
    axis: PaneAxis,
    weights: [Double] = [0.5, 0.5],
    bounds: CGSize = CGSize(width: 1000, height: 800),
    spacing: CGFloat = 8
) throws -> (frame: PaneDividerFrame, tree: PaneTree) {
    let children = (0..<weights.count).map { leaf("L\($0)", sid($0 + 1)) }
    let tree = try PaneTree(root: split("S", axis, children, weights))
    let frames = tree.frames(in: bounds, spacing: spacing)
    let frame = try #require(frames.dividers.first, "分割線が1本以上あること")
    return (frame, tree)
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

private func commitFraction(_ output: PaneDividerDragMachine.Output) -> Double? {
    if case .commit(_, let fraction) = output { return fraction }
    return nil
}

private func ghost(_ output: PaneDividerDragMachine.Output) -> PaneDividerGhost? {
    if case .preview(let ghost) = output { return ghost }
    return nil
}

// MARK: - 不変条件1（最重要）: ドラッグ中は確定しない

@Test
func changed_neverCommits_overManyTranslations() throws {
    // ADR 0116 回帰防止の中核契約。1回の確認では足りないので列挙的に突く。
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    #expect(commitFraction(machine.begin(frame, minimumPaneExtent: 240)) == nil, "begin でも確定しない")

    for step in stride(from: -2000.0, through: 2000.0, by: 20.0) {
        let output = machine.changed(translation: CGFloat(step))
        #expect(commitFraction(output) == nil, "changed(translation: \(step)) が確定値を返した")
        #expect(ghost(output) != nil, "changed(translation: \(step)) は preview を返すこと")
    }
    #expect(machine.ghost != nil, "ドラッグは継続している")
}

@Test
func changed_neverCommits_forVerticalAxisToo() throws {
    let (frame, _) = try dividerFrame(axis: .vertical)
    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: 160)
    for step in stride(from: -1000.0, through: 1000.0, by: 25.0) {
        #expect(commitFraction(machine.changed(translation: CGFloat(step))) == nil,
                "changed(translation: \(step)) が確定値を返した")
    }
}

@Test
func machineWithoutBegin_staysIdle() throws {
    var machine = PaneDividerDragMachine()
    #expect(machine.changed(translation: 50) == .idle)
    #expect(machine.ended(translation: 50) == .idle)
    #expect(machine.cancelled() == .idle)
    #expect(machine.ghost == nil)
}

// MARK: - begin / preview の位置

@Test
func begin_returnsGhostAtTheCurrentDividerCenter() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    let output = machine.begin(frame, minimumPaneExtent: 240)

    let initial = try #require(ghost(output), "begin は preview を返すこと")
    #expect(initial.divider == frame.id)
    #expect(initial.axis == .horizontal)
    expectClose(initial.position, frame.gapRect.midX, 0.5, "ゴーストの初期位置は現在の分割線の中心")
    expectClose(initial.crossOrigin, frame.gapRect.minY, 0.5, "直交方向の始点")
    expectClose(initial.crossExtent, frame.gapRect.height, 0.5, "直交方向の長さ")
    #expect(machine.ghost == initial)
}

@Test
func begin_verticalAxis_returnsGhostAtTheCurrentDividerCenter() throws {
    let (frame, _) = try dividerFrame(axis: .vertical)
    var machine = PaneDividerDragMachine()
    let initial = try #require(ghost(machine.begin(frame, minimumPaneExtent: 160)))

    #expect(initial.axis == .vertical)
    expectClose(initial.position, frame.gapRect.midY, 0.5, "ゴーストの初期位置")
    expectClose(initial.crossOrigin, frame.gapRect.minX, 0.5, "直交方向の始点")
    expectClose(initial.crossExtent, frame.gapRect.width, 0.5, "直交方向の長さ")
}

@Test
func changed_movesGhostByTheTranslation() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    let initial = try #require(ghost(machine.begin(frame, minimumPaneExtent: 240)))

    let moved = try #require(ghost(machine.changed(translation: 100)))
    expectClose(moved.position, initial.position + 100, 0.5, "ゴーストは指の移動量ぶん動く")

    let back = try #require(ghost(machine.changed(translation: -100)))
    expectClose(back.position, initial.position - 100, 0.5, "逆方向も同じ")

    let zero = try #require(ghost(machine.changed(translation: 0)))
    expectClose(zero.position, initial.position, 0.5, "0 に戻せば元の位置")
}

// MARK: - ended: 一度だけ確定する

@Test
func ended_commitsExactlyOnceAndClearsState() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: 240)
    machine.changed(translation: 120)

    let output = machine.ended(translation: 120)
    guard case .commit(let divider, let fraction) = output else {
        Issue.record("ended が .commit を返さなかった: \(output)"); return
    }
    #expect(divider == frame.id)
    #expect(fraction > 0 && fraction < 1)
    #expect(machine.ghost == nil, "確定後はドラッグ状態が残らない")

    #expect(machine.ended(translation: 120) == .idle, "2回目の ended は確定しない")
    #expect(machine.changed(translation: 200) == .idle, "確定後の changed も無効")
}

@Test
func ended_commitsTheSameFractionThePreviewShowed() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    for translation in [-300.0, -50.0, 0.0, 50.0, 300.0] {
        var machine = PaneDividerDragMachine()
        machine.begin(frame, minimumPaneExtent: 240)
        let preview = try #require(ghost(machine.changed(translation: CGFloat(translation))))
        let fraction = try #require(commitFraction(machine.ended(translation: CGFloat(translation))))

        // ゴーストの中心位置と、確定値から再構成した位置が一致すること。
        let reconstructed = frame.segmentOrigin
            + frame.segmentExtent * CGFloat(fraction)
            + frame.gapRect.width / 2
        expectClose(preview.position, reconstructed, 0.5,
                    "translation=\(translation): preview と確定値が一致")
    }
}

@Test
func cancelled_doesNotCommit() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: 240)
    machine.changed(translation: 250)

    #expect(machine.cancelled() == .idle)
    #expect(machine.ghost == nil, "中断でドラッグ状態が消える")
    #expect(machine.ended(translation: 250) == .idle, "中断後に確定できない")
}

// MARK: - クランプ（最小ペイン長・最小比率）

@Test
func drag_clampsSoBothPanesKeepMinimumExtent() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)   // segmentExtent = 992
    let minimum: CGFloat = 240
    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: minimum)

    // 右端まで引っ張っても leading は segmentExtent - minimum を超えない。
    let maxFraction = try #require(commitFraction(machine.ended(translation: 5000)))
    let leadingExtent = frame.segmentExtent * CGFloat(maxFraction)
    #expect(leadingExtent <= frame.segmentExtent - minimum + 0.5,
            "trailing 側が最小長を割らない (leading=\(leadingExtent))")

    var machine2 = PaneDividerDragMachine()
    machine2.begin(frame, minimumPaneExtent: minimum)
    let minFraction = try #require(commitFraction(machine2.ended(translation: -5000)))
    #expect(frame.segmentExtent * CGFloat(minFraction) >= minimum - 0.5,
            "leading 側が最小長を割らない")
}

@Test
func drag_clampsGhostPositionToo() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var machine = PaneDividerDragMachine()
    machine.begin(frame, minimumPaneExtent: 240)
    let far = try #require(ghost(machine.changed(translation: 100_000)))

    let maxCenter = frame.segmentOrigin + (frame.segmentExtent - 240) + frame.gapRect.width / 2
    #expect(far.position <= maxCenter + 0.5, "ゴーストもクランプされる（指と一緒に無限に飛ばない）")
}

@Test
func drag_fractionStaysWithinMinimumDividerFraction() throws {
    let (frame, _) = try dividerFrame(axis: .horizontal)
    for translation in [-100_000.0, -1000.0, 1000.0, 100_000.0] {
        var machine = PaneDividerDragMachine()
        machine.begin(frame, minimumPaneExtent: 1)   // 最小長では縛らない
        let fraction = try #require(commitFraction(machine.ended(translation: CGFloat(translation))))
        #expect(fraction >= PaneTree.minimumDividerFraction - 1e-9,
                "translation=\(translation): 下限クランプ")
        #expect(fraction <= 1 - PaneTree.minimumDividerFraction + 1e-9,
                "translation=\(translation): 上限クランプ")
    }
}

@Test
func drag_whenSegmentIsTooSmallForBothMinimums_fallsBackToEqualSplit() throws {
    // segmentExtent < minimumPaneExtent * 2 のときは 0.5 に倒す。
    let (frame, _) = try dividerFrame(
        axis: .horizontal,
        bounds: CGSize(width: 300, height: 200)
    )
    for translation in [-500.0, 0.0, 500.0] {
        var machine = PaneDividerDragMachine()
        machine.begin(frame, minimumPaneExtent: 240)   // 2 * 240 = 480 > segmentExtent(292)
        let fraction = try #require(commitFraction(machine.ended(translation: CGFloat(translation))))
        expectClose(fraction, 0.5, 1e-9, "translation=\(translation): 等分へ倒す")
    }
}

// MARK: - 不変条件3: begin 時の基準値がドラッグ中に動かない

@Test
func changed_doesNotRebaseOnSubsequentCalls() throws {
    // translation は「開始点からの累積移動量」。changed を重ねても基準が動いてはならない。
    let (frame, _) = try dividerFrame(axis: .horizontal)
    var stepwise = PaneDividerDragMachine()
    stepwise.begin(frame, minimumPaneExtent: 240)
    for translation in [10.0, 30.0, 60.0, 100.0] {
        stepwise.changed(translation: CGFloat(translation))
    }
    let stepwiseGhost = try #require(stepwise.ghost)

    var direct = PaneDividerDragMachine()
    direct.begin(frame, minimumPaneExtent: 240)
    direct.changed(translation: 100)
    let directGhost = try #require(direct.ghost)

    expectClose(stepwiseGhost.position, directGhost.position, 1e-9,
                "同じ最終 translation なら経路に依らず同じ位置")
}

// MARK: - 不変条件4: 純粋型であること

@Test
func paneDividerDrag_sourceDoesNotImportUIFrameworks() throws {
    let path = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // SessionFeatureTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // SessionFeature (package root)
        .appendingPathComponent("Sources/SessionFeature/PaneLayout/PaneDividerDrag.swift")
    let source = try String(contentsOf: path, encoding: .utf8)
    #expect(!source.contains("import SwiftUI"), "純粋型に SwiftUI を持ち込まない")
    #expect(!source.contains("import AppKit"), "純粋型に AppKit を持ち込まない")
}
