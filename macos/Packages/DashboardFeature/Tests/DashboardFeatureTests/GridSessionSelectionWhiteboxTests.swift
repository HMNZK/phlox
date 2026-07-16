import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Test
@MainActor
func gridSessionSelection_nilShowsAllFilteredNodes() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    #expect(dashboard.gridSessionSelection == nil)
    #expect(dashboard.filteredGridSessionNodes(projectID: nil).map(\.id) == [firstID, secondID])
}

@Test
@MainActor
func gridSessionSelection_selectionFiltersVisibleNodes() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    dashboard.gridSessionSelection = [firstID]
    #expect(dashboard.filteredGridSessionNodes(projectID: nil).map(\.id) == [firstID])
}

@Test
@MainActor
func gridSessionSelection_toggleFromNilExcludesSession() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    dashboard.toggleGridSessionSelection(firstID)
    #expect(dashboard.gridSessionSelection == [secondID])
    #expect(dashboard.filteredGridSessionNodes(projectID: nil).map(\.id) == [secondID])
}

@Test
@MainActor
func gridSessionSelection_spawnAddsToActiveSelection() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    dashboard.gridSessionSelection = [firstID]

    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    #expect(dashboard.gridSessionSelection == [firstID, secondID])
}

@Test
@MainActor
func gridSessionSelection_removePrunesUnknownIDs() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    dashboard.gridSessionSelection = [firstID, secondID]

    _ = await dashboard.removeSession(firstID)
    #expect(dashboard.gridSessionSelection == [secondID])
}

@Test
@MainActor
func gridSessionSelection_clearResetsToNil() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    dashboard.gridSessionSelection = [firstID]

    dashboard.clearGridSessionSelection()
    #expect(dashboard.gridSessionSelection == nil)
}

@Test
@MainActor
func gridSessionSelection_orchestrationSpawnDoesNotPolluteSelection() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
    let firstID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    _ = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    dashboard.gridSessionSelection = [firstID]

    _ = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        from: firstID,
        launchContext: .orchestration
    )

    let candidateIDs = Set(dashboard.gridSessionPickerCandidates().map(\.id))
    #expect(dashboard.gridSessionSelection!.isSubset(of: candidateIDs))
    #expect(dashboard.gridSessionSelection == [firstID])
}

@Test
@MainActor
func gridSessionSelection_filterChangeNormalizesSelection() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectAURL = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
    let projectBURL = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: projectAURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projectBURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectAID = try #require(dashboard.addProject(name: "Project A", directoryPath: projectAURL.path))
    let projectBID = try #require(dashboard.addProject(name: "Project B", directoryPath: projectBURL.path))
    let sessionAID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectAID)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectBID)

    dashboard.gridSessionFilterProjectID = projectAID
    dashboard.gridSessionSelection = [sessionAID]

    dashboard.gridSessionFilterProjectID = projectBID
    dashboard.normalizeGridSessionSelectionForFilterChange()

    #expect(dashboard.gridSessionSelection == nil)
}

@Test
@MainActor
func gridSessionSelection_spawnInOtherWorkspaceDoesNotAddToSelection() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectAURL = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
    let projectBURL = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: projectAURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projectBURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectAID = try #require(dashboard.addProject(name: "Project A", directoryPath: projectAURL.path))
    let projectBID = try #require(dashboard.addProject(name: "Project B", directoryPath: projectBURL.path))
    let sessionAID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectAID)

    dashboard.gridSessionFilterProjectID = projectAID
    dashboard.gridSessionSelection = [sessionAID]

    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectBID)

    #expect(dashboard.gridSessionSelection == [sessionAID])
}
