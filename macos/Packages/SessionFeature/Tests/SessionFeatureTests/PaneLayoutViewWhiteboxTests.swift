import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-4 の白箱テスト（実装役が著す敵対的テスト）。受け入れテストが押さえていない
// 「literal に実装すると通ってしまうが実際には壊れている」経路を潰す。
//
// 狙う正しさハザード:
//  H1 attach 競合 — ツリーを入れ子に描かない（ビューがツリーの構造を歩いていないこと）。
//  H2 AppKit 遮蔽 — 分割線ハンドルがタイルより後（前面）に置かれていること。
//  H3 ADR 0116  — onChanged からレイアウト操作が出る経路が1本も無いこと。
//  併せてドロップ判定・ドラッグ確定の数値的な境界（端 25%・軸ごとの最小ペイン長）。

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

private let testBounds = CGSize(width: 1000, height: 800)
private let testSpacing: CGFloat = 8

private func twoPaneTree(_ axis: PaneAxis) throws -> PaneTree {
    try PaneTree(root: split("S", axis, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.5]))
}

/// 横分割の中に縦分割が入った木（軸ごとの最小ペイン長を取り違えると落ちる形）。
private func mixedTree() throws -> PaneTree {
    try PaneTree(root: split(
        "S",
        .horizontal,
        [
            leaf("A", sid(1)),
            split("T", .vertical, [leaf("B", sid(2)), leaf("C", sid(3))], [0.5, 0.5]),
        ],
        [0.5, 0.5]
    ))
}

private func newInteraction() -> PaneDividerInteraction {
    PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
}

private func sessionFeatureSource(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // SessionFeatureTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // SessionFeature（パッケージルート）
        .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// コメントを取り除いたソース。構造の検査は散文ではなくコードに対して行う
/// （コメントに書いた「onLayoutAction を呼ばない」という注意書きで落ちないように）。
private func sessionFeatureCode(_ relativePath: String) throws -> String {
    let source = try sessionFeatureSource(relativePath)
    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> Substring in
            guard let comment = line.range(of: "//") else { return line }
            return line[line.startIndex..<comment.lowerBound]
        }
        .joined(separator: "\n")
}

/// `onChanged { ... }` のクロージャ本体を、波括弧の対応を取って全て切り出す。
private func onChangedBodies(in code: String) -> [String] {
    var bodies: [String] = []
    var searchStart = code.startIndex
    while let marker = code.range(of: "onChanged", range: searchStart..<code.endIndex) {
        searchStart = marker.upperBound
        guard let open = code[marker.upperBound...].firstIndex(of: "{") else { continue }
        var depth = 0
        var index = open
        var end = code.endIndex
        while index < code.endIndex {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
            index = code.index(after: index)
        }
        bodies.append(String(code[open..<end]))
    }
    return bodies
}

// MARK: - PaneDropZone: 帯の境界と「比で測る」こと

@Test
func dropZone_edgeBandBoundaryIsExclusive() {
    // ちょうど edgeFraction は中央側（「未満」なら split）。0.5pt 内側なら split。
    let size = CGSize(width: 400, height: 400)
    #expect(PaneDropZone.target(for: CGPoint(x: 100, y: 200), in: size) == .swap,
            "比がちょうど 0.25 の点は入れ替え")
    #expect(PaneDropZone.target(for: CGPoint(x: 99.5, y: 200), in: size) == .split(.leading))
    #expect(PaneDropZone.target(for: CGPoint(x: 300, y: 200), in: size) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: 300.5, y: 200), in: size) == .split(.trailing))
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 100), in: size) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 99.5), in: size) == .split(.top))
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 300), in: size) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 300.5), in: size) == .split(.bottom))
}

@Test
func dropZone_measuresRatiosNotAbsoluteDistances() {
    // 横長タイル。絶対距離で測る実装だと短辺（上下）の帯ばかりが当たる。
    let wide = CGSize(width: 2000, height: 200)
    // 左端から 300pt（比 0.15）・上端から 60pt（比 0.30）。絶対距離なら top、比なら leading。
    #expect(PaneDropZone.target(for: CGPoint(x: 300, y: 60), in: wide) == .split(.leading))
    // 縦長タイルで対称のケース。絶対距離なら leading、比なら top。
    let tall = CGSize(width: 200, height: 2000)
    #expect(PaneDropZone.target(for: CGPoint(x: 60, y: 300), in: tall) == .split(.top))
}

@Test
func dropZone_centerHalfSurvivesExtremeAspectRatios() {
    // 極端な縦横比でも中央 50%×50% は必ず入れ替えになる（帯が中央を食い尽くさない）。
    for size in [
        CGSize(width: 60, height: 2000),
        CGSize(width: 2000, height: 60),
        CGSize(width: 4000, height: 3),
        CGSize(width: 101, height: 97),
    ] {
        for fx in stride(from: 0.25, through: 0.75, by: 0.05) {
            for fy in stride(from: 0.25, through: 0.75, by: 0.05) {
                let point = CGPoint(x: size.width * CGFloat(fx), y: size.height * CGFloat(fy))
                #expect(PaneDropZone.target(for: point, in: size) == .swap,
                        "\(size) の中央帯 (\(fx), \(fy)) は入れ替え")
            }
        }
    }
}

@Test
func dropZone_tieBreakOrderCoversEveryAdjacentPair() {
    // 優先順 leading → top → trailing → bottom を4隅すべてで固定する。
    let size = CGSize(width: 400, height: 400)
    #expect(PaneDropZone.target(for: CGPoint(x: 20, y: 20), in: size) == .split(.leading),
            "leading と top の同率は leading")
    #expect(PaneDropZone.target(for: CGPoint(x: 20, y: 380), in: size) == .split(.leading),
            "leading と bottom の同率は leading")
    #expect(PaneDropZone.target(for: CGPoint(x: 380, y: 20), in: size) == .split(.top),
            "top と trailing の同率は top")
    #expect(PaneDropZone.target(for: CGPoint(x: 380, y: 380), in: size) == .split(.trailing),
            "trailing と bottom の同率は trailing")
}

@Test
func dropZone_mapsEachEdgeIndependentlyOnAsymmetricTiles() {
    let size = CGSize(width: 800, height: 200)
    #expect(PaneDropZone.target(for: CGPoint(x: 10, y: 100), in: size) == .split(.leading))
    #expect(PaneDropZone.target(for: CGPoint(x: 790, y: 100), in: size) == .split(.trailing))
    #expect(PaneDropZone.target(for: CGPoint(x: 400, y: 5), in: size) == .split(.top))
    #expect(PaneDropZone.target(for: CGPoint(x: 400, y: 195), in: size) == .split(.bottom))
}

@Test
func dropZone_nonFinitePointFallsBackToSwap() {
    // ドラッグ座標が壊れていても分割を誘発しない（決定論・クラッシュしない）。
    let size = CGSize(width: 400, height: 300)
    let notANumber = CGFloat.nan
    #expect(PaneDropZone.target(for: CGPoint(x: notANumber, y: notANumber), in: size) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: notANumber, y: 150), in: size) == .swap)
}

// MARK: - PaneDividerInteraction: ドラッグ中の不変条件

@Test
func interaction_neverCommitsAcrossExtremeTranslations() throws {
    for axis in PaneAxis.allCases {
        let tree = try twoPaneTree(axis)
        let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)
        var interaction = newInteraction()
        interaction.began(frame)

        // ゴーストは「最小ペイン長でクランプした比率」から作られるので、指を無限に動かしても
        // 隣接2枚の領域の内側（両端から最小ペイン長ぶん内側）に留まる。
        let minimumExtent: CGFloat = axis == .horizontal ? 240 : 160
        let gapThickness = axis == .horizontal ? frame.gapRect.width : frame.gapRect.height
        let lowerBound = frame.segmentOrigin + minimumExtent + gapThickness / 2
        let upperBound = frame.segmentOrigin + frame.segmentExtent - minimumExtent + gapThickness / 2

        let extremes: [CGFloat] = [-1e9, -5000, -0.5, 0, 0.5, 5000, 1e9, .infinity, -.infinity, .nan]
        for value in extremes {
            let translation = axis == .horizontal
                ? CGSize(width: value, height: -777)
                : CGSize(width: -777, height: value)
            let action = interaction.changed(frame, translation: translation)
            #expect(action == nil, "\(axis) の changed(\(value)) が確定を返した（ADR 0116 の回帰）")

            let ghost = try #require(interaction.ghost)
            #expect(ghost.position.isFinite, "\(axis) の translation=\(value) でゴーストが非有限になった")
            #expect(ghost.position >= lowerBound - 0.5,
                    "\(axis) の translation=\(value): ゴーストが最小ペイン長を越えて手前へ出た")
            #expect(ghost.position <= upperBound + 0.5,
                    "\(axis) の translation=\(value): ゴーストが最小ペイン長を越えて奥へ出た")
        }
    }
}

@Test
func interaction_changedIsAbsoluteNotAccumulated() throws {
    // DragGesture の translation は開始点からの累積値。差分として足し込む実装だと
    // 同じ値を2回受けただけでゴーストが倍動く。
    let tree = try twoPaneTree(.horizontal)
    let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)
    var interaction = newInteraction()
    interaction.began(frame)

    interaction.changed(frame, translation: CGSize(width: 100, height: 0))
    interaction.changed(frame, translation: CGSize(width: 100, height: 0))
    let repeated = try #require(interaction.ghost)
    #expect(abs(repeated.position - (frame.gapRect.midX + 100)) < 0.5, "同じ translation は同じ位置")

    interaction.changed(frame, translation: CGSize(width: 0, height: 0))
    let back = try #require(interaction.ghost)
    #expect(abs(back.position - frame.gapRect.midX) < 0.5, "translation 0 で開始位置へ戻る")
}

@Test
func interaction_verticalDividerIgnoresHorizontalTranslation() throws {
    // 受け入れテストは横分割で軸の取り出しを固定している。軸を取り違えた実装が
    // 縦分割だけ生き残らないよう、鏡像のケースを押さえる。
    let tree = try twoPaneTree(.vertical)
    let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)

    var unmoved = newInteraction()
    unmoved.began(frame)
    unmoved.changed(frame, translation: CGSize(width: 400, height: 0))
    let stayed = try #require(unmoved.ghost)
    #expect(abs(stayed.position - frame.gapRect.midY) < 0.5, "縦分割は横方向の移動で動かない")

    var moved = newInteraction()
    moved.began(frame)
    moved.changed(frame, translation: CGSize(width: 0, height: 120))
    let shifted = try #require(moved.ghost)
    #expect(abs(shifted.position - (frame.gapRect.midY + 120)) < 0.5, "縦分割は縦方向の移動で動く")
}

@Test
func interaction_ghostPredictsTheCommittedDividerPosition() throws {
    // 「見た目（ゴースト）＝結果（確定後のレイアウト）」をアダプタの層で固定する。
    for axis in PaneAxis.allCases {
        let tree = try twoPaneTree(axis)
        let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)

        for value in [-300.0, -80.0, 0.0, 80.0, 300.0] {
            let translation = axis == .horizontal
                ? CGSize(width: CGFloat(value), height: 0)
                : CGSize(width: 0, height: CGFloat(value))
            var interaction = newInteraction()
            interaction.began(frame)
            interaction.changed(frame, translation: translation)
            let ghost = try #require(interaction.ghost)
            let committed = interaction.ended(frame, translation: translation)

            guard case .setDivider(let divider, let fraction)? = committed else {
                Issue.record("\(axis) の translation=\(value) で確定が得られない"); return
            }
            let after = tree.settingDivider(divider, leadingFraction: fraction)
                .frames(in: testBounds, spacing: testSpacing)
            let updated = try #require(after.dividers.first)
            let center = axis == .horizontal ? updated.gapRect.midX : updated.gapRect.midY
            #expect(abs(center - ghost.position) <= 1.0,
                    "\(axis) の translation=\(value): 確定後の分割線がゴーストの位置に来ない")
        }
    }
}

@Test
func interaction_choosesTheMinimumExtentPerDividerAxis() throws {
    // 同じ木の中に両軸の分割線がある。軸ごとに 240 / 160 を使い分けないと落ちる。
    let tree = try mixedTree()
    let frames = tree.frames(in: testBounds, spacing: testSpacing)
    let horizontal = try #require(frames.dividers.first(where: { $0.axis == .horizontal }))
    let vertical = try #require(frames.dividers.first(where: { $0.axis == .vertical }))

    var horizontalDrag = newInteraction()
    horizontalDrag.began(horizontal)
    let horizontalCommit = horizontalDrag.ended(horizontal, translation: CGSize(width: 100_000, height: 0))
    guard case .setDivider(_, let horizontalFraction)? = horizontalCommit else {
        Issue.record("横分割の確定が得られない"); return
    }
    let horizontalExtent = horizontal.segmentExtent * CGFloat(horizontalFraction)
    #expect(abs(horizontalExtent - (horizontal.segmentExtent - 240)) <= 0.5,
            "横分割は幅 240 で止まる（実測 \(horizontalExtent) / 全長 \(horizontal.segmentExtent)）")

    var verticalDrag = newInteraction()
    verticalDrag.began(vertical)
    let verticalCommit = verticalDrag.ended(vertical, translation: CGSize(width: 0, height: 100_000))
    guard case .setDivider(_, let verticalFraction)? = verticalCommit else {
        Issue.record("縦分割の確定が得られない"); return
    }
    let verticalExtent = vertical.segmentExtent * CGFloat(verticalFraction)
    #expect(abs(verticalExtent - (vertical.segmentExtent - 160)) <= 0.5,
            "縦分割は高さ 160 で止まる（実測 \(verticalExtent) / 全長 \(vertical.segmentExtent)）")
    #expect(verticalExtent > vertical.segmentExtent - 240 + 1,
            "縦分割に幅の最小値（240）を使っている")
}

@Test
func interaction_endedWithoutBeganDoesNotCommit() throws {
    let tree = try twoPaneTree(.horizontal)
    let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)
    var interaction = newInteraction()
    let action = interaction.ended(frame, translation: CGSize(width: 120, height: 0))
    #expect(action == nil, "掴んでいないのに確定した")
    #expect(interaction.ghost == nil)
}

@Test
func interaction_isReusableAfterCancel() throws {
    // 中断は「その1回」を捨てるだけで、次のドラッグは通常どおり確定できる。
    let tree = try twoPaneTree(.horizontal)
    let frame = try #require(tree.frames(in: testBounds, spacing: testSpacing).dividers.first)
    var interaction = newInteraction()
    interaction.began(frame)
    interaction.changed(frame, translation: CGSize(width: 200, height: 0))
    interaction.cancelled()

    interaction.began(frame)
    interaction.changed(frame, translation: CGSize(width: 60, height: 0))
    let action = interaction.ended(frame, translation: CGSize(width: 60, height: 0))
    guard case .setDivider(let divider, let fraction)? = action else {
        Issue.record("中断後の再ドラッグが確定しない"); return
    }
    #expect(divider == frame.id)
    #expect(fraction > 0.5, "右へ動かした分だけ leading が広がる")
}

@Test
func interaction_equalizeTargetsTheGrabbedSplitEvenWhenNested() throws {
    // 入れ子の分割線をダブルクリックしたら、その内側の split が等分になる（root ではない）。
    let tree = try mixedTree()
    let frames = tree.frames(in: testBounds, spacing: testSpacing)
    let vertical = try #require(frames.dividers.first(where: { $0.axis == .vertical }))
    let interaction = newInteraction()
    #expect(interaction.equalize(vertical) == .equalize(pid("T")))

    let horizontal = try #require(frames.dividers.first(where: { $0.axis == .horizontal }))
    #expect(interaction.equalize(horizontal) == .equalize(pid("S")))
}

// MARK: - ハザードの構造テスト（ソーススキャン）

@Test
func dragOnChangedNeverEmitsLayoutActions() throws {
    // H3 / ADR 0116: onChanged からレイアウト操作を流す経路が1本も無いこと。
    // 分割線ハンドル側は必ず1つ以上ある（0件なら検査が空振りしている）。
    #expect(!onChangedBodies(in: try sessionFeatureCode("PaneDividerHandleView.swift")).isEmpty,
            "分割線ドラッグの onChanged が見つからない")

    for path in ["PaneDividerHandleView.swift", "PaneLayoutView.swift"] {
        let code = try sessionFeatureCode(path)
        for body in onChangedBodies(in: code) {
            #expect(!body.contains("onLayoutAction"),
                    "\(path): onChanged からレイアウト操作を流している（ADR 0116 の回帰）")
        }
    }
}

@Test
func dividerHandlesArePlacedAfterTilesInTheStack() throws {
    // H2: AppKit の NSView に遮られないよう、掴みしろはタイルより後（前面）へ置く。
    let code = try sessionFeatureCode("PaneLayoutView.swift")
    let tile = try #require(code.range(of: "PaneTileView("))
    let handle = try #require(code.range(of: "PaneDividerHandleView("))
    #expect(tile.lowerBound < handle.lowerBound,
            "分割線ハンドルがタイルより前（背面）に置かれている")
}

@Test
func layoutViewUsesTheTreeOnlyForRectangles() throws {
    // H1 / D3: ビューはツリーの構造を歩かない（歩くとレイアウトがビュー階層へ染み出す）。
    let code = try sessionFeatureCode("PaneLayoutView.swift")
    #expect(!code.contains("PaneNode"), "ビューがツリーのノードを直接扱っている")
    #expect(!code.contains("PaneSplit"), "ビューがツリーの分割ノードを直接扱っている")
    #expect(!code.contains(".children"), "ビューがツリーの子を歩いている")
    #expect(code.contains(".id(session.id)"), "タイルの identity をセッションで固定すること")
}

@Test
func dividerDragUsesLocalCoordinatesWithMinimumDistance() throws {
    // ゼロ距離ドラッグは AppKit のマウストラッキングを壊す。ゴースト方式では
    // 分割線自体は動かないので、基準がずれないローカル座標でよい。
    let code = try sessionFeatureCode("PaneDividerHandleView.swift")
    #expect(code.contains("DragGesture(minimumDistance: 1, coordinateSpace: .local)"))
}

@MainActor
@Test
func layoutViewPassesTheDecidedMinimumPaneExtents() {
    // D12: 幅 240 / 高さ 160。
    #expect(PaneLayoutView.minimumPaneWidth == 240)
    #expect(PaneLayoutView.minimumPaneHeight == 160)
}
