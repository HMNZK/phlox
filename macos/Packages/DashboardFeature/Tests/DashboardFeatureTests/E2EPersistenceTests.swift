import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

@Suite("E2E Persistence")
struct E2EPersistenceTests {

    // MARK: - Test 1 (S2 正常系: 再起動相当の復元)

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func s2_restartRestoresSessionNamesAndProjectPlacement() async throws {
        let dataDirectory = try makePersistenceDataDirectory()
        defer { cleanupPersistenceDataDirectory(dataDirectory) }

        let workspaceURL = dataDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let projectAFolder = workspaceURL.appendingPathComponent("alpha", isDirectory: true)
        let projectBFolder = workspaceURL.appendingPathComponent("beta", isDirectory: true)
        try FileManager.default.createDirectory(at: projectAFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectBFolder, withIntermediateDirectories: true)

        let sessionStore = JSONSessionStore(fileURL: dataDirectory.appendingPathComponent("sessions.json"))
        let projectStore = JSONProjectStore(fileURL: dataDirectory.appendingPathComponent("projects.json"))

        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makePersistenceEnvironment(
            dataDirectory: dataDirectory,
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL,
            sessionStore: sessionStore,
            projectStore: projectStore
        )

        var dashboard: DashboardViewModel? = DashboardViewModel(environment: environment)
        await dashboard?.start()

        let projectA = try #require(dashboard?.addProject(name: "Alpha", directoryPath: projectAFolder.path))
        let projectB = try #require(dashboard?.addProject(name: "Beta", directoryPath: projectBFolder.path))

        let sessionA = try await dashboard?.spawnNewSession(kind: .claudeCode, projectID: projectA)
        let sessionB = try await dashboard?.spawnNewSession(kind: .claudeCode, projectID: projectB)
        let sessionAID = try #require(sessionA)
        let sessionBID = try #require(sessionB)

        dashboard?.sessions[0].terminalCoordinator.onResize(80, 24)
        dashboard?.sessions[1].terminalCoordinator.onResize(80, 24)
        try await waitUntil { ptyManager.spawnCalls.count == 2 }

        dashboard?.renameSession(sessionAID, to: "E2E-Alpha")
        dashboard?.renameSession(sessionBID, to: "E2E-Beta")

        let persisted = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            let loaded = await sessionStore.load()
            return loaded.count == 2
                && loaded.contains { $0.id == sessionAID && $0.name == "E2E-Alpha" && $0.projectID == projectA }
                && loaded.contains { $0.id == sessionBID && $0.name == "E2E-Beta" && $0.projectID == projectB }
        }
        #expect(persisted, "セッション2本の永続化が完了しなかった")

        // 再起動相当: ViewModel を破棄し、同じデータディレクトリで再構築する。
        dashboard = nil

        let restoredPTYManager = MockPTYManager()
        let (restoreHookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let restoreEnvironment = makePersistenceEnvironment(
            dataDirectory: dataDirectory,
            pty: restoredPTYManager,
            hookStream: restoreHookStream,
            workspaceDirectory: workspaceURL,
            sessionStore: sessionStore,
            projectStore: projectStore
        )
        let restoredDashboard = DashboardViewModel(environment: restoreEnvironment)
        await restoredDashboard.start()

        #expect(restoredDashboard.sessions.count == 2)
        let names = Set(restoredDashboard.sessions.map(\.name))
        #expect(names == ["E2E-Alpha", "E2E-Beta"])

        let restoredA = try #require(restoredDashboard.sessions.first { $0.id == sessionAID })
        let restoredB = try #require(restoredDashboard.sessions.first { $0.id == sessionBID })
        #expect(restoredA.projectID == projectA)
        #expect(restoredB.projectID == projectB)

        // claudeCode は statusBootstrap=.viaHook のため、再起動後は hook 待ちで .starting になる。
        #expect(restoredA.status == .starting)
        #expect(restoredB.status == .starting)

        try await waitUntil { restoredPTYManager.spawnCalls.count == 2 }
    }

    // MARK: - Test 2 (S2 異常系: 破損 JSON)

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func s2_corruptSessionsJSONStartsWithEmptyState() async throws {
        let dataDirectory = try makePersistenceDataDirectory()
        defer { cleanupPersistenceDataDirectory(dataDirectory) }

        let sessionsURL = dataDirectory.appendingPathComponent("sessions.json")
        try Data(#"{"broken":"#.utf8).write(to: sessionsURL, options: .atomic)

        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makePersistenceEnvironment(
            dataDirectory: dataDirectory,
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: dataDirectory.appendingPathComponent("workspace", isDirectory: true),
            sessionStore: JSONSessionStore(fileURL: sessionsURL),
            projectStore: JSONProjectStore(fileURL: dataDirectory.appendingPathComponent("projects.json"))
        )

        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        #expect(dashboard.sessions.isEmpty)
        #expect(dashboard.projects.isEmpty)

        let loaded = await JSONSessionStore(fileURL: sessionsURL).load()
        #expect(loaded.isEmpty)

        // JSONFileStore は破損ファイルを退避し、元パスを空にする。
        #expect(!FileManager.default.fileExists(atPath: sessionsURL.path))
        let quarantined = try FileManager.default.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sessions.json.corrupt-") }
        #expect(quarantined.count == 1)
    }

    // MARK: - Test 3 (S6: プロジェクト配置の永続化)

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func s6_projectPlacementSurvivesRestart() async throws {
        let dataDirectory = try makePersistenceDataDirectory()
        defer { cleanupPersistenceDataDirectory(dataDirectory) }

        let workspaceURL = dataDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let folderA = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
        let folderB = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        let sessionStore = JSONSessionStore(fileURL: dataDirectory.appendingPathComponent("sessions.json"))
        let projectStore = JSONProjectStore(fileURL: dataDirectory.appendingPathComponent("projects.json"))

        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makePersistenceEnvironment(
            dataDirectory: dataDirectory,
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL,
            sessionStore: sessionStore,
            projectStore: projectStore
        )

        var dashboard: DashboardViewModel? = DashboardViewModel(environment: environment)
        await dashboard?.start()

        let projectA = try #require(dashboard?.addProject(name: "A", directoryPath: folderA.path))
        let projectB = try #require(dashboard?.addProject(name: "B", directoryPath: folderB.path))
        let sessionID = try await dashboard?.spawnNewSession(kind: .claudeCode, projectID: projectA)
        let resolvedSessionID = try #require(sessionID)

        dashboard?.sessions[0].terminalCoordinator.onResize(80, 24)
        try await waitUntil { ptyManager.spawnCalls.count == 1 }

        await dashboard?.moveSession(resolvedSessionID, to: projectB)

        let moved = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            let saved = await sessionStore.load().first { $0.id == resolvedSessionID }
            return saved?.projectID == projectB && saved?.workingDirectory == folderB.path
        }
        #expect(moved, "moveSession 後の projectID / workingDirectory が永続化されなかった")

        dashboard = nil

        let restoredPTYManager = MockPTYManager()
        let (restoreHookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let restoreEnvironment = makePersistenceEnvironment(
            dataDirectory: dataDirectory,
            pty: restoredPTYManager,
            hookStream: restoreHookStream,
            workspaceDirectory: workspaceURL,
            sessionStore: sessionStore,
            projectStore: projectStore
        )
        let restoredDashboard = DashboardViewModel(environment: restoreEnvironment)
        await restoredDashboard.start()

        #expect(restoredDashboard.sessions.count == 1)
        let restored = try #require(restoredDashboard.sessions.first)
        #expect(restored.id == resolvedSessionID)
        #expect(restored.projectID == projectB)
        let savedAfterRestore = await sessionStore.load().first { $0.id == resolvedSessionID }
        #expect(savedAfterRestore?.workingDirectory == folderB.path)
    }

    // MARK: - Test 4 (S9-A: Bypass 設定と hooks 設定ファイルの切り替え)

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    func s9a_bypassTogglesClaudeHooksSettingsFileSelectionAndContent() throws {
        let dataDirectory = try makePersistenceDataDirectory()
        defer { cleanupPersistenceDataDirectory(dataDirectory) }

        let dispatcherPath = "/tmp/phlox-e2e-test-dispatcher.sh"
        let bypassURL = dataDirectory.appendingPathComponent("hooks.json")
        let restrictedURL = dataDirectory.appendingPathComponent("hooks-restricted.json")
        try writeClaudeHooksSettingsFile(to: bypassURL, defaultMode: "bypassPermissions", dispatcherPath: dispatcherPath)
        try writeClaudeHooksSettingsFile(to: restrictedURL, defaultMode: "default", dispatcherPath: dispatcherPath)

        let environment = makeBypassPlannerEnvironment(
            claudeSettingsURL: bypassURL,
            claudeSettingsRestrictedURL: restrictedURL
        )
        let planner = AgentLaunchPlanner()
        let sessionID = SessionID()

        let bypassOnPlan = try planner.plan(
            kind: .claudeCode,
            environment: environment,
            sessionID: sessionID,
            sessionToken: "e2e-token",
            bypassEnabled: true
        )
        let bypassOffPlan = try planner.plan(
            kind: .claudeCode,
            environment: environment,
            sessionID: sessionID,
            sessionToken: "e2e-token",
            bypassEnabled: false
        )

        #expect(bypassOnPlan.args.contains(bypassURL.path))
        #expect(!bypassOnPlan.args.contains(restrictedURL.path))
        #expect(bypassOffPlan.args.contains(restrictedURL.path))
        #expect(!bypassOffPlan.args.contains(bypassURL.path))

        let bypassOnMode = try readClaudeDefaultMode(from: bypassURL)
        let restrictedMode = try readClaudeDefaultMode(from: restrictedURL)
        #expect(bypassOnMode == "bypassPermissions")
        #expect(restrictedMode == "default")
        #expect(bypassOnMode != restrictedMode)
    }

    // MARK: - Test 5 (partialRestore: 復元未完了時の破壊的保存抑止)

    @Test @MainActor
    func partialRestore_preservesStoreEntryCountWhenDestructiveSaveRunsDuringRestore() async throws {
        let sessionCount = 5
        let descriptors = (0..<sessionCount).map { index in
            makePartialRestoreDescriptor(index: index)
        }
        let sessionStore = CountingInMemorySessionStore(descriptors)
        let projects = (0..<3).map { index in
            Project(
                name: "Project-\(index)",
                directoryPath: "/tmp/phlox-partial-restore-\(index)",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                isManagedDirectory: false
            )
        }
        let projectStore = CountingInMemoryProjectStore(projects)

        let coordinator = SessionPersistenceCoordinator(
            sessionStore: sessionStore,
            projectStore: projectStore,
            logError: { _, _ in }
        )

        coordinator.beginSessionRestore()

        coordinator.removeSession(descriptors[0].id)
        coordinator.persistProjects([projects[0]])
        await coordinator.waitForPendingWrites()

        #expect(await sessionStore.load().count == sessionCount)
        #expect(await sessionStore.saveCount == 0)
        #expect(await projectStore.load().count == 3)
        #expect(await projectStore.saveCount == 0)

        coordinator.completeSessionRestore()

        coordinator.removeSession(descriptors[0].id)
        await coordinator.waitForPendingWrites()
        #expect(await sessionStore.load().count == sessionCount - 1)
        #expect(await sessionStore.saveCount == 1)
    }
}

// MARK: - Private helpers (WP-E4 固有。E2ETestSupport は編集しない)

private func makePersistenceDataDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-e2e-persist-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupPersistenceDataDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
}

@MainActor
private func makePersistenceEnvironment(
    dataDirectory: URL,
    pty: any PTYManagerProtocol,
    hookStream: AsyncStream<(SessionID, HookEvent)>,
    workspaceDirectory: URL,
    sessionStore: JSONSessionStore,
    projectStore: JSONProjectStore
) -> AppEnvironment {
    try? FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
    return AppEnvironment(
        pty: pty,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: dataDirectory.appendingPathComponent("hooks.json"),
        claudeSettingsRestrictedURL: dataDirectory.appendingPathComponent("hooks-restricted.json"),
        hookDispatcherPath: "/tmp/phlox-e2e-test-dispatcher.sh",
        claudeBinaryPath: "/tmp/phlox-e2e-fake-claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceDirectory,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        projects: projectStore,
        sessions: sessionStore,
        cliPath: "/tmp/phlox-e2e-test-cli"
    )
}

private func makeBypassPlannerEnvironment(
    claudeSettingsURL: URL,
    claudeSettingsRestrictedURL: URL
) -> AppEnvironment {
    AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: AsyncStream { _ in }),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: claudeSettingsURL,
        claudeSettingsRestrictedURL: claudeSettingsRestrictedURL,
        hookDispatcherPath: "/tmp/phlox-e2e-test-dispatcher.sh",
        claudeBinaryPath: "/tmp/phlox-e2e-fake-claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: FileManager.default.temporaryDirectory,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/phlox-e2e-test-cli"
    )
}

private func writeClaudeHooksSettingsFile(
    to url: URL,
    defaultMode: String,
    dispatcherPath: String
) throws {
    let settings: [String: Any] = [
        "permissions": [
            "defaultMode": defaultMode,
        ],
        "statusLine": [
            "type": "command",
            "command": "/tmp/phlox-e2e-statusline.sh",
        ],
        "hooks": [
            "SessionStart": [["matcher": "", "hooks": [["type": "command", "command": "'\(dispatcherPath)' sessionStart"]]]],
            "Stop": [["matcher": "", "hooks": [["type": "command", "command": "'\(dispatcherPath)' stop"]]]],
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
    try data.write(to: url, options: .atomic)
}

private func readClaudeDefaultMode(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = try #require(json?["permissions"] as? [String: Any])
    return try #require(permissions["defaultMode"] as? String)
}

private func makePartialRestoreDescriptor(index: Int) -> PersistedSessionDescriptor {
    let sessionID = SessionID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!)
    return PersistedSessionDescriptor(
        id: sessionID,
        kind: .claudeCode,
        workingDirectory: "/tmp/phlox-partial-restore-\(index)",
        name: "Session-\(index)",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: Double(index)),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:],
        token: "token-\(index)"
    )
}

private actor CountingInMemorySessionStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]
    private(set) var saveCount = 0

    init(_ sessions: [PersistedSessionDescriptor]) {
        self.stored = sessions
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        stored = sessions
        saveCount += 1
    }
}

private actor CountingInMemoryProjectStore: ProjectStoreProtocol {
    private var stored: [Project]
    private(set) var saveCount = 0

    init(_ projects: [Project]) {
        self.stored = projects
    }

    func load() async -> [Project] {
        stored
    }

    func save(_ projects: [Project]) async throws {
        stored = projects
        saveCount += 1
    }
}
