import Foundation
import Testing
@testable import SessionFeature

private extension ChatTranscriptSlice {
    var renderCostVisibleItemCount: Int {
        blocks.reduce(0) { count, block in
            switch block.content {
            case .single:
                return count + 1
            case .commandGroup(_, let items):
                return count + items.count
            }
        }
    }
}

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
    func thousandItemTranscript_groupedVisibleSliceContainsAtMostFiftyItems() {
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
        let range = window.visibleRange(totalCount: items.count)
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: range.startIndex)

        #expect(slice.hiddenItemCount == 950)
        #expect(slice.renderCostVisibleItemCount <= 50)
    }
}
