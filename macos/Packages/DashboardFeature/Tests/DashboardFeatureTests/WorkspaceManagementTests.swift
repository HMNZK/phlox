import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

// MARK: - In-memory Project store

actor InMemoryProjectStore: ProjectStoreProtocol {
    private var stored: [Project] = []

    func load() async -> [Project] {
        stored
    }

    func save(_ projects: [Project]) async throws {
        stored = projects
    }
}

@MainActor
private func makeTestEnvironmentWithProjects(
    pty: any PTYManagerProtocol,
    hookStream: AsyncStream<(SessionID, HookEvent)>,
    workspaceDirectory: URL,
    projectStore: InMemoryProjectStore = InMemoryProjectStore(),
    sessionStore: any SessionStoreProtocol = NoOpSessionStore(),
    agentBinaryPaths: [AgentKind: String] = [:]
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
        agentBinaryPaths: agentBinaryPaths,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        projects: projectStore,
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
}

// MARK: - CWD 削除ガード

@Test @MainActor
func removeSession_preservesUserSelectedProjectDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let userFolder = workspaceURL.appendingPathComponent("user-project", isDirectory: true)
    try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
    let markerURL = userFolder.appendingPathComponent("keep-me.txt")
    try Data("important".utf8).write(to: markerURL)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "User", directoryPath: userFolder.path)
    )
    try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let sessionID = dashboard.sessions[0].id

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.removeSession(sessionID)

    #expect(FileManager.default.fileExists(atPath: userFolder.path))
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
}

@Test @MainActor
func removeSession_doesNotDeleteSiblingDirectoryWithSimilarPrefix() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let siblingURL = workspaceURL.appendingPathComponent("workspace2", isDirectory: true)
    try FileManager.default.createDirectory(at: siblingURL, withIntermediateDirectories: true)
    let siblingMarker = siblingURL.appendingPathComponent("sibling.txt")
    try Data("sibling".utf8).write(to: siblingMarker)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    #expect(sessionWorkspaceURL.path.hasPrefix(workspaceURL.path))
    #expect(sessionWorkspaceURL != siblingURL)

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.removeSession(sessionID)

    #expect(!FileManager.default.fileExists(atPath: sessionWorkspaceURL.path))
    #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    #expect(FileManager.default.fileExists(atPath: siblingMarker.path))
}

@Test @MainActor
func removeSession_doesNotFollowSymlinkOutsideWorkspaceRoot() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let externalURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)
    defer { cleanupTemporaryWorkspaceRoot(externalURL) }
    let externalMarker = externalURL.appendingPathComponent("external.txt")
    try Data("external".utf8).write(to: externalMarker)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    try FileManager.default.createDirectory(at: sessionWorkspaceURL, withIntermediateDirectories: true)

    try FileManager.default.removeItem(at: sessionWorkspaceURL)
    try FileManager.default.createSymbolicLink(at: sessionWorkspaceURL, withDestinationURL: externalURL)

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.removeSession(sessionID)

    #expect(FileManager.default.fileExists(atPath: externalURL.path))
    #expect(FileManager.default.fileExists(atPath: externalMarker.path))
}

// MARK: - Codex 同一 CWD

@Test @MainActor
func spawnNewSession_codex_allowsMultipleSessionsInSameProjectDirectory() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("shared-codex", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "Shared", directoryPath: projectFolder.path)
    )

    let firstID = try await dashboard.spawnNewSession(kind: .codex, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .codex, projectID: projectID)

    #expect(firstID != secondID)
    #expect(dashboard.sessions.count == 2)
    #expect(dashboard.sessions.allSatisfy { $0.agentKind == .codex })
    #expect(dashboard.sessions.allSatisfy { $0.projectID == projectID })

    let hooksURL = CodexHooksManager.hooksFileURL(in: projectFolder)
    #expect(FileManager.default.fileExists(atPath: hooksURL.path))
    let hooksData = try Data(contentsOf: hooksURL)
    let hooksJSON = try JSONSerialization.jsonObject(with: hooksData) as? [String: Any]
    let hooks = try #require(hooksJSON?["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
    let stopHooks = try #require(stopEntries.first?["hooks"] as? [[String: Any]])
    let stopCommand = try #require(stopHooks.first?["command"] as? String)
    #expect(stopCommand == "'/tmp/agent-dashboard-test-dispatcher.sh' stop")
    #expect(!stopCommand.contains("PHLOX_SESSION_ID="))

    await dashboard.removeSession(firstID)
    #expect(FileManager.default.fileExists(atPath: hooksURL.path))

    await dashboard.removeSession(secondID)
    #expect(!FileManager.default.fileExists(atPath: hooksURL.path))
}

// MARK: - project CWD で起動

@Test @MainActor
func spawnNewSession_usesProjectDirectoryAsWorkingDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("my-app", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "My App", directoryPath: projectFolder.path)
    )
    try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    #expect(dashboard.sessions[0].projectID == projectID)

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.workingDirectory == projectFolder.path)
}

// MARK: - addProject 重複拒否

@Test @MainActor
func addProject_rejectsDuplicateStandardizedDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("dup", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let first = dashboard.addProject(name: "A", directoryPath: projectFolder.path + "/")
    #expect(first != nil)
    #expect(dashboard.projects.count == 1)

    let symlinkPath = workspaceURL.appendingPathComponent("dup-link", isDirectory: true).path
    try FileManager.default.createSymbolicLink(
        atPath: symlinkPath,
        withDestinationPath: projectFolder.path
    )
    let second = dashboard.addProject(name: "B", directoryPath: symlinkPath)
    #expect(second == nil)
    #expect(dashboard.projects.count == 1)
}

/// save の同時実行を検出する Project store。人工遅延で save の重なりを顕在化させる。
actor OverlapDetectingProjectStore: ProjectStoreProtocol {
    private var activeSaves = 0
    private(set) var maxConcurrentSaves = 0
    private(set) var saveHistory: [[Project]] = []

    func load() async -> [Project] { [] }

    func save(_ projects: [Project]) async throws {
        activeSaves += 1
        maxConcurrentSaves = max(maxConcurrentSaves, activeSaves)
        // actor の再入を許す待機点。直列化されていなければここで save が重なる。
        try? await Task.sleep(for: .milliseconds(20))
        saveHistory.append(projects)
        activeSaves -= 1
    }
}

@Test @MainActor
func persistProjects_serializesSavesAndPersistsLatestState() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folder = workspaceURL.appendingPathComponent("serialized", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let store = OverlapDetectingProjectStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        projects: store,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Original", directoryPath: folder.path))
    dashboard.renameProject(projectID, to: "Renamed")

    try await waitUntil { await store.saveHistory.count == 2 }

    // 保存は直列に実行され（重なりなし）、最後の書き込みが最新状態を反映する。
    #expect(await store.maxConcurrentSaves == 1)
    #expect(await store.saveHistory.last?.first?.name == "Renamed")
}

// MARK: - moveSession

@Test @MainActor
func moveSession_restartsInTargetProjectDirectoryAndRoutesHooks() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectB = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    let vm = dashboard.sessions[0]
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.moveSession(sessionID, to: projectB)

    // 移動先フォルダを CWD として再 spawn し、projectID が更新される。
    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    #expect(ptyManager.spawnCalls.last?.workingDirectory == folderB.path)
    #expect(ptyManager.killedIDs == [sessionID])
    #expect(vm.projectID == projectB)

    // 差し替え後の hook stream 経由で status が更新される。
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
}

@Test @MainActor
func moveSession_persistsProjectIDAndWorkingDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("persist-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("persist-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        sessionStore: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let projectB = try #require(dashboard.addProject(name: "B", directoryPath: folderB.path))
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.projectID == projectA
    }

    await dashboard.moveSession(sessionID, to: projectB)

    // 再起動後の復元が移動先で行われるよう、descriptor の projectID / workingDirectory が更新される。
    try await waitUntil {
        let saved = await sessionStore.load().first(where: { $0.id == sessionID })
        return saved?.projectID == projectB && saved?.workingDirectory == folderB.path
    }
    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(saved.projectID == projectB)
    #expect(saved.workingDirectory == folderB.path)
}

@Test @MainActor
func changeWorkspace_persistsNewWorkingDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("cwd-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("cwd-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        sessionStore: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectA = try #require(dashboard.addProject(name: "A", directoryPath: folderA.path))
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.workingDirectory == folderA.path
    }

    await dashboard.changeWorkspace(sessionID, to: folderB)

    // 再起動後の復元が新 CWD で行われるよう、descriptor の workingDirectory が更新される。
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.workingDirectory == folderB.path
    }
    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(saved.workingDirectory == folderB.path)
    // changeWorkspace は projectID を変更しない。
    #expect(saved.projectID == projectA)
}

// MARK: - removeProject / renameProject

@Test @MainActor
func removeProject_stopsSessionsRemovesProjectAndPersists() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folder = workspaceURL.appendingPathComponent("doomed", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let projectStore = InMemoryProjectStore()
    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        projectStore: projectStore,
        sessionStore: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Doomed", directoryPath: folder.path))
    let firstID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    let secondID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    await dashboard.removeProject(projectID)

    // 配下セッションは全停止・除去され、プロジェクトも一覧から消える。
    #expect(dashboard.sessions.isEmpty)
    #expect(dashboard.projects.isEmpty)
    #expect(Set(ptyManager.killedIDs) == Set([firstID, secondID]))

    // セッション・プロジェクトの両ストアからも消える。
    try await waitUntil { await sessionStore.load().isEmpty }
    try await waitUntil { await projectStore.load().isEmpty }
}

@Test @MainActor
func renameProject_updatesNameAndPersists() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folder = workspaceURL.appendingPathComponent("renamed", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let projectStore = InMemoryProjectStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        projectStore: projectStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(dashboard.addProject(name: "Before", directoryPath: folder.path))

    dashboard.renameProject(projectID, to: "After")

    #expect(dashboard.projects.first?.name == "After")
    try await waitUntil {
        await projectStore.load().first?.name == "After"
    }

    // 存在しない projectID の rename は no-op。
    dashboard.renameProject(ProjectID(), to: "Ghost")
    #expect(dashboard.projects.count == 1)
    #expect(dashboard.projects.first?.name == "After")
}

@Test @MainActor
func start_loadsPersistedProjects() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("persisted", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let store = InMemoryProjectStore()
    let existing = Project(
        name: "Saved",
        directoryPath: projectFolder.path,
        createdAt: Date(),
        isManagedDirectory: false
    )
    try await store.save([existing])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironmentWithProjects(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceURL,
        projectStore: store
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.projects.count == 1)
    #expect(dashboard.projects[0].name == "Saved")
}
