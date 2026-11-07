import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

/// TranscriptWindow（トランスクリプトの末尾 N 件表示・隠れ件数・expand・reset）の純ロジック。
/// ジャンプと上限でずれる窓（ADR 0228）は SessionFeature の TranscriptWindowBoundedTests が担う。
/// 名指しハザードの「off-by-one（start と hidden とスライス表示件数の整合）」と
/// 「window 拡張の単調性・末尾追従」を内部不変条件として符号化する。
/// AutoFollow 等の view 挙動は ChatAutoFollowAcceptanceTests が担う。
@Suite("Transcript window", .serialized)
struct TranscriptWindowTests {

    // 不変条件（全域）: startIndex == hiddenCount、かつ表示件数 = total - start = min(total, limit)、
    // かつ startIndex は 0...total に収まる。off-by-one をあらゆる (total, expandCount) で検出する。
    @Test
    func invariant_sliceCoversExactlyTail_forAllInputs() {
        for expandCount in 0..<4 {
            var window = TranscriptWindow()
            for _ in 0..<expandCount { window.expand() }
            let limit = window.limit
            for total in [0, 1, 49, 50, 199, 200, 201, 399, 400, 1000, 5000] {
                let (start, hidden) = window.visibleRange(totalCount: total)
                #expect(start == hidden, "startIndex と hiddenCount がずれている total=\(total) limit=\(limit)")
                #expect(start >= 0, "startIndex が負 total=\(total)")
                #expect(start <= total, "startIndex が total を超過 total=\(total) start=\(start)")
                let visibleCount = total - start
                #expect(visibleCount == min(total, limit),
                        "表示件数が min(total, limit) と一致しない total=\(total) limit=\(limit) visible=\(visibleCount)")
                // スライスが実配列に対して有効域であること（先頭 hidden 件を落とした末尾）。
                let items = Array(0..<total)
                let slice = items[start...]
                #expect(slice.count == visibleCount, "スライス長が表示件数と一致しない total=\(total)")
                if total > 0, let lastVisible = slice.last {
                    #expect(lastVisible == total - 1, "スライスの末尾が全体の末尾でない（末尾追従が壊れている）")
                }
            }
        }
    }

    // expand はユーザー操作1回につき step 分だけ表示を増やす（隠れが減る）。
    @Test
    func expand_growsWindowByStep() {
        var window = TranscriptWindow()
        let total = window.limit + TranscriptWindow.expandStep + 10
        let before = window.visibleRange(totalCount: total)
        window.expand()
        let after = window.visibleRange(totalCount: total)
        #expect(after.hiddenCount == before.hiddenCount - TranscriptWindow.expandStep,
                "expand で隠れ件数が step 分減っていない")
        #expect(window.limit == TranscriptWindow.defaultLimit + TranscriptWindow.expandStep)

        // 全件を超えて拡張しても負にならない。
        window.expand()
        let final = window.visibleRange(totalCount: total)
        #expect(final.hiddenCount == 0)
        #expect(final.startIndex == 0)
    }

    // expand は limit を上限（maxStages 段。ADR 0228）まで単調増加させ、上限で止まる。
    // 隠れ件数は単調減少（0 で下げ止まり）する。
    @Test
    func expand_isMonotonicUntilStageCapAndClampsAtZero() {
        var window = TranscriptWindow()
        let total = TranscriptWindow.defaultLimit + 3 * TranscriptWindow.expandStep
        let cap = TranscriptWindow.maxStages * TranscriptWindow.defaultLimit
        var previousHidden = window.visibleRange(totalCount: total).hiddenCount
        var previousLimit = window.limit
        for _ in 0..<10 {
            window.expand()
            #expect(window.limit == min(previousLimit + TranscriptWindow.expandStep, cap),
                    "expand が step 分増えていない、または上限を超えた")
            let hidden = window.visibleRange(totalCount: total).hiddenCount
            #expect(hidden <= previousHidden, "expand で隠れ件数が増えた")
            #expect(hidden >= 0, "隠れ件数が負")
            previousHidden = hidden
            previousLimit = window.limit
        }
        #expect(window.limit == cap, "10 回の expand で上限に届いていない")
        // 十分拡張すれば全件表示（隠れ 0・start 0）に到達する。
        #expect(window.visibleRange(totalCount: total).hiddenCount == 0)
        #expect(window.visibleRange(totalCount: total).startIndex == 0)
    }

    // ストリーミング追従: limit 未満から超過へ item が増えても、常に末尾を含み続ける
    // （新規 item 追加で先頭境界が動くだけで、可視スライスの末尾は常に最新）。
    @Test
    func streamingGrowth_alwaysIncludesTail() {
        let window = TranscriptWindow()
        var lastStart = 0
        for total in stride(from: 0, through: TranscriptWindow.defaultLimit + 500, by: 7) {
            let (start, hidden) = window.visibleRange(totalCount: total)
            // 末尾 min(total, limit) 件が可視。
            #expect(total - start == min(total, window.limit))
            // total が limit を超えた後は start が単調非減少（先頭が押し出されていく）。
            if total > window.limit {
                #expect(start >= lastStart, "追従中に開始位置が巻き戻った total=\(total)")
            }
            #expect(hidden == max(0, total - window.limit))
            lastStart = start
        }
    }

    // reset は expand の履歴に依らず必ず既定へ戻す（べき等）。
    @Test
    func reset_isIdempotentToDefault() {
        var window = TranscriptWindow()
        for _ in 0..<5 { window.expand() }
        window.reset()
        #expect(window.limit == TranscriptWindow.defaultLimit)
        window.reset()
        #expect(window.limit == TranscriptWindow.defaultLimit)
        // reset 後の visibleRange は既定 limit の挙動に戻る。
        let over = TranscriptWindow.defaultLimit + 25
        #expect(window.visibleRange(totalCount: over).hiddenCount == 25)
    }

    // 既定 limit と expand step は有限の定数で定義される。
    @Test
    func constants_withinContractBounds() {
        #expect((50...500).contains(TranscriptWindow.defaultLimit))
        #expect(TranscriptWindow.expandStep >= 50)
    }

    // 展開アンカー（追加要望）: ビューポートを留めるアンカーは「押下時の先頭可視 item」
    // ＝ visibleRange(totalCount).startIndex の item。expand 後もそのアンカーは可視スライスに
    // 残り（newStart <= anchorIndex）、かつ上に以前隠れていた行が現れて遡れる（newStart < anchorIndex）。
    @Test
    func expandAnchor_preExpandFirstVisibleStaysVisibleWithEarlierAbove() {
        var window = TranscriptWindow()
        let total = TranscriptWindow.defaultLimit + TranscriptWindow.expandStep + 50
        let anchorIndex = window.visibleRange(totalCount: total).startIndex  // 押下時の先頭可視 index
        #expect(anchorIndex > 0, "前提: アンカーより上に隠れ item がある")
        window.expand()
        let newStart = window.visibleRange(totalCount: total).startIndex
        #expect(newStart <= anchorIndex, "expand 後にアンカー item が可視スライスから外れた")
        #expect(newStart < anchorIndex, "expand 後にアンカーの上へ遡れる（以前隠れていた）item が現れていない")
        // 全件を超えて展開した端では、アンカー item は依然可視（先頭 0 まで露出）。
        window.expand()
        window.expand()
        let fullStart = window.visibleRange(totalCount: total).startIndex
        #expect(fullStart <= anchorIndex)
    }
}
