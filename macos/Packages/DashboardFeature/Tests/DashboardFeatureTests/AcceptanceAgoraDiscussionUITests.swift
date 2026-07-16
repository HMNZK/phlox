// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-5.md — アゴラ討論モード UI（表示範囲の2モード化・討論中ヘッダ）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

// MARK: - 表示範囲の2モード化（AgoraParticipantsPolicy 討論モード）

@Suite("AgoraParticipantsPolicy discussion mode acceptance (task-5)")
struct AcceptanceAgoraDiscussionParticipantsTests {
    @Test func 討論中は参加者集合のみを入力順で返し_階層は無視する() {
        let rootA = SessionID(), childA1 = SessionID(), grandA = SessionID()
        let rootB = SessionID()
        // 孫（grandA）でも討論参加者なら含める。集合が正であり階層は見ない。
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, childA1, grandA, rootB],
            parentByID: [childA1: rootA, grandA: childA1],
            discussionParticipants: [rootA, grandA]
        )
        #expect(result == [rootA, grandA])
    }

    @Test func 討論中は非参加者をルートでも除外する() {
        let rootA = SessionID(), rootB = SessionID(), childB = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, rootB, childB],
            parentByID: [childB: rootB],
            discussionParticipants: [rootB, childB]
        )
        #expect(result == [rootB, childB])
    }

    @Test func 討論中で参加者集合が空なら空を返す() {
        let rootA = SessionID(), childA = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, childA],
            parentByID: [childA: rootA],
            discussionParticipants: []
        )
        #expect(result.isEmpty)
    }

    @Test func 非討論_nil_は現行どおりルートと直接の子を返し孫を除外する() {
        let rootA = SessionID(), childA = SessionID(), grandA = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, childA, grandA],
            parentByID: [childA: rootA, grandA: childA],
            discussionParticipants: nil
        )
        #expect(result == [rootA, childA])
    }
}

// MARK: - 討論中ヘッダ（AgoraDiscussionHeaderView）

@Suite("AgoraDiscussionHeaderView acceptance (task-5)")
@MainActor
struct AcceptanceAgoraDiscussionHeaderTests {
    @Test func 発言カウンタは_n_slash_max_形式() {
        let view = AgoraDiscussionHeaderView(
            utteranceCount: 3,
            maxUtterances: 30,
            participants: [],
            onStop: {}
        )
        #expect(view.counterText == "3/30")
    }

    @Test func 参加者チップは役割があれば名前と役割の両方を含む() {
        let text = AgoraDiscussionHeaderView.chipText(name: "参加者A", role: "レビュアー")
        #expect(text.contains("参加者A"))
        #expect(text.contains("レビュアー"))
    }

    @Test func 参加者チップは役割が無ければ名前のみ() {
        #expect(AgoraDiscussionHeaderView.chipText(name: "参加者B", role: nil) == "参加者B")
        #expect(AgoraDiscussionHeaderView.chipText(name: "参加者B", role: "") == "参加者B")
    }
}
