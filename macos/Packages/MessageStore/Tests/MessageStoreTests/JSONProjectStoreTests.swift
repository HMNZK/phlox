import AgentDomain
import Foundation
import Testing
@testable import MessageStore

private struct ProjectsFileEnvelope: Decodable {
    let schemaVersion: Int
    let projects: [Project]
}

private func temporaryProjectsFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MessageStoreTests-\(UUID().uuidString).json")
}

private func removeProjectsFile(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove test projects file \(url.path): \(error)")
    }
}

private func quarantinedFiles(for url: URL) -> [URL] {
    let directory = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + ".corrupt-"
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )) ?? []
    return contents.filter { $0.lastPathComponent.hasPrefix(prefix) }
}

private func removeQuarantinedFiles(for url: URL) {
    for fileURL in quarantinedFiles(for: url) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private func makeProject(
    name: String = "Test Workspace",
    directoryPath: String = "/tmp/test-workspace"
) -> Project {
    Project(
        name: name,
        directoryPath: directoryPath,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        isManagedDirectory: false
    )
}

@Test func saveAndLoad_roundTrip() async throws {
    let url = temporaryProjectsFileURL()
    defer { removeProjectsFile(at: url) }

    let store = JSONProjectStore(fileURL: url)
    let projects = [
        makeProject(name: "Alpha", directoryPath: "/tmp/alpha"),
        makeProject(name: "Beta", directoryPath: "/tmp/beta"),
    ]

    try await store.save(projects)
    let loaded = await store.load()

    #expect(loaded == projects)
}

@Test func load_missingFileReturnsEmpty() async {
    let url = temporaryProjectsFileURL()
    defer { removeProjectsFile(at: url) }

    let store = JSONProjectStore(fileURL: url)
    let loaded = await store.load()

    #expect(loaded.isEmpty)
}

@Test func load_invalidJSONReturnsEmpty() async throws {
    let url = temporaryProjectsFileURL()
    defer { removeProjectsFile(at: url) }
    defer { removeQuarantinedFiles(for: url) }

    try "{ not valid json }".data(using: .utf8)!.write(to: url, options: .atomic)

    let store = JSONProjectStore(fileURL: url)
    let loaded = await store.load()

    #expect(loaded.isEmpty)
}

@Test func load_corruptFileIsQuarantinedBeforeReturningEmpty() async throws {
    let url = temporaryProjectsFileURL()
    defer { removeProjectsFile(at: url) }
    defer { removeQuarantinedFiles(for: url) }

    let corruptData = try #require("{ not valid json }".data(using: .utf8))
    try corruptData.write(to: url, options: .atomic)

    let store = JSONProjectStore(fileURL: url)
    let loaded = await store.load()

    // 破損ファイルは退避され、次の save が破損データを上書きできないようにする
    #expect(loaded.isEmpty)
    let quarantined = quarantinedFiles(for: url)
    #expect(quarantined.count == 1)
    let preserved = try Data(contentsOf: try #require(quarantined.first))
    #expect(preserved == corruptData)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func save_writesSchemaVersionWrapper() async throws {
    let url = temporaryProjectsFileURL()
    defer { removeProjectsFile(at: url) }

    let store = JSONProjectStore(fileURL: url)
    let projects = [makeProject()]

    try await store.save(projects)

    let data = try Data(contentsOf: url)
    let envelope = try JSONDecoder().decode(ProjectsFileEnvelope.self, from: data)

    #expect(envelope.schemaVersion == 1)
    #expect(envelope.projects == projects)
}
