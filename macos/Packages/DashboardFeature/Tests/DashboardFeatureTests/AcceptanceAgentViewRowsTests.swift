// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — エージェントビュー行表示（R1/R2）と composer 宛先解決（R3）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

// MARK: - R1: ユーザー発言は右寄せ（発言者ヘッダなし）、エージェント発言は左（ヘッダあり）

@Test func acceptance_rowPolicy_userMessage_hidesSpeakerHeader() {
    let item = ChatItem.userMessage(id: "u1", text: "hi", timestamp: Date(), attachments: [])
    #expect(AgentChatRowPolicy.showsSpeakerHeader(for: .chatItem(item)) == false)
}

@Test func acceptance_rowPolicy_agentMessage_showsSpeakerHeader() {
    let item = ChatItem.agentMessage(id: "a1", text: "hello", timestamp: Date())
    #expect(AgentChatRowPolicy.showsSpeakerHeader(for: .chatItem(item)) == true)
}

@Test func acceptance_rowPolicy_terminalText_showsSpeakerHeader() {
    #expect(AgentChatRowPolicy.showsSpeakerHeader(for: .terminalText("$ ls")) == true)
}

// MARK: - R3: composer はツリーの根（メインセッション）宛て

@Test func acceptance_composerTarget_selectedLeaf_resolvesToRoot() {
    let root = SessionID()
    let mid = SessionID()
    let leaf = SessionID()
    let parents: [SessionID: SessionID?] = [root: nil, mid: root, leaf: mid]

    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: leaf, parentByID: parents) == root)
    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: mid, parentByID: parents) == root)
    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: root, parentByID: parents) == root)
}

@Test func acceptance_composerTarget_unknownOrNilSelection_returnsNil() {
    let root = SessionID()
    let parents: [SessionID: SessionID?] = [root: nil]

    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: nil, parentByID: parents) == nil)
    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: SessionID(), parentByID: parents) == nil)
}

@Test func acceptance_composerTarget_parentOutsideMap_treatsChildAsRoot() {
    let known = SessionID()
    let unknownParent = SessionID()
    let parents: [SessionID: SessionID?] = [known: unknownParent]

    // 親がマップ外（不可視・消滅済み）なら、辿れる最上位＝known を根とみなす
    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: known, parentByID: parents) == known)
}

@Test func acceptance_composerTarget_cycle_terminatesAndReturnsNonNil() {
    let a = SessionID()
    let b = SessionID()
    let parents: [SessionID: SessionID?] = [a: b, b: a]

    // 循環しても無限ループせず、非 nil を返して打ち切る
    #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: a, parentByID: parents) != nil)
}
