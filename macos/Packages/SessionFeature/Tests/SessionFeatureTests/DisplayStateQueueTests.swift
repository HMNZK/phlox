import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

// 本文の書き込みに失敗したあとは、本文より新しい表示状態だけを残さない。
private actor FailingUpsertStore: TranscriptStore {
    var failsUpsert = true
    private(set) var savedDisplayStates: [ChatDisplayState] = []

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { [] }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        if failsUpsert { throw CocoaError(.fileWriteNoPermission) }
    }
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
    func saveDisplayState(_ state: ChatDisplayState, for sessionID: SessionID) async throws {
        savedDisplayStates.append(state)
    }
    func recover() { failsUpsert = false }
}

@Test @MainActor
func displayStateIsSkippedAfterAFailedTranscriptWriteAndResumesAfterASuccess() async {
    let store = FailingUpsertStore()
    let queue = TranscriptPersistenceQueue(sessionID: SessionID(), store: store)
    let state = ChatDisplayState(turnUsageByItemID: [:], lastTurnCompletedAt: .now, subAgents: [])
    let item = ChatItem.agentMessage(id: "a", text: "x", timestamp: .now)

    queue.enqueueUpsert([item])
    queue.enqueueDisplayState(state)
    await queue.waitForPendingWrites()
    #expect(await store.savedDisplayStates.isEmpty)

    await store.recover()
    queue.enqueueUpsert([item])
    queue.enqueueDisplayState(state)
    await queue.waitForPendingWrites()
    #expect(await store.savedDisplayStates == [state])
}
