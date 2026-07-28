import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// task-2 の白箱テスト。受け入れテスト（AcceptancePaneDividerDragTests / ContractPaneDividerCommitTests）が
// 固定した契約に対し、**名指しされた正しさハザード**を狙い撃ちで潰す:
//
//  H1 ドラッグ中の確定（ADR 0116 の性能防壁）→ 乱択の操作列で「`.commit` の総数 == 有効な `ended` の
//     回数」を数え、`begin` / `changed` / `cancelled` からは一度も出ないことを確認する。加えて
//     `PaneDividerGhost` が比率を**持っていない**ことを Mirror で固定する（持たせた瞬間に
//     preview 値をレイアウトへ流す経路が復活するため、型の防壁そのものを検査する）。
//  H2 points → 比率の変換（分母は「隣接2枚の合計」であって split 全体ではない）→
//     ①クランプに当たらない範囲でゴーストが指と 1:1 で動くこと（分母を取り違えると比が狂う）
//     ②確定値を settingDivider に適用して再レイアウトすると、掴んだ分割線の segmentExtent /
//     segmentOrigin が不変で leadingFraction が確定値に一致すること（spacing の二重引きを殺す）。
//  H3 基準の非更新 → 極端値を挟んだ乱択の中間列を経由しても、最終 translation が同じなら
//     ゴースト位置・確定値が**ビット単位**で一致すること。
//  H4 2段クランプ → 乱択の frame × translation で「両側 >= minimumPaneExtent」かつ
//     「fraction ∈ [minimumDividerFraction, 1 - minimumDividerFraction]」。境界・±無限大・NaN・
//     退化した segment（0 長）まで含めて有限値に収まること。

@Suite("Whitebox: PaneDividerDragMachine（task-2 の正しさハザード）")
struct PaneDividerDragWhiteboxTests {

    // MARK: - ハーネス

    private func sid(_ n: Int) -> SessionID {
        let hex = String(format: "%012x", n)
        return SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(hex)")!)
    }

    /// 決定論的な擬似乱数（SplitMix64）。テストの再現性のため std の乱数源を使わない。
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

    /// 乱択の木（子2〜4・軸は階層ごとに反転・weights は正の乱数で合計は 1 でない）。
    private func randomNode(
        _ rng: inout SeededGenerator,
        counter: inout Int,
        depth: Int,
        axis: PaneAxis
    ) -> PaneNode {
        counter += 1
        let selfIndex = counter
        let childCount = Int.random(in: 2...4, using: &rng)
        var children: [PaneNode] = []
        var weights: [Double] = []
        for _ in 0..<childCount {
            if depth > 0, Int.random(in: 0...2, using: &rng) == 0 {
                children.append(
                    randomNode(
                        &rng,
                        counter: &counter,
                        depth: depth - 1,
                        axis: axis == .horizontal ? .vertical : .horizontal
                    )
                )
            } else {
                counter += 1
                children.append(.leaf(id: PaneID("L\(counter)"), session: sid(counter)))
            }
            weights.append(Double.random(in: 0.2...3.0, using: &rng))
        }
        return .split(PaneSplit(id: PaneID("S\(selfIndex)"), axis: axis, children: children, weights: weights))
    }

    private func randomTree(_ rng: inout SeededGenerator) throws -> PaneTree {
        var counter = 0
        let axis: PaneAxis = Bool.random(using: &rng) ? .horizontal : .vertical
        return try PaneTree(root: randomNode(&rng, counter: &counter, depth: 2, axis: axis))
    }

    /// 分割線の軸方向の中心（実レイアウト上の位置）。
    private func center(_ frame: PaneDividerFrame) -> CGFloat {
        frame.axis == .horizontal ? frame.gapRect.midX : frame.gapRect.midY
    }

    private func commitFraction(_ output: PaneDividerDragMachine.Output) -> Double? {
        if case .commit(_, let fraction) = output { return fraction }
        return nil
    }

    private func ghost(_ output: PaneDividerDragMachine.Output) -> PaneDividerGhost? {
        if case .preview(let ghost) = output { return ghost }
        return nil
    }

    /// 単純な2分割の分割線（幾何が手計算できる基準ケース）。
    private func simpleFrame(
        axis: PaneAxis = .horizontal,
        weights: [Double] = [0.5, 0.5],
        bounds: CGSize = CGSize(width: 1000, height: 800),
        spacing: CGFloat = 8
    ) throws -> PaneDividerFrame {
        let children = (0..<weights.count).map { PaneNode.leaf(id: PaneID("L\($0)"), session: sid($0 + 1)) }
        let tree = try PaneTree(
            root: .split(PaneSplit(id: PaneID("S"), axis: axis, children: children, weights: weights))
        )
        return try #require(tree.frames(in: bounds, spacing: spacing).dividers.first)
    }

    // MARK: - H1: ドラッグ中は確定しない（性能防壁）

    @Test("乱択の操作列でも .commit は「有効な ended」の回数しか出ない")
    func commitHappensOnlyOnEnded_overRandomOperationSequences() throws {
        var rng = SeededGenerator(seed: 0x5eed_0002)
        let frame = try simpleFrame()

        var machine = PaneDividerDragMachine()
        var dragging = false
        var expectedCommits = 0
        var observedCommits = 0

        for _ in 0..<4000 {
            switch Int.random(in: 0...9, using: &rng) {
            case 0:   // begin
                let output = machine.begin(frame, minimumPaneExtent: 240)
                #expect(commitFraction(output) == nil, "begin は確定しない")
                #expect(ghost(output) != nil, "begin は preview を返す")
                dragging = true
            case 1...6:   // changed
                let translation = CGFloat(Double.random(in: -5000...5000, using: &rng))
                let output = machine.changed(translation: translation)
                #expect(commitFraction(output) == nil, "changed は確定しない（translation=\(translation)）")
                #expect((output == .idle) == !dragging, "begin していなければ .idle、していれば .preview")
            case 7...8:   // ended
                let output = machine.ended(translation: CGFloat(Double.random(in: -5000...5000, using: &rng)))
                if dragging { expectedCommits += 1 }
                if commitFraction(output) != nil { observedCommits += 1 }
                dragging = false
            default:      // cancelled
                #expect(machine.cancelled() == .idle, "cancelled は常に .idle")
                dragging = false
            }
            #expect((machine.ghost != nil) == dragging, "ghost の有無がドラッグ状態と一致する")
        }

        #expect(observedCommits == expectedCommits, "確定は有効な ended の回数だけ起きる")
        #expect(expectedCommits > 0, "テスト自体が ended を踏んでいること")
    }

    @Test("乱択の frame × translation でも changed からは確定値が出ない")
    func changedNeverCommits_overRandomFramesAndTranslations() throws {
        var rng = SeededGenerator(seed: 0x5eed_0003)
        for _ in 0..<40 {
            let tree = try randomTree(&rng)
            let bounds = CGSize(
                width: CGFloat(Double.random(in: 400...2000, using: &rng)),
                height: CGFloat(Double.random(in: 400...2000, using: &rng))
            )
            let spacing = CGFloat([0.0, 4.0, 8.0, 16.0].randomElement(using: &rng)!)
            for frame in tree.frames(in: bounds, spacing: spacing).dividers {
                var machine = PaneDividerDragMachine()
                machine.begin(frame, minimumPaneExtent: CGFloat([1.0, 40.0, 120.0, 240.0].randomElement(using: &rng)!))
                for _ in 0..<10 {
                    let translation = CGFloat(Double.random(in: -10_000...10_000, using: &rng))
                    let output = machine.changed(translation: translation)
                    #expect(commitFraction(output) == nil, "changed が確定した（translation=\(translation)）")
                    #expect(ghost(output) != nil, "changed は preview を返す")
                }
                #expect(machine.ghost != nil, "ドラッグは継続している")
            }
        }
    }

    @Test("ゴーストは比率を持たない（preview をレイアウト更新へ流す経路を型で塞いでいる）")
    func ghostCarriesNoFraction() throws {
        let frame = try simpleFrame()
        var machine = PaneDividerDragMachine()
        let preview = try #require(ghost(machine.begin(frame, minimumPaneExtent: 240)))

        // ここに比率（settingDivider へ渡せる値）を足した瞬間、ADR 0116 の防壁が
        // 「呼び出し側の作法」に格下げされる。プロパティ集合を機械的に固定して退行を止める。
        let labels = Set(Mirror(reflecting: preview).children.compactMap(\.label))
        #expect(labels == ["divider", "axis", "position", "crossOrigin", "crossExtent"],
                "PaneDividerGhost のプロパティ集合が変わった: \(labels.sorted())")
    }

    // MARK: - H2: points → 比率の変換（分母は隣接2枚の合計）

    @Test("クランプに当たらない範囲では、ゴーストは指の移動量と 1:1 で動く")
    func ghostTracksTheFingerOneToOne_whenUnclamped() throws {
        var rng = SeededGenerator(seed: 0x5eed_0004)
        var checked = 0
        for _ in 0..<40 {
            let tree = try randomTree(&rng)
            let bounds = CGSize(
                width: CGFloat(Double.random(in: 600...2000, using: &rng)),
                height: CGFloat(Double.random(in: 600...2000, using: &rng))
            )
            let spacing = CGFloat([0.0, 4.0, 8.0, 16.0].randomElement(using: &rng)!)
            for frame in tree.frames(in: bounds, spacing: spacing).dividers {
                // クランプの外側だけを見たいので、初期比率が十分内側にある分割線を使い、
                // 最小長は segmentExtent の 10%（= 比率 0.1）に取る。
                guard frame.segmentExtent > 1,
                      frame.leadingFraction >= 0.15, frame.leadingFraction <= 0.85 else { continue }
                let minimumPaneExtent = frame.segmentExtent * 0.1

                var machine = PaneDividerDragMachine()
                let start = try #require(ghost(machine.begin(frame, minimumPaneExtent: minimumPaneExtent)))
                for _ in 0..<5 {
                    // 目標比率は [0.15, 0.85]（クランプ範囲 [0.1, 0.9] の内側）。
                    let target = Double.random(in: 0.15...0.85, using: &rng)
                    let translation = CGFloat(target - frame.leadingFraction) * frame.segmentExtent
                    let moved = try #require(ghost(machine.changed(translation: translation)))
                    // 分母を「split 全体」や「segmentExtent - spacing」に取り違えると、
                    // ここで translation に対する比例係数がずれて落ちる。
                    #expect(abs(moved.position - (start.position + translation)) <= 1e-6,
                            "1:1 で動かない: expected \(start.position + translation), got \(moved.position)")
                    checked += 1
                }
            }
        }
        #expect(checked > 100, "十分な件数を検査したこと（実績 \(checked) 件）")
    }

    @Test("確定値を settingDivider に適用すると、掴んだ分割線の幾何が確定値どおりになる")
    func commitAppliesExactlyToTheGrabbedPair() throws {
        var rng = SeededGenerator(seed: 0x5eed_0005)
        var checked = 0
        for _ in 0..<40 {
            let tree = try randomTree(&rng)
            let bounds = CGSize(
                width: CGFloat(Double.random(in: 500...2000, using: &rng)),
                height: CGFloat(Double.random(in: 500...2000, using: &rng))
            )
            let spacing = CGFloat([0.0, 4.0, 8.0, 16.0].randomElement(using: &rng)!)
            let before = tree.frames(in: bounds, spacing: spacing)
            for frame in before.dividers {
                let minimumPaneExtent = CGFloat([1.0, 40.0, 120.0].randomElement(using: &rng)!)
                let translation = CGFloat(Double.random(in: -1500...1500, using: &rng))

                var machine = PaneDividerDragMachine()
                machine.begin(frame, minimumPaneExtent: minimumPaneExtent)
                machine.changed(translation: translation)
                let ghostPosition = try #require(machine.ghost?.position)
                let fraction = try #require(commitFraction(machine.ended(translation: translation)))

                let after = tree.settingDivider(frame.id, leadingFraction: fraction)
                    .frames(in: bounds, spacing: spacing)
                let updated = try #require(after.dividers.first(where: { $0.id == frame.id }),
                                           "確定後も同じ分割線 ID が存在する")

                // 隣接2枚の占める区間そのものは動かない（他のペインを巻き込まない）。
                #expect(abs(updated.segmentExtent - frame.segmentExtent) <= 1e-6,
                        "segmentExtent が変わった")
                #expect(abs(updated.segmentOrigin - frame.segmentOrigin) <= 1e-6,
                        "segmentOrigin が変わった")
                // 確定した比率が、そのまま「隣接2枚の合計に対する leading の取り分」になる。
                if frame.segmentExtent > 1 {
                    #expect(abs(updated.leadingFraction - fraction) <= 1e-9,
                            "確定比率が反映されていない: expected \(fraction), got \(updated.leadingFraction)")
                }
                // ゴーストが指していた位置に実際の分割線が来る。
                #expect(abs(center(updated) - ghostPosition) <= 1e-6,
                        "ゴースト位置と確定後の分割線がずれた: \(center(updated)) vs \(ghostPosition)")
                checked += 1
            }
        }
        #expect(checked > 100, "十分な件数を検査したこと（実績 \(checked) 件）")
    }

    @Test("translation 0 で確定してもレイアウトは動かない（往復で漂流しない）")
    func zeroTranslationCommit_leavesLayoutUnchanged() throws {
        var rng = SeededGenerator(seed: 0x5eed_0006)
        for _ in 0..<20 {
            let tree = try randomTree(&rng)
            let bounds = CGSize(width: 1440, height: 900)
            let spacing: CGFloat = 8
            let before = tree.frames(in: bounds, spacing: spacing)
            var current = tree
            // 全分割線を順に「掴んで動かさず離す」。
            for frame in before.dividers {
                var machine = PaneDividerDragMachine()
                machine.begin(frame, minimumPaneExtent: 1)
                let fraction = try #require(commitFraction(machine.ended(translation: 0)))
                current = current.settingDivider(frame.id, leadingFraction: fraction)
            }
            let after = current.frames(in: bounds, spacing: spacing)
            #expect(after.tiles.count == before.tiles.count)
            for (lhs, rhs) in zip(before.tiles, after.tiles) {
                #expect(lhs.session == rhs.session)
                #expect(abs(lhs.rect.minX - rhs.rect.minX) <= 1e-6, "x が漂流した")
                #expect(abs(lhs.rect.minY - rhs.rect.minY) <= 1e-6, "y が漂流した")
                #expect(abs(lhs.rect.width - rhs.rect.width) <= 1e-6, "幅が漂流した")
                #expect(abs(lhs.rect.height - rhs.rect.height) <= 1e-6, "高さが漂流した")
            }
        }
    }

    // MARK: - H3: begin の基準がドラッグ中に動かない

    @Test("極端値を挟んだ乱択の中間列を経由しても、最終 translation が同じならビット単位で同じ")
    func ghostAndCommitArePathIndependent_bitForBit() throws {
        var rng = SeededGenerator(seed: 0x5eed_0007)
        let frames = [
            try simpleFrame(axis: .horizontal, weights: [0.3, 0.7]),
            try simpleFrame(axis: .vertical, weights: [0.5, 0.5]),
            try simpleFrame(axis: .horizontal, weights: [0.2, 0.3, 0.5], bounds: CGSize(width: 1600, height: 900))
        ]
        for frame in frames {
            for _ in 0..<20 {
                let final = CGFloat(Double.random(in: -800...800, using: &rng))

                var wandering = PaneDividerDragMachine()
                wandering.begin(frame, minimumPaneExtent: 120)
                // クランプに何度も張り付かせてから戻る（張り付きが基準を書き換えないことの検査）。
                for extreme in [1e9, -1e9, 0.0, .infinity, -.infinity, 5.0, -5.0] {
                    wandering.changed(translation: CGFloat(extreme))
                }
                for _ in 0..<10 {
                    wandering.changed(translation: CGFloat(Double.random(in: -5000...5000, using: &rng)))
                }
                let wanderingGhost = try #require(ghost(wandering.changed(translation: final)))

                var direct = PaneDividerDragMachine()
                direct.begin(frame, minimumPaneExtent: 120)
                let directGhost = try #require(ghost(direct.changed(translation: final)))

                #expect(wanderingGhost == directGhost, "ゴーストが経路に依存した")
                #expect(wandering.ended(translation: final) == direct.ended(translation: final),
                        "確定値が経路に依存した")
            }
        }
    }

    @Test("begin をやり直すと新しい frame が基準になる")
    func beginRebasesToTheNewFrame() throws {
        let wide = try simpleFrame(axis: .horizontal, weights: [0.5, 0.5])
        let narrow = try simpleFrame(axis: .horizontal, weights: [0.25, 0.75])

        var machine = PaneDividerDragMachine()
        machine.begin(wide, minimumPaneExtent: 120)
        machine.changed(translation: 300)
        let restarted = try #require(ghost(machine.begin(narrow, minimumPaneExtent: 120)))
        #expect(abs(restarted.position - narrow.gapRect.midX) <= 1e-9, "掴み直した分割線の中心から始まる")

        let fraction = try #require(commitFraction(machine.ended(translation: 0)))
        #expect(abs(fraction - narrow.leadingFraction) <= 1e-9, "確定値も新しい基準に従う")
    }

    @Test("cancelled の後に掴み直せる。cancelled 中の changed / ended は無効")
    func cancelledThenBeginAgain() throws {
        let frame = try simpleFrame()
        var machine = PaneDividerDragMachine()
        machine.begin(frame, minimumPaneExtent: 240)
        machine.changed(translation: 300)
        #expect(machine.cancelled() == .idle)
        #expect(machine.changed(translation: 300) == .idle, "中断後の changed は無効")
        #expect(machine.ended(translation: 300) == .idle, "中断後の ended は確定しない")

        let resumed = try #require(ghost(machine.begin(frame, minimumPaneExtent: 240)))
        #expect(abs(resumed.position - frame.gapRect.midX) <= 1e-9, "掴み直しは元の位置から")
        #expect(commitFraction(machine.ended(translation: 40)) != nil, "掴み直した後は確定できる")
    }

    // MARK: - H4: 2段クランプ

    @Test("任意の translation で両側のペインが最小長を保ち、比率も下限・上限に収まる")
    func clampKeepsBothPanesAtLeastMinimum() throws {
        var rng = SeededGenerator(seed: 0x5eed_0008)
        var checked = 0
        for _ in 0..<40 {
            let tree = try randomTree(&rng)
            let bounds = CGSize(
                width: CGFloat(Double.random(in: 500...2000, using: &rng)),
                height: CGFloat(Double.random(in: 500...2000, using: &rng))
            )
            let spacing = CGFloat([0.0, 4.0, 8.0, 16.0].randomElement(using: &rng)!)
            for frame in tree.frames(in: bounds, spacing: spacing).dividers {
                let minimumPaneExtent = CGFloat([1.0, 40.0, 120.0, 240.0].randomElement(using: &rng)!)
                for _ in 0..<8 {
                    let translation = CGFloat(Double.random(in: -50_000...50_000, using: &rng))
                    var machine = PaneDividerDragMachine()
                    machine.begin(frame, minimumPaneExtent: minimumPaneExtent)
                    let ghostPosition = try #require(ghost(machine.changed(translation: translation))?.position)
                    let fraction = try #require(commitFraction(machine.ended(translation: translation)))

                    #expect(fraction.isFinite, "確定値が有限")
                    #expect(fraction >= PaneTree.minimumDividerFraction - 1e-12, "下限クランプ")
                    #expect(fraction <= 1 - PaneTree.minimumDividerFraction + 1e-12, "上限クランプ")
                    #expect(ghostPosition.isFinite, "ゴースト位置が有限")

                    if frame.segmentExtent >= minimumPaneExtent * 2 {
                        let leading = frame.segmentExtent * CGFloat(fraction)
                        let trailing = frame.segmentExtent - leading
                        #expect(leading >= minimumPaneExtent - 1e-6, "leading 側が最小長を割った")
                        #expect(trailing >= minimumPaneExtent - 1e-6, "trailing 側が最小長を割った")
                    } else {
                        #expect(abs(fraction - 0.5) <= 1e-12, "両側の最小長を満たせないときは等分")
                    }
                    // ゴーストも確定値と同じクランプ後の位置に居る。
                    let expected = frame.segmentOrigin + frame.segmentExtent * CGFloat(fraction)
                        + (frame.axis == .horizontal ? frame.gapRect.width : frame.gapRect.height) / 2
                    #expect(abs(ghostPosition - expected) <= 1e-9, "ゴーストがクランプ後の位置と一致しない")
                    checked += 1
                }
            }
        }
        #expect(checked > 200, "十分な件数を検査したこと（実績 \(checked) 件）")
    }

    @Test("クランプは leading / trailing で対称")
    func clampIsSymmetric() throws {
        let frame = try simpleFrame(axis: .horizontal, weights: [0.5, 0.5])   // 初期 0.5
        for magnitude in [0.0, 1.0, 100.0, 245.0, 246.0, 1000.0, 1e9] {
            var forward = PaneDividerDragMachine()
            forward.begin(frame, minimumPaneExtent: 240)
            let plus = try #require(commitFraction(forward.ended(translation: CGFloat(magnitude))))

            var backward = PaneDividerDragMachine()
            backward.begin(frame, minimumPaneExtent: 240)
            let minus = try #require(commitFraction(backward.ended(translation: CGFloat(-magnitude))))

            #expect(abs((plus - 0.5) - (0.5 - minus)) <= 1e-12,
                    "magnitude=\(magnitude): 対称でない (\(plus) / \(minus))")
        }
    }

    @Test("無限大は境界にちょうど張り付き、NaN は等分へ倒れる")
    func nonFiniteTranslationsStayWithinBounds() throws {
        let frame = try simpleFrame()   // segmentExtent = 992
        let minimum: CGFloat = 240
        var machine = PaneDividerDragMachine()
        machine.begin(frame, minimumPaneExtent: minimum)

        let upper = try #require(commitFraction(machine.ended(translation: .infinity)))
        #expect(abs(upper - Double((frame.segmentExtent - minimum) / frame.segmentExtent)) <= 1e-12,
                "+∞ は上限に張り付く")

        var machine2 = PaneDividerDragMachine()
        machine2.begin(frame, minimumPaneExtent: minimum)
        let lower = try #require(commitFraction(machine2.ended(translation: -.infinity)))
        #expect(abs(lower - Double(minimum / frame.segmentExtent)) <= 1e-12, "-∞ は下限に張り付く")

        var machine3 = PaneDividerDragMachine()
        machine3.begin(frame, minimumPaneExtent: minimum)
        let nanGhost = try #require(ghost(machine3.changed(translation: CGFloat.nan)))
        #expect(nanGhost.position.isFinite, "NaN でもゴースト位置が有限")
        let nanFraction = try #require(commitFraction(machine3.ended(translation: CGFloat.nan)))
        #expect(abs(nanFraction - 0.5) <= 1e-12, "NaN は等分へ倒す")
    }

    @Test("退化した segment（0 長・最小長を満たせない）でも NaN を出さず等分へ倒す")
    func degenerateSegmentsFallBackToEqualSplit() throws {
        // ① レイアウト確定前の 0 サイズ。
        let zero = try simpleFrame(bounds: CGSize(width: 0, height: 0))
        #expect(zero.segmentExtent == 0)
        for translation in [-1000.0, 0.0, 1000.0] {
            var machine = PaneDividerDragMachine()
            let start = try #require(ghost(machine.begin(zero, minimumPaneExtent: 240)))
            #expect(start.position.isFinite, "0 サイズでも位置が有限")
            let moved = try #require(ghost(machine.changed(translation: CGFloat(translation))))
            #expect(moved.position == start.position, "0 サイズなら動かない")
            let fraction = try #require(commitFraction(machine.ended(translation: CGFloat(translation))))
            #expect(abs(fraction - 0.5) <= 1e-12, "等分へ倒す")
        }

        // ② segmentExtent がちょうど minimumPaneExtent * 2（境界。クランプ区間が1点に潰れる）。
        let exact = try simpleFrame(bounds: CGSize(width: 1000, height: 800))   // segmentExtent = 992
        for minimum in [496.0, 496.000001] {
            for translation in [-3000.0, 0.0, 3000.0] {
                var machine = PaneDividerDragMachine()
                machine.begin(exact, minimumPaneExtent: CGFloat(minimum))
                let fraction = try #require(commitFraction(machine.ended(translation: CGFloat(translation))))
                #expect(abs(fraction - 0.5) <= 1e-12,
                        "minimum=\(minimum), translation=\(translation): 等分に固定される")
            }
        }

        // ③ minimumPaneExtent が 0 以下でも比率クランプは効く。
        var machine = PaneDividerDragMachine()
        machine.begin(exact, minimumPaneExtent: 0)
        let fraction = try #require(commitFraction(machine.ended(translation: 100_000)))
        #expect(abs(fraction - (1 - PaneTree.minimumDividerFraction)) <= 1e-12,
                "最小長が無くても比率の上限で止まる")
    }

    // MARK: - 軸ごとの直交方向

    @Test("直交方向の描画範囲は gapRect から軸に応じて引き継ぐ")
    func crossExtentFollowsTheAxis() throws {
        let horizontal = try simpleFrame(axis: .horizontal)
        var machine = PaneDividerDragMachine()
        let hGhost = try #require(ghost(machine.begin(horizontal, minimumPaneExtent: 100)))
        #expect(hGhost.crossOrigin == horizontal.gapRect.minY)
        #expect(hGhost.crossExtent == horizontal.gapRect.height)
        #expect(hGhost.divider == horizontal.id)

        let vertical = try simpleFrame(axis: .vertical)
        var machine2 = PaneDividerDragMachine()
        let vGhost = try #require(ghost(machine2.begin(vertical, minimumPaneExtent: 100)))
        #expect(vGhost.crossOrigin == vertical.gapRect.minX)
        #expect(vGhost.crossExtent == vertical.gapRect.width)

        // 縦分割では translation が y 方向。確定後の分割線も y 方向で一致する。
        machine2.changed(translation: 90)
        let ghostPosition = try #require(machine2.ghost?.position)
        #expect(abs(ghostPosition - (vGhost.position + 90)) <= 1e-6, "縦分割でも指と 1:1")
        #expect(commitFraction(machine2.ended(translation: 90)) != nil)
    }
}
