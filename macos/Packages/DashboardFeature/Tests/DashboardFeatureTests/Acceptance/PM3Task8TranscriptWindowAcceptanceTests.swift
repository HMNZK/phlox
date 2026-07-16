import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-8 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-8.md — TranscriptWindow の純ロジック（末尾 N 件・隠れ件数・expand・reset）。
// AutoFollow 等の view 挙動は既存 ChatAutoFollowAcceptanceTests（編集禁止）が凍結する。

@Suite(.serialized)
struct PM3Task8TranscriptWindowAcceptanceTests {

    // 既定 limit と expand step は有限の定数で定義される。
    @Test
    func constants_areBoundedFiniteValues() {
        #expect(
            (50...500).contains(TranscriptWindow.defaultLimit),
            "既定表示件数が有限の定数（50...500）で定義されていない: \(TranscriptWindow.defaultLimit)"
        )
        #expect(
            TranscriptWindow.expandStep >= 50,
            "拡張幅が 50 未満: \(TranscriptWindow.expandStep)"
        )
    }

    // items ≤ limit なら全件表示・隠れ 0。
    @Test
    func visibleRange_showsAllWhenWithinLimit() {
        let window = TranscriptWindow()
        let (start, hidden) = window.visibleRange(totalCount: 10)
        #expect(start == 0)
        #expect(hidden == 0)
        let boundary = window.visibleRange(totalCount: window.limit)
        #expect(boundary.startIndex == 0)
        #expect(boundary.hiddenCount == 0)
    }

    // 超過時は末尾 limit 件のみ・隠れ件数 = total - limit。
    @Test
    func visibleRange_showsTailWhenOverLimit() {
        let window = TranscriptWindow()
        let total = window.limit + 37
        let (start, hidden) = window.visibleRange(totalCount: total)
        #expect(hidden == 37, "隠れ件数が total - limit と一致しない: \(hidden)")
        #expect(start == 37, "表示開始位置が隠れ件数と一致しない: \(start)")
        #expect(total - start == window.limit, "表示件数が limit と一致しない")
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

    // reset はセッション切替時に既定へ戻す。
    @Test
    func reset_restoresDefaultLimit() {
        var window = TranscriptWindow()
        window.expand()
        window.expand()
        #expect(window.limit > TranscriptWindow.defaultLimit)
        window.reset()
        #expect(window.limit == TranscriptWindow.defaultLimit)
    }

    // reveal（ステージ1指摘の裁定 = 案b）: 隠れ域の item へのユーザー起点ジャンプは、
    // scrollTo の前に window を広げてターゲットを可視にする。既に可視なら何もしない。
    @Test
    func reveal_makesHiddenIndexVisibleAndIsNoOpWhenVisible() {
        var window = TranscriptWindow()
        let total = TranscriptWindow.defaultLimit + 300
        // 先頭付近（index 10）は既定 window では隠れている。
        let hiddenBefore = window.visibleRange(totalCount: total).startIndex
        #expect(hiddenBefore > 10, "テスト前提: index 10 は隠れ域")
        window.reveal(index: 10, totalCount: total)
        let (start, _) = window.visibleRange(totalCount: total)
        #expect(start <= 10, "reveal 後もジャンプ先 index 10 が可視スライスに含まれていない: start=\(start)")

        // 既に可視の index では limit を変えない（無駄な全件展開をしない）。
        var alreadyVisible = TranscriptWindow()
        let before = alreadyVisible.limit
        alreadyVisible.reveal(index: total - 1, totalCount: total)
        #expect(alreadyVisible.limit == before, "可視 index への reveal で limit が変わった")

        // 端: index 0（最古）も可視にできる。
        var toOldest = TranscriptWindow()
        toOldest.reveal(index: 0, totalCount: total)
        #expect(toOldest.visibleRange(totalCount: total).startIndex == 0)
    }

    // reveal の成長耐性（stage2 指摘の裁定）: reveal 後、遅延 scrollTo までに
    // ストリーミングで item が増えても（expandStep 件まで）ターゲットは可視のまま。
    // ぴったり totalCount - index に合わせる実装は 1 件の増加で破綻するため契約で禁止する。
    @Test
    func reveal_keepsTargetVisibleWhileTranscriptGrows() {
        var window = TranscriptWindow()
        let targetIndex = 10
        let oldTotal = TranscriptWindow.defaultLimit + 300

        window.reveal(index: targetIndex, totalCount: oldTotal)
        #expect(window.visibleRange(totalCount: oldTotal).startIndex <= targetIndex)

        // 遅延中に 1 件増えた場合。
        #expect(
            window.visibleRange(totalCount: oldTotal + 1).startIndex <= targetIndex,
            "reveal 直後の 1 delta でターゲットが再び隠れ域に落ちる（マージン不足）"
        )
        // expandStep 件までの成長に耐える。
        #expect(
            window.visibleRange(totalCount: oldTotal + TranscriptWindow.expandStep).startIndex <= targetIndex,
            "expandStep 件までの成長でターゲットが隠れ域に落ちる"
        )
    }

    // 空・少数の端ケース。
    @Test
    func visibleRange_edgeCases() {
        let window = TranscriptWindow()
        let empty = window.visibleRange(totalCount: 0)
        #expect(empty.startIndex == 0)
        #expect(empty.hiddenCount == 0)
        let one = window.visibleRange(totalCount: 1)
        #expect(one.startIndex == 0)
        #expect(one.hiddenCount == 0)
    }
}
