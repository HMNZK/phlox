import AgentDomain
import Foundation

public struct NoOpSessionStore: SessionStoreProtocol {
    public init() {}

    public func load() async -> [PersistedSessionDescriptor] {
        []
    }

    public func save(_ sessions: [PersistedSessionDescriptor]) async throws {}
}
