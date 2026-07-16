import Foundation
import AgentDomain

// Hidden secret: transcript writes are serialized through one FIFO Task chain.
@MainActor
final class TranscriptPersistenceQueue {
    private let sessionID: SessionID
    private let store: any TranscriptStore
    private var task: Task<Void, Never>?

    init(sessionID: SessionID, store: any TranscriptStore) {
        self.sessionID = sessionID
        self.store = store
    }

    func enqueueUpsert(_ items: [ChatItem]) {
        guard !items.isEmpty else { return }
        let sessionID = sessionID
        let store = store
        let previous = task
        task = Task {
            await previous?.value
            do {
                try await store.upsertTranscriptItems(items, for: sessionID)
            } catch {
                let message = "Phlox: transcript persistence failed for \(sessionID): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
    }

    func enqueueReplace(_ items: [ChatItem]) {
        let sessionID = sessionID
        let store = store
        let previous = task
        task = Task {
            await previous?.value
            do {
                try await store.replaceTranscript(for: sessionID, with: items)
            } catch {
                let message = "Phlox: transcript replace failed for \(sessionID): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
    }

    func waitForPendingWrites() async {
        await task?.value
        task = nil
    }
}
