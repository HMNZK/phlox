import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Test
@MainActor
func workspaceSidebar_hasUnseenCompletionDetectsForestDescendant() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let parentID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    let childID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        from: parentID,
        launchContext: .orchestration
    )

    #expect(flattenSessionTreeIDs(dashboard.sessionForest(in: projectID)) == [parentID, childID])

    #expect(dashboard.hasUnseenCompletion(in: projectID) == false)

    let child = try #require(dashboard.sessions.first { $0.id == childID })
    child.hasUnseenCompletion = true

    #expect(dashboard.hasUnseenCompletion(in: projectID) == true)
}

@Test
@MainActor
func workspaceSidebar_hasUnseenCompletionIgnoresForestExternalNode() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let visibleID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    let hiddenID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .orchestration
    )

    #expect(flattenSessionTreeIDs(dashboard.sessionForest(in: projectID)) == [visibleID])

    let hidden = try #require(dashboard.sessions.first { $0.id == hiddenID })
    hidden.hasUnseenCompletion = true

    #expect(dashboard.hasUnseenCompletion(in: projectID) == false)
}

private func flattenSessionTreeIDs(_ nodes: [SessionTreeNode]) -> [SessionID] {
    nodes.flatMap { [$0.id] + flattenSessionTreeIDs($0.children) }
}

@Test
func workspaceSidebar_relativeTimeRoundsDownAtLargeBoundaries() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(364 * 86_400)) == "12か月")
    #expect(SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(729 * 86_400)) == "1年")
    #expect(SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(730 * 86_400)) == "2年")
}
