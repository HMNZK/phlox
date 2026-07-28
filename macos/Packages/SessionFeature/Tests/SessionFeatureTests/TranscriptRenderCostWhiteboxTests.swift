import Foundation
import Testing
@testable import SessionFeature

@Suite("Transcript render cost white-box")
struct TranscriptRenderCostWhiteboxTests {
    @Test
    func thousandItemTranscript_initialEagerRenderIsBoundedToFiftyItems() {
        let totalCount = 1000
        let window = TranscriptWindow(context: .single)
        let range = window.visibleRange(totalCount: totalCount)
        let visibleCount = totalCount - range.startIndex

        #expect(range.startIndex == 950)
        #expect(visibleCount <= 50)
        #expect(visibleCount * 4 <= 200)
    }

    @Test
    func thousandCommandTranscript_groupedVisibleSliceContainsAtMostFiftyBlocks() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<1000).map { index in
            ChatItem.commandExecution(
                id: "command-\(index)",
                command: "command \(index)",
                output: "output",
                timestamp: timestamp
            )
        }
        let window = TranscriptWindow(context: .single)
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: window.limit)

        #expect(slice.hiddenBlockCount == 0)
        #expect(slice.blocks.count <= TranscriptWindow.defaultLimit)
        #expect(slice.blocks.count == 1)
    }

    /// 上のケースは 1000 件すべてがコマンドで 1 ブロックに畳まれるため上限アサーションが自明に真になる。
    /// レンダコスト上限の正本ファイルとして、隠れ域が実際に発生し上限が binding になるケースも固定する。
    @Test
    func thousandBlockTranscript_visibleBlocksAreBoundedAndRemainderIsHidden() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<1000).map { index in
            ChatItem.agentMessage(id: "agent-\(index)", text: "text \(index)", timestamp: timestamp)
        }
        let window = TranscriptWindow(context: .single)
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: window.limit)

        #expect(ChatTranscriptGrouping.blockCount(of: items) == 1000)
        #expect(slice.blocks.count == TranscriptWindow.defaultLimit)  // 上限に張り付く＝binding
        #expect(slice.hiddenBlockCount == 950)
        #expect(slice.blocks.last?.id == "agent-999")                 // 末尾を含み続ける
    }
}
