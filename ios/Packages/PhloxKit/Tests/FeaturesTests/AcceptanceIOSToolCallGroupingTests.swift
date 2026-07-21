// 契約の正本: tasks/task-5.md — iOS チャットの連続ツールコール（.command）集約。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// Mac の ChatTranscriptGrouping（AcceptanceToolCallGroupingTests）と同一契約の iOS 版:
//   - 連続する2件以上の .command は1つの commandGroup（id = 先頭 message の id・順序保存）
//   - 単独の .command・他種 message は single
//   - .command 以外はグループ境界
//   - blocks の平坦化は入力と完全一致（欠落・重複・並べ替えなし）
//   - グループ末尾への追記で既存グループの id は変わらない（identity 安定）

import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String, _ command: String = "swift build") -> ChatMessage {
    .command(id: id, command: command, output: "output of \(command)")
}

private func agent(_ id: String, _ text: String = "done") -> ChatMessage {
    .agent(id: id, text: text)
}

private func flatten(_ blocks: [SessionDetailChatBlock]) -> [ChatMessage] {
    blocks.flatMap { block -> [ChatMessage] in
        switch block {
        case .single(let message): [message]
        case .commandGroup(_, let items): items
        }
    }
}

@Suite("Acceptance: iOS ツールコール集約（task-5）")
struct AcceptanceIOSToolCallGroupingTests {
    @Test func 連続する複数のコマンドは1つのグループになる() {
        let messages = [cmd("c1"), cmd("c2"), cmd("c3")]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)

        #expect(blocks.count == 1)
        guard case .commandGroup(let id, let grouped) = blocks[0] else {
            Issue.record("expected commandGroup, got \(blocks[0])")
            return
        }
        #expect(id == "c1")  // グループ id は先頭 message の id
        #expect(grouped == messages)  // 順序保存
    }

    @Test func 単独のコマンドはsingleのまま() {
        let messages = [agent("a1"), cmd("c1"), agent("a2")]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)

        #expect(blocks.count == 3)
        guard case .single(let message) = blocks[1] else {
            Issue.record("expected single, got \(blocks[1])")
            return
        }
        #expect(message.id == "c1")
    }

    @Test func 他種メッセージがグループ境界になる() {
        let messages = [agent("a1"), cmd("c1"), cmd("c2"), agent("a2"), cmd("c3")]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)

        #expect(blocks.count == 4)
        #expect(blocks.map(\.id) == ["a1", "c1", "a2", "c3"])
        guard case .commandGroup(_, let grouped) = blocks[1] else {
            Issue.record("expected commandGroup at index 1, got \(blocks[1])")
            return
        }
        #expect(grouped.map(\.id) == ["c1", "c2"])
        guard case .single = blocks[3] else {
            Issue.record("expected single at index 3, got \(blocks[3])")
            return
        }
    }

    @Test func 平坦化すると入力と完全一致する() {
        let messages = [
            agent("a1"), cmd("c1"), cmd("c2"), cmd("c3"),
            agent("a2"), cmd("c4"), agent("a3"),
        ]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)
        #expect(flatten(blocks) == messages)
    }

    @Test func 空入力は空のブロック列() {
        #expect(SessionDetailToolCallGrouping.blocks(from: []).isEmpty)
    }

    @Test func グループ末尾への追記で既存グループのidが変わらない() {
        let before = SessionDetailToolCallGrouping.blocks(from: [cmd("c1"), cmd("c2")])
        let after = SessionDetailToolCallGrouping.blocks(from: [cmd("c1"), cmd("c2"), cmd("c3")])

        #expect(before.count == 1)
        #expect(after.count == 1)
        #expect(before[0].id == after[0].id)  // ストリーミング追記で identity が揺れない
    }
}
