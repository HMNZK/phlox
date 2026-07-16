// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — エージェント選択カード列の並び方向ポリシー。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import DesignSystem
@testable import DashboardFeature

// 定数の凍結: カード外形最小幅はビュー実装（minWidth 148 + 内側 padding m ×2）と一致
@Test func agentStartCardsLayout_constants_matchCardVisuals() {
    #expect(AgentStartCardsLayoutPolicy.cardMinOuterWidth == 148 + DSSpacing.m * 2)
    #expect(AgentStartCardsLayoutPolicy.interCardSpacing == DSSpacing.m)
    #expect(AgentStartCardsLayoutPolicy.containerHorizontalPadding == DSSpacing.l)
}

// 必要幅 = n×カード外形幅 + (n-1)×間隔 + 左右 padding
@Test func agentStartCardsLayout_requiredWidth_isLinearInCardCount() {
    let c = AgentStartCardsLayoutPolicy.cardMinOuterWidth
    let s = AgentStartCardsLayoutPolicy.interCardSpacing
    let p = AgentStartCardsLayoutPolicy.containerHorizontalPadding
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 1) == c + p * 2)
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3) == c * 3 + s * 2 + p * 2)
}

// 丁度収まる幅では横並びのまま
@Test func agentStartCardsLayout_exactFit_staysHorizontal() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need, cardCount: 3) == false)
}

// 1pt でも足りなければ縦積み
@Test func agentStartCardsLayout_oneShort_stacksVertically() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need - 1, cardCount: 3) == true)
}

// カード1枚以下は縦積みしない（横=縦で同義のため常に横並び扱い）
@Test func agentStartCardsLayout_singleOrNoCard_neverStacks() {
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: 0, cardCount: 1) == false)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: -10, cardCount: 0) == false)
}

// 幅ゼロで複数枚なら縦積み
@Test func agentStartCardsLayout_zeroWidth_stacks() {
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: 0, cardCount: 2) == true)
}
