// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — 空状態エージェント選択カードのモデル。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import AgentDomain
import Testing
@testable import DashboardFeature

@Test func agentStartCards_preserveAvailableOrder() {
    let cards = AgentStartCardsModel.cards(available: [.claudeCode, .codex, .cursor])
    #expect(cards.map(\.kind) == [.claudeCode, .codex, .cursor])
}

@Test func agentStartCards_singleKind_producesSingleCard() {
    let cards = AgentStartCardsModel.cards(available: [.codex])
    #expect(cards.count == 1)
    #expect(cards.first?.id == .codex)
}

@Test func agentStartCards_emptyAvailable_returnsEmpty() {
    #expect(AgentStartCardsModel.cards(available: []).isEmpty)
}
