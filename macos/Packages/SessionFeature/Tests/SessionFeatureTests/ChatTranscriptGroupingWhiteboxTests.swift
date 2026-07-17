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

private extension ChatTranscriptSlice {
    var visibleItemCount: Int {
        blocks.reduce(0) { count, block in
            switch block.content {
            case .single:
                count + 1
            case .commandGroup(_, let items):
                count + items.count
            }
        }
    }
}

@Suite("ChatTranscriptGrouping white-box")
struct ChatTranscriptGroupingWhiteboxTests {
    @Test func グループ跨ぎでも一回の展開で以前の項目が増える() {
        let items =
            (0..<100).map { groupingAgent("a\($0)") } +
            (0..<400).map { groupingCommand("c\($0)") }

        var window = TranscriptWindow()
        let before = ChatTranscriptGrouping.visibleSlice(
            from: items,
            startingAt: window.visibleRange(totalCount: items.count).startIndex
        )

        window.expand()

        let after = ChatTranscriptGrouping.visibleSlice(
            from: items,
            startingAt: window.visibleRange(totalCount: items.count).startIndex
        )

        #expect(after.hiddenItemCount < before.hiddenItemCount)
        #expect(before.visibleItemCount <= TranscriptWindow.defaultLimit)
        #expect(after.visibleItemCount <= TranscriptWindow.defaultLimit + TranscriptWindow.expandStep)
        #expect(before.blocks.first?.id == "c0")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func window境界がグループ内部でも先頭identityを維持する() {
        let items = [
            groupingAgent("a1"),
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
            groupingAgent("a2"),
        ]

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: 2)

        #expect(slice.hiddenItemCount == 2)
        #expect(slice.blocks.map(\.id) == ["c1", "a2"])
        guard case .commandGroup(let id, let grouped) = slice.blocks[0].content else {
            Issue.record("expected commandGroup")
            return
        }
        #expect(id == "c2")
        #expect(grouped.map(\.id) == ["c2", "c3"])
    }

    @Test func window展開前後で既存グループidentityが変わらない() {
        let items = [
            groupingAgent("a1"),
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
            groupingAgent("a2"),
        ]

        let before = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: 3)
        let after = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: 0)

        #expect(before.blocks.first?.id == "c1")
        #expect(after.blocks.contains(where: { $0.id == before.blocks.first?.id }))
    }

    @Test func window内にグループ末尾1件だけでも表示identityを先頭に固定する() {
        let items = [
            groupingCommand("c1"),
            groupingCommand("c2"),
            groupingCommand("c3"),
        ]

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: 2)

        #expect(slice.hiddenItemCount == 2)
        #expect(slice.blocks.first?.id == "c1")
        guard case .single(let item) = slice.blocks[0].content else {
            Issue.record("expected a single-item partial block")
            return
        }
        #expect(item.id == "c3")
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
