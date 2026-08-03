import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
import SessionFeature
@testable import DashboardFeature

private actor WorktreeIsolationProjectStore: ProjectStoreProtocol {
    private var stored: [Project] = []

    func load() async -> [Project] {
        stored
    }

    func save(_ projects: [Project]) async throws {
        stored = projects
    }
}

private actor WorktreeIsolationSessionStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]

    init(_ stored: [PersistedSessionDescriptor]) {
        self.stored = stored
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        stored = sessions
    }
}

private struct WorktreeIsolationTestGitError: Error {}

private func runWorktreeIsolationGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory

    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    process.environment = environment

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw WorktreeIsolationTestGitError()
    }
    return String(decoding: data, as: UTF8.self)
}

private func makeWorktreeIsolationRepository() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-repository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try runWorktreeIsolationGit(["init", "--initial-branch=main"], in: root)
    // worktree add には root commit だけが必要なので、設定・add を別プロセスで起動しない。
    _ = try runWorktreeIsolationGit([
        "-c", "user.name=phlox-test",
        "-c", "user.email=test@phlox.local",
        "-c", "commit.gpgsign=false",
        "-c", "core.hooksPath=/dev/null",
        "commit", "--allow-empty", "-m", "initial",
    ], in: root)
    return root
}

private enum WorktreeIsolationRepositoryFixture {
    static let repositoryResult: Result<URL, Error> = {
        do {
            return .success(try makeWorktreeIsolationRepository())
        } catch {
            return .failure(error)
        }
    }()

    static func repository() throws -> URL {
        try repositoryResult.get()
    }
}

private func cleanupWorktreeIsolationTestWorktree(
    at worktreePath: URL,
    branchName: String,
    in repository: URL
) {
    if FileManager.default.fileExists(atPath: worktreePath.path) {
        do {
            _ = try runWorktreeIsolationGit(
                ["worktree", "remove", "--force", worktreePath.path],
                in: repository
            )
        } catch {
            Issue.record("テスト用 worktree の削除に失敗: \(error)")
        }
    }

    do {
        // refs/heads/<name> が無い場合も成功するため、一覧確認と削除を 1 回にまとめる。
        // worktree の削除は上で別途行い、対象ブランチ以外には触れない。
        _ = try runWorktreeIsolationGit(
            ["update-ref", "-d", "refs/heads/\(branchName)"],
            in: repository
        )
    } catch {
        Issue.record("テスト用ブランチの削除に失敗: \(error)")
    }
}

@MainActor
private func makeWorktreeIsolationEnvironment(
    pty: MockPTYManager,
    workspaceDirectory: URL,
    projectStore: WorktreeIsolationProjectStore,
    sessionStore: any SessionStoreProtocol = NoOpSessionStore(),
    agentBinaryPaths: [AgentKind: String] = [.codex: "/usr/local/bin/codex"]
) -> AppEnvironment {
    AppEnvironment(
        pty: pty,
        hook: MockHookServer(events: AsyncStream { _ in }),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/phlox-worktree-test-hooks.json"),
        hookDispatcherPath: "/tmp/phlox-worktree-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: agentBinaryPaths,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        projects: projectStore,
        sessions: sessionStore,
        cliPath: "/tmp/phlox-worktree-test-cli"
    )
}

// 各テストが実 git を複数回起動するため、パッケージ全体の並列実行で
// タイミング依存テストの待機期限を圧迫しないよう、この契約テスト群だけ直列化する。
@Suite(.serialized)
struct WorktreeIsolationSpawnTests {

@Test @MainActor
func worktreeIsolation_spawnUsesDedicatedWorktreeAndCleanupRemovesOnlyOwnedWorktree() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let project = Project(
        name: "isolated",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
    let worktreeURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let branch = WorktreeIsolationPlanner.branchName(for: sessionID)

    #expect(ptyManager.spawnCalls.first?.workingDirectory == worktreeURL.path)
    #expect(FileManager.default.fileExists(atPath: worktreeURL.path))
    #expect(GitBranchReader.currentBranch(at: worktreeURL.path) == branch)

    await dashboard.removeSession(sessionID)

    #expect(!FileManager.default.fileExists(atPath: worktreeURL.path))
    #expect(try runWorktreeIsolationGit(["branch", "--list", branch], in: repository)
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test @MainActor
func worktreeIsolation_nonGitProjectAbortsWithoutUsingSharedDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-non-git-workspace-\(UUID().uuidString)", isDirectory: true)
    let projectDirectory = workspaceRoot.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let project = Project(
        name: "non-git",
        directoryPath: projectDirectory.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    await dashboard.start()

    do {
        _ = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
        Issue.record("隔離不能なプロジェクトの spawn が成功した")
    } catch {
        #expect(error.localizedDescription.contains("Git"))
    }

    #expect(ptyManager.spawnCalls.isEmpty)
    let workspaceEntries = try FileManager.default.contentsOfDirectory(
        at: workspaceRoot,
        includingPropertiesForKeys: nil,
        options: []
    )
    #expect(workspaceEntries.map(\.standardizedFileURL.path) == [projectDirectory.standardizedFileURL.path])
}

@Test @MainActor
func worktreeIsolation_togglePersistsOnAndOffWithoutChangingOptionalSchema() async throws {
    let ptyManager = MockPTYManager()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-toggle-workspace-\(UUID().uuidString)", isDirectory: true)
    let projectDirectory = workspaceRoot.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let projectStore = WorktreeIsolationProjectStore()
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let projectID = try #require(
        dashboard.addProject(name: "toggle", directoryPath: projectDirectory.path)
    )

    dashboard.setWorktreeIsolationEnabled(true, for: projectID)
    try await waitUntil {
        await projectStore.load().first(where: { $0.id == projectID })?.worktreeIsolationEnabled == true
    }
    #expect(dashboard.projects.first?.usesWorktreeIsolation == true)

    dashboard.setWorktreeIsolationEnabled(false, for: projectID)
    try await waitUntil {
        await projectStore.load().first(where: { $0.id == projectID })?.worktreeIsolationEnabled == false
    }
    #expect(dashboard.projects.first?.worktreeIsolationEnabled == false)
    #expect(dashboard.projects.first?.usesWorktreeIsolation == false)
}

@Test @MainActor
func worktreeIsolation_cleanupLeavesUncommittedWorktreeAndShowsWarning() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-dirty-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    var createdWorktreeURL: URL?
    var createdBranch: String?
    defer {
        if let createdWorktreeURL, let createdBranch {
            cleanupWorktreeIsolationTestWorktree(
                at: createdWorktreeURL,
                branchName: createdBranch,
                in: repository
            )
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspaceRoot.path)
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let project = Project(
        name: "dirty",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
    let worktreeURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let branch = WorktreeIsolationPlanner.branchName(for: sessionID)
    createdWorktreeURL = worktreeURL
    createdBranch = branch
    let userFile = worktreeURL.appendingPathComponent("user-change.txt")
    try Data("keep this change\n".utf8).write(to: userFile)

    await dashboard.removeSession(sessionID)

    #expect(FileManager.default.fileExists(atPath: worktreeURL.path))
    #expect(FileManager.default.fileExists(atPath: userFile.path))
    #expect(dashboard.workspaceCleanupWarning == .worktreeRetained(path: worktreeURL.path))
    #expect(try runWorktreeIsolationGit(["branch", "--list", branch], in: repository)
        .contains(branch))
}

@Test @MainActor
func worktreeIsolation_cleanupShowsBranchWarningWhenOnlyBranchRemovalFails() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-branch-warning-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    var worktreeURL: URL?
    var branchName: String?
    defer {
        if let worktreeURL, let branchName {
            cleanupWorktreeIsolationTestWorktree(
                at: worktreeURL,
                branchName: branchName,
                in: repository
            )
        }
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let project = Project(
        name: "branch-warning",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
    let spawnedWorktreeURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let spawnedBranchName = WorktreeIsolationPlanner.branchName(for: sessionID)
    worktreeURL = spawnedWorktreeURL
    branchName = spawnedBranchName
    let committedFile = spawnedWorktreeURL.appendingPathComponent("committed-change.txt")
    try Data("unmerged branch commit\n".utf8).write(to: committedFile)
    _ = try runWorktreeIsolationGit(["add", committedFile.path], in: spawnedWorktreeURL)
    _ = try runWorktreeIsolationGit([
        "-c", "user.name=phlox-test",
        "-c", "user.email=test@phlox.local",
        "-c", "commit.gpgsign=false",
        "commit", "-m", "unmerged session work"
    ], in: spawnedWorktreeURL)

    await dashboard.removeSession(sessionID)

    #expect(!FileManager.default.fileExists(atPath: spawnedWorktreeURL.path))
    #expect(try runWorktreeIsolationGit(["branch", "--list", spawnedBranchName], in: repository)
        .contains(spawnedBranchName))
    #expect(dashboard.workspaceCleanupWarning == .branchRetained(branchName: spawnedBranchName))
    #expect(dashboard.workspaceCleanupWarning?.title == "セッション用ブランチを残しています")
    #expect(dashboard.workspaceCleanupWarning?.message.contains("worktree は削除しました") == true)
}

@Test @MainActor
func worktreeIsolation_failedCreationRollsBackNewBranchAndPreservesPreexistingRecreateBranch() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-failed-workspace-\(UUID().uuidString)", isDirectory: true)
    let restoredSessionID = SessionID()
    let restoredBranch = WorktreeIsolationPlanner.branchName(for: restoredSessionID)
    let restoredWorktreePath = workspaceRoot.appendingPathComponent(
        restoredSessionID.rawValue.uuidString,
        isDirectory: true
    )
    _ = try runWorktreeIsolationGit(["branch", restoredBranch], in: repository)
    try Data("workspace root is intentionally a file\n".utf8).write(to: workspaceRoot)
    defer {
        do {
            cleanupWorktreeIsolationTestWorktree(
                at: restoredWorktreePath,
                branchName: restoredBranch,
                in: repository
            )
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let project = Project(
        name: "failed-creation",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let descriptor = PersistedSessionDescriptor(
        id: restoredSessionID,
        kind: .codex,
        workingDirectory: restoredWorktreePath.path,
        name: "preexisting-branch",
        projectID: project.id,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:]
    )
    let sessionStore = WorktreeIsolationSessionStore([descriptor])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore,
        sessionStore: sessionStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: workspaceRoot.path)
    await dashboard.start()

    // 復元失敗後の遅延 spawn（150ms debounce）を取りこぼさないための静穏待ち。
    try await Task.sleep(for: .milliseconds(500))
    #expect(ptyManager.spawnCalls.isEmpty)
    do {
        _ = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
        Issue.record("書き込み不能な親ディレクトリでも worktree 作成が成功した")
    } catch {
        #expect(error.localizedDescription.contains("worktree"))
    }

    let branches = try runWorktreeIsolationGit(
        ["for-each-ref", "refs/heads", "--format=%(refname:short)"],
        in: repository
    )
    let sessionBranches = branches.split(whereSeparator: \.isNewline)
        .map(String.init)
        .filter { $0.hasPrefix("phlox/session/") }
    #expect(sessionBranches == [restoredBranch])
    #expect(ptyManager.spawnCalls.isEmpty)
}

@Test
func restoreFailureClassification_suppressesGitErrors() {
    let gitError: Error = WorktreeIsolationGitError.commandFailed(
        arguments: ["worktree", "list"],
        output: "repository is unavailable"
    )
    let spawnError: Error = WorktreeIsolationSpawnError.aborted(
        .worktreePathOccupied("/tmp/occupied")
    )
    let unrelatedError: Error = AgentLaunchPlannerError.binaryNotFound(.codex)

    #expect(SessionRestoreCoordinator.shouldSuppressSpawn(for: gitError))
    #expect(SessionRestoreCoordinator.shouldSuppressSpawn(for: spawnError))
    #expect(!SessionRestoreCoordinator.shouldSuppressSpawn(for: unrelatedError))
}

@Test @MainActor
func restore_binaryNotFound_placeholderMessageIdentifiesTheAgent() async throws {
    let sessionID = SessionID()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-restore-error-message-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "missing-codex",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:]
    )
    let ptyManager = MockPTYManager()
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: WorktreeIsolationProjectStore(),
        sessionStore: WorktreeIsolationSessionStore([descriptor]),
        agentBinaryPaths: [:]
    )
    let dashboard = DashboardViewModel(environment: environment)

    await dashboard.start()
    let vm = try #require(dashboard.sessions.first { $0.id == sessionID })
    guard case .error(let message) = vm.status else {
        Issue.record("復元失敗セッションが error 状態でない: \(vm.status)")
        return
    }
    #expect(
        message.contains("codex"),
        "復元失敗メッセージからエージェント名が失われている: \(message)"
    )
    #expect(ptyManager.spawnCalls.isEmpty)
}

@Test @MainActor
func restore_chatBinaryNotFound_placeholderMessageIdentifiesTheAgent() async throws {
    let sessionID = SessionID()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-chat-restore-error-message-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "missing-codex-chat",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        backend: .appServer,
        codexThreadId: "thread-missing-codex"
    )
    let ptyManager = MockPTYManager()
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: WorktreeIsolationProjectStore(),
        sessionStore: WorktreeIsolationSessionStore([descriptor]),
        agentBinaryPaths: [:]
    )
    let dashboard = DashboardViewModel(environment: environment)

    await dashboard.start()
    let chat = try #require(dashboard.sessionNodes.first { $0.id == sessionID }?.appServer)
    guard case .failed(let message) = chat.restoreState else {
        Issue.record("チャット復元失敗セッションが failed 状態でない: \(chat.restoreState)")
        return
    }
    #expect(
        message.contains("codex"),
        "チャット復元失敗メッセージからエージェント名が失われている: \(message)"
    )
}

@Test @MainActor
func worktreeIsolation_restoreReusesRegisteredWorktreeThroughCoordinator() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-restore-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    let sessionID = SessionID()
    let branchName = WorktreeIsolationPlanner.branchName(for: sessionID)
    let worktreePath = workspaceRoot.appendingPathComponent(
        sessionID.rawValue.uuidString,
        isDirectory: true
    )
    defer {
        cleanupWorktreeIsolationTestWorktree(
            at: worktreePath,
            branchName: branchName,
            in: repository
        )
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    _ = try runWorktreeIsolationGit(
        ["worktree", "add", "-b", branchName, worktreePath.path],
        in: repository
    )
    let project = Project(
        name: "restore",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: worktreePath.path,
        name: "restored",
        projectID: project.id,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:]
    )
    let sessionStore = WorktreeIsolationSessionStore([descriptor])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore,
        sessionStore: sessionStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )

    await dashboard.start()
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    #expect(ptyManager.spawnCalls.first?.id == sessionID)
    #expect(ptyManager.spawnCalls.first?.workingDirectory == worktreePath.path)
    #expect(GitBranchReader.currentBranch(at: worktreePath.path) == branchName)
}

@Test @MainActor
func worktreeIsolation_restoreTracksExistingWorktreeAfterIsolationIsDisabled() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-restore-disabled-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    let sessionID = SessionID()
    let branchName = WorktreeIsolationPlanner.branchName(for: sessionID)
    let worktreePath = workspaceRoot.appendingPathComponent(
        sessionID.rawValue.uuidString,
        isDirectory: true
    )
    defer {
        cleanupWorktreeIsolationTestWorktree(
            at: worktreePath,
            branchName: branchName,
            in: repository
        )
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    _ = try runWorktreeIsolationGit(
        ["worktree", "add", "-b", branchName, worktreePath.path],
        in: repository
    )
    let project = Project(
        name: "restore-disabled",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: false
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: worktreePath.path,
        name: "restored-disabled",
        projectID: project.id,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:]
    )
    let sessionStore = WorktreeIsolationSessionStore([descriptor])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore,
        sessionStore: sessionStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )

    await dashboard.start()
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    #expect(ptyManager.spawnCalls.first?.workingDirectory == worktreePath.path)

    await dashboard.removeSession(sessionID)

    #expect(!FileManager.default.fileExists(atPath: worktreePath.path))
    #expect(try runWorktreeIsolationGit(["branch", "--list", branchName], in: repository)
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test @MainActor
func worktreeIsolation_restoreRecreatesMissingWorktreeFromExistingBranch() async throws {
    let ptyManager = MockPTYManager()
    let repository = try WorktreeIsolationRepositoryFixture.repository()
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-worktree-recreate-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    let sessionID = SessionID()
    let branchName = WorktreeIsolationPlanner.branchName(for: sessionID)
    let worktreePath = workspaceRoot.appendingPathComponent(
        sessionID.rawValue.uuidString,
        isDirectory: true
    )
    defer {
        cleanupWorktreeIsolationTestWorktree(
            at: worktreePath,
            branchName: branchName,
            in: repository
        )
        do {
            try FileManager.default.removeItem(at: workspaceRoot)
        } catch {
            Issue.record("テスト後の一時ディレクトリ削除に失敗: \(error)")
        }
    }

    _ = try runWorktreeIsolationGit(
        ["worktree", "add", "-b", branchName, worktreePath.path],
        in: repository
    )
    try FileManager.default.removeItem(at: worktreePath)
    let project = Project(
        name: "recreate",
        directoryPath: repository.path,
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: true
    )
    let projectStore = WorktreeIsolationProjectStore()
    try await projectStore.save([project])
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: worktreePath.path,
        name: "recreated",
        projectID: project.id,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:]
    )
    let sessionStore = WorktreeIsolationSessionStore([descriptor])
    let environment = makeWorktreeIsolationEnvironment(
        pty: ptyManager,
        workspaceDirectory: workspaceRoot,
        projectStore: projectStore,
        sessionStore: sessionStore
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )

    await dashboard.start()
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    #expect(ptyManager.spawnCalls.first?.id == sessionID)
    #expect(ptyManager.spawnCalls.first?.workingDirectory == worktreePath.path)
    #expect(FileManager.default.fileExists(atPath: worktreePath.path))
    #expect(GitBranchReader.currentBranch(at: worktreePath.path) == branchName)
}

}
