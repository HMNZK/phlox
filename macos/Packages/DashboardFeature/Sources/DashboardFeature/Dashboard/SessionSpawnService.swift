import Foundation
import Darwin
import AgentDomain
import DesignSystem
import HookServer
import PTYKit
import Security
import TerminalUI
import CodexAppServerKit
import SessionFeature

// 隠している秘密: launch plan 生成・VM 生成・env/token 組み立て・appServer throw 後始末の詳細。

struct WorktreeIsolationGitResult: Sendable {
    let terminationStatus: Int32
    let output: String
}

enum WorktreeIsolationGitError: Error, LocalizedError, Sendable {
    case processLaunch(arguments: [String], message: String)
    case commandFailed(arguments: [String], output: String)

    var errorDescription: String? {
        switch self {
        case .processLaunch(let arguments, let message):
            return "git " + arguments.joined(separator: " ") + " を実行できませんでした: " + message
        case .commandFailed(let arguments, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "git " + arguments.joined(separator: " ") + " に失敗しました。"
            }
            return "git " + arguments.joined(separator: " ") + " に失敗しました: " + detail
        }
    }
}

struct WorktreeIsolationRepositoryState: Sendable {
    let isGitRepository: Bool
    let localBranchNames: Set<String>
    let worktreePathExists: Bool
    let isRegisteredWorktree: Bool
}

/// worktree の生成・削除で使う git 実行経路。`GitBranchSwitcher.runGit` と同じく、
/// stdout/stderr を 1 本の Pipe へ集約する。worktree の作成・削除は書き込み操作なので、
/// 読み取り専用の `WorkingTreeService.runGit` の `--no-optional-locks` は付けない。
enum WorktreeIsolationGit {
    static func inspect(
        repository: URL,
        worktreePath: URL
    ) async throws -> WorktreeIsolationRepositoryState {
        try await runOffMainActor {
            try inspectSynchronously(repository: repository, worktreePath: worktreePath)
        }
    }

    static func addWorktree(
        at path: URL,
        branchName: String,
        in repository: URL,
        createsBranch: Bool,
        pruneStaleWorktrees: Bool
    ) async throws {
        try await runOffMainActor {
            if pruneStaleWorktrees {
                let arguments = ["worktree", "prune"]
                _ = try requireSuccess(
                    run(arguments: arguments, in: repository),
                    arguments: arguments
                )
            }
            try addWorktreeSynchronously(
                at: path,
                branchName: branchName,
                in: repository,
                createsBranch: createsBranch
            )
        }
    }

    static func removeWorktree(at path: URL, from repository: URL) async throws {
        _ = try await runOffMainActor {
            try requireSuccess(
                run(arguments: ["worktree", "remove", path.path], in: repository),
                arguments: ["worktree", "remove", path.path]
            )
        }
    }

    static func removeBranch(
        _ branchName: String,
        from repository: URL,
        force: Bool = false
    ) async throws {
        try await runOffMainActor {
            try removeBranchSynchronously(branchName, from: repository, force: force)
        }
    }

    /// 作成途中の枝だけを回収する。元から存在した枝には呼び出さない。
    static func removeBranchIfPresent(
        _ branchName: String,
        from repository: URL
    ) async throws {
        try await runOffMainActor {
            try removeBranchIfPresentSynchronously(branchName, from: repository)
        }
    }

    static func rollbackFailedWorktreeCreation(
        path: URL,
        branchName: String,
        repository: URL,
        branchWasPreexisting: Bool,
        workspaceDirectory: URL
    ) async throws -> String? {
        try await runOffMainActor {
            try rollbackFailedWorktreeCreationSynchronously(
                path: path,
                branchName: branchName,
                repository: repository,
                branchWasPreexisting: branchWasPreexisting,
                workspaceDirectory: workspaceDirectory
            )
        }
    }

    private static func runOffMainActor<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: .userInitiated) {
            try operation()
        }.value
    }

    private static func inspectSynchronously(
        repository: URL,
        worktreePath: URL
    ) throws -> WorktreeIsolationRepositoryState {
        guard isDirectory(repository) else {
            return WorktreeIsolationRepositoryState(
                isGitRepository: false,
                localBranchNames: [],
                worktreePathExists: pathExistsIncludingDanglingSymlink(worktreePath),
                isRegisteredWorktree: false
            )
        }

        let repositoryCheckArguments = ["rev-parse", "--is-inside-work-tree"]
        let repositoryCheck = try run(
            arguments: repositoryCheckArguments,
            in: repository
        )
        guard repositoryCheck.terminationStatus == 0,
              repositoryCheck.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return WorktreeIsolationRepositoryState(
                isGitRepository: false,
                localBranchNames: [],
                worktreePathExists: pathExistsIncludingDanglingSymlink(worktreePath),
                isRegisteredWorktree: false
            )
        }

        let branchesArguments = [
            "for-each-ref",
            "refs/heads",
            "--format=%(refname:short)",
        ]
        let branchesOutput = try requireSuccess(
            run(arguments: branchesArguments, in: repository),
            arguments: branchesArguments
        )
        let branchNames = Set(
            branchesOutput
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let worktreeListArguments = ["worktree", "list", "--porcelain"]
        let worktreeListOutput = try requireSuccess(
            run(arguments: worktreeListArguments, in: repository),
            arguments: worktreeListArguments
        )
        let targetPath = normalizedPath(worktreePath)
        let isRegistered = worktreeListOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("worktree ") }
            .contains {
                normalizedPath(URL(fileURLWithPath: String($0.dropFirst("worktree ".count)))) == targetPath
            }

        return WorktreeIsolationRepositoryState(
            isGitRepository: true,
            localBranchNames: branchNames,
            worktreePathExists: pathExistsIncludingDanglingSymlink(worktreePath),
            isRegisteredWorktree: isRegistered
        )
    }

    private static func addWorktreeSynchronously(
        at path: URL,
        branchName: String,
        in repository: URL,
        createsBranch: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let arguments = createsBranch
            ? ["worktree", "add", "-b", branchName, path.path]
            : ["worktree", "add", path.path, branchName]
        _ = try requireSuccess(
            run(arguments: arguments, in: repository),
            arguments: arguments
        )
    }

    private static func removeBranchSynchronously(
        _ branchName: String,
        from repository: URL,
        force: Bool
    ) throws {
        let arguments = ["branch", force ? "-D" : "-d", branchName]
        _ = try requireSuccess(
            run(arguments: arguments, in: repository),
            arguments: arguments
        )
    }

    private static func removeBranchIfPresentSynchronously(
        _ branchName: String,
        from repository: URL
    ) throws {
        let ref = "refs/heads/\(branchName)"
        let lookupArguments = ["show-ref", "--verify", "--quiet", ref]
        let lookup = try run(arguments: lookupArguments, in: repository)
        guard lookup.terminationStatus == 0 else {
            guard lookup.terminationStatus == 1 else {
                throw WorktreeIsolationGitError.commandFailed(
                    arguments: lookupArguments,
                    output: lookup.output
                )
            }
            return
        }

        try removeBranchSynchronously(branchName, from: repository, force: true)
    }

    private static func rollbackFailedWorktreeCreationSynchronously(
        path: URL,
        branchName: String,
        repository: URL,
        branchWasPreexisting: Bool,
        workspaceDirectory: URL
    ) throws -> String? {
        var problems: [String] = []
        var isRegistered = false

        do {
            isRegistered = try isRegisteredWorktreeSynchronously(at: path, in: repository)
        } catch {
            problems.append("作成途中の worktree の登録状態を確認できませんでした: \(error.localizedDescription)")
        }

        if isRegistered {
            do {
                try removeWorktreeSynchronously(at: path, from: repository)
            } catch {
                problems.append("作成途中の worktree を安全に戻せませんでした: \(error.localizedDescription)")
            }
        } else {
            removeUnregisteredEmptyPathIfSafe(
                path: path,
                workspaceDirectory: workspaceDirectory,
                problems: &problems
            )
        }

        if !branchWasPreexisting {
            do {
                try removeBranchIfPresentSynchronously(branchName, from: repository)
            } catch {
                problems.append("作成途中のブランチを削除できませんでした: \(error.localizedDescription)")
            }
        }

        return problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    private static func isRegisteredWorktreeSynchronously(at path: URL, in repository: URL) throws -> Bool {
        let arguments = ["worktree", "list", "--porcelain"]
        let output = try requireSuccess(
            run(arguments: arguments, in: repository),
            arguments: arguments
        )
        let targetPath = normalizedPath(path)
        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("worktree ") }
            .contains {
                normalizedPath(URL(fileURLWithPath: String($0.dropFirst("worktree ".count)))) == targetPath
            }
    }

    private static func removeWorktreeSynchronously(at path: URL, from repository: URL) throws {
        let arguments = ["worktree", "remove", path.path]
        _ = try requireSuccess(
            run(arguments: arguments, in: repository),
            arguments: arguments
        )
    }

    private static func removeUnregisteredEmptyPathIfSafe(
        path: URL,
        workspaceDirectory: URL,
        problems: inout [String]
    ) {
        guard pathExistsIncludingDanglingSymlink(path) else { return }

        let normalizedPath = path.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedWorkspace = workspaceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard isContained(normalizedPath, in: normalizedWorkspace) else {
            problems.append("作成途中のパスが workspaceDirectory 外にあるため削除しませんでした: \(path.path)")
            return
        }

        var info = stat()
        guard lstat(path.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            problems.append("作成途中のパスがディレクトリではないため削除しませんでした: \(path.path)")
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            if contents.isEmpty {
                try FileManager.default.removeItem(at: path)
            } else {
                problems.append("作成途中の worktree に内容が残っています。ユーザーデータ保護のため削除しませんでした: \(path.path)")
            }
        } catch {
            problems.append("作成途中のパスを確認・削除できませんでした: \(error.localizedDescription)")
        }
    }

    private static func isContained(_ path: URL, in root: URL) -> Bool {
        let pathComponents = path.pathComponents
        let rootComponents = root.pathComponents
        guard pathComponents.count >= rootComponents.count else { return false }
        return Array(pathComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func pathExistsIncludingDanglingSymlink(_ path: URL) -> Bool {
        var info = stat()
        return lstat(path.path, &info) == 0
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func run(arguments: [String], in directory: URL) throws -> WorktreeIsolationGitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WorktreeIsolationGitError.processLaunch(
                arguments: arguments,
                message: error.localizedDescription
            )
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()
        return WorktreeIsolationGitResult(
            terminationStatus: process.terminationStatus,
            output: output
        )
    }

    static func requireSuccess(
        _ result: WorktreeIsolationGitResult,
        arguments: [String]
    ) throws -> String {
        guard result.terminationStatus == 0 else {
            throw WorktreeIsolationGitError.commandFailed(
                arguments: arguments,
                output: result.output
            )
        }
        return result.output
    }
}

enum WorktreeIsolationSpawnError: Error, LocalizedError {
    case aborted(WorktreeIsolationFailure)
    case worktreeCreationFailed(path: String, branchName: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .aborted(let failure):
            switch failure {
            case .notAGitRepository(let path):
                return "Git リポジトリではないため、セッションの起動を中止しました: " + path
            case .branchAlreadyExists(let branchName):
                return "セッション用 Git ブランチが既に存在するため、起動を中止しました: " + branchName
            case .worktreePathOccupied(let path):
                return "セッション用 worktree のパスが既に使われているため、起動を中止しました: " + path
            }
        case .worktreeCreationFailed(let path, let branchName, let detail):
            return "セッション用 worktree を作成できなかったため、起動を中止しました。パス: "
                + path + "、ブランチ: " + branchName + "。" + detail
        }
    }
}

@MainActor
final class SessionSpawnService {
    struct AppServerSpawnResult {
        let vm: ChatSessionViewModel
        let codexThreadId: String?
        let chatNativeSessionId: String?
        let appServerUserAgent: String?
        let sessionName: String
    }

    private let environment: AppEnvironment
    private let persistence: SessionPersistenceCoordinator
    private let sessionHooks: SessionHookInstaller
    private let codexUserHooksEnabledProvider: @MainActor () -> Bool
    private let sessionNodesSnapshot: @MainActor () -> [SessionNode]
    private let projectsSnapshot: @MainActor () -> [Project]
    private let setHookContinuation: @MainActor (SessionID, AsyncStream<(SessionID, HookEvent)>.Continuation) -> Void
    private let registerOwnedWorkspace: @MainActor (SessionID, URL, URL?) -> Void
    private let cleanupOwnedWorkspace: @MainActor (SessionID) async -> Void
    private let lastUsedChatSettings: @MainActor (String) -> LastUsedChatSettings?
    private let recordLastUsedChatSettings: @MainActor (String, String?, String?) -> Void
    private let logError: @MainActor (Error, String) -> Void

    init(
        environment: AppEnvironment,
        persistence: SessionPersistenceCoordinator,
        sessionHooks: SessionHookInstaller,
        codexUserHooksEnabledProvider: @escaping @MainActor () -> Bool,
        sessionNodesSnapshot: @escaping @MainActor () -> [SessionNode],
        projectsSnapshot: @escaping @MainActor () -> [Project],
        setHookContinuation: @escaping @MainActor (SessionID, AsyncStream<(SessionID, HookEvent)>.Continuation) -> Void,
        registerOwnedWorkspace: @escaping @MainActor (SessionID, URL, URL?) -> Void,
        cleanupOwnedWorkspace: @escaping @MainActor (SessionID) async -> Void,
        lastUsedChatSettings: @escaping @MainActor (String) -> LastUsedChatSettings?,
        recordLastUsedChatSettings: @escaping @MainActor (String, String?, String?) -> Void,
        logError: @escaping @MainActor (Error, String) -> Void
    ) {
        self.environment = environment
        self.persistence = persistence
        self.sessionHooks = sessionHooks
        self.codexUserHooksEnabledProvider = codexUserHooksEnabledProvider
        self.sessionNodesSnapshot = sessionNodesSnapshot
        self.projectsSnapshot = projectsSnapshot
        self.setHookContinuation = setHookContinuation
        self.registerOwnedWorkspace = registerOwnedWorkspace
        self.cleanupOwnedWorkspace = cleanupOwnedWorkspace
        self.lastUsedChatSettings = lastUsedChatSettings
        self.recordLastUsedChatSettings = recordLastUsedChatSettings
        self.logError = logError
    }

    /// 新規 spawn と復元が共用する非同期入口。worktree の検査・生成は detached executor
    /// で行い、MainActor は git の終了待ちで塞がない。
    func prepareSessionLaunchAsync(
        ref: AgentRef,
        sessionID: SessionID,
        sessionToken: String,
        workingDirectoryOverride: String?,
        projectID: ProjectID?,
        launchMode: AgentLaunchMode = .newSession(),
        backend: SessionBackend = .pty,
        extraEnv: [String: String] = [:],
        isolationIntent: WorktreeIsolationIntent = .newSession
    ) async throws -> AgentLaunchPlan {
        let codexUserHooksEnabled = codexUserHooksEnabledProvider()
        let sanitizedPlan = try makeSanitizedLaunchPlan(
            ref: ref,
            sessionID: sessionID,
            sessionToken: sessionToken,
            workingDirectoryOverride: workingDirectoryOverride,
            launchMode: launchMode,
            backend: backend,
            extraEnv: extraEnv,
            codexUserHooksEnabled: codexUserHooksEnabled
        )
        let isolationProject = projectID.flatMap { projectID in
            projectsSnapshot().first(where: { $0.id == projectID })
        }
        let worktree = try await prepareWorktreeIsolation(
            project: isolationProject,
            sessionID: sessionID,
            intent: isolationIntent,
            workingDirectoryOverride: workingDirectoryOverride
        )
        return try finishSessionLaunch(
            sanitizedPlan,
            sessionID: sessionID,
            projectID: projectID,
            worktree: worktree,
            backend: backend,
            codexUserHooksEnabled: codexUserHooksEnabled
        )
    }

    private func makeSanitizedLaunchPlan(
        ref: AgentRef,
        sessionID: SessionID,
        sessionToken: String,
        workingDirectoryOverride: String?,
        launchMode: AgentLaunchMode,
        backend: SessionBackend,
        extraEnv: [String: String],
        codexUserHooksEnabled: Bool
    ) throws -> AgentLaunchPlan {
        let planner = AgentLaunchPlanner()
        let rawPlan = try planner.plan(
            ref: ref,
            environment: environment,
            sessionID: sessionID,
            sessionToken: sessionToken,
            workingDirectoryOverride: workingDirectoryOverride,
            launchMode: launchMode,
            backend: backend,
            bypassEnabled: BypassSettings.isEnabled(for: ref, catalog: environment.agentCatalog),
            codexUserHooksEnabled: codexUserHooksEnabled,
            extraEnv: extraEnv
        )
        return sanitizeCursorLaunchPlanIfNeeded(rawPlan)
    }

    private func finishSessionLaunch(
        _ sanitizedPlan: AgentLaunchPlan,
        sessionID: SessionID,
        projectID: ProjectID?,
        worktree: (repository: URL, path: URL)?,
        backend: SessionBackend,
        codexUserHooksEnabled: Bool
    ) throws -> AgentLaunchPlan {
        let plan: AgentLaunchPlan
        if let worktree {
            registerOwnedWorkspace(sessionID, worktree.path, worktree.repository)
            plan = planReplacingWorkingDirectory(sanitizedPlan, with: worktree.path.path)
        } else {
            plan = sanitizedPlan
        }

        if let cwd = plan.workingDirectory {
            let workingDirectory = URL(fileURLWithPath: cwd, isDirectory: true)
            if worktree == nil, shouldTrackOwnedWorkspace(projectID: projectID) {
                try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
                registerOwnedWorkspace(sessionID, workingDirectory, nil)
            }

            // idle 検知フックは PTY 経路専用。チャットモード（appServer）は NormalizedChatEvent
            // ベースの独自ステートマシンで完了検知するため、フック設置は行わない。
            guard backend == .pty else {
                return plan
            }

            if !(plan.ref == .builtin(.codex) && codexUserHooksEnabled) {
                let hookOutcome = try sessionHooks.install(
                    descriptor: plan.descriptor,
                    sessionID: sessionID,
                    workingDirectory: workingDirectory
                )
                if hookOutcome == .skippedExistingUserFile {
                    logError(
                        WorkspaceSetupError.hooksSkippedExistingUserFile,
                        "Hooks were not installed for \(sessionID) because existing user files are present"
                    )
                }
            }
        }

        return plan
    }

    func makeSessionViewModel(
        id sessionID: SessionID,
        startedAt: Date = Date(),
        projectID: ProjectID?,
        parentSessionID: SessionID? = nil,
        name: String,
        plan: AgentLaunchPlan,
        launchContext: SessionLaunchContext = .interactive
    ) -> SessionViewModel {
        let terminalCoordinator = TerminalCoordinator()
        terminalCoordinator.applyFontSize(TerminalFontSettings.currentSize())
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        setHookContinuation(sessionID, hookContinuation)

        let spawnRequest = SessionViewModel.SpawnRequest(
            command: plan.command,
            args: plan.args,
            env: plan.env,
            workingDirectory: plan.workingDirectory,
            agentDescriptor: plan.descriptor,
            statusBootstrap: plan.statusBootstrap,
            postSpawnReset: plan.postSpawnReset,
            debugDump: plan.debugDump
        )

        let vm = SessionViewModel(
            id: sessionID,
            startedAt: startedAt,
            ptyManager: environment.pty,
            hookEvents: hookStream,
            terminalCoordinator: terminalCoordinator,
            spawnRequest: spawnRequest
        )
        vm.projectID = projectID
        vm.parentSessionID = parentSessionID
        vm.launchContext = launchContext
        vm.name = name
        TerminalPreparation.apply(plan.scrollbackPolicy, to: terminalCoordinator)
        return vm
    }

    func makeChatSessionViewModel(
        id sessionID: SessionID,
        startedAt: Date = Date(),
        projectID: ProjectID?,
        parentSessionID: SessionID? = nil,
        name: String,
        plan: AgentLaunchPlan,
        launchContext: SessionLaunchContext = .interactive,
        sessionOriginForWrite: (@MainActor () -> SessionOrigin)? = nil,
        registerSessionForWrite: (@MainActor (ChatSessionViewModel) -> Void)? = nil
    ) async throws -> ChatSessionViewModel {
        let broker = ChatApprovalBroker()
        let client = try await environment.structuredClientFactory(
            plan.descriptor.ref,
            plan.command,
            plan.workingDirectory,
            plan.env,
            broker.serverRequestHandler
        )
        // 新規 Claude/Codex チャットへ同一の履歴一覧 provider/loader を注入する。
        let history: (
            historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
            historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
        )? = switch plan.descriptor.ref {
        case .builtin(.claudeCode):
            environment.claudeSessionHistoryProviders(workingDirectory: plan.workingDirectory)
        case .builtin(.codex):
            environment.codexSessionHistoryProviders(workingDirectory: plan.workingDirectory)
        default:
            nil
        }
        let vm = ChatSessionViewModel(
            id: sessionID,
            startedAt: startedAt,
            agentRef: plan.descriptor.ref,
            client: client,
            approvalBroker: broker,
            workingDirectory: plan.workingDirectory,
            transcriptStore: environment.transcriptStore,
            // Keep the injectable seam on the production path, but source it exclusively
            // from AgentModelCatalog. The catalog is the single authority shared with the API.
            spawnAgentModelsProvider: { [ref = plan.descriptor.ref] in
                switch ref {
                case .builtin(.claudeCode):
                    return AgentModelCatalog.models(for: .claudeCode).map(\.id)
                case .builtin(.cursor):
                    return AgentModelCatalog.models(for: .cursor).map(\.id)
                default:
                    return []
                }
            },
            historyProvider: history?.historyProvider,
            historyTranscriptLoader: history?.historyTranscriptLoader
        )
        let sessionOrigin = sessionOriginForWrite?() ?? SessionOrigin(
            launchContext: launchContext,
            parentSessionID: parentSessionID
        )
        vm.projectID = projectID
        vm.parentSessionID = sessionOrigin.parentSessionID
        vm.launchContext = sessionOrigin.launchContext
        vm.name = name
        let agentID = plan.descriptor.ref.id
        vm.codexSettingsDidChange = { [weak self] settings in
            self?.persistence.persistCodexSettings(id: sessionID, settings: settings)
            if let settings {
                self?.recordLastUsedChatSettings(agentID, settings.selectedModel, settings.selectedEffort)
            }
        }
        registerSessionForWrite?(vm)
        return vm
    }

    func makeRestoreErrorSession(
        _ descriptor: PersistedSessionDescriptor,
        sessionToken: String,
        message: String,
        suppressSpawn: Bool = false
    ) -> SessionViewModel {
        let terminalCoordinator = TerminalCoordinator()
        terminalCoordinator.applyFontSize(TerminalFontSettings.currentSize())
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        setHookContinuation(descriptor.id, hookContinuation)
        let agentDescriptor = descriptorForPresentation(ref: descriptor.agentRef)
        var env = descriptor.env
        env["PHLOX_TOKEN"] = sessionToken

        let spawnRequest = SessionViewModel.SpawnRequest(
            command: descriptor.command,
            args: descriptor.args,
            env: env,
            workingDirectory: descriptor.workingDirectory,
            agentDescriptor: agentDescriptor,
            statusBootstrap: agentDescriptor.launchSpec.statusBootstrap,
            postSpawnReset: nil,
            debugDump: false
        )
        let vm = SessionViewModel(
            id: descriptor.id,
            startedAt: descriptor.startedAt,
            ptyManager: environment.pty,
            hookEvents: hookStream,
            terminalCoordinator: terminalCoordinator,
            spawnRequest: spawnRequest
        )
        vm.projectID = descriptor.projectID
        vm.parentSessionID = descriptor.parentSessionID
        vm.launchContext = descriptor.launchContext
        vm.name = descriptor.name
        if suppressSpawn {
            vm.markRestoreFailedWithoutSpawn(message)
        } else {
            vm.markRestoreFailed(message)
        }
        return vm
    }

    /// appServer（チャット）復元が失敗したときの可視プレースホルダ VM（makeRestoreErrorSession のチャット版）。
    /// `makeChatSessionViewModel` / `prepareSessionLaunch` が throw した後は実クライアントが存在しないため、
    /// 接続を張らない no-op クライアントで VM を組み、`markRestoreFailed` で失敗表示のみ行う。
    /// `startNew`/`restore` を呼ばないのでイベントループ・接続は起動せず、存在しないプロセスへの再接続で
    /// さらに throw / hang することはない。
    func makeRestoreErrorChatSession(
        _ descriptor: PersistedSessionDescriptor,
        message: String
    ) -> ChatSessionViewModel {
        let vm = ChatSessionViewModel(
            id: descriptor.id,
            startedAt: descriptor.startedAt,
            agentRef: descriptor.agentRef,
            client: DisconnectedStructuredAgentClient(),
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: descriptor.workingDirectory
        )
        vm.projectID = descriptor.projectID
        vm.parentSessionID = descriptor.parentSessionID
        vm.launchContext = descriptor.launchContext
        vm.name = descriptor.name
        vm.markRestoreFailed(message)
        return vm
    }

    func descriptorForPresentation(ref: AgentRef) -> AgentDescriptor {
        if let descriptor = environment.agentCatalog.descriptor(for: ref) {
            return descriptor
        }
        return AgentDescriptor(
            ref: ref,
            displayName: ref.id,
            binaryName: ref.id,
            symbolName: "terminal",
            colorRGB: AgentRGB(0x8A, 0x8F, 0x98),
            bypassKey: "phlox.bypass.\(ref.id)",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
    }

    func startAppServerSession(
        id sessionID: SessionID,
        ref: AgentRef,
        projectID: ProjectID?,
        parentSessionID: SessionID?,
        name: String,
        plan: AgentLaunchPlan,
        launchContext: SessionLaunchContext,
        sessionOriginForWrite: (@MainActor () -> SessionOrigin)? = nil,
        registerSessionForWrite: (@MainActor (ChatSessionViewModel) -> Void)? = nil,
        unregisterFailedSession: (@MainActor (SessionID) -> Void)? = nil
    ) async throws -> AppServerSpawnResult {
        // A2: この分岐ローカルの do/catch で後始末を閉じる（.pty 分岐の prepareSessionLaunch catch は
        // switch より前で完結しており、ここと重複解放しない）。throw 位置で解放対象が異なる:
        //  - makeChatSessionViewModel throw → chatVM 未生成なので terminate せず、token/workspace のみ解放。
        //  - startNew throw → chatVM 生成済みなので terminate() を追加で呼ぶ。
        // startNew 前に一覧登録された場合も、失敗時は unregisterFailedSession で除去する。
        // 永続化は呼び出し元で startNew 成功後に行う。
        var createdChatVM: ChatSessionViewModel?
        do {
            let chatVM = try await makeChatSessionViewModel(
                id: sessionID,
                projectID: projectID,
                parentSessionID: parentSessionID,
                name: name,
                plan: plan,
                launchContext: launchContext,
                sessionOriginForWrite: sessionOriginForWrite,
                registerSessionForWrite: registerSessionForWrite
            )
            createdChatVM = chatVM
            let persistedSettings = CursorModelListProvider.persistedSettings(
                from: lastUsedChatSettings(ref.id)
            )
            try await chatVM.startNew(
                approvalPolicy: Self.appServerApprovalPolicy(for: chatVM.launchContext),
                sandbox: Self.appServerSandboxPolicy(for: chatVM.launchContext),
                persistedSettings: persistedSettings
            )
            return AppServerSpawnResult(
                vm: chatVM,
                codexThreadId: ref == .builtin(.codex) ? chatVM.threadId : nil,
                chatNativeSessionId: chatVM.chatNativeSessionId,
                appServerUserAgent: chatVM.appServerUserAgent,
                sessionName: chatVM.name
            )
        } catch {
            unregisterFailedSession?(sessionID)
            await createdChatVM?.terminate()
            await environment.tokenStore.remove(session: sessionID)
            await cleanupOwnedWorkspace(sessionID)
            throw error
        }
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func initialResumeID(for ref: AgentRef, sessionID: SessionID) async -> String? {
        guard let descriptor = environment.agentCatalog.descriptor(for: ref) else { return nil }
        switch descriptor.launchSpec.initialResumeIDStrategy {
        case .phloxUUID:
            return sessionID.rawValue.uuidString.lowercased()
        case .cursorCreateChat:
            guard let command = environment.binaryPath(for: .cursor) else { return nil }
            // createChatID は async（terminationHandler 待ち）のため detached Task は不要（P4）。
            return try? await CursorChatCreator(
                command: command,
                pathEnvironment: environment.pathEnvironment
            ).createChatID()
        case .codexNativeFromHook, .none:
            return nil
        }
    }

    /// 明示的 projectID を優先し、未指定かつ親セッションありなら親の projectID を継承する。
    func resolveProjectID(explicit projectID: ProjectID?, parentSessionID: SessionID?) -> ProjectID? {
        if let projectID { return projectID }
        guard let parentSessionID,
              let parent = sessionNodesSnapshot().first(where: { $0.id == parentSessionID }) else {
            return nil
        }
        return parent.projectID
    }

    func resolvedWorkingDirectoryPath(projectID: ProjectID?, sessionID: SessionID) -> String? {
        if let projectID,
           let project = projectsSnapshot().first(where: { $0.id == projectID }) {
            return project.directoryPath
        }
        return nil
    }

    nonisolated static func appServerApprovalPolicy(
        for context: SessionLaunchContext,
        defaults: UserDefaults = .phloxDefaults()
    ) -> ApprovalPolicy {
        appServerPolicies(for: context, defaults: defaults).approvalPolicy
    }

    nonisolated static func appServerSandboxPolicy(
        for context: SessionLaunchContext,
        defaults: UserDefaults = .phloxDefaults()
    ) -> SandboxPolicy {
        appServerPolicies(for: context, defaults: defaults).sandbox
    }

    private nonisolated static func appServerPolicies(
        for context: SessionLaunchContext,
        defaults: UserDefaults
    ) -> (approvalPolicy: ApprovalPolicy, sandbox: SandboxPolicy) {
        let fullAccess: Bool
        switch context {
        case .interactive, .remoteUser:
            fullAccess = BypassSettings.isEnabled(for: .codex, defaults: defaults)
        case .orchestration:
            fullAccess = true
        }

        if fullAccess {
            return (.named("never"), .named("danger-full-access"))
        }
        return (.named("on-request"), .named("workspace-write"))
    }

    private func prepareWorktreeIsolation(
        project: Project?,
        sessionID: SessionID,
        intent: WorktreeIsolationIntent,
        workingDirectoryOverride: String?
    ) async throws -> (repository: URL, path: URL)? {
        guard let project else { return nil }

        let worktreePath = environment.sessionWorkspaceDirectory(for: sessionID)

        if !project.usesWorktreeIsolation {
            // 隔離を一度も使っていない通常経路は、従来どおり git を検査しない。
            // ただし、隔離を使っていたセッションを off 後に復元する場合だけは、
            // 保存済み CWD が期待パスと一致し、実在する登録済み worktree である
            // という観測事実を確認して、終了時の後始末対象として引き継ぐ。
            guard intent == .restore,
                  let workingDirectoryOverride,
                  standardizedDirectoryPath(workingDirectoryOverride)
                    == standardizedDirectoryPath(worktreePath.path) else {
                return nil
            }

            do {
                let state = try await WorktreeIsolationGit.inspect(
                    repository: project.directoryURL,
                    worktreePath: worktreePath
                )
                guard state.isGitRepository,
                      state.worktreePathExists,
                      state.isRegisteredWorktree else {
                    return nil
                }
                return (project.directoryURL, worktreePath)
            } catch {
                logError(
                    error,
                    "Failed to inspect a restored worktree while isolation is disabled for \(sessionID)"
                )
                return nil
            }
        }

        let state = try await WorktreeIsolationGit.inspect(
            repository: project.directoryURL,
            worktreePath: worktreePath
        )
        let outcome = worktreeIsolationOutcome(
            project: project,
            sessionID: sessionID,
            worktreePath: worktreePath,
            state: state,
            intent: intent
        )
        return try await applyWorktreeIsolationOutcome(
            outcome,
            project: project
        )
    }

    private func worktreeIsolationOutcome(
        project: Project,
        sessionID: SessionID,
        worktreePath: URL,
        state: WorktreeIsolationRepositoryState,
        intent: WorktreeIsolationIntent
    ) -> WorktreeIsolationOutcome {
        WorktreeIsolationPlanner.plan(
            project: project,
            sessionID: sessionID,
            sessionWorkspaceDirectory: worktreePath.path,
            isGitRepository: state.isGitRepository,
            existingBranchNames: state.localBranchNames,
            worktreePathExists: state.worktreePathExists,
            isRegisteredWorktree: state.isRegisteredWorktree,
            intent: intent
        )
    }

    private func applyWorktreeIsolationOutcome(
        _ outcome: WorktreeIsolationOutcome,
        project: Project
    ) async throws -> (repository: URL, path: URL)? {
        switch outcome {
        case .disabled:
            return nil
        case .abort(let failure):
            throw WorktreeIsolationSpawnError.aborted(failure)
        case .reuse(let path, _):
            return (project.directoryURL, URL(fileURLWithPath: path, isDirectory: true))
        case .create(let path, let branchName), .recreate(let path, let branchName):
            let pathURL = URL(fileURLWithPath: path, isDirectory: true)
            let branchWasPreexisting: Bool
            let createsBranch: Bool
            switch outcome {
            case .create:
                branchWasPreexisting = false
                createsBranch = true
            case .recreate:
                branchWasPreexisting = true
                createsBranch = false
            default:
                preconditionFailure("worktree creation case was already narrowed")
            }
            do {
                try await WorktreeIsolationGit.addWorktree(
                    at: pathURL,
                    branchName: branchName,
                    in: project.directoryURL,
                    createsBranch: createsBranch,
                    pruneStaleWorktrees: branchWasPreexisting
                )
            } catch {
                let rollbackDetail: String?
                do {
                    rollbackDetail = try await WorktreeIsolationGit.rollbackFailedWorktreeCreation(
                        path: pathURL,
                        branchName: branchName,
                        repository: project.directoryURL,
                        branchWasPreexisting: branchWasPreexisting,
                        workspaceDirectory: environment.workspaceDirectory
                    )
                } catch {
                    rollbackDetail = "作成途中の worktree の後始末を実行できませんでした: \(error.localizedDescription)"
                }
                let detail = [error.localizedDescription, rollbackDetail]
                    .compactMap { $0 }
                    .joined(separator: " ")
                throw WorktreeIsolationSpawnError.worktreeCreationFailed(
                    path: path,
                    branchName: branchName,
                    detail: detail
                )
            }
            return (project.directoryURL, pathURL)
        }
    }

    private func planReplacingWorkingDirectory(
        _ plan: AgentLaunchPlan,
        with path: String
    ) -> AgentLaunchPlan {
        AgentLaunchPlan(
            command: plan.command,
            args: plan.args,
            env: plan.env,
            workingDirectory: path,
            ref: plan.ref,
            descriptor: plan.descriptor,
            scrollbackPolicy: plan.scrollbackPolicy,
            statusBootstrap: plan.statusBootstrap,
            postSpawnReset: plan.postSpawnReset,
            debugDump: plan.debugDump
        )
    }

    private func sanitizeCursorLaunchPlanIfNeeded(_ plan: AgentLaunchPlan) -> AgentLaunchPlan {
        guard plan.ref.builtinKind == .cursor else { return plan }
        let env = CursorShellSanitizer.sanitizedLaunchEnvironment(fallback: plan.env)
        // NOTE: env 以外は全フィールドをそのまま複製する。AgentLaunchPlan に stored
        // プロパティを追加したらここも更新すること（デフォルト値付きだと memberwise init が
        // 省略でき、新フィールドが silent に欠落しうる）。
        return AgentLaunchPlan(
            command: plan.command,
            args: plan.args,
            env: env,
            workingDirectory: plan.workingDirectory,
            ref: plan.ref,
            descriptor: plan.descriptor,
            scrollbackPolicy: plan.scrollbackPolicy,
            statusBootstrap: plan.statusBootstrap,
            postSpawnReset: plan.postSpawnReset,
            debugDump: plan.debugDump
        )
    }

    private func shouldTrackOwnedWorkspace(projectID: ProjectID?) -> Bool {
        guard let projectID else { return true }
        guard let project = projectsSnapshot().first(where: { $0.id == projectID }) else { return false }
        return project.isManagedDirectory
    }

    private func standardizedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
