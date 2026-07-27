import Foundation
import Testing
@testable import SessionFeature

private let groupingTestTime = Date(timeIntervalSince1970: 1_700_000_000)

private func groupingCommand(_ id: String, output: String = "output") -> ChatItem {
    .commandExecution(id: id, command: "command \(id)", output: output, timestamp: groupingTestTime)
}

private func groupingAgent(_ id: String) -> ChatItem {
    .agentMessage(id: id, text: id, timestamp: groupingTestTime)
}

@Suite("ChatTranscriptGrouping white-box")
struct ChatTranscriptGroupingWhiteboxTests {
    @Test func グループ跨ぎでも一回の展開で以前のブロックが増える() {
        let items =
            (0..<100).map { groupingAgent("a\($0)") } +
            (0..<400).map { groupingCommand("c\($0)") }

        var window = TranscriptWindow()
        let before = ChatTranscriptGrouping.visibleSlice(
            from: items,
            blockLimit: window.limit
        )

        window.expand()

        let after = ChatTranscriptGrouping.visibleSlice(
            from: items,
            blockLimit: window.limit
        )

        #expect(after.hiddenBlockCount < before.hiddenBlockCount)
        #expect(before.blocks.count <= TranscriptWindow.defaultLimit)
        #expect(after.blocks.count <= TranscriptWindow.defaultLimit + TranscriptWindow.expandStep)
        #expect(before.blocks.first?.id == "a51")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func window境界はグループ内部を切らず先頭identityを維持する() {
        let items = [
            groupingAgent("a1"),
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
            groupingAgent("a2"),
        ]

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 2)

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
        let items = [
            groupingAgent("a1"),
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
            groupingAgent("a2"),
        ]

        let before = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 2)
        let after = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 5)

        #expect(before.blocks.first?.id == "c1")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func 単独コマンドも安定した先頭identityのグループになる() {
        let items = [
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
        ]

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 1)

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
        let items = [groupingCommand("c1"), groupingCommand("c2", output: "")]

        let presentation = CommandGroupPresentation(
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
            groupingCommand("c1", output: "output"),
            groupingCommand("c2", output: " \n\t "),
            groupingCommand("c3", output: ""),
        ]

        let presentation = CommandGroupPresentation(
            items: items,
            lastTranscriptID: "c3",
            isTurnRunning: false
        )

        #expect(!presentation.isRunning)
        #expect(presentation.rows.map(\.id) == ["c1"])
    }

    @Test func グループ内コマンドのジャンプ先は安定したグループidentityに解決する() {
        let items = [
            groupingAgent("a1"),
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
        ]

        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "c2", in: items) == "c1")
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "c3", in: items) == "c1")
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "a1", in: items) == "a1")
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "missing", in: items) == "missing")
    }

    @Test func 全て空出力かつ非実行中ならグループカードを描画しない() {
        let presentation = CommandGroupPresentation(
            items: [
                groupingCommand("c1", output: ""),
                groupingCommand("c2", output: " \n\t "),
            ],
            lastTranscriptID: "c2",
            isTurnRunning: false
        )

        #expect(presentation.rows.isEmpty)
        #expect(!presentation.shouldRender)
    }
}
