import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature

@Suite("Workspace collision wiring (task-1)")
struct WorkspaceCollisionWiringTests {
    @Test @MainActor
    func sessionExposesRawWorkspacePathWithoutChangingDisplayPath() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        ))
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(
            name: "Project",
            directoryPath: projectURL.path
        ))
        let sessionID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )
        let session = try #require(dashboard.sessions.first { $0.id == sessionID })

        #expect(session.rawWorkspacePath == projectURL.path)
        #expect(session.workspacePath == (projectURL.path as NSString).abbreviatingWithTildeInPath)
    }

    @Test @MainActor
    func dashboardBuildsActiveWorkspaceInputs() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        ))
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(
            name: "Shared",
            directoryPath: projectURL.path
        ))
        let firstID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )
        let secondID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )

        let workspaces = dashboard.workspaceSessionWorkspaces
        #expect(Set(workspaces.map(\.sessionID)) == Set([firstID, secondID]))
        #expect(workspaces.allSatisfy { $0.workingDirectory == projectURL.path && $0.isActive })
    }
}
