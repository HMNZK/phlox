// iOS チャットのツールコール（.command）集約。
//
// 契約:
//   - 連続する1件以上の .command は1つの commandGroup（id = 先頭 message の id・順序保存）。
//     1件でも集約する（macOS の ChatTranscriptGrouping は 2 件以上で集約＝意図的に異なる）。
//   - .command 以外の message は single であり、グループ境界になる
//   - blocks の平坦化は入力と完全一致（欠落・重複・並べ替えなし）
//   - グループ末尾への追記で既存グループの id は変わらない（identity 安定）
//   - 表示窓の境界は常にグループの先頭に置かれ、グループは部分化されない
//   - 空出力行フィルタ・見出し・展開行数上限は CommandGroupRowWindowTests が守る

import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String, _ command: String = "swift build") -> ChatMessage {
    .command(id: id, command: command, output: "output of \(command)")
}

private func commandWithOutput(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "command \(id)", output: output)
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

@Suite("iOS ツールコール集約")
struct ToolCallGroupingTests {
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

    @Test func window境界は常にグループの先頭に置かれる() {
        let messages = [
            agent("a1"),
            commandWithOutput("c1"),
            commandWithOutput("c2"),
            commandWithOutput("c3"),
            agent("a2"),
        ]

        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 2)

        #expect(slice.hiddenBlockCount == 1)
        #expect(slice.blocks.map(\.id) == ["c1", "a2"])
        guard case .commandGroup(let id, let grouped) = slice.blocks[0].content else {
            Issue.record("expected commandGroup")
            return
        }
        #expect(id == "c1")
        #expect(grouped.map(\.id) == ["c1", "c2", "c3"])
    }

    @Test func window展開前後で既存グループidentityが変わらない() {
        let messages = [
            agent("a1"),
            commandWithOutput("c1"),
            commandWithOutput("c2"),
            commandWithOutput("c3"),
            agent("a2"),
        ]

        let before = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 2)
        let after = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 3)

        #expect(before.blocks.first?.id == "c1")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func commandGroupはblockLimit1でも部分化されない() {
        let messages = [
            commandWithOutput("c1"),
            commandWithOutput("c2"),
            commandWithOutput("c3"),
        ]

        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 1)

        #expect(slice.hiddenBlockCount == 0)
        #expect(slice.blocks.first?.id == "c1")
        guard case .commandGroup(let id, let grouped) = slice.blocks[0].content else {
            Issue.record("expected a command group")
            return
        }
        #expect(id == "c1")
        #expect(grouped.map(\.id) == ["c1", "c2", "c3"])
    }

    @Test func 空出力の完了済みコマンドは展開行から除外する() {
        let items = [
            commandWithOutput("c1", output: "output"),
            commandWithOutput("c2", output: " \n\t "),
            commandWithOutput("c3", output: ""),
        ]

        let header = SessionDetailCommandGroupHeader(
            items: items,
            lastTranscriptID: "c3",
            isTurnRunning: false
        )
        let rows = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c3",
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(!header.isRunning)
        #expect(rows.rows.map(\.id) == ["c1"])
    }

    @Test func グループ内コマンドのジャンプ先は安定したグループidentityに解決する() {
        let messages = [
            agent("a1"),
            commandWithOutput("c1"),
            commandWithOutput("c2"),
            commandWithOutput("c3"),
        ]

        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "c2", in: messages) == "c1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "c3", in: messages) == "c1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "a1", in: messages) == "a1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "missing", in: messages) == "missing")
    }

    @Test func 全て空出力かつ非実行中ならグループカードを描画しない() {
        let items = [
            commandWithOutput("c1", output: ""),
            commandWithOutput("c2", output: " \n\t "),
        ]
        let header = SessionDetailCommandGroupHeader(
            items: items,
            lastTranscriptID: "c2",
            isTurnRunning: false
        )
        let rows = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c2",
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(rows.rows.isEmpty)
        #expect(!header.shouldRender)
    }

    @Test func 単独で空出力かつ非実行中でもコマンド行を残して描画する() {
        let items = [commandWithOutput("c1", output: "")]
        let header = SessionDetailCommandGroupHeader(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: false
        )
        let rows = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(rows.rows.map(\.id) == ["c1"])
        #expect(rows.rows.first?.command == "command c1")
        #expect(rows.rows.first?.output.isEmpty == true)
        #expect(header.shouldRender)
        #expect(!header.isRunning)
    }

    @Test func transcriptSliceはwindowとグループidentityを両立する() {
        let messages =
            (0..<100).map { agent("a\($0)", "a\($0)") } +
            (0..<400).map { commandWithOutput("c\($0)") }

        var window = TranscriptWindow()
        let before = SessionDetailTranscriptSlice(messages: messages, window: window)
        window.expand()
        let after = SessionDetailTranscriptSlice(messages: messages, window: window)

        #expect(after.hiddenCount < before.hiddenCount)
        #expect(before.visibleBlocks.count <= TranscriptWindow.defaultLimit)
        #expect(after.visibleBlocks.count <= TranscriptWindow.defaultLimit + TranscriptWindow.expandStep)
        #expect(before.visibleBlocks.last?.id == "c0")
        #expect(after.visibleBlocks.contains(where: { $0.id == before.visibleBlocks.last?.id }))
    }
}
