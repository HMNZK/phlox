// task-1 白箱テスト: プロジェクト選択と GUI spawn の backend 解決。

import AgentDomain
import Foundation
import PTYKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@MainActor
private func whiteboxDashboardWithTwoProjects() async throws -> (
    dashboard: DashboardViewModel,
    projectA: ProjectID,
    projectB: ProjectID,
    workspaceRoot: URL
) {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
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

    let projectStore = InMemoryProjectStore()
    try await projectStore.save([projectA, projectB])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        projects: projectStore,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    return (dashboard, projectA.id, projectB.id, workspaceRoot)
}

@Suite(.serialized)
struct StartAreaSelectionWhiteboxTests {
    @Test @MainActor
    func spawnUsesSelectedProjectNotFirstProject() async throws {
        let (dashboard, projectA, projectB, workspaceRoot) = try await whiteboxDashboardWithTwoProjects()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let spawnedID = try await dashboard.spawnNewSessionUsingDefaultProject(
            kind: .claudeCode,
            selectedSessionID: nil,
            selectedProjectID: projectB
        )

        let spawned = try #require(dashboard.sessionNode(id: spawnedID))
        #expect(spawned.projectID == projectB)
        #expect(spawned.projectID != projectA)
    }

    @Test @MainActor
    func defaultChatPreference_spawnsAppServerForStructuredChatAgent() async throws {
        let suite = "whitebox-chat-pref-\(UUID().uuidString)"
        setenv("PHLOX_DEFAULTS_SUITE", suite, 1)
        defer {
            unsetenv("PHLOX_DEFAULTS_SUITE")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let projectFolder = workspaceRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let project = Project(
            name: "Project",
            directoryPath: projectFolder.path,
            createdAt: Date(),
            isManagedDirectory: false
        )
        let projectStore = InMemoryProjectStore()
        try await projectStore.save([project])

        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            projects: projectStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"],
            appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let spawnedID = try await dashboard.spawnNewSessionUsingDefaultProject(
            kind: .claudeCode,
            selectedSessionID: nil,
            selectedProjectID: project.id
        )

        let spawned = try #require(dashboard.sessionNode(id: spawnedID))
        #expect(spawned.appServer != nil)
        #expect(ptyManager.spawnCalls.isEmpty)
    }

    @Test @MainActor
    func terminalPreference_spawnsPtyEvenForStructuredChatAgent() async throws {
        let suite = "whitebox-terminal-pref-\(UUID().uuidString)"
        setenv("PHLOX_DEFAULTS_SUITE", suite, 1)
        defer {
            unsetenv("PHLOX_DEFAULTS_SUITE")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(
            DefaultSessionBackendPreference.terminal.rawValue,
            forKey: DefaultSessionBackendPreference.storageKey
        )

        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let projectFolder = workspaceRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let project = Project(
            name: "Project",
            directoryPath: projectFolder.path,
            createdAt: Date(),
            isManagedDirectory: false
        )
        let projectStore = InMemoryProjectStore()
        try await projectStore.save([project])

        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            projects: projectStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let spawnedID = try await dashboard.spawnNewSessionUsingDefaultProject(
            kind: .claudeCode,
            selectedSessionID: nil,
            selectedProjectID: project.id
        )

        let spawned = try #require(dashboard.sessionNode(id: spawnedID))
        #expect(spawned.pty != nil)
        #expect(!ptyManager.spawnCalls.isEmpty)
    }
}

@Test
func startAreaPolicy_allQuadrants_matchContract() {
    #expect(StartAreaPolicy.content(hasSelectedProject: true, hasSelectedSession: true) == .sessionContent)
    #expect(StartAreaPolicy.content(hasSelectedProject: false, hasSelectedSession: true) == .sessionContent)
    #expect(StartAreaPolicy.content(hasSelectedProject: true, hasSelectedSession: false) == .agentStartCards)
    #expect(StartAreaPolicy.content(hasSelectedProject: false, hasSelectedSession: false) == .selectProjectPlaceholder)
}
