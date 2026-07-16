// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — 「履歴から再開」カードとフローティング composer の非重なり。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Testing
import CoreGraphics
@testable import SessionFeature

@Suite("ChatHistoryStartLayout acceptance (task-1)")
struct AcceptanceChatHistoryLayoutTests {
    // maxCardHeight = clamp(availableHeight − composerHeight − 56, 120...360)

    @Test func 大きいウィンドウでは現行上限360を維持する() {
        #expect(ChatHistoryStartLayout.maxCardHeight(availableHeight: 800, composerHeight: 120) == 360)
    }

    @Test func 小さいウィンドウではcomposerと外側余白を除いた残りに縮む() {
        // 400 − 120 − 56 = 224
        #expect(ChatHistoryStartLayout.maxCardHeight(availableHeight: 400, composerHeight: 120) == 224)
    }

    @Test func 極小ウィンドウでも操作可能な下限120を割らない() {
        #expect(ChatHistoryStartLayout.maxCardHeight(availableHeight: 200, composerHeight: 160) == 120)
    }

    @Test func 境界_残りがちょうど360なら360() {
        // 536 − 120 − 56 = 360
        #expect(ChatHistoryStartLayout.maxCardHeight(availableHeight: 536, composerHeight: 120) == 360)
    }

    // bottomInset = composerHeight（カードのセンタリング領域を composer の上に制限）

    @Test func 下側インセットはcomposer実測高に一致する() {
        #expect(ChatHistoryStartLayout.bottomInset(composerHeight: 120) == 120)
    }

    @Test func composer非表示時はインセットゼロ() {
        #expect(ChatHistoryStartLayout.bottomInset(composerHeight: 0) == 0)
    }
}
