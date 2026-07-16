import AgentDomain
import Foundation

private struct SessionsFile: Codable, Sendable {
    var schemaVersion: Int = 1
    var sessions: [PersistedSessionDescriptor]
}

public actor JSONSessionStore: SessionStoreProtocol {
    private let store: JSONFileStore<SessionsFile>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL, category: "JSONSessionStore")
    }

    public func load() async -> [PersistedSessionDescriptor] {
        store.load()?.sessions ?? []
    }

    public func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        try store.save(SessionsFile(schemaVersion: 1, sessions: sessions))
    }
}
