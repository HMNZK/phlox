// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — アゴラのフラットグループチャット（参加者選別＋時系列マージ）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

// MARK: - fixtures

private func msg(_ id: String, at t: TimeInterval?) -> TeamTimelineSourceMessage {
    TeamTimelineSourceMessage(
        id: id,
        timestamp: t.map { Date(timeIntervalSince1970: $0) },
        content: .terminalText(id)
    )
}

private func src(
    _ id: SessionID,
    parent: SessionID?,
    name: String,
    _ messages: [TeamTimelineSourceMessage]
) -> AgentTimelineSource {
    AgentTimelineSource(
        id: id,
        parentSessionID: parent,
        displayName: name,
        agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
        messages: messages
    )
}

// MARK: - 参加者選別（AgoraParticipantsPolicy）

@Suite("AgoraParticipantsPolicy acceptance (task-3)")
struct AcceptanceAgoraParticipantsTests {
    @Test func ルートと直接の子だけを入力順で返し_孫は除外する() {
        let rootA = SessionID(), childA1 = SessionID(), grandA = SessionID()
        let childA2 = SessionID(), rootB = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, childA1, grandA, childA2, rootB],
            parentByID: [childA1: rootA, grandA: childA1, childA2: rootA]
        )
        #expect(result == [rootA, childA1, childA2, rootB])
    }

    @Test func 全員ルートならそのまま返す() {
        let a = SessionID(), b = SessionID()
        let result = AgoraParticipantsPolicy.participants(orderedIDs: [a, b], parentByID: [:])
        #expect(result == [a, b])
    }

    @Test func 親が一覧外の未知IDでもルート扱いの親を持つ子として含める() {
        let root = SessionID(), orphan = SessionID(), unknownParent = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [root, orphan],
            parentByID: [orphan: unknownParent]
        )
        #expect(result == [root, orphan])
    }

    @Test func 循環親参照のノードは除外し停止する() {
        let root = SessionID(), a = SessionID(), b = SessionID()
        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [root, a, b],
            parentByID: [a: b, b: a]
        )
        #expect(result == [root])
    }

    @Test func 空入力は空を返す() {
        #expect(AgoraParticipantsPolicy.participants(orderedIDs: [], parentByID: [:]) == [])
    }
}

// MARK: - フラットマージ（AgoraTimelineBuilder）

@Suite("AgoraTimelineBuilder acceptance (task-3)")
struct AcceptanceAgoraTimelineBuilderTests {
    @Test func 参加者の発言だけをtimestamp昇順で1本に混ぜる() {
        let root = SessionID(), child = SessionID(), grand = SessionID()
        let items = AgoraTimelineBuilder.build(
            sources: [
                src(root, parent: nil, name: "main", [msg("a", at: 10), msg("c", at: 30)]),
                src(child, parent: root, name: "sub", [msg("b", at: 20)]),
                src(grand, parent: child, name: "worker", [msg("x", at: 15)]),
            ],
            participants: [root, child]
        )
        #expect(items.map(\.sourceMessageID) == ["a", "b", "c"])
        #expect(!items.contains { $0.sessionID == grand })
    }

    @Test func 参加者が空なら空を返す() {
        let root = SessionID()
        let items = AgoraTimelineBuilder.build(
            sources: [src(root, parent: nil, name: "main", [msg("a", at: 10)])],
            participants: []
        )
        #expect(items.isEmpty)
    }

    @Test func sourcesに無い参加者IDは無視する() {
        let root = SessionID(), ghost = SessionID()
        let items = AgoraTimelineBuilder.build(
            sources: [src(root, parent: nil, name: "main", [msg("a", at: 10)])],
            participants: [root, ghost]
        )
        #expect(items.map(\.sourceMessageID) == ["a"])
    }

    @Test func 同時刻はsources出現順で決定的に並ぶ() {
        let first = SessionID(), second = SessionID()
        let items = AgoraTimelineBuilder.build(
            sources: [
                src(first, parent: nil, name: "one", [msg("f", at: 10)]),
                src(second, parent: nil, name: "two", [msg("s", at: 10)]),
            ],
            participants: [first, second]
        )
        #expect(items.map(\.sourceMessageID) == ["f", "s"])
    }

    @Test func timestamp欠損はtimestamp持ちの後ろに回る() {
        let a = SessionID(), b = SessionID()
        let items = AgoraTimelineBuilder.build(
            sources: [
                src(a, parent: nil, name: "one", [msg("noTime", at: nil)]),
                src(b, parent: nil, name: "two", [msg("timed", at: 10)]),
            ],
            participants: [a, b]
        )
        #expect(items.map(\.sourceMessageID) == ["timed", "noTime"])
    }
}
