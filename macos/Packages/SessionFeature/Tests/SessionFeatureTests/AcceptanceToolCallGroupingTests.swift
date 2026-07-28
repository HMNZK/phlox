// 契約の正本: tasks/task-1.md（tool-call-collapse-threshold run）— 連続ツールコール（.commandExecution）の集約。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【契約変更の記録】旧契約（ADR 0096 / phlox-ux-5fixes task-3）は「連続する2件以上の
// .commandExecution を集約し、単独の .commandExecution は single のまま」だった。
// ユーザー要求「ツールコールの数と折りたたむ閾値は無関係にしてほしい」により
// **1件でも集約する** へ変更した。これはテストを弱める行為ではなく、要求由来の契約変更である
// （decision-log.md / docs/phase0.md SC1 参照）。この変更により macOS は iOS（ADR 0026）と
// 同じ契約に揃う。
//
// 現行契約:
//   - 連続する1件以上の .commandExecution は1つの commandGroup（id = 先頭 item の id・順序保存）
//   - .commandExecution 以外の item は single であり、グループ境界になる
//   - blocks の平坦化は入力と完全一致（欠落・重複・並べ替えなし）
//   - グループ末尾への追記で既存グループの id は変わらない（identity 安定）
//   - 単独コマンドのジャンプ先はそのコマンド自身の id（＝そのグループの先頭 item の id）

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

@Suite("Acceptance: ツールコール集約（1件でも集約）")
struct AcceptanceToolCallGroupingTests {
    @Test func 連続する複数のコマンドは1つのグループになる() {
        let items = [cmd("c1"), cmd("c2"), cmd("c3")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 1)
        guard case .commandGroup(let id, let grouped) = blocks[0] else {
            Issue.record("expected commandGroup, got \(blocks[0])")
            return
        }
        #expect(id == "c1")                              // id は先頭 item の id
        #expect(grouped.map(\.id) == ["c1", "c2", "c3"]) // 順序保存
    }

    @Test func 単独のコマンドも1件のグループになる() {
        let items = [agent("a1"), cmd("c1"), agent("a2")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 3)
        guard case .commandGroup(let id, let grouped) = blocks[1] else {
            Issue.record("expected commandGroup, got \(blocks[1])")
            return
        }
        #expect(id == "c1")
        #expect(grouped.map(\.id) == ["c1"])
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
        guard case .commandGroup(_, let trailing) = blocks[3] else {
            Issue.record("expected commandGroup at index 3, got \(blocks[3])")
            return
        }
        #expect(trailing.map(\.id) == ["c3"])
    }

    @Test func 他種itemはsingleのまま() {
        let items = [agent("a1"), .error(id: "e1", message: "boom", timestamp: t0)]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 2)
        for block in blocks {
            guard case .single = block else {
                Issue.record("expected single, got \(block)")
                return
            }
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

    @Test func 単独コマンドが2件目の追記でグループになってもidが変わらない() {
        let before = ChatTranscriptGrouping.blocks(from: [agent("a1"), cmd("c1")])
        let after = ChatTranscriptGrouping.blocks(from: [agent("a1"), cmd("c1"), cmd("c2")])

        #expect(before.count == 2)
        #expect(after.count == 2)
        #expect(before[1].id == "c1")
        #expect(after[1].id == "c1")
    }

    @Test func 単独コマンドのジャンプ先は自身のid() {
        let items = [agent("a1"), cmd("c1"), agent("a2")]
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "c1", in: items) == "c1")
    }

    @Test func グループ内コマンドのジャンプ先はグループ先頭のid() {
        let items = [agent("a1"), cmd("c1"), cmd("c2"), cmd("c3")]
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "c3", in: items) == "c1")
    }
}
