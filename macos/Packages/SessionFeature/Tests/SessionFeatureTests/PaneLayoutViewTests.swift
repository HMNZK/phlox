import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// PaneLayoutView の判断ロジック。
//
// ビューの正しさを目視やソーススキャンだけに委ねないため、判断のロジックは
// SwiftUI に触れない純粋型（PaneDropZone / PaneDividerInteraction）へ切り出し、
// そこを振る舞いで固定する。ビューは「純粋型の戻り値をそのまま流す薄い殻」になる。
// ウィンドウに載せた実際の挙動は PaneLayoutViewHostedTests。
//
// 中核契約:
// - PaneDividerInteraction.changed は**常に nil を返す**（ADR 0116 の性能防壁。
//   ドラッグ中はレイアウトを更新できない）。
// - PaneDropZone は端 25% で分割、中央で入れ替え。中央領域は常に残る。
// - 描画はフラットな ZStack ＋ 絶対配置（D3。NSViewRepresentable の attach 競合対策）。
// 後半は、実装が literal に書かれても通ってしまう境界（帯の境界・比で測る・軸ごとの最小長など）を押さえる。

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

// MARK: - PaneDropZone: 端で分割・中央で入れ替え

@Test
func dropZone_cornersPickTheNearestEdge() {
    let size = CGSize(width: 400, height: 400)
    // 左上寄りだが上の方が近い
    #expect(PaneDropZone.target(for: CGPoint(x: 60, y: 20), in: size) == .split(.top))
    // 左上寄りだが左の方が近い
    #expect(PaneDropZone.target(for: CGPoint(x: 20, y: 60), in: size) == .split(.leading))
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

// MARK: - コードの規約（ソーススキャン）

@Test
func paneLayoutView_doesNotReintroduceForbiddenModifiers() throws {
    // 規約の検査としてソースの文字列を読む（振る舞いの検査に書き直せなかった）。守りたいのは
    // 「Lazy スタック（ADR 0030）と fixedSize（ADR 0045）が起こすレイアウト非収束での CPU 固着」だが、
    // どちらも実ウィンドウのスクロール・リサイズ中にだけ起きて、ヘッドレスでは再現しない
    // （ADR 0045 が同じ試行の失敗を記録している）。PaneLayoutView 自体は絶対配置の ZStack で
    // スクロールも持たないため、この禁止は将来の編集者への規約として置いている。
    let source = try sessionFeatureSource("PaneLayoutView.swift")
    #expect(!source.contains("LazyVStack"), "ADR 0030: LazyVStack を再導入しない")
    #expect(!source.contains("LazyHStack"), "ADR 0030: LazyHStack を再導入しない")
    #expect(!source.contains("fixedSize"), "ADR 0045 の趣旨: fixedSize を新規に足さない")
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
func dropZone_outsidePointsSplitEvenBeyondTheEdgeBand() {
    // タイルの外の点は「中央」ではありえないので、帯（25%）より遠くても入れ替えにしない。
    let size = CGSize(width: 300, height: 200)
    #expect(PaneDropZone.target(for: CGPoint(x: 150, y: 260), in: size) == .split(.bottom),
            "下へ 60pt（比 0.3）はみ出していても入れ替えにしない")
    #expect(PaneDropZone.target(for: CGPoint(x: -90, y: 100), in: size) == .split(.leading),
            "左へ 90pt（比 0.3）はみ出していても入れ替えにしない")
    // 境界ちょうどは「外」ではない。内側の規則（比と閾値）がそのまま効く。
    #expect(PaneDropZone.target(for: CGPoint(x: 150, y: 200), in: size) == .split(.bottom))
    #expect(PaneDropZone.target(for: CGPoint(x: 150, y: 100), in: size) == .swap)
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
func dividerHandlesArePlacedAfterTilesInTheStack() throws {
    // H2: AppKit の NSView に遮られないよう、掴みしろはタイルより後（前面）へ置く。
    // 規約の検査としてソースの順序を読む（振る舞いの検査に書き直せなかった）。現在の幾何では
    // 掴む領域（8pt）が隙間（8pt）と同じ幅で、端末の NSView も隙間から 10pt 内側にあるため、
    // 掴みしろとタイルの NSView が重ならず、順序を逆にしても hitTest もドラッグも変わらない
    // （画面外のウィンドウで順序を逆にして確認済み）。重なる幾何（掴む領域を隙間より太くする等）に
    // 変えたときは、この検査を hitTest の検査へ置き換える。
    let code = try sessionFeatureCode("PaneLayoutView.swift")
    let tile = try #require(code.range(of: "PaneTileView("))
    let handle = try #require(code.range(of: "PaneDividerHandleView("))
    #expect(tile.lowerBound < handle.lowerBound,
            "分割線ハンドルがタイルより前（背面）に置かれている")
}
