import Foundation
import AgentDomain
import MessageStore
import os

final class MockMessageStore: MessageStoreProtocol, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var recorded: [AgentMessage] = []
    }

    var recorded: [AgentMessage] {
        state.withLock { $0.recorded }
    }

    func record(_ message: AgentMessage) async {
        state.withLock { $0.recorded.append(message) }
    }

    func recent(limit: Int) async -> [AgentMessage] {
        state.withLock { state in
            if limit <= 0 { return [] }
            return Array(state.recorded.suffix(limit))
        }
    }

    func message(id: UUID) async -> AgentMessage? {
        state.withLock { state in
            state.recorded.first { $0.id == id }
        }
    }

    func thread(rootID: UUID) async -> [AgentMessage] {
        state.withLock { state in
            state.recorded
                .filter { $0.id == rootID || $0.inReplyTo == rootID }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }
}
