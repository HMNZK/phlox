import Foundation
import Testing
@testable import SessionFeature

private let blockWindowTestTime = Date(timeIntervalSince1970: 1_700_000_000)

private func blockWindowAgent(_ id: String) -> ChatItem {
    .agentMessage(id: id, text: id, timestamp: blockWindowTestTime)
}

private func blockWindowCommand(_ id: String) -> ChatItem {
    .commandExecution(id: id, command: id, output: "output", timestamp: blockWindowTestTime)
}

@Suite("ChatTranscript block window white-box")
struct ChatTranscriptBlockWindowWhiteboxTests {
    @Test func 列挙した入力表で可視ブロック数は窓の上限を超えない() {
        let limits = [TranscriptWindow.gridTileDefaultLimit, TranscriptWindow.defaultLimit]
        let leadingCounts = [0, 1, 49, 50, 51, 1000, 2000]
        let commandRunLengths = [0, 1, 2, 49, 50, 999]
        let trailingCounts = [0, 1]

        for limit in limits {
            for leadingCount in leadingCounts {
                for commandRunLength in commandRunLengths {
                    for trailingCount in trailingCounts {
                        let items =
                            (0..<leadingCount).map { blockWindowAgent("leading-\($0)") } +
                            (0..<commandRunLength).map { blockWindowCommand("command-\($0)") } +
                            (0..<trailingCount).map { blockWindowAgent("trailing-\($0)") }
                        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: limit)
                        let totalBlockCount = ChatTranscriptGrouping.blockCount(of: items)

                        #expect(slice.blocks.count <= limit)
                        #expect(slice.blocks.count == min(totalBlockCount, limit))
                        #expect(slice.hiddenBlockCount == max(0, totalBlockCount - limit))
                    }
                }
            }
        }
    }

    @Test func blockIndexは隠れたコマンドを含むブロックの位置を返す() {
        let items =
            (0..<60).map { blockWindowAgent("agent-\($0)") } +
            (0..<500).map { blockWindowCommand("command-\($0)") }

        #expect(ChatTranscriptGrouping.blockCount(of: items) == 61)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "agent-0", in: items) == 0)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "command-499", in: items) == 60)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "missing", in: items) == nil)
    }
}
