import Foundation
import Testing
@testable import AgentDomain

private func makeProject(
    id: ProjectID = ProjectID(),
    name: String = "My Workspace",
    directoryPath: String = "/tmp/agent-dashboard-workspace",
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    isManagedDirectory: Bool = false
) -> Project {
    Project(
        id: id,
        name: name,
        directoryPath: directoryPath,
        createdAt: createdAt,
        isManagedDirectory: isManagedDirectory
    )
}

@Test func project_codableRoundTrip() throws {
    let original = makeProject(
        id: ProjectID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!),
        name: "Codable Test",
        directoryPath: "/Users/test/project",
        isManagedDirectory: true
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Project.self, from: data)

    #expect(decoded == original)
}

@Test func project_directoryURLDerivedFromPath() {
    let path = "/var/tmp/workspace-folder"
    let project = makeProject(directoryPath: path)

    #expect(project.directoryURL == URL(fileURLWithPath: path, isDirectory: true))
    #expect(project.directoryURL.isFileURL)
}

@Test func projectID_codableRoundTrip() throws {
    let id = ProjectID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)

    let data = try JSONEncoder().encode(id)
    let decoded = try JSONDecoder().decode(ProjectID.self, from: data)

    #expect(decoded == id)
    #expect(decoded.description == id.rawValue.uuidString)
}
