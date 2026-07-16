import AgentDomain
import Foundation

private struct ProjectsFile: Codable, Sendable {
    var schemaVersion: Int = 1
    var projects: [Project]
}

public actor JSONProjectStore: ProjectStoreProtocol {
    private let store: JSONFileStore<ProjectsFile>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL, category: "JSONProjectStore")
    }

    public func load() async -> [Project] {
        store.load()?.projects ?? []
    }

    public func save(_ projects: [Project]) async throws {
        try store.save(ProjectsFile(schemaVersion: 1, projects: projects))
    }
}
