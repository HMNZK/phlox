// 契約の正本: tasks/task-1.md（ios-single-toolcall-row run）— iOS チャットのツールコール（.command）集約。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【契約変更の記録】旧契約（phlox-ux-5fixes task-5）は「連続する2件以上の .command を集約し、
// 単独の .command は single のまま」だった。ユーザー要求により **1件でも集約する** へ変更した。
// これはテストを弱める行為ではなく、要求由来の契約変更である（decision-log.md 参照）。
// この変更により iOS は macOS の ChatTranscriptGrouping（2件以上で集約）と**意図的に異なる**契約になる。
//
// 現行契約:
//   - 連続する1件以上の .command は1つの commandGroup（id = 先頭 message の id・順序保存）
//   - .command 以外の message は single であり、グループ境界になる
//   - blocks の平坦化は入力と完全一致（欠落・重複・並べ替えなし）
//   - グループ末尾への追記で既存グループの id は変わらない（identity 安定）
//   - 見出しは "ツール実行 ×\(件数)"。単独コマンドは "ツール実行 ×1"
//   - 単独コマンドは出力が空でもヘッダを描画する（可視性の後退を防ぐ）
//   - 2件以上で全件空出力かつ非実行中なら描画しない（従来ルールの維持）

import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String, _ command: String = "swift build") -> ChatMessage {
    .command(id: id, command: command, output: "output of \(command)")
}

private func emptyCmd(_ id: String, _ command: String = "swift build") -> ChatMessage {
    .command(id: id, command: command, output: "")
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

@Suite("Acceptance: iOS ツールコール集約（task-1 / 1件でも集約）")
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

    @Test func 単独のコマンドも1件のグループになる() {
        let messages = [agent("a1"), cmd("c1"), agent("a2")]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)

        #expect(blocks.count == 3)
        #expect(blocks.map(\.id) == ["a1", "c1", "a2"])
        guard case .commandGroup(let id, let grouped) = blocks[1] else {
            Issue.record("expected commandGroup, got \(blocks[1])")
            return
        }
        #expect(id == "c1")
        #expect(grouped.map(\.id) == ["c1"])
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
        guard case .commandGroup(let tailID, let tailItems) = blocks[3] else {
            Issue.record("expected commandGroup at index 3, got \(blocks[3])")
            return
        }
        #expect(tailID == "c3")
        #expect(tailItems.map(\.id) == ["c3"])
    }

    @Test func 他種メッセージはsingleのまま() {
        let messages = [agent("a1"), .error(id: "e1", message: "boom")]
        let blocks = SessionDetailToolCallGrouping.blocks(from: messages)

        #expect(blocks.count == 2)
        for block in blocks {
            guard case .single = block else {
                Issue.record("expected single, got \(block)")
                return
            }
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

    @Test func 単独コマンドが1件のグループになっても既存グループのidは変わらない() {
        let before = SessionDetailToolCallGrouping.blocks(from: [cmd("c1")])
        let after = SessionDetailToolCallGrouping.blocks(from: [cmd("c1"), cmd("c2")])

        #expect(before.count == 1)
        #expect(after.count == 1)
        #expect(before[0].id == "c1")
        #expect(before[0].id == after[0].id)  // 1件→2件の遷移で identity が揺れない
    }

    @Test func 単独コマンドのジャンプ先は自分自身のグループidに解決する() {
        let messages = [agent("a1"), cmd("c1"), agent("a2")]

        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "c1", in: messages) == "c1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "a2", in: messages) == "a2")
    }

    @Test func 単独コマンドの見出しは件数1つきの集約ヘッダになる() {
        let presentation = SessionDetailCommandGroupPresentation(
            items: [cmd("c1")],
            lastTranscriptID: "c1",
            isTurnRunning: false
        )

        #expect(presentation.title == "ツール実行 ×1")
        #expect(presentation.shouldRender)
        #expect(presentation.rows.map(\.id) == ["c1"])
    }

    @Test func 単独コマンドは出力が空でもヘッダを描画する() {
        let presentation = SessionDetailCommandGroupPresentation(
            items: [emptyCmd("c1")],
            lastTranscriptID: "c1",
            isTurnRunning: false
        )

        #expect(!presentation.isRunning)
        #expect(presentation.rows.isEmpty)  // 展開しても出力は無い
        #expect(presentation.shouldRender)  // それでも1行ヘッダは消えない（可視性の後退防止）
    }

    @Test func 複数件で全て空出力かつ非実行中なら従来どおり描画しない() {
        let presentation = SessionDetailCommandGroupPresentation(
            items: [emptyCmd("c1"), emptyCmd("c2")],
            lastTranscriptID: "c2",
            isTurnRunning: false
        )

        #expect(presentation.rows.isEmpty)
        #expect(!presentation.shouldRender)  // 2件以上の既存ルールは変更しない
    }
}
