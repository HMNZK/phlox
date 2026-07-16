import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

/// PM3 task-8 白箱テスト（実装役著述）。
/// 受け入れテスト（PM3Task8TranscriptWindowAcceptanceTests）が凍結する外形契約に加えて、
/// 名指しハザードである「off-by-one（start と hidden とスライス表示件数の整合）」と
/// 「window 拡張の単調性・末尾追従」を内部不変条件として符号化する。
@Suite(.serialized)
struct PM3Task8TranscriptWindowWhiteboxTests {

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

    // expand は limit を単調増加させ、隠れ件数を単調減少（0 で下げ止まり）させる。
    @Test
    func expand_isMonotonicAndClampsAtZero() {
        var window = TranscriptWindow()
        let total = TranscriptWindow.defaultLimit + 3 * TranscriptWindow.expandStep
        var previousHidden = window.visibleRange(totalCount: total).hiddenCount
        var previousLimit = window.limit
        for _ in 0..<10 {
            window.expand()
            #expect(window.limit > previousLimit, "expand で limit が増えていない")
            let hidden = window.visibleRange(totalCount: total).hiddenCount
            #expect(hidden <= previousHidden, "expand で隠れ件数が増えた")
            #expect(hidden >= 0, "隠れ件数が負")
            previousHidden = hidden
            previousLimit = window.limit
        }
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

    // defaultLimit が範囲内・expandStep が下限以上（受け入れ側と重複するが白箱の前提として明示）。
    @Test
    func constants_withinContractBounds() {
        #expect((50...500).contains(TranscriptWindow.defaultLimit))
        #expect(TranscriptWindow.expandStep >= 50)
    }

    // reveal（ステージ1差し戻し）: あらゆる隠れ域 index を可視化し、可視 index では no-op。
    // 範囲外 index は安全に無視する（対象行が現セッションに無いケースの防御）。
    @Test
    func reveal_makesAnyHiddenIndexVisible_andNoOpWhenVisible() {
        let total = TranscriptWindow.defaultLimit + 400
        // 隠れ域の全 index を可視化できる（境界含む）。
        for index in [0, 1, 50, TranscriptWindow.defaultLimit - 1] {
            var window = TranscriptWindow()
            window.reveal(index: index, totalCount: total)
            let start = window.visibleRange(totalCount: total).startIndex
            #expect(start <= index, "reveal 後に index=\(index) が可視域に入っていない start=\(start)")
        }
        // 可視域 index では limit 不変。
        var visible = TranscriptWindow()
        let base = visible.limit
        for index in [total - 1, total - 10, total - visible.limit] {
            visible.reveal(index: index, totalCount: total)
            #expect(visible.limit == base, "可視 index=\(index) への reveal で limit が変わった")
        }
        // 範囲外 index（別セッション由来の解決ミスなど）は無視。
        var oob = TranscriptWindow()
        let before = oob.limit
        oob.reveal(index: -1, totalCount: total)
        oob.reveal(index: total, totalCount: total)
        oob.reveal(index: total + 100, totalCount: total)
        #expect(oob.limit == before, "範囲外 index で limit が変わった")
    }

    // reveal は単調（limit を縮めない）。より浅い reveal の後に深い reveal をしても逆行しない。
    // total を十分大きく取り、中間 index の reveal 後も先頭側がまだ隠れ域に残るようにする
    // （マージン +expandStep で全件可視化されない配置）。
    @Test
    func reveal_isMonotonic() {
        let total = TranscriptWindow.defaultLimit + 1000
        var window = TranscriptWindow()
        window.reveal(index: 900, totalCount: total)       // 中間を可視化（まだ先頭側は隠れ域）
        let deep = window.limit
        #expect(window.visibleRange(totalCount: total).startIndex > 0, "テスト前提: 先頭側はまだ隠れ域")
        window.reveal(index: total - 1, totalCount: total) // 可視域 → no-op
        #expect(window.limit == deep, "可視 index への reveal で limit が縮んだ/変わった")
        window.reveal(index: 0, totalCount: total)         // さらに深く（最古）
        #expect(window.limit >= deep, "深い reveal で limit が縮んだ")
        #expect(window.visibleRange(totalCount: total).startIndex == 0)
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

    // reveal のマージン（stage2 差し戻し）: 露出はぴったりでなく expandStep 分の余裕を持ち、
    // reveal 後に item が expandStep 件まで増えてもターゲットが可視のまま（遅延 scrollTo 空振り防止）。
    @Test
    func reveal_marginToleratesStreamingGrowthUpToExpandStep() {
        for targetIndex in [0, 1, 37, TranscriptWindow.defaultLimit - 1] {
            var window = TranscriptWindow()
            let oldTotal = TranscriptWindow.defaultLimit + 300
            // 前提: 隠れ域。
            #expect(window.visibleRange(totalCount: oldTotal).startIndex > targetIndex)
            window.reveal(index: targetIndex, totalCount: oldTotal)
            // reveal 直後〜expandStep 件の成長まで、ターゲットは可視スライスに入り続ける。
            for delta in [0, 1, TranscriptWindow.expandStep] {
                let start = window.visibleRange(totalCount: oldTotal + delta).startIndex
                #expect(start <= targetIndex,
                        "index=\(targetIndex) が delta=\(delta) の成長で隠れ域へ落ちた start=\(start)")
            }
        }
    }
}
