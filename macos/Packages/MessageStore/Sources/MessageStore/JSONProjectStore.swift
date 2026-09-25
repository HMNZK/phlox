import AgentDomain
import Foundation

private struct ProjectsFile: Codable, Sendable {
    var schemaVersion: Int = 1
    var projects: [Project]

    init(schemaVersion: Int = 1, projects: [Project]) {
        self.schemaVersion = schemaVersion
        self.projects = projects
    }

    // 版番号の無いファイルは 1 とみなす（版番号しか違わないファイルを壊れた扱いで退避しない）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projects = try container.decode([Project].self, forKey: .projects)
    }
}

public actor JSONProjectStore: ProjectStoreProtocol {
    private let store: JSONFileStore<ProjectsFile>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL, category: "JSONProjectStore")
    }

    /// `load()` と同じ復号で読めるか。移行の前に確かめる（C-64）。
    public static func canRead(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(ProjectsFile.self, from: data)) != nil
    }

    public func load() async -> [Project] {
        store.load()?.projects ?? []
    }

    public func save(_ projects: [Project]) async throws {
        try store.save(ProjectsFile(schemaVersion: 1, projects: projects))
    }
}
