// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — セレクトカード表示条件（R4）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Testing
@testable import DashboardFeature

@Test func acceptance_startArea_sessionSelected_showsSessionContent() {
    #expect(StartAreaPolicy.content(hasSelectedProject: true, hasSelectedSession: true) == .sessionContent)
    #expect(StartAreaPolicy.content(hasSelectedProject: false, hasSelectedSession: true) == .sessionContent)
}

@Test func acceptance_startArea_projectSelected_noSession_showsAgentStartCards() {
    #expect(StartAreaPolicy.content(hasSelectedProject: true, hasSelectedSession: false) == .agentStartCards)
}

@Test func acceptance_startArea_noProject_noSession_showsSelectProjectPlaceholder() {
    #expect(StartAreaPolicy.content(hasSelectedProject: false, hasSelectedSession: false) == .selectProjectPlaceholder)
}
