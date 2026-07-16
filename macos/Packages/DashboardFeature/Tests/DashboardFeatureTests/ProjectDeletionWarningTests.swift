import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

// MARK: - projectDeletionDescendantCount

@Test @MainActor
func projectDeletionDescendantCount_includesCrossProjectChild() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeProjectDeletionTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectB = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))

    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB, from: parentID)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    #expect(dashboard.projectDeletionDescendantCount(of: projectA) == 1)
    #expect(dashboard.projectDeletionDescendantCount(of: projectB) == 0)
}

@Test @MainActor
func projectDeletionDescendantCount_isZeroWhenDescendantsStayInSameProject() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folder = workspaceURL.appendingPathComponent("solo-project", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeProjectDeletionTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Solo", directoryPath: folder.path))
    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, from: parentID)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    #expect(dashboard.projectDeletionDescendantCount(of: projectID) == 0)
}

@Test @MainActor
func projectDeletionDescendantCount_includesNestedCrossProjectGrandchild() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("nested-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("nested-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeProjectDeletionTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectB = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))

    let grandparentID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA, from: grandparentID)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB, from: parentID)
    try await waitUntil { ptyManager.spawnCalls.count == 3 }

    #expect(dashboard.projectDeletionDescendantCount(of: projectA) == 1)
}

@Test @MainActor
func projectDeletionDescendantCount_deduplicatesOverlappingSubtrees() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("dedupe-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("dedupe-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeProjectDeletionTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectB = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))

    let rootID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    let crossID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB, from: rootID)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB, from: crossID)
    try await waitUntil { ptyManager.spawnCalls.count == 3 }

    #expect(dashboard.projectDeletionDescendantCount(of: projectA) == 2)
}

// MARK: - ProjectDeletionDialogText

@Test
func projectDeletionDialogText_title_omitsCountWhenZero() {
    #expect(ProjectDeletionDialogText.title(descendantCount: 0) == "このプロジェクトを削除しますか?")
}

@Test
func projectDeletionDialogText_title_includesCountWhenPositive() {
    #expect(ProjectDeletionDialogText.title(descendantCount: 1) == "このプロジェクトの削除で子孫1件も削除されますか?")
    #expect(ProjectDeletionDialogText.title(descendantCount: 3) == "このプロジェクトの削除で子孫3件も削除されますか?")
}

@Test
func projectDeletionDialogText_message_omitsCountWhenZero() {
    #expect(
        ProjectDeletionDialogText.message(descendantCount: 0)
            == "配下のセッションはすべて停止されます。フォルダ自体は削除されません。"
    )
}

@Test
func projectDeletionDialogText_message_includesCountWhenPositive() {
    let message = ProjectDeletionDialogText.message(descendantCount: 2)
    #expect(message.contains("子孫セッション2件"))
    #expect(message.contains("この一覧に表示されていない子孫セッション"))
    #expect(message.contains("フォルダ自体は削除されません。"))
}

// MARK: - Helpers

actor InMemoryProjectStoreForDeletionTests: ProjectStoreProtocol {
    private var stored: [Project] = []

    func load() async -> [Project] {
        stored
    }

    func save(_ projects: [Project]) async throws {
        stored = projects
    }
}

@MainActor
private func makeProjectDeletionTestEnvironment(
    pty: any PTYManagerProtocol,
    hookStream: AsyncStream<(SessionID, HookEvent)>,
    workspaceDirectory: URL
) -> AppEnvironment {
    AppEnvironment(
        pty: pty,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: [:],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        projects: InMemoryProjectStoreForDeletionTests(),
        sessions: NoOpSessionStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
}
