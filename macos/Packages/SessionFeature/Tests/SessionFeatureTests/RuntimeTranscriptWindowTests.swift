import Foundation
import AgentDomain
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

    @Test func aColdSemanticJumpStartsAtOneStageAndCanStillExpand() {
        let blocks = (0..<200).map { number in
            SessionRuntimeChatReadBlock(id: "message-\(number)", ownerInputID: nil,
                content: .item(.inline(.agentMessage(id: "message-\(number)",
                    text: String(repeating: "あ", count: 100), timestamp: .distantPast))))
        }
        var window = TranscriptWindow()
        expandSevenTimes(&window, blocks: blocks)

        let revealed = window.reveal(itemID: "message-70", in: blocks)
        let initial = window.slice(of: blocks)
        let anchor = window.loadEarlier(in: blocks)
        let expanded = window.slice(of: blocks)

        #expect(revealed)
        #expect(initial.blocks.count == 18)
        #expect(initial.blocks.first?.id == "message-70")
        #expect(initial.blocks.last?.id == "message-87")
        #expect(expanded.blocks.count > initial.blocks.count)
        #expect(anchor == "message-70")
        #expect(expanded.blocks.contains { $0.id == "message-70" })
    }

    @Test func theFirstSuccessfulJumpFrameAlreadyUsesItsColdWindow() {
        let fixture = pendingJumpFixture()
        var projection = fixture.0
        let window = fixture.1
        let pending = RuntimeChatPendingJump(itemID: "message-70", epoch: projection.epoch, intentToken: UUID())
        projection.appliedIntentToken = pending.intentToken

        let visible = pending.windowForRender(window, projection: projection).slice(of: fixture.2)

        #expect(visible.blocks.count == 18)
        #expect(visible.blocks.first?.id == "message-70")
        #expect(visible.blocks.last?.id == "message-87")
        #expect(window.slice(of: fixture.2).blocks.count == 50)
    }

    @Test func aFailedRepeatJumpDoesNotShrinkThePreviouslyCommittedPage() {
        let fixture = pendingJumpFixture()
        var projection = fixture.0
        let window = fixture.1
        let pending = RuntimeChatPendingJump(itemID: "message-70", epoch: projection.epoch, intentToken: UUID())
        projection.error = "本文の取得に失敗しました"

        let visible = pending.windowForRender(window, projection: projection).slice(of: fixture.2)

        #expect(visible.blocks.count == 50)
        #expect(visible.blocks.first?.id == "message-70")
        #expect(visible.blocks.last?.id == "message-119")
    }

    @Test func aPendingJumpFromAnOldEpochDoesNotPrepareTheNewExecutionWindow() {
        let fixture = pendingJumpFixture()
        var projection = fixture.0
        let window = fixture.1
        let pending = RuntimeChatPendingJump(itemID: "message-70", epoch: UUID(), intentToken: UUID())
        projection.appliedIntentToken = pending.intentToken

        let visible = pending.windowForRender(window, projection: projection).slice(of: fixture.2)

        #expect(visible.blocks.count == 50)
        #expect(visible.blocks.last?.id == "message-119")
    }

    @Test func aLaterJumpDoesNotUseThePreviousTargetsSuccessfulPage() {
        let fixture = pendingJumpFixture()
        var projection = fixture.0
        let window = fixture.1
        let pending = RuntimeChatPendingJump(itemID: "message-90", epoch: projection.epoch, intentToken: UUID())
        projection.appliedIntentToken = pending.intentToken

        let visible = pending.windowForRender(window, projection: projection).slice(of: fixture.2)

        #expect(visible.blocks.count == 50)
        #expect(visible.blocks.first?.id == "message-70")
        #expect(visible.blocks.last?.id == "message-119")
    }

    private func pendingJumpFixture() -> (RuntimeChatReadProjection, TranscriptWindow, [SessionRuntimeChatReadBlock]) {
        let blocks = (0..<200).map { number in
            SessionRuntimeChatReadBlock(id: "message-\(number)", ownerInputID: nil,
                content: .item(.inline(.agentMessage(id: "message-\(number)",
                    text: String(repeating: "あ", count: 100), timestamp: .distantPast))))
        }
        var window = TranscriptWindow()
        expandSevenTimes(&window, blocks: blocks)
        var projection = RuntimeChatReadProjection()
        projection.appliedIntentToken = UUID()
        var page = SessionRuntimeChatReadPage(sessionID: SessionID(), executionID: UUID(), transcriptRevision: 12,
            revision: 3, totalBlockCount: 200, startIndex: 70, blocks: Array(blocks[70..<120]),
            olderCursor: nil, newerCursor: nil, latestHeader: nil, turnUsageByItemID: [:])
        page.revealTarget = .init(inputID: nil, cardID: nil, rowID: nil, entryID: "message-70", itemID: "message-70")
        projection.page = page
        return (projection, window, page.blocks)
    }

    private func expandSevenTimes(_ window: inout TranscriptWindow, blocks: [SessionRuntimeChatReadBlock]) {
        for _ in 0..<7 { _ = window.loadEarlier(in: blocks) }
    }
}
