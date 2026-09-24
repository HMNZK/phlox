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

/// サイドバーに出ない内部セッション（orchestration）も削除されるので、同じプロジェクトの分として数え、「ほかのプロジェクト」に混ぜない。
@Test @MainActor
func projectDeletionDescendantCount_treatsHiddenChildInSameProjectAsOwn() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let folderA = workspaceURL.appendingPathComponent("hidden-a", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeProjectDeletionTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let rootID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA, from: rootID, launchContext: .orchestration)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    #expect(dashboard.projectDeletionDescendantCount(of: projectA) == 0)
    #expect(dashboard.gridSessionNodes(in: projectA).count == 2)
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

// MARK: - ProjectDeletionDialogText（09 D4 / 03 F8 の文言）

@Test
func projectDeletionDialogText_title_namesTheProject() {
    #expect(ProjectDeletionDialogText.title(projectName: "phlox-core") == "プロジェクト「phlox-core」を削除しますか?")
}

@Test
func projectDeletionDialogText_message_countsSessionsAndChildren() {
    #expect(
        ProjectDeletionDialogText.message(sessionCount: 6, childCount: 2)
            == "このプロジェクトのセッション 6 件（子セッション 2 件を含む）を停止し、一覧から外します。会話は元に戻せません。"
    )
    #expect(
        ProjectDeletionDialogText.message(sessionCount: 3, childCount: 0)
            == "このプロジェクトのセッション 3 件を停止し、一覧から外します。会話は元に戻せません。"
    )
    #expect(ProjectDeletionDialogText.message(sessionCount: 0, childCount: 0) == "このプロジェクトを一覧から外します。")
}

/// ほかのプロジェクトにある子孫も一緒に消えるので、「このプロジェクトのセッション」に混ぜずに分けて書く。
@Test
func projectDeletionDialogText_message_namesChildrenInOtherProjects() {
    #expect(
        ProjectDeletionDialogText.message(sessionCount: 4, childCount: 1, otherProjectChildCount: 2)
            == "このプロジェクトのセッション 4 件（子セッション 1 件を含む）と、ほかのプロジェクトにある子セッション 2 件を停止し、一覧から外します。会話は元に戻せません。"
    )
    #expect(
        ProjectDeletionDialogText.message(sessionCount: 1, childCount: 0, otherProjectChildCount: 3)
            == "このプロジェクトのセッション 1 件と、ほかのプロジェクトにある子セッション 3 件を停止し、一覧から外します。会話は元に戻せません。"
    )
}

@Test
func projectDeletionDialogText_note_keepsTheFolder() {
    #expect(ProjectDeletionDialogText.note(folderPath: "~/dev/phlox") == "フォルダ「~/dev/phlox」とその中のファイルは削除されません。")
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
