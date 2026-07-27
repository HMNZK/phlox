import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "command \(id)", output: output)
}

private func agent(_ id: String) -> ChatMessage {
    .agent(id: id, text: id)
}

@Suite("SessionDetailToolCallGrouping white-box")
struct IOSToolCallGroupingWhiteboxTests {
    @Test func window境界は常にグループの先頭に置かれる() {
        let messages = [
            agent("a1"),
            cmd("c1"),
            cmd("c2"),
            cmd("c3"),
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
            cmd("c1"),
            cmd("c2"),
            cmd("c3"),
            agent("a2"),
        ]

        let before = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 2)
        let after = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 3)

        #expect(before.blocks.first?.id == "c1")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func commandGroupはblockLimit1でも部分化されない() {
        let messages = [
            cmd("c1"),
            cmd("c2"),
            cmd("c3"),
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

    @Test func 集約カードは件数見出しと末尾コマンドの実行中状態を持つ() {
        let items = [cmd("c1"), cmd("c2", output: "")]

        let presentation = SessionDetailCommandGroupPresentation(
            items: items,
            lastTranscriptID: "c2",
            isTurnRunning: true
        )

        #expect(presentation.title == "ツール実行 ×2")
        #expect(presentation.isRunning)
        #expect(presentation.rows.map(\.id) == ["c1", "c2"])
        #expect(presentation.rows.map(\.isRunning) == [false, true])
    }

    @Test func 空出力の完了済みコマンドは展開行から除外する() {
        let items = [
            cmd("c1", output: "output"),
            cmd("c2", output: " \n\t "),
            cmd("c3", output: ""),
        ]

        let presentation = SessionDetailCommandGroupPresentation(
            items: items,
            lastTranscriptID: "c3",
            isTurnRunning: false
        )

        #expect(!presentation.isRunning)
        #expect(presentation.rows.map(\.id) == ["c1"])
    }

    @Test func グループ内コマンドのジャンプ先は安定したグループidentityに解決する() {
        let messages = [
            agent("a1"),
            cmd("c1"),
            cmd("c2"),
            cmd("c3"),
        ]

        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "c2", in: messages) == "c1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "c3", in: messages) == "c1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "a1", in: messages) == "a1")
        #expect(SessionDetailToolCallGrouping.scrollTargetID(containing: "missing", in: messages) == "missing")
    }

    @Test func 全て空出力かつ非実行中ならグループカードを描画しない() {
        let presentation = SessionDetailCommandGroupPresentation(
            items: [
                cmd("c1", output: ""),
                cmd("c2", output: " \n\t "),
            ],
            lastTranscriptID: "c2",
            isTurnRunning: false
        )

        #expect(presentation.rows.isEmpty)
        #expect(!presentation.shouldRender)
    }

    @Test func 単独で空出力かつ非実行中でもコマンド行を残して描画する() {
        let presentation = SessionDetailCommandGroupPresentation(
            items: [cmd("c1", output: "")],
            lastTranscriptID: "c1",
            isTurnRunning: false
        )

        #expect(presentation.rows.map(\.id) == ["c1"])
        #expect(presentation.rows.first?.command == "command c1")
        #expect(presentation.rows.first?.output.isEmpty == true)
        #expect(presentation.shouldRender)
    }

    @Test func transcriptSliceはwindowとグループidentityを両立する() {
        let messages =
            (0..<100).map { agent("a\($0)") } +
            (0..<400).map { cmd("c\($0)") }

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
