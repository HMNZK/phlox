// 契約の正本: tasks/task-3.md — 連続ツールコール（.commandExecution）の集約。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止（ハーネス欠陥は PM 承認の上でのみ修理可）。
//
// 凍結 API:
//   enum ChatTranscriptBlock: Identifiable, Equatable { case single(ChatItem); case commandGroup(id: String, items: [ChatItem]) }
//   enum ChatTranscriptGrouping { static func blocks(from items: [ChatItem]) -> [ChatTranscriptBlock] }
// 契約:
//   - 連続する2件以上の .commandExecution は1つの commandGroup（id = 先頭 item の id・順序保存）
//   - 単独の .commandExecution・他種 item は single
//   - .commandExecution 以外はグループ境界
//   - blocks の平坦化は入力と完全一致（欠落・重複・並べ替えなし）
//   - グループ末尾への追記で既存グループの id は変わらない（identity 安定）

import Foundation
import Testing
@testable import SessionFeature

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func cmd(_ id: String, _ command: String = "swift build") -> ChatItem {
    .commandExecution(id: id, command: command, output: "output of \(command)", timestamp: t0)
}

private func agent(_ id: String, _ text: String = "done") -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: t0)
}

private func flatten(_ blocks: [ChatTranscriptBlock]) -> [ChatItem] {
    blocks.flatMap { block -> [ChatItem] in
        switch block {
        case .single(let item): [item]
        case .commandGroup(_, let items): items
        }
    }
}

@Suite("Acceptance: ツールコール集約（task-3）")
struct AcceptanceToolCallGroupingTests {
    @Test func 連続する複数のコマンドは1つのグループになる() {
        let items = [cmd("c1"), cmd("c2"), cmd("c3")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 1)
        guard case .commandGroup(let id, let grouped) = blocks[0] else {
            Issue.record("expected commandGroup, got \(blocks[0])")
            return
        }
        #expect(id == "c1")  // グループ id は先頭 item の id
        #expect(grouped == items)  // 順序保存
    }

    @Test func 単独のコマンドはsingleのまま() {
        let items = [agent("a1"), cmd("c1"), agent("a2")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 3)
        guard case .single(let item) = blocks[1] else {
            Issue.record("expected single, got \(blocks[1])")
            return
        }
        #expect(item.id == "c1")
    }

    @Test func 他種itemがグループ境界になる() {
        let items = [agent("a1"), cmd("c1"), cmd("c2"), agent("a2"), cmd("c3")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

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
        let items = [
            agent("a1"), cmd("c1"), cmd("c2"), cmd("c3"),
            agent("a2"), cmd("c4"), agent("a3"),
        ]
        let blocks = ChatTranscriptGrouping.blocks(from: items)
        #expect(flatten(blocks) == items)
    }

    @Test func 空入力は空のブロック列() {
        #expect(ChatTranscriptGrouping.blocks(from: []).isEmpty)
    }

    @Test func グループ末尾への追記で既存グループのidが変わらない() {
        let before = ChatTranscriptGrouping.blocks(from: [cmd("c1"), cmd("c2")])
        let after = ChatTranscriptGrouping.blocks(from: [cmd("c1"), cmd("c2"), cmd("c3")])

        #expect(before.count == 1)
        #expect(after.count == 1)
        #expect(before[0].id == after[0].id)  // ストリーミング追記で identity が揺れない
    }
}
