import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-4（分割ツリーの描画ビュー）の受け入れテスト。PM が著す不変の契約
// （実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を
// 得たうえでハーネス部分に限り修理してよい）。
//
// ビューの正しさを目視やソーススキャンだけに委ねないため、判断のロジックは
// SwiftUI に触れない純粋型（PaneDropZone / PaneDividerInteraction）へ切り出し、
// そこを振る舞いで固定する。ビューは「純粋型の戻り値をそのまま流す薄い殻」になる。
//
// 中核契約:
// - PaneDividerInteraction.changed は**常に nil を返す**（ADR 0116 の性能防壁。
//   ドラッグ中はレイアウトを更新できない、を型と振る舞いで担保する）。
// - PaneDropZone は端 25% で分割、中央で入れ替え。中央領域は常に残る。
// - 描画はフラットな ZStack ＋ 絶対配置（D3。NSViewRepresentable の attach 競合対策）。

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

private func dividerFrame(
    axis: PaneAxis,
    bounds: CGSize = CGSize(width: 1000, height: 800),
    spacing: CGFloat = 8
) throws -> PaneDividerFrame {
    let tree = try PaneTree(root: split(
        "S", axis, [leaf("A", sid(1)), leaf("B", sid(2))], [0.5, 0.5]
    ))
    return try #require(tree.frames(in: bounds, spacing: spacing).dividers.first)
}

private func sessionFeatureSource(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // SessionFeatureTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // SessionFeature（パッケージルート）
        .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - PaneDividerInteraction: ドラッグ中は絶対に確定しない

@Test
func interaction_changedAlwaysReturnsNil_horizontal() throws {
    let frame = try dividerFrame(axis: .horizontal)
    var interaction = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    // #expect / #require はマクロ展開でクロージャに包むため、mutating メソッドを
    // 式の中で直接呼べない。結果をローカルに束ねてから検査する（アサーションの意味は同じ）。
    let beganAction = interaction.began(frame)
    #expect(beganAction == nil, "began でもレイアウトを更新しない")

    for dx in stride(from: -1500.0, through: 1500.0, by: 15.0) {
        let action = interaction.changed(frame, translation: CGSize(width: dx, height: 37))
        #expect(action == nil, "changed(dx: \(dx)) がレイアウト操作を返した（ADR 0116 の回帰）")
    }
    #expect(interaction.ghost != nil, "ドラッグ中はゴーストが存在する")
}

@Test
func interaction_changedAlwaysReturnsNil_vertical() throws {
    let frame = try dividerFrame(axis: .vertical)
    var interaction = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    interaction.began(frame)
    for dy in stride(from: -1200.0, through: 1200.0, by: 15.0) {
        let action = interaction.changed(frame, translation: CGSize(width: 91, height: dy))
        #expect(action == nil, "changed(dy: \(dy)) がレイアウト操作を返した（ADR 0116 の回帰）")
    }
}

@Test
func interaction_endedReturnsSetDividerForTheGrabbedDivider() throws {
    let frame = try dividerFrame(axis: .horizontal)
    var interaction = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    interaction.began(frame)
    interaction.changed(frame, translation: CGSize(width: 90, height: 0))

    let endedAction = interaction.ended(frame, translation: CGSize(width: 90, height: 0))
    let action = try #require(endedAction)
    guard case .setDivider(let divider, let fraction) = action else {
        Issue.record("ended が .setDivider を返さなかった: \(action)"); return
    }
    #expect(divider == frame.id)
    #expect(fraction > 0 && fraction < 1)
    #expect(interaction.ghost == nil, "確定後はゴーストが消える")
}

@Test
func interaction_usesTheAxisMatchingTranslationComponent() throws {
    // 横分割は translation.width、縦分割は translation.height だけを見る。
    let horizontal = try dividerFrame(axis: .horizontal)
    var a = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    a.began(horizontal)
    a.changed(horizontal, translation: CGSize(width: 0, height: 400))
    let unmovedGhost = try #require(a.ghost)
    #expect(abs(unmovedGhost.position - horizontal.gapRect.midX) < 0.5,
            "横分割は縦方向の移動で動かない")

    var b = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    b.began(horizontal)
    b.changed(horizontal, translation: CGSize(width: 120, height: 0))
    let movedGhost = try #require(b.ghost)
    #expect(abs(movedGhost.position - (horizontal.gapRect.midX + 120)) < 0.5,
            "横分割は横方向の移動で動く")
}

@Test
func interaction_cancelledDoesNotCommit() throws {
    let frame = try dividerFrame(axis: .horizontal)
    var interaction = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    interaction.began(frame)
    interaction.changed(frame, translation: CGSize(width: 200, height: 0))

    let cancelledAction = interaction.cancelled()
    #expect(cancelledAction == nil)
    #expect(interaction.ghost == nil)
    let afterCancelAction = interaction.ended(frame, translation: CGSize(width: 200, height: 0))
    #expect(afterCancelAction == nil, "中断後は確定できない")
}

@Test
func interaction_equalizeReturnsTheSplitOfTheGrabbedDivider() throws {
    let frame = try dividerFrame(axis: .horizontal)
    let interaction = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    #expect(interaction.equalize(frame) == .equalize(frame.id.split))
}

@Test
func interaction_appliesTheAxisSpecificMinimumPaneExtent() throws {
    // 縦分割（高さを制限）は 160、横分割（幅を制限）は 240 でクランプされる。
    let bounds = CGSize(width: 1000, height: 800)
    let horizontal = try dividerFrame(axis: .horizontal, bounds: bounds)
    var a = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    a.began(horizontal)
    guard case .setDivider(_, let hFraction)? =
        a.ended(horizontal, translation: CGSize(width: 100_000, height: 0)) else {
        Issue.record("横分割の確定が得られない"); return
    }
    #expect(horizontal.segmentExtent * CGFloat(hFraction) <= horizontal.segmentExtent - 240 + 0.5,
            "横分割は幅 240 で止まる")

    let vertical = try dividerFrame(axis: .vertical, bounds: bounds)
    var b = PaneDividerInteraction(minimumPaneWidth: 240, minimumPaneHeight: 160)
    b.began(vertical)
    guard case .setDivider(_, let vFraction)? =
        b.ended(vertical, translation: CGSize(width: 0, height: 100_000)) else {
        Issue.record("縦分割の確定が得られない"); return
    }
    #expect(vertical.segmentExtent * CGFloat(vFraction) <= vertical.segmentExtent - 160 + 0.5,
            "縦分割は高さ 160 で止まる")
    #expect(vertical.segmentExtent * CGFloat(vFraction) > vertical.segmentExtent - 240,
            "縦分割に幅の最小値を使っていない")
}

// MARK: - PaneDropZone: 端で分割・中央で入れ替え

@Test
func dropZone_centerMeansSwap() {
    let size = CGSize(width: 400, height: 300)
    for point in [CGPoint(x: 200, y: 150), CGPoint(x: 150, y: 120), CGPoint(x: 250, y: 180)] {
        #expect(PaneDropZone.target(for: point, in: size) == .swap, "中央 \(point) は入れ替え")
    }
}

@Test
func dropZone_edgesMeanSplit() {
    let size = CGSize(width: 400, height: 300)
    #expect(PaneDropZone.target(for: CGPoint(x: 10, y: 150), in: size) == .split(.leading))
    #expect(PaneDropZone.target(for: CGPoint(x: 390, y: 150), in: size) == .split(.trailing))
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 10), in: size) == .split(.top))
    #expect(PaneDropZone.target(for: CGPoint(x: 200, y: 290), in: size) == .split(.bottom))
}

@Test
func dropZone_centerRegionIsAlwaysHalfTheTile() {
    // edgeFraction は 0.25 なので、中央 50%×50% は必ず swap になる。
    #expect(PaneDropZone.edgeFraction > 0)
    #expect(PaneDropZone.edgeFraction < 0.5, "中央領域が消えない閾値であること")

    let size = CGSize(width: 200, height: 200)
    for x in stride(from: 51.0, through: 149.0, by: 7.0) {
        for y in stride(from: 51.0, through: 149.0, by: 7.0) {
            #expect(PaneDropZone.target(for: CGPoint(x: x, y: y), in: size) == .swap,
                    "中央帯 (\(x), \(y)) は入れ替え")
        }
    }
}

@Test
func dropZone_cornersPickTheNearestEdgeDeterministically() {
    let size = CGSize(width: 400, height: 400)
    // 左上寄りだが上の方が近い
    #expect(PaneDropZone.target(for: CGPoint(x: 60, y: 20), in: size) == .split(.top))
    // 左上寄りだが左の方が近い
    #expect(PaneDropZone.target(for: CGPoint(x: 20, y: 60), in: size) == .split(.leading))
    // 完全な同率（左上の対角）は leading 優先（決定論）
    #expect(PaneDropZone.target(for: CGPoint(x: 20, y: 20), in: size) == .split(.leading))
    // 右下の同率は trailing 優先（leading→top→trailing→bottom の順）
    #expect(PaneDropZone.target(for: CGPoint(x: 380, y: 380), in: size) == .split(.trailing))
}

@Test
func dropZone_degenerateSizeFallsBackToSwap() {
    #expect(PaneDropZone.target(for: CGPoint(x: 0, y: 0), in: CGSize(width: 0, height: 0)) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: 5, y: 5), in: CGSize(width: 0, height: 100)) == .swap)
    #expect(PaneDropZone.target(for: CGPoint(x: 5, y: 5), in: CGSize(width: 100, height: -3)) == .swap)
}

@Test
func dropZone_pointsOutsideTheTileStillResolveToAnEdge() {
    // ドラッグ中に境界の外へ出てもクラッシュせず、決定論的に決まる。
    let size = CGSize(width: 300, height: 200)
    #expect(PaneDropZone.target(for: CGPoint(x: -50, y: 100), in: size) == .split(.leading))
    #expect(PaneDropZone.target(for: CGPoint(x: 350, y: 100), in: size) == .split(.trailing))
    #expect(PaneDropZone.target(for: CGPoint(x: 150, y: -20), in: size) == .split(.top))
    #expect(PaneDropZone.target(for: CGPoint(x: 150, y: 260), in: size) == .split(.bottom))
}

@Test
func dropZone_outsidePointsPickTheNearestEdgeByDistanceNotSign() {
    // 範囲外の角方向でも「最も近い辺」を選ぶ。距離は符号付きの比ではなく絶対値で測る。
    let size = CGSize(width: 400, height: 200)
    // 左へ 10pt・上へ 100pt はみ出している → 近いのは左辺
    #expect(PaneDropZone.target(for: CGPoint(x: -10, y: -100), in: size) == .split(.leading))
    // 上へ 5pt・左へ 200pt はみ出している → 近いのは上辺
    #expect(PaneDropZone.target(for: CGPoint(x: -200, y: -5), in: size) == .split(.top))
    // 右へ 8pt・下へ 150pt はみ出している → 近いのは右辺
    #expect(PaneDropZone.target(for: CGPoint(x: 408, y: 350), in: size) == .split(.trailing))
    // 下へ 4pt・右へ 300pt はみ出している → 近いのは下辺
    #expect(PaneDropZone.target(for: CGPoint(x: 700, y: 204), in: size) == .split(.bottom))
}

// MARK: - 純粋型であること / ADR の制約（ソーススキャン）

@Test
func pureTypes_doNotImportUIFrameworks() throws {
    for path in ["PaneLayout/PaneDropZone.swift", "PaneLayout/PaneDividerInteraction.swift"] {
        let source = try sessionFeatureSource(path)
        #expect(!source.contains("import SwiftUI"), "\(path) が SwiftUI を import している")
        #expect(!source.contains("import AppKit"), "\(path) が AppKit を import している")
    }
}

@Test
func paneLayoutView_keepsViewIdentityPerSession() throws {
    // D3: レイアウトが変わってもタイルのビュー identity を保つ。
    // これが崩れると NSViewRepresentable の attach 競合でタイルが空白になる。
    let source = try sessionFeatureSource("PaneLayoutView.swift")
    #expect(source.contains(".id(session.id)") || source.contains(".id(node.session)"),
            "タイルに session ごとの .id を付けること")
}

@Test
func paneLayoutView_doesNotReintroduceForbiddenModifiers() throws {
    let source = try sessionFeatureSource("PaneLayoutView.swift")
    #expect(!source.contains("LazyVStack"), "ADR 0030: LazyVStack を再導入しない")
    #expect(!source.contains("LazyHStack"), "ADR 0030: LazyHStack を再導入しない")
    #expect(!source.contains("fixedSize"), "ADR 0045 の趣旨: fixedSize を新規に足さない")
}

@Test
func paneLayoutView_doesNotNestTreeIntoStacks() throws {
    // D3: ツリーを HStack/VStack の入れ子として描かない（矩形計算にだけ使う）。
    // フラットな ZStack ＋ 絶対配置であることを、frames() の利用と .position の存在で確認する。
    let source = try sessionFeatureSource("PaneLayoutView.swift")
    #expect(source.contains("frames("), "tree.frames(in:spacing:) の結果を使って配置すること")
    #expect(source.contains(".position("), "絶対配置であること")
    #expect(source.contains("ZStack"), "フラットな ZStack で重ねること")
}

@Test
func paneLayoutView_routesDragThroughThePureInteraction() throws {
    // ビューが自前で閾値やドラッグ確定を書かず、テスト済みの純粋型に委ねていること。
    let source = try sessionFeatureSource("PaneLayoutView.swift")
        + (try sessionFeatureSource("PaneDividerHandleView.swift"))
    #expect(source.contains("PaneDividerInteraction"), "ドラッグは PaneDividerInteraction 経由")
    #expect(source.contains("PaneDropZone"), "ドロップ判定は PaneDropZone 経由")
}
