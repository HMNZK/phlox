import Foundation
import Testing
@testable import SessionFeature

@Suite struct RuntimeTranscriptWindowTests {
    @Test func semanticBlocksKeepTheExistingEightStageWeightBudgetAndScrollAnchor() {
        let blocks = (0..<1_000).map { number in
            SessionRuntimeChatReadBlock(id: "message-\(number)", ownerInputID: nil,
                content: .item(.inline(.agentMessage(id: "message-\(number)",
                    text: String(repeating: "あ", count: 100), timestamp: .distantPast))))
        }
        var window = TranscriptWindow()
        expandSevenTimes(&window, blocks: blocks)
        let before = window.slice(of: blocks)

        let anchor = window.loadEarlier(in: blocks)
        let after = window.slice(of: blocks)

        #expect(before.blocks.count == 148)
        #expect(after.blocks.count == 148)
        #expect(after.hiddenBlockCount < before.hiddenBlockCount)
        #expect(after.hiddenNewerBlockCount > 0)
        #expect(anchor.map { id in after.blocks.contains { $0.id == id } } == true)
    }

    @Test func semanticGridJumpKeepsItsTargetInsideTheBoundedWindow() {
        let blocks = (0..<1_000).map { number in
            SessionRuntimeChatReadBlock(id: "input-\(number)", ownerInputID: "input-\(number)",
                content: .item(.inline(.userMessage(id: "input-\(number)", text: "依頼", timestamp: .distantPast))))
        }
        var window = TranscriptWindow(context: .gridTile)

        let revealed = window.reveal(itemID: "input-17", in: blocks)
        let slice = window.slice(of: blocks)

        #expect(revealed)
        #expect(slice.blocks.contains { $0.id == "input-17" })
        #expect(slice.blocks.count <= 128)
        #expect(slice.hiddenNewerBlockCount > 0)
    }

    private func expandSevenTimes(_ window: inout TranscriptWindow, blocks: [SessionRuntimeChatReadBlock]) {
        for _ in 0..<7 { _ = window.loadEarlier(in: blocks) }
    }
}
