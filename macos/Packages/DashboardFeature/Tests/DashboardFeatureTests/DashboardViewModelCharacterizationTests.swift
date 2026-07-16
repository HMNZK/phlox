// DashboardViewModel 特性化テスト（Feathers / task-5）
// 現在の観測可能な振る舞いを固定する。既存テストが覆う領域は重複させない。

import AgentDomain
import Foundation
import PTYKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Helpers

@MainActor
private func characterizationDashboard(
    projects: [Project] = [],
    persistedSessions: [PersistedSessionDescriptor] = [],
    agentBinaryPaths: [AgentKind: String] = [:],
    workspaceDirectory: URL = URL(fileURLWithPath: "/tmp/phlox-char-dashboard-workspace")
) async throws -> DashboardViewModel {
    let projectStore = InMemoryProjectStore()
    if !projects.isEmpty {
        try await projectStore.save(projects)
    }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        projects: projectStore,
        sessions: InMemorySessionStore(persistedSessions),
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: agentBinaryPaths
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    return dashboard
}

@MainActor
private func characterizationDashboardWithProjectFolder() async throws -> (
    dashboard: DashboardViewModel,
    projectID: ProjectID,
    projectFolder: URL,
    workspaceRoot: URL
) {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    let projectFolder = workspaceRoot.appendingPathComponent("char-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let dashboard = try await characterizationDashboard(workspaceDirectory: workspaceRoot)
    let projectID = try #require(dashboard.addProject(name: "Char Project", directoryPath: projectFolder.path))
    return (dashboard, projectID, projectFolder, workspaceRoot)
}

// MARK: - Characterization tests

@Test @MainActor
func characterization_start_emptyStore_exposesBaselineDashboardState() async throws {
    let dashboard = try await characterizationDashboard()

    #expect(dashboard.sessions.isEmpty)
    #expect(dashboard.sessionNodes.isEmpty)
    #expect(dashboard.projects.isEmpty)
    #expect(dashboard.unseenCompletionCount == 0)
    #expect(dashboard.restoredSessionPresentation == nil)
    #expect(dashboard.gridSessionSelection == nil)
}

@Test @MainActor
func characterization_defaultProjectID_usesSelectedSessionProjectWhenAssigned() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let folderA = workspaceRoot.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceRoot.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let projectA = Project(
        name: "Project A",
        directoryPath: folderA.path,
        createdAt: Date(timeIntervalSince1970: 100),
        isManagedDirectory: false
    )
    let projectB = Project(
        name: "Project B",
        directoryPath: folderB.path,
        createdAt: Date(timeIntervalSince1970: 200),
        isManagedDirectory: false
    )

    let sessionInA = SessionID()
    let sessionInB = SessionID()
    let dashboard = try await characterizationDashboard(
        projects: [projectA, projectB],
        persistedSessions: [
            makePersistedSessionDescriptor(
                id: sessionInA,
                workingDirectory: folderA.path,
                projectID: projectA.id,
                startedAt: Date(timeIntervalSince1970: 1_000)
            ),
            makePersistedSessionDescriptor(
                id: sessionInB,
                workingDirectory: folderB.path,
                projectID: projectB.id,
                startedAt: Date(timeIntervalSince1970: 2_000)
            ),
        ],
        workspaceDirectory: workspaceRoot
    )

    #expect(dashboard.defaultProjectID(forSelectedSession: sessionInA) == projectA.id)
    #expect(dashboard.defaultProjectID(forSelectedSession: sessionInB) == projectB.id)
}

@Test @MainActor
func characterization_defaultProjectID_fallsBackToFirstProjectWhenSelectionUnassigned() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let folderA = workspaceRoot.appendingPathComponent("project-a", isDirectory: true)
    let unassignedFolder = workspaceRoot.appendingPathComponent("unassigned", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unassignedFolder, withIntermediateDirectories: true)

    let projectA = Project(
        name: "Project A",
        directoryPath: folderA.path,
        createdAt: Date(timeIntervalSince1970: 100),
        isManagedDirectory: false
    )

    let unassignedID = SessionID()
    let dashboard = try await characterizationDashboard(
        projects: [projectA],
        persistedSessions: [
            makePersistedSessionDescriptor(
                id: unassignedID,
                workingDirectory: unassignedFolder.path,
                projectID: nil,
                startedAt: Date(timeIntervalSince1970: 1_000)
            ),
        ],
        workspaceDirectory: workspaceRoot
    )

    #expect(dashboard.defaultProjectID(forSelectedSession: unassignedID) == projectA.id)
    #expect(dashboard.defaultProjectID(forSelectedSession: nil) == projectA.id)
}

@Test @MainActor
func characterization_defaultProjectID_returnsNilWhenNoProjectsExist() async throws {
    let dashboard = try await characterizationDashboard()

    #expect(dashboard.defaultProjectID(forSelectedSession: nil) == nil)
    #expect(dashboard.defaultProjectID(forSelectedSession: SessionID()) == nil)
}

@Test @MainActor
func characterization_spawnNewSessionUsingDefaultProject_throwsNoProjectWhenNoProjects() async throws {
    let dashboard = try await characterizationDashboard()

    await #expect(throws: AgentSpawnError.noProject) {
        try await dashboard.spawnNewSessionUsingDefaultProject(
            kind: .claudeCode,
            selectedSessionID: nil
        )
    }
}

@Test @MainActor
func characterization_spawnNewSessionUsingDefaultProject_spawnsInResolvedDefaultProject() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let anchorID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let spawnedID = try await dashboard.spawnNewSessionUsingDefaultProject(
        kind: .claudeCode,
        selectedSessionID: anchorID
    )

    let spawned = try #require(dashboard.sessionNode(id: spawnedID))
    #expect(spawned.projectID == projectID)
    #expect(spawned.agentRef.builtinKind == .claudeCode)
}

@Test @MainActor
func characterization_removeSession_unknownIDReturnsFalseWithoutMutation() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let existingID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let countBefore = dashboard.sessions.count

    let removed = await dashboard.removeSession(SessionID())

    #expect(removed == false)
    #expect(dashboard.sessions.count == countBefore)
    #expect(dashboard.sessionNode(id: existingID) != nil)
}

@Test @MainActor
func characterization_addProject_duplicateDirectoryReturnsNilAndKeepsSingleProject() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let projectFolder = workspaceRoot.appendingPathComponent("dup-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let dashboard = try await characterizationDashboard(workspaceDirectory: workspaceRoot)
    let firstID = try #require(dashboard.addProject(name: "First", directoryPath: projectFolder.path))
    let duplicateID = dashboard.addProject(name: "Duplicate", directoryPath: projectFolder.path)

    #expect(duplicateID == nil)
    #expect(dashboard.projects.count == 1)
    #expect(dashboard.projects.first?.id == firstID)
    #expect(dashboard.projects.first?.name == "First")
}

@Test @MainActor
func characterization_unassignedSessions_listsOnlyNilProjectBoundSessions() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let assignedID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let unassignedID = try await dashboard.spawnNewSession(kind: .claudeCode)

    #expect(dashboard.unassignedSessions.map(\.id) == [unassignedID])
    #expect(!dashboard.unassignedSessions.map(\.id).contains(assignedID))
}

@Test @MainActor
func characterization_sessionsIn_returnsOnlyMatchingProjectMembership() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let folderA = workspaceRoot.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceRoot.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let dashboard = try await characterizationDashboard(workspaceDirectory: workspaceRoot)
    let projectAID = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectBID = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))

    let sessionAID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectAID)
    let sessionBID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectBID)

    #expect(dashboard.sessions(in: projectAID).map(\.id) == [sessionAID])
    #expect(dashboard.sessions(in: projectBID).map(\.id) == [sessionBID])
}

@Test @MainActor
func characterization_isGridSessionSelected_nilSelectionTreatsAllVisibleAsSelected() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    #expect(dashboard.gridSessionSelection == nil)
    #expect(dashboard.isGridSessionSelected(firstID))
    #expect(dashboard.isGridSessionSelected(secondID))
}

@Test @MainActor
func characterization_isGridSessionSelected_explicitSubsetExcludesOthers() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    dashboard.gridSessionSelection = [firstID]

    #expect(dashboard.isGridSessionSelected(firstID))
    #expect(!dashboard.isGridSessionSelected(secondID))
}

@Test @MainActor
func characterization_availableAgentDescriptors_includesClaudeAndResolvedOptionals() {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()

    let envWithCodex = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )
    let dashboardWithCodex = DashboardViewModel(environment: envWithCodex)
    #expect(dashboardWithCodex.availableAgentDescriptors.map(\.ref) == [
        .builtin(.claudeCode),
        .builtin(.codex),
    ])

    let envEmpty = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboardEmpty = DashboardViewModel(environment: envEmpty)
    #expect(dashboardEmpty.availableAgentDescriptors.map(\.ref) == [.builtin(.claudeCode)])
}

@Test @MainActor
func characterization_sessionChatMessages_nilForPTYEmptyArrayForAppServer() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let projectFolder = workspaceRoot.appendingPathComponent("char-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        workspaceDirectory: workspaceRoot,
        appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let projectID = try #require(dashboard.addProject(name: "Char Project", directoryPath: projectFolder.path))

    let ptyID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, backend: .pty)
    let chatID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        backend: .appServer
    )

    #expect(dashboard.sessionChatMessages(for: ptyID) == nil)
    #expect(dashboard.sessionChatMessages(for: chatID) == [])
    #expect(dashboard.sessionChatMessages(for: SessionID()) == nil)
}

@Test @MainActor
func characterization_descendantCount_unknownRootReturnsZero() async throws {
    let (dashboard, projectID, _, workspaceRoot) = try await characterizationDashboardWithProjectFolder()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    #expect(dashboard.descendantCount(of: SessionID()) == 0)
}
