import Foundation
import Testing
@testable import Features

// task-1（iOS チャット履歴の折りたたみ）の受け入れテスト。PM が著す不変の契約。
// 実装役は編集禁止。テストハーネスの欠陥を発見した場合のみ PM に報告し承認を得て
// ハーネス部分に限り修理してよい（アサーションの改変は禁止）。
//
// 契約の骨子（macOS の TranscriptWindow を iOS へ移植・単一表示のみ・grid 文脈なし）:
// - 既定の表示件数上限 defaultLimit = 50、拡張ステップ expandStep = 50（200 から引き下げ、初回描画を軽くする）。
// - visibleRange(totalCount:) は totalCount のみから末尾スライスの開始位置と隠れ件数を返す純関数。
//   totalCount <= limit のとき (startIndex: 0, hiddenCount: 0)。
//   超過時は (startIndex: totalCount - limit, hiddenCount: totalCount - limit)。負にならない。
// - expand() は limit を expandStep 分だけ単調増加させる（縮まない）。ユーザーの「以前のメッセージを表示」操作でのみ呼ぶ。
// - reset() は既定へ戻す（セッション切替時）。
// - スクロール量・可視領域・GeometryReader 計測に一切連動しない（ADR 0030 の再入禁止を構造で担保）。
@Suite
struct TranscriptWindowAcceptanceTests {

    @Test
    func defaultLimitAndExpandStepAreLoweredForFasterFirstPaint() {
        #expect(TranscriptWindow.defaultLimit == 50)
        #expect(TranscriptWindow.expandStep == 50)
    }

    @Test
    func visibleRange_withinLimit_showsAllWithoutHidden() {
        let window = TranscriptWindow()
        let range = window.visibleRange(totalCount: 50)
        #expect(range.startIndex == 0)
        #expect(range.hiddenCount == 0)
    }

    @Test
    func visibleRange_exceedingLimit_showsTailAndHidesRest() {
        let window = TranscriptWindow()
        let range = window.visibleRange(totalCount: 130)
        #expect(range.startIndex == 80)   // 130 - 50
        #expect(range.hiddenCount == 80)
    }

    @Test
    func expand_growsWindowByOneStep_monotonically() {
        var window = TranscriptWindow()
        window.expand()
        let range = window.visibleRange(totalCount: 130)
        #expect(range.startIndex == 30)   // 130 - (50 + 50)
        #expect(range.hiddenCount == 30)
    }

    @Test
    func reset_returnsToDefaultLimit() {
        var window = TranscriptWindow()
        window.expand()
        window.reset()
        #expect(window.visibleRange(totalCount: 130).startIndex == 80)  // 130 - 50 に戻る
    }

    @Test
    func visibleRange_zeroCount_isSafeAndNonNegative() {
        let window = TranscriptWindow()
        let range = window.visibleRange(totalCount: 0)
        #expect(range.startIndex == 0)
        #expect(range.hiddenCount == 0)
    }
}
