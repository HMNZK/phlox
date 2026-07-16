import Foundation
import AgentDomain
import DesignSystem
import HookServer
import PTYKit
import Security
import TerminalUI
import CodexAppServerKit
import SessionFeature

// 隠している秘密: launch plan 生成・VM 生成・env/token 組み立て・appServer throw 後始末の詳細。

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
    private let registerOwnedWorkspace: @MainActor (SessionID, URL) -> Void
    private let cleanupOwnedWorkspace: @MainActor (SessionID) -> Void
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
        registerOwnedWorkspace: @escaping @MainActor (SessionID, URL) -> Void,
        cleanupOwnedWorkspace: @escaping @MainActor (SessionID) -> Void,
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

    func prepareSessionLaunch(
        ref: AgentRef,
        sessionID: SessionID,
        sessionToken: String,
        workingDirectoryOverride: String?,
        projectID: ProjectID?,
        launchMode: AgentLaunchMode = .newSession(),
        backend: SessionBackend = .pty,
        extraEnv: [String: String] = [:]
    ) throws -> AgentLaunchPlan {
        let planner = AgentLaunchPlanner()
        let bypassEnabled = BypassSettings.isEnabled(for: ref, catalog: environment.agentCatalog)
        let codexUserHooksEnabled = codexUserHooksEnabledProvider()
        let rawPlan = try planner.plan(
            ref: ref,
            environment: environment,
            sessionID: sessionID,
            sessionToken: sessionToken,
            workingDirectoryOverride: workingDirectoryOverride,
            launchMode: launchMode,
            backend: backend,
            bypassEnabled: bypassEnabled,
            codexUserHooksEnabled: codexUserHooksEnabled,
            extraEnv: extraEnv
        )
        let plan = sanitizeCursorLaunchPlanIfNeeded(rawPlan)

        if let cwd = plan.workingDirectory {
            let workingDirectory = URL(fileURLWithPath: cwd, isDirectory: true)
            if shouldTrackOwnedWorkspace(projectID: projectID) {
                try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
                registerOwnedWorkspace(sessionID, workingDirectory)
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
        launchContext: SessionLaunchContext = .interactive
    ) async throws -> ChatSessionViewModel {
        let broker = ChatApprovalBroker()
        let client = try await environment.structuredClientFactory(
            plan.descriptor.ref,
            plan.command,
            plan.workingDirectory,
            plan.env,
            broker.serverRequestHandler
        )
        // Claude 新規チャットに履歴一覧 provider/loader を注入（task-9。Claude 以外は nil）。
        let history = plan.descriptor.ref == .builtin(.claudeCode)
            ? environment.claudeSessionHistoryProviders(workingDirectory: plan.workingDirectory)
            : nil
        let vm = ChatSessionViewModel(
            id: sessionID,
            startedAt: startedAt,
            agentRef: plan.descriptor.ref,
            client: client,
            approvalBroker: broker,
            workingDirectory: plan.workingDirectory,
            transcriptStore: environment.transcriptStore,
            spawnAgentModelsProvider: CursorModelListProvider.makeSpawnAgentModelsProvider(
                ref: plan.descriptor.ref,
                command: plan.command,
                env: plan.env,
                workingDirectory: plan.workingDirectory
            ),
            historyProvider: history?.historyProvider,
            historyTranscriptLoader: history?.historyTranscriptLoader
        )
        vm.projectID = projectID
        vm.parentSessionID = parentSessionID
        vm.launchContext = launchContext
        vm.name = name
        let agentID = plan.descriptor.ref.id
        vm.codexSettingsDidChange = { [weak self] settings in
            self?.persistence.persistCodexSettings(id: sessionID, settings: settings)
            if let settings {
                self?.recordLastUsedChatSettings(agentID, settings.selectedModel, settings.selectedEffort)
            }
        }
        return vm
    }

    func makeRestoreErrorSession(
        _ descriptor: PersistedSessionDescriptor,
        sessionToken: String,
        message: String
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
        vm.markRestoreFailed(message)
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
        launchContext: SessionLaunchContext
    ) async throws -> AppServerSpawnResult {
        // A2: この分岐ローカルの do/catch で後始末を閉じる（.pty 分岐の prepareSessionLaunch catch は
        // switch より前で完結しており、ここと重複解放しない）。throw 位置で解放対象が異なる:
        //  - makeChatSessionViewModel throw → chatVM 未生成なので terminate せず、token/workspace のみ解放。
        //  - startNew throw → chatVM 生成済みなので terminate() を追加で呼ぶ。
        // どちらも sessionNodes へは未 append（append は startNew 成功後）・未永続化（persistSession は switch の後）。
        var createdChatVM: ChatSessionViewModel?
        do {
            let chatVM = try await makeChatSessionViewModel(
                id: sessionID,
                projectID: projectID,
                parentSessionID: parentSessionID,
                name: name,
                plan: plan,
                launchContext: launchContext
            )
            createdChatVM = chatVM
            let persistedSettings = CursorModelListProvider.persistedSettings(
                from: lastUsedChatSettings(ref.id)
            )
            try await chatVM.startNew(
                approvalPolicy: Self.appServerApprovalPolicy(for: launchContext),
                sandbox: Self.appServerSandboxPolicy(for: launchContext),
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
            await createdChatVM?.terminate()
            await environment.tokenStore.remove(session: sessionID)
            cleanupOwnedWorkspace(sessionID)
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

    static func appServerApprovalPolicy(for context: SessionLaunchContext) -> ApprovalPolicy {
        switch context {
        case .interactive:
            .named("on-request")
        case .orchestration:
            .named("never")
        }
    }

    static func appServerSandboxPolicy(for context: SessionLaunchContext) -> SandboxPolicy {
        switch context {
        case .interactive:
            .named("workspace-write")
        case .orchestration:
            .named("danger-full-access")
        }
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
}
