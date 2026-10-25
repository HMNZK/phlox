import AppKit
import Foundation
import AgentDomain
import ControlServer
import DesignSystem
import HookServer
import MessageStore
import PTYKit
import TerminalUI
import Observation
import Security
import CodexAppServerKit
import StructuredChatKit
import SessionFeature

public enum WorkspaceCleanupWarning: Codable, Equatable, Sendable {
    case worktreeRetained(path: String)
    case branchRetained(branchName: String)
    /// worktree でない作業フォルダを消せなかった。`path` は消せなかったファイル（分からなければフォルダ）。
    case workspaceRetained(path: String)

    public var title: String {
        switch self {
        case .workspaceRetained:
            return "作業フォルダを片付けられませんでした"
        case .worktreeRetained:
            return "セッション用 worktree を残しています"
        case .branchRetained:
            return "セッション用ブランチを残しています"
        }
    }

    public var message: String {
        switch self {
        case .worktreeRetained(let path):
            return "セッション用 worktree を削除できませんでした。未コミット変更がある場合は worktree を残しています: \(path)"
        case .branchRetained(let branchName):
            return "worktree は削除しましたが、セッション用ブランチを削除できませんでした。ブランチを確認してください: \(branchName)"
        case .workspaceRetained(let path):
            return "作業フォルダを削除できなかったため、次の場所に残しています: \(path)"
        }
    }
}

/// セッション一覧と新規作成・削除を担当する。
///
/// API 契約 (M6a で本実装、M6b は本シグネチャに依存):
/// - `init` の引数を変更しないこと
/// - public プロパティ / メソッドの追加は可、削除・名称変更は不可
@MainActor
@Observable
public final class DashboardViewModel {
    public var claudeUsageDidChange: ((AgentRateLimitsSnapshot, UUID) -> Void)?
    private enum APISpawnLimitSource {
        case parent(SessionID?)
        case controlRequester(SessionID?)
    }

    private struct OwnedWorkspace {
        let directory: URL
        let worktreeRepository: URL?
    }

    public private(set) var sessions: [SessionViewModel] = []
    public private(set) var sessionNodes: [SessionNode] = []

    /// 未確認の完了(.running→.idle になり、まだ選択されていない)セッション数。Dock バッジに使う。
    public private(set) var unseenCompletionCount: Int = 0
    @ObservationIgnored public var unseenCompletionCountDidChange: ((Int) -> Void)?

    /// セッション生成が成功した直後に呼ばれる疎結合コールバック。
    /// DashboardFeature を解析 SDK に依存させないため、App 層がここに購読して配線する。
    /// 渡すのは AgentKind のみ（PII なし）。
    @ObservationIgnored public var sessionDidSpawn: ((AgentRef) -> Void)?

    public private(set) var projects: [Project] = []
    /// worktree の削除を安全に拒否したとき、ユーザーへ残置を伝えるための警告。
    public private(set) var workspaceCleanupWarning: WorkspaceCleanupWarning?
    /// 後始末に失敗した理由（git の出力の 1 行目。09 D2 の「（Permission denied）」）。
    public private(set) var workspaceCleanupFailureReason: String?
    public private(set) var restoredSessionPresentation: RestoredSessionPresentation?
    public private(set) var discardedSessionCountNotice: Int?

    /// グリッドに表示するセッションの選択（nil = 全表示）。永続化しない。
    /// 絞り込みは描画時の刈り込み（`paneLayoutForDisplay()`）だけで表現し、
    /// 永続ツリーには触れない（隠したセッションの位置を失わないため）。
    public var gridSessionSelection: Set<SessionID>? {
        didSet { if gridSessionSelection != oldValue { gridTemporarySessionID = nil } }
    }
    /// グリッドのワークスペース絞り込み（`AppRouter.gridFilterProjectID` の写し。候補算出用）。
    var gridSessionFilterProjectID: ProjectID? {
        didSet { if gridSessionFilterProjectID != oldValue { gridTemporarySessionID = nil } }
    }
    /// 通知から範囲外のセッションを開いたとき、一時的にグリッドへ加える 1 件（11）。範囲を変えると外れる。
    public private(set) var gridTemporarySessionID: SessionID?

    private static let readinessPollInterval: Duration = .milliseconds(20)
    private static let donePollInterval: Duration = .milliseconds(100)
    /// API 経由 spawn の制限値（実体は SpawnPolicy、R2）。
    static let maxAPISpawnDepth = SpawnPolicy.maxAPISpawnDepth
    static let maxAPISpawnCountPerSecond = SpawnPolicy.maxAPISpawnCountPerSecond
    static let apiSpawnRateLimitWindowSeconds = SpawnPolicy.apiSpawnRateLimitWindowSeconds

    private struct OwnedServices {
        let environment: AppEnvironment
        let sessionHooks: SessionHookInstaller
        let persistence: SessionPersistenceCoordinator
        let messaging: MessagingService
        let codexDiscoveryNow: @Sendable () -> Date
        let rateLimitNow: @Sendable () -> Date
        let livePIDProvider: @MainActor @Sendable (SessionID) async -> pid_t?
    }

    @ObservationIgnored private var ownedServices: OwnedServices?
    @ObservationIgnored private var runtimeCommandHandler: DashboardRuntimeCommandHandler?
    @ObservationIgnored private var runtimeProjectionSnapshot: DashboardRuntimeSnapshot?
    @ObservationIgnored private var runtimeCommandTail: Task<Void, Never>?
    @ObservationIgnored private var pendingRuntimeCommandCount = 0
    @ObservationIgnored private var pendingRuntimeControlCount = 0
    private struct RuntimeFirstMessage {
        let operationID: UUID
        let task: Task<Void, Never>
    }
    @ObservationIgnored private var runtimeFirstMessages: [SessionID: RuntimeFirstMessage] = [:]
    private enum FirstMessageDelivery {
        case awaitDelivery
        case acceptIntoRuntime
    }
    @ObservationIgnored private var hasAppliedInitialRuntimePresentation = false
    public private(set) var runtimeCommandError: String?
    private var historyNames: [SessionHistoryKey: String] = [:]
    public var isRuntimeProjection: Bool { runtimeCommandHandler != nil }

    private var requiredOwnedServices: OwnedServices {
        guard let ownedServices else { preconditionFailure("Runtime projection cannot access execution services") }
        return ownedServices
    }
    private var environment: AppEnvironment { requiredOwnedServices.environment }
    private var sessionHooks: SessionHookInstaller { requiredOwnedServices.sessionHooks }
    private var persistence: SessionPersistenceCoordinator { requiredOwnedServices.persistence }
    private var messaging: MessagingService { requiredOwnedServices.messaging }
    /// 起動時の復元中は永続化を抑止する（復元途中の中間状態を書き戻さない）。
    @ObservationIgnored private var layoutRestoreInProgress = true
    /// 起動時のセッション復元が済んだか。前回の起動の通知を片付けるのは、これが済んでから（11）。
    public private(set) var hasRestoredSessions = false

    public private(set) var gridLayoutState: GridLayoutState
    public var paneLayout: PaneTree {
        gridLayoutState.customLayout?.tree ?? PaneLayoutPreset.balanced.tree(for: sessionNodes.map(\.id))
    }
    public var paneLayoutPresetState: PaneLayoutStore.PresetState { gridLayoutState.customLayout?.presetState ?? .init() }
    @ObservationIgnored public var gridCanvasSize = CGSize(width: 540, height: 440)
    @ObservationIgnored private let paneLayoutStore: PaneLayoutStore?
    private var hookMultiplexTask: Task<Void, Never>?
    private var sessionHookContinuations: [SessionID: AsyncStream<(SessionID, HookEvent)>.Continuation] = [:]
    private var spawnTimestamps: [SessionID: [Date]] = [:]
    private var unattributedControlAPISpawnTimestamps: [Date] = []
    private var ownedWorkspaceDirectories: [SessionID: OwnedWorkspace] = [:]
    /// アゴラ討論の実セッション配線。UI はここから phase/participants などを読む。
    @ObservationIgnored private var spawnService: SessionSpawnService?
    /// 画面からの起動だけを 08 F2 の案内の対象にする。API・スマホからの起動のパスは出さない。
    @TaskLocal static var reportsWorktreeCreation = false
    @TaskLocal static var newChatHistoryLoader: (@Sendable () throws -> [ClaudeSessionHistoryEntry])?
    /// 画面からの起動がいま作っている worktree のパス（作り始めた順）。
    private var worktreeCreationPaths: [String] = []
    /// 08 F2 の案内に出す worktree のパス。作っていなければ nil。
    /// ponytail: 画面からの起動が重なったら先に作り始めたものを出す。起動ごとに出し分けるなら起動の識別子を案内まで渡す。
    public var worktreeCreationPath: String? { runtimeProjectionSnapshot?.worktreeCreationPath ?? worktreeCreationPaths.first }
    /// 復元で前回の worktree を作り直す前にたずねる（09 E2）。引数はパス・ブランチ・ブランチが残っているか。
    /// アプリは `start()` の前に置く。nil なら確認しない。
    @ObservationIgnored public var worktreeRecreationConfirmer: (@MainActor (_ path: String, _ branchName: String, _ branchExists: Bool) -> Bool)?
    @ObservationIgnored private var restoreCoordinator: SessionRestoreCoordinator?
    /// 「この会話から再開」の処理中のセッション（続けて押しても 2 つ目のプロセスを作らない）。
    @ObservationIgnored private var resumingChatSessionIDs: Set<SessionID> = []
    @ObservationIgnored private var removingSessionIDs: Set<SessionID> = []
    private var codexDiscoveryNow: @Sendable () -> Date { requiredOwnedServices.codexDiscoveryNow }
    /// send/spawn のレート制限に使う現在時刻シーム。既定は実時計。テストは固定時刻を
    /// 注入してスライディングウィンドウを決定論化する（実時計依存の断続的失敗の除去）。
    private var rateLimitNow: @Sendable () -> Date { requiredOwnedServices.rateLimitNow }
    /// spawn 後に当該セッションの live pid を引くための seam。永続化する pid の取得元。
    /// 既定は nil（pid 未捕捉＝従来挙動。descriptor の pid は nil のまま）。
    /// PTYManager は actor で pid アクセサが actor 隔離 async のため、seam も async とし
    /// CompositionRoot で `{ id in await pty.pid(for: id) }` を渡す。pid 未取得時は nil
    /// フォールバック（後方互換）。
    private var livePIDProvider: @MainActor @Sendable (SessionID) async -> pid_t? { requiredOwnedServices.livePIDProvider }
    /// rollout 走査で claim 済みの native id（永続化完了前の二重割当防止）。
    @ObservationIgnored private var codexDiscovery: CodexNativeSessionDiscoveryController?
    private var lastUsedChatSettingsStore = LastUsedChatSettingsStore()
    private var failedNewChatRequests: [SessionID: NewChatLaunchRequest] = [:]
    public private(set) var restartingNewChatIDs: Set<SessionID> = []

    /// task-3: sessionNodes の ID→ノード索引（`sessionNode(id:)` の O(1) 参照用）。
    /// `sessionNodes` への追加・削除は必ず `appendSessionNode`/`removeSessionNode` を経由させ、
    /// この索引を同期させること。ADR 0010: body 評価中に @Observable state を書き換えないよう、
    /// 非観測ストレージ（@ObservationIgnored）に置く。
    @ObservationIgnored private var sessionNodeIndex: [SessionID: SessionNode] = [:]

    /// task-3: `sessionForest(in:)` の結果キャッシュ。キーは projectID。
    /// 呼び出しごとに `sessionTreeInputs(for:)`（フラットな値スナップショット、Equatable）を再計算し、
    /// 前回キャッシュした入力と一致すれば forest を再利用、不一致なら再構築してキャッシュを更新する。
    /// 内容ベースの無効化のため、追加・削除・親子変更・改名・ステータス変更のいずれでも
    /// 取りこぼしなく反映される（個別のミューテーション経路を列挙して invalidate する必要がない）。
    /// ADR 0010: 読み取り関数内での更新のため非観測ストレージ（@ObservationIgnored）に置く。
    @ObservationIgnored private var sessionForestCache: [ProjectID: (inputs: [SessionTreeInput], forest: [SessionTreeNode])] = [:]

    var lastUsedChatSettingsStoreForTesting: LastUsedChatSettingsStore {
        get { lastUsedChatSettingsStore }
        set { lastUsedChatSettingsStore = newValue }
    }

    private init(projectionCommandHandler: @escaping DashboardRuntimeCommandHandler, paneLayoutStore: PaneLayoutStore?) {
        self.paneLayoutStore = paneLayoutStore
        self.gridLayoutState = paneLayoutStore?.loadState() ?? .automatic(previousCustom: nil)
        self.runtimeCommandHandler = projectionCommandHandler
    }

    public init(
        environment: AppEnvironment,
        codexUserHooksEnabledProvider: @escaping @MainActor () -> Bool = {
            CodexUserHooksSettings.isEnabled()
        },
        codexDiscoveryRetryInterval: Duration = .milliseconds(500),
        codexDiscoveryMaxRetryDuration: Duration = .seconds(120),
        codexDiscoveryNow: @escaping @Sendable () -> Date = Date.init,
        rateLimitNow: @escaping @Sendable () -> Date = Date.init,
        orphanReaper: any OrphanReaper = PosixOrphanReaper(),
        livePIDProvider: @escaping @MainActor @Sendable (SessionID) async -> pid_t? = { _ in nil },
        paneLayoutStore: PaneLayoutStore? = PaneLayoutStore(userDefaults: .phloxDefaults())
    ) {
        self.paneLayoutStore = paneLayoutStore
        self.gridLayoutState = paneLayoutStore?.loadState() ?? .automatic(previousCustom: nil)
        let sessionHooks = SessionHookInstaller(
            dispatcherPath: environment.hookDispatcherPath,
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        let persistence = SessionPersistenceCoordinator(
            sessionStore: environment.sessions,
            projectStore: environment.projects,
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        let messaging = MessagingService(
            pty: environment.pty,
            messages: environment.messages,
            now: rateLimitNow
        )
        self.ownedServices = OwnedServices(environment: environment, sessionHooks: sessionHooks,
                                           persistence: persistence, messaging: messaging,
                                           codexDiscoveryNow: codexDiscoveryNow, rateLimitNow: rateLimitNow,
                                           livePIDProvider: livePIDProvider)
        self.spawnService = SessionSpawnService(
            environment: environment,
            persistence: persistence,
            sessionHooks: sessionHooks,
            codexUserHooksEnabledProvider: codexUserHooksEnabledProvider,
            sessionNodesSnapshot: { [weak self] in self?.sessionNodes ?? [] },
            projectsSnapshot: { [weak self] in self?.projects ?? [] },
            setHookContinuation: { [weak self] sessionID, continuation in
                self?.sessionHookContinuations[sessionID] = continuation
            },
            registerOwnedWorkspace: { [weak self] sessionID, url, worktreeRepository in
                self?.ownedWorkspaceDirectories[sessionID] = OwnedWorkspace(
                    directory: url,
                    worktreeRepository: worktreeRepository
                )
            },
            cleanupOwnedWorkspace: { [weak self] sessionID in
                await self?.cleanupOwnedWorkspace(for: sessionID)
            },
            lastUsedChatSettings: { [weak self] agentID in
                self?.lastUsedChatSettingsStore.lastUsed(agentID: agentID)
            },
            recordLastUsedChatSettings: { [weak self] agentID, settings in
                self?.lastUsedChatSettingsStore.record(
                    agentID: agentID,
                    model: settings.selectedModel,
                    effort: settings.selectedEffort,
                    permission: settings.selectedPermissionProfile,
                    isPlanMode: settings.isPlanMode
                )
            },
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        spawnService?.historyEntriesProvider = { [weak self] ref, directories in
            guard let self else { return [] }
            return try await self.loadHistoryEntries(agentRef: ref, workingDirectories: directories)
        }
        spawnService?.historyEntriesFilter = { [weak self] ref, entries in
            self?.availableHistoryEntries(entries, agentRef: ref) ?? []
        }
        spawnService?.onClaudeUsage = { [weak self] snapshot, id in self?.claudeUsageDidChange?(snapshot, id) }
        spawnService?.onWorktreeCreation = { [weak self] path, isStarting in
            guard let self, Self.reportsWorktreeCreation else { return }
            if isStarting {
                worktreeCreationPaths.append(path)
            } else if let index = worktreeCreationPaths.firstIndex(of: path) {
                worktreeCreationPaths.remove(at: index)
            }
        }
        spawnService?.onWorktreeCreated = { [weak self] projectID, path in
            guard let self, let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
            var paths = projects[index].worktreePaths ?? []
            guard !paths.contains(where: { Self.standardizedDirectoryPath($0) == Self.standardizedDirectoryPath(path) }) else { return }
            paths.append(path)
            projects[index].worktreePaths = paths
            persistProjects()
        }
        spawnService?.confirmWorktreeRecreation = { [weak self] path, branch, branchExists in
            self?.worktreeRecreationConfirmer?(path, branch, branchExists) ?? true
        }
        self.codexDiscovery = CodexNativeSessionDiscoveryController(
            environment: environment,
            persistence: persistence,
            retryInterval: codexDiscoveryRetryInterval,
            maxRetryDuration: codexDiscoveryMaxRetryDuration,
            now: codexDiscoveryNow,
            sessionsSnapshot: { [weak self] in self?.sessions ?? [] },
            sessionNodesSnapshot: { [weak self] in self?.sessionNodes ?? [] }
        )
        self.restoreCoordinator = SessionRestoreCoordinator(
            environment: environment,
            persistence: persistence,
            spawnService: self.spawnService!,
            codexDiscovery: self.codexDiscovery!,
            orphanReaper: orphanReaper,
            codexNow: codexDiscoveryNow,
            livePIDProvider: livePIDProvider,
            appendPTYSession: { [weak self] vm in
                self?.observeUnseenCompletion(for: vm)
                self?.sessions.append(vm)
                self?.appendSessionNode(.pty(vm))
                self?.refreshUnseenCompletionCount()
            },
            appendAppServerSession: { [weak self] vm in
                self?.observeUnseenCompletion(for: vm)
                self?.appendSessionNode(.appServer(vm))
                self?.refreshUnseenCompletionCount()
            },
            refreshUnseenCompletionCount: { [weak self] in
                self?.refreshUnseenCompletionCount()
            },
            publishRestoredSessionPresentation: { [weak self] in
                self?.publishRestoredSessionPresentation()
            },
            privilegedRequesterProvider: { [weak self] in
                self?.privilegedRequesters ?? []
            },
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        self.persistence.liveTitleState = { [weak self] id in
            self?.sessionNode(id: id)?.titleState
        }
    }

    private var codexDiscoveryController: CodexNativeSessionDiscoveryController {
        guard let codexDiscovery else {
            preconditionFailure("Codex discovery controller must be initialized")
        }
        return codexDiscovery
    }

    private var sessionSpawnService: SessionSpawnService {
        guard let spawnService else {
            preconditionFailure("Session spawn service must be initialized")
        }
        return spawnService
    }

    private var sessionRestoreCoordinator: SessionRestoreCoordinator {
        guard let restoreCoordinator else {
            preconditionFailure("Session restore coordinator must be initialized")
        }
        return restoreCoordinator
    }

    var codexDiscoveryTaskCountForTesting: Int {
        codexDiscoveryController.taskCount
    }

    /// 永続化直列チェーンの保留書き込みが全て完了するまで待つ（テスト用の決定的待機）。
    /// 削除など enqueue 済みの保存を、任意 sleep でなく確定的にドレインして検証できるようにする。
    func waitForPendingPersistenceWritesForTesting() async {
        await persistence.waitForPendingWrites()
    }

    public func takeDiscardedSessionCountNotice() -> Int? {
        if isRuntimeProjection { enqueueProjectedAction(.takeDiscardedSessionCountNotice) }
        defer { discardedSessionCountNotice = nil }
        return discardedSessionCountNotice
    }

    private func observeUnseenCompletion(for session: any ControllableSession) {
        let sessionID = session.id
        session.userNotificationGate = { [weak self] channel in
            let client: SessionSurfaceClient = switch channel {
            case .local: .desktop
            case .remote: .mobile
            }
            return self?.isReachableFromUI(sessionID, from: client) ?? true
        }
        session.unseenCompletionDidChange = { [weak self] in
            self?.refreshUnseenCompletionCount()
        }
        if let chat = session as? ChatSessionViewModel {
            chat.titleStateDidChange = { [weak self] state in
                self?.persistence.persistSessionName(id: sessionID, name: state.name)
            }
            chat.resumeConversationHandler = { [weak self] in
                Task { await self?.resumeEndedChatSession(sessionID) }
            }
        }
    }

    /// 04 B3「この会話から再開」: プロセスが終わったチャットを、保存済みの会話 ID から新しいプロセスで開き直す。
    /// 起動時の復元と同じ経路で VM を作り直し、会話を読み込み終えてから同じ位置のノードを差し替える
    /// （先に差し替えると、空の会話で開いたビューが末尾へ寄らない）。
    func resumeEndedChatSession(_ id: SessionID) async {
        if isRuntimeProjection {
            await performProjectedAction(.resumeChat(id))
            return
        }
        guard case .appServer(let ended) = sessionNode(id: id), ended.processExit != nil,
              resumingChatSessionIDs.insert(id).inserted else { return }
        defer { resumingChatSessionIDs.remove(id) }
        await ended.terminate()
        guard let resumed = await sessionRestoreCoordinator.resumeChatSession(id: id) else {
            ended.markRestoreFailed("chat restore failed: missing session record")
            return
        }
        // 開き直せなかったら差し替えない。終わった会話に理由を出し、再開ボタンを残してやり直せるようにする。
        if case .failed(let message) = resumed.restoreState {
            await resumed.terminate()
            ended.markRestoreFailed(message)
            return
        }
        // 開き直している間に閉じられたら、新しいプロセスを画面に出さずに止める（残すと誰も止めない）。
        guard !removingSessionIDs.contains(id), case .appServer(let current) = sessionNode(id: id), current === ended else {
            await resumed.terminate()
            await environment.tokenStore.remove(session: id)
            return
        }
        observeUnseenCompletion(for: resumed)
        replaceSessionNode(.appServer(resumed))
        refreshUnseenCompletionCount()
    }

    private func refreshUnseenCompletionCount() {
        // PTY / Chat 両種別を node レベルで数える（Dock バッジは「要対応セッション数」）。
        let count = sessionNodes.filter {
            $0.hasUnseenCompletion && isReachableFromUI($0.id, from: .desktop)
        }.count
        guard count != unseenCompletionCount else { return }
        unseenCompletionCount = count
        unseenCompletionCountDidChange?(count)
    }

    /// M6a で実装。HookServer の events ストリームを購読し、SessionViewModel へディスパッチする。
    /// セッション復元: 保存 descriptor を現在の環境で再 plan し、アプリ内蔵 PTY で再 spawn する。
    public func start() async {
        guard !isRuntimeProjection else { return }
        guard hookMultiplexTask == nil else { return }

        projects = await environment.projects.load()

        let hookDeliveries = environment.hook.deliveries
        hookMultiplexTask = Task { @MainActor [weak self] in
            for await delivery in hookDeliveries {
                await self?.codexDiscoveryController.persistCodexResumeIDIfNeeded(
                    sessionID: delivery.sessionID,
                    nativeSessionId: delivery.nativeSessionId
                )
                self?.sessionHookContinuations[delivery.sessionID]?.yield((delivery.sessionID, delivery.event))
            }
        }

        await sessionRestoreCoordinator.restorePersistedSessions()
        let discardedCount = await environment.sessions.takeDiscardedSessionCount()
        if discardedCount > 0 { discardedSessionCountNotice = discardedCount }
        layoutRestoreInProgress = false
        hasRestoredSessions = true
        reloadAndReconcilePaneLayout()
    }

    /// セッション用 worktree の置き場所。
    var sessionWorkspaceRoot: URL {
        if let snapshot = runtimeProjectionSnapshot, let root = snapshot.workspaceRoot { return root }
        guard !isRuntimeProjection else { preconditionFailure("Runtime snapshot has no workspace root") }
        return environment.workspaceDirectory
    }

    /// 新規チャットで選べる CLI。解決できた組込 CLI だけを返す。
    public var availableAgentKinds: [AgentKind] {
        if let runtimeProjectionSnapshot { return runtimeProjectionSnapshot.availableAgentKinds }
        return [.claudeCode] + AgentRegistry.optionalBinaryKinds.filter { environment.binaryPath(for: $0) != nil }
    }

    public func defaultProjectIDForNewChat(selectedProjectID: ProjectID?, selectedSessionID: SessionID?) -> ProjectID? {
        if let selectedProjectID { return selectedProjectID }
        if let selectedSessionID,
           let projectID = sessionNode(id: selectedSessionID)?.projectID {
            return projectID
        }
        return projects.count == 1 ? projects.first?.id : nil
    }

    /// 指定ワークスペース（Project）に属するセッション一覧。
    public func sessions(in projectID: ProjectID) -> [SessionViewModel] {
        sessions.filter { $0.projectID == projectID }
    }

    public func sessionNodes(in projectID: ProjectID) -> [SessionNode] {
        sessionNodes.filter { $0.projectID == projectID && Self.isVisibleInSidebar($0) }
    }

    /// 上段のセッションタブの候補。サイドバーの行に加え、親の下にいる内部セッション（`.orchestration`）も入れる（03 G3・06 Grid の決定）。
    public func tabSessionNodes(in projectID: ProjectID) -> [SessionNode] {
        sessionNodes.filter { $0.projectID == projectID && isShownOnSessionSurfaces($0) }
    }

    /// ワークスペース絞り込みグリッド用。サイドバー用の sessionNodes(in:) と違い .orchestration サブセッションも含む。
    public func gridSessionNodes(in projectID: ProjectID) -> [SessionNode] {
        sessionNodes.filter { $0.projectID == projectID }
    }

    public func sessionForest(in projectID: ProjectID) -> [SessionTreeNode] {
        let inputs = sessionTreeInputs(for: projectID)
        if let cached = sessionForestCache[projectID], cached.inputs == inputs {
            return cached.forest
        }
        let forest = SessionTree.buildForest(from: inputs)
            .filter { Self.isVisibleInSidebar(launchContext: $0.launchContext) }
        sessionForestCache[projectID] = (inputs: inputs, forest: forest)
        return forest
    }

    public func hasUnseenCompletion(in projectID: ProjectID) -> Bool {
        containsSidebarSession(in: projectID) { $0.hasUnseenCompletion }
    }

    public func requiresAttention(for node: SessionNode) -> Bool {
        SessionAttentionPolicy.requiresAttention(
            status: node.status,
            hasUnseenCompletion: node.hasUnseenCompletion
        )
    }

    /// サイドバーのプロジェクト欄赤表示用。配下セッションのいずれかが `requiresAttention` なら true。
    public func hasAttention(in projectID: ProjectID) -> Bool {
        containsSidebarSession(in: projectID) { requiresAttention(for: $0) }
    }

    private func containsSidebarSession(
        in projectID: ProjectID,
        where predicate: (SessionNode) -> Bool
    ) -> Bool {
        let sidebarNodeIDs = Set(sessionForest(in: projectID).flatMap(Self.sessionTreeNodeIDs))
        return sessionNodes.contains { node in
            sidebarNodeIDs.contains(node.id) && predicate(node)
        }
    }

    public func sessionNode(id: SessionID) -> SessionNode? {
        sessionNodeIndex[id]
    }

    /// `sessionNodes` への追加は必ずこのヘルパー経由で行い、`sessionNodeIndex` の同期漏れを防ぐ。
    private func appendSessionNode(_ node: SessionNode) {
        sessionNodes.append(node)
        sessionNodeIndex[node.id] = node
        if !layoutRestoreInProgress { gridSessionSelectionDidSpawn(node.id) }
        reconcilePaneLayout(persist: !layoutRestoreInProgress)
    }

    /// 同じ ID のノードを同じ位置で差し替える（並び・レイアウトを保つ）。
    private func replaceSessionNode(_ node: SessionNode) {
        guard let index = sessionNodes.firstIndex(where: { $0.id == node.id }) else { return }
        sessionNodes[index] = node
        sessionNodeIndex[node.id] = node
    }

    /// `sessionNodes` からの単一 ID 除去は必ずこのヘルパー経由で行い、`sessionNodeIndex` の同期漏れを防ぐ。
    private func removeSessionNode(id: SessionID) {
        sessionNodes.removeAll { $0.id == id }
        sessionNodeIndex.removeValue(forKey: id)
        if !layoutRestoreInProgress { normalizeGridSessionSelection() }
        reconcilePaneLayout(persist: !layoutRestoreInProgress)
    }

    private static func sessionTreeNodeIDs(in node: SessionTreeNode) -> [SessionID] {
        [node.id] + node.children.flatMap(sessionTreeNodeIDs)
    }

    private static func isVisibleInSidebar(_ node: SessionNode) -> Bool {
        isVisibleInSidebar(launchContext: node.launchContext)
    }

    private nonisolated static func isVisibleInSidebar(launchContext: SessionLaunchContext) -> Bool {
        isVisibleInGrid(launchContext: launchContext)
    }

    public nonisolated static func isVisibleInGrid(launchContext: SessionLaunchContext) -> Bool {
        launchContext != .orchestration
    }

    /// 未登録セッション（spawn 途中）は true を返す＝fail-open。
    public func isReachableFromUI(
        _ sessionID: SessionID,
        from client: SessionSurfaceClient
    ) -> Bool {
        guard let node = sessionNode(id: sessionID) else { return true }
        // 親の下の内部セッションは、プロジェクトが無くても絞り込みなしのグリッドに出る。
        if client == .desktop, isShownOnSessionSurfaces(node) { return true }
        return SessionReachability.isReachable(
            from: client,
            launchContext: node.launchContext,
            projectID: node.projectID
        )
    }

    /// クライアント指定前からの呼び出し元向け。従来の macOS 到達可能性として扱う。
    public func isReachableFromUI(_ sessionID: SessionID) -> Bool {
        isReachableFromUI(sessionID, from: .desktop)
    }

    /// プロジェクト絞り込み無しグリッドに表示するセッション。内部セッションは親の下にいるものだけ出す
    /// （親が消えた・親の無い `.orchestration` は出さない。ADR 0027 の孤児の除外は維持）。
    public var gridVisibleSessionNodes: [SessionNode] {
        sessionNodes.filter(isShownOnSessionSurfaces)
    }

    /// 通常のセッションか、祖先をたどると通常のセッションに着く内部セッションか。
    func isShownOnSessionSurfaces(_ node: SessionNode) -> Bool {
        var current = node
        var seen: Set<SessionID> = []
        while !Self.isVisibleInGrid(launchContext: current.launchContext) {
            guard let parentID = current.controllable.parentSessionID, seen.insert(current.id).inserted,
                  let parent = sessionNode(id: parentID) else { return false }
            current = parent
        }
        return true
    }

    /// グリッド表示の選択 UI 用。ワークスペース絞り込み文脈内の全セッション（selection 適用前）。
    public func gridSessionPickerCandidates() -> [SessionNode] {
        if let projectID = gridSessionFilterProjectID,
           projects.contains(where: { $0.id == projectID }) {
            return gridSessionNodes(in: projectID)
        }
        return gridVisibleSessionNodes
    }

    /// ワークスペース絞り込みと selection を合成したグリッド表示集合。
    public func filteredGridSessionNodes(projectID: ProjectID?) -> [SessionNode] {
        let base: [SessionNode]
        if let projectID, projects.contains(where: { $0.id == projectID }) {
            base = gridSessionNodes(in: projectID)
        } else {
            base = gridVisibleSessionNodes
        }
        let wrapped = base.map { GridSessionSelectionItem(node: $0) }
        let filtered = GridSessionSelectionFilter.apply(wrapped, selection: gridSessionSelection).map(\.node)
        guard let extraID = gridTemporarySessionID, !filtered.contains(where: { $0.id == extraID }),
              let extra = sessionNodes.first(where: { $0.id == extraID }) else { return filtered }
        return filtered + [extra]
    }

    /// 通知から開くセッションがグリッドの範囲外なら、範囲を変えずに一時的に加える。
    public func revealInGrid(_ id: SessionID) {
        guard !gridTileOrder().contains(id), sessionNodes.contains(where: { $0.id == id }) else { return }
        gridTemporarySessionID = id
    }

    /// 表示用の木は保存せず、呼び出し元ウィンドウの寸法から導く。
    public func paneLayoutForDisplay(in viewport: CGSize? = nil) -> PaneTree { gridLayoutForDisplay(in: viewport).tree }

    public func gridLayoutForDisplay(in viewport: CGSize? = nil) -> PaneGridLayout {
        let viewport = viewport ?? gridCanvasSize
        let visible = Set(filteredGridSessionNodes(projectID: gridSessionFilterProjectID).map(\.id))
        switch gridLayoutState {
        case .automatic:
            return .automatic(sessions: orderedGridSessionIDs(visible: visible), viewport: viewport)
        case .custom(let custom):
            return PaneGridLayout(tree: custom.tree.pruned(visible: visible), canvasSize: CGSize(
                width: max(viewport.width, custom.canvasMinimum.width),
                height: max(viewport.height, custom.canvasMinimum.height)))
        }
    }

    private func orderedGridSessionIDs(visible: Set<SessionID>) -> [SessionID] {
        var ordered: [SessionID] = []
        let projectIDs = Set(projects.map(\.id))
        let groups = projects.map { project in sessionNodes.filter { $0.projectID == project.id } }
            + [sessionNodes.filter { $0.projectID.map { !projectIDs.contains($0) } ?? true }]
        for group in groups {
            let inputs = group.map { node in SessionTreeInput(
                id: node.id, parentSessionID: node.controllable.parentSessionID, projectID: node.projectID,
                launchContext: node.launchContext, status: node.status, name: node.name,
                agentRef: node.agentRef, displayStatus: node.displayStatus) }
            ordered += SessionTree.buildForest(from: inputs).flatMap(Self.sessionTreeNodeIDs)
            let placed = Set(ordered)
            ordered += group.map(\.id).filter { !placed.contains($0) }
        }
        var seen: Set<SessionID> = []
        return ordered.filter { visible.contains($0) && seen.insert($0).inserted }
    }

    private func customStateForCurrentDisplay(in viewport: CGSize? = nil) -> CustomGridLayout {
        if case .custom(let custom) = gridLayoutState { return custom }
        let shown = gridLayoutForDisplay(in: viewport)
        let tree = shown.tree.retainingHidden(from: paneLayout, allSessions: sessionNodes.map(\.id), bounds: shown.canvasSize, spacing: PaneGridLayout.spacing)
        return CustomGridLayout(tree: tree, presetState: paneLayoutPresetState, canvasMinimum: shown.canvasSize)
    }

    private func commitGridLayout(_ state: GridLayoutState, persist: Bool = true) {
        guard state != gridLayoutState else { return }
        gridLayoutState = state
        if persist { paneLayoutStore?.saveState(state) }
    }

    public func handlePaneLayoutAction(_ action: PaneLayoutAction, in viewport: CGSize? = nil) {
        var custom = customStateForCurrentDisplay(in: viewport)
        let original = custom.tree
        switch action {
        case .setDivider(let divider, let fraction): custom.tree = original.settingDivider(divider, leadingFraction: fraction)
        case .insertBySplitting(let session, let target, let edge):
            guard sessionNodeIndex[session] != nil else { return }
            custom.tree = original.inserting(session, splitting: target, edge: edge)
        case .swap(let first, let second): custom.tree = original.swapping(first, second)
        case .equalize(let split): custom.tree = original.equalizing(split)
        case .applyPreset(let preset):
            custom.tree = preset.tree(for: original.readingOrder(in: gridLayoutForDisplay(in: viewport).canvasSize, spacing: PaneGridLayout.spacing))
            custom.presetState = .init(preset: preset)
        }
        if case .applyPreset = action {} else {
            guard custom.tree != original else { return }
            custom.presetState.isAdjusted = true
        }
        commitGridLayout(.custom(custom))
    }

    private func reconcilePaneLayout(persist: Bool = true) {
        guard var custom = gridLayoutState.customLayout else { return }
        custom.tree = custom.tree.reconciled(with: sessionNodes.map(\.id), bounds: PaneLayoutStore.reconcileBounds, spacing: 0)
        let state: GridLayoutState = gridLayoutState.isAutomatic ? .automatic(previousCustom: custom) : .custom(custom)
        commitGridLayout(state, persist: persist)
    }

    public func restoreAutomaticGridLayout() {
        guard case .custom(let custom) = gridLayoutState else { return }
        commitGridLayout(.automatic(previousCustom: custom))
    }

    public var canUndoAutomaticGridLayout: Bool {
        gridLayoutState.isAutomatic && gridLayoutState.customLayout != nil
    }

    public func undoAutomaticGridLayout() {
        guard case .automatic(let previous?) = gridLayoutState else { return }
        commitGridLayout(.custom(previous))
        reconcilePaneLayout()
    }

    private func reloadAndReconcilePaneLayout() {
        gridLayoutState = paneLayoutStore?.loadState() ?? .automatic(previousCustom: nil)
        reconcilePaneLayout()
    }

    public func isGridSessionSelected(_ id: SessionID) -> Bool {
        gridSessionSelection == nil || gridSessionSelection!.contains(id)
    }

    public func toggleGridSessionSelection(_ id: SessionID) {
        let candidates = Set(gridSessionPickerCandidates().map(\.id))
        guard candidates.contains(id) else { return }

        if gridSessionSelection == nil {
            let next = candidates.subtracting([id])
            gridSessionSelection = GridSessionSelectionFilter.normalized(selection: next, existing: candidates)
            return
        }

        var next = gridSessionSelection!
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        if next == candidates {
            gridSessionSelection = nil
        } else {
            gridSessionSelection = GridSessionSelectionFilter.normalized(selection: next, existing: candidates)
        }
    }

    public func clearGridSessionSelection() {
        gridSessionSelection = nil
    }

    /// グリッドのタイルを左上から数えた並び（⌘1–9 とタイル見出しの番号）。行の上から、同じ行は左から。
    public func gridTileOrder(in viewport: CGSize? = nil) -> [SessionID] {
        let layout = gridLayoutForDisplay(in: viewport)
        return layout.tree.readingOrder(in: layout.canvasSize, spacing: PaneGridLayout.spacing)
    }

    /// 06 キーボード（⌥⌘⇧＋矢印）: タイルをその向きの隣と入れ替える。隣が無ければ何もしない。
    public func swapGridTile(_ id: SessionID, toward direction: PaneDirection, in viewport: CGSize? = nil) {
        let layout = gridLayoutForDisplay(in: viewport)
        guard let other = layout.tree.neighbor(of: id, toward: direction, in: layout.canvasSize, spacing: PaneGridLayout.spacing) else { return }
        handlePaneLayoutAction(.swap(id, other), in: viewport)
    }

    /// 06 キーボード（⌃⌥＋矢印）: タイルの辺の分割線を 5% 動かす。
    /// 動かした結果を実際の大きさ・隙間で並べ、縮むタイルがドラッグと同じ最小の大きさを下回るなら動かさない。
    public func nudgeGridDivider(of id: SessionID, toward direction: PaneDirection, in viewport: CGSize? = nil) {
        let layout = gridLayoutForDisplay(in: viewport)
        let shown = layout.tree
        let bounds = layout.canvasSize
        guard let nudged = shown.nudgedDivider(of: id, toward: direction, in: bounds, spacing: PaneGridLayout.spacing) else { return }
        let custom = customStateForCurrentDisplay(in: viewport)
        let updated = custom.tree.nudgingDivider(nudged.id, by: nudged.delta)
        guard updated != custom.tree else { return }
        let visible = Set(shown.sessions)
        let before = Dictionary(uniqueKeysWithValues: shown.frames(in: bounds, spacing: PaneGridLayout.spacing).tiles.map { ($0.session, $0.rect.size) })
        let isHorizontal = direction == .left || direction == .right
        let minimum = isHorizontal ? PaneLayoutView.minimumPaneWidth : PaneLayoutView.minimumPaneHeight
        let tooSmall = updated.pruned(visible: visible).frames(in: bounds, spacing: PaneGridLayout.spacing).tiles.contains { tile in
            guard let old = before[tile.session] else { return false }
            let (was, now) = isHorizontal ? (old.width, tile.rect.width) : (old.height, tile.rect.height)
            return now < was && now < minimum
        }
        guard !tooSmall else { return }
        var next = custom
        next.tree = updated
        next.presetState.isAdjusted = true
        commitGridLayout(.custom(next))
    }

    /// グリッドから外す（06: タイルの ✕・⌘W・右クリック）。表示するセッションの選択から除くだけで、
    /// セッションは消さない。最後の 1 枚は外さない（選択が空になると全件表示へ戻るため）。
    /// 外したら、次にフォーカスするタイルを返す。
    @discardableResult
    public func removeFromGrid(_ id: SessionID, in viewport: CGSize? = nil) -> SessionID? {
        let order = gridTileOrder(in: viewport)
        guard order.count > 1, let index = order.firstIndex(of: id) else { return nil }
        if id == gridTemporarySessionID { gridTemporarySessionID = nil } else { toggleGridSessionSelection(id) }
        let remaining = order.filter { $0 != id }
        return remaining[min(index, remaining.count - 1)]
    }

    private func normalizeGridSessionSelection() {
        let existing = Set(gridSessionPickerCandidates().map(\.id))
        gridSessionSelection = GridSessionSelectionFilter.normalized(
            selection: gridSessionSelection,
            existing: existing
        )
    }

    func normalizeGridSessionSelectionForFilterChange() {
        normalizeGridSessionSelection()
    }

    /// 選んで絞ったグリッドに、新しいセッションを足す。内部セッションは足さない（オーケストレーションが
    /// 子を次々に立てても、選んだタイルが押し流されないように）。
    private func gridSessionSelectionDidSpawn(_ id: SessionID) {
        guard gridSessionSelection != nil, sessionNode(id: id)?.launchContext != .orchestration else { return }
        let candidates = Set(gridSessionPickerCandidates().map(\.id))
        guard candidates.contains(id) else { return }
        gridSessionSelection!.insert(id)
    }

    @MainActor
    private struct GridSessionSelectionItem: Identifiable {
        let node: SessionNode
        let id: SessionID

        init(node: SessionNode) {
            self.node = node
            self.id = node.id
        }
    }

    /// テーマからターミナルパレットを構築する（起動時・ライブ切替で共用）。
    public static func makeTerminalPalette(from theme: AppTheme) -> TerminalPalette {
        TerminalPalette(
            background: TerminalPalette.Channel(
                theme.terminalBackground.r, theme.terminalBackground.g, theme.terminalBackground.b
            ),
            foreground: TerminalPalette.Channel(
                theme.terminalForeground.r, theme.terminalForeground.g, theme.terminalForeground.b
            ),
            ansi: theme.ansi.map { TerminalPalette.Channel($0.r, $0.g, $0.b) }
        )
    }

    /// 現在のカラースキーマを既存ターミナルへ即時反映する（設定からのライブ切替用）。
    public func reapplyTheme() {
        TerminalCoordinator.activePalette = Self.makeTerminalPalette(from: ThemeStore.active)
        // セッションの端末とプロジェクトのターミナルへ当て直す。
        TerminalCoordinator.applyActivePaletteToAll()
    }

    /// ⌘+ / ⌘− / ⌘0 の対象（13 Review: フォーカス中の領域）。
    public enum FontSizeTarget: Equatable {
        case terminal
        case chat
        /// セッションを選んでいない。両方を同じ段数だけ動かす（従来どおり）。
        case both
    }

    /// 前面の領域から、文字サイズを変える対象を決める。
    /// ターミナル型は会話タブ自体が端末。チャット型は子タブの「ターミナル」を前に出しているときだけ端末。
    public static func fontSizeTarget(
        node: SessionNode?,
        selectedChildTab: ProjectTab?
    ) -> FontSizeTarget {
        if case .terminal = selectedChildTab { return .terminal }
        guard let node else { return .both }
        if node.pty != nil { return .terminal }
        return .chat
    }

    /// 文字サイズを steps 段だけ増減し、全セッションへ即時適用して永続化する。
    public func adjustFontSize(by steps: CGFloat, target: FontSizeTarget) {
        if target != .chat {
            applyTerminalFontSize(TerminalFontSettings.adjusted(
                from: TerminalFontSettings.currentSize(),
                by: steps * TerminalFontSettings.step
            ))
        }
        if target != .terminal {
            ChatFontSettings.save(ChatFontSettings.adjusted(
                from: ChatFontSettings.currentScale(),
                by: steps * ChatFontSettings.step
            ))
        }
    }

    /// ⌘0（実寸）。
    public func resetFontSize(target: FontSizeTarget) {
        if target != .chat {
            applyTerminalFontSize(NSFont.systemFontSize)
        }
        if target != .terminal {
            ChatFontSettings.save(ChatFontSettings.defaultScale)
        }
    }

    /// ターミナルの文字サイズを保存し、開いている全セッションの端末へ当てる。設定画面で変えたときも使う。
    public func applyTerminalFontSize(_ size: CGFloat) {
        TerminalFontSettings.save(size)
        for session in sessions {
            session.terminalCoordinator.applyFontSize(TerminalFontSettings.displaySize(size))
        }
    }

    /// 06: グリッドと単体を切り替えたとき、端末の文字をその表示の大きさへ当て直す。
    public func setTerminalGridLayout(_ isGrid: Bool) {
        guard TerminalFontSettings.isGridLayout != isGrid else { return }
        TerminalFontSettings.isGridLayout = isGrid
        applyTerminalFontSize(TerminalFontSettings.currentSize())
    }

    public func runningBreakdown(in projectID: ProjectID) -> RunningSessionBreakdown {
        Self.runningBreakdown(in: projectID, from: sessionTreeInputs(for: projectID))
    }

    public func runningSessionCount(in projectID: ProjectID) -> Int {
        runningBreakdown(in: projectID).total
    }

    nonisolated static func runningBreakdown(in projectID: ProjectID, from inputs: [SessionTreeInput]) -> RunningSessionBreakdown {
        let forest = SessionTree.buildForest(from: inputs.filter { $0.projectID == projectID })
        var visible = 0
        var nestedOrchestration = 0

        func visit(_ node: SessionTreeNode, depth: Int) {
            if isRunning(node.displayStatus) {
                if depth == 0 {
                    if isVisibleInGrid(launchContext: node.launchContext) {
                        visible += 1
                    }
                } else if node.launchContext == .orchestration {
                    nestedOrchestration += 1
                } else {
                    visible += 1
                }
            }
            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }

        for root in forest where isVisibleInGrid(launchContext: root.launchContext) {
            visit(root, depth: 0)
        }

        return RunningSessionBreakdown(visible: visible, nestedOrchestration: nestedOrchestration)
    }

    private func sessionTreeInputs(for projectID: ProjectID) -> [SessionTreeInput] {
        sessionNodes
            .filter { $0.projectID == projectID }
            .map { node in
                SessionTreeInput(
                    id: node.id,
                    parentSessionID: node.controllable.parentSessionID,
                    projectID: node.projectID,
                    launchContext: node.launchContext,
                    status: node.status,
                    name: node.name,
                    agentRef: node.agentRef,
                    displayStatus: node.displayStatus
                )
            }
    }

    nonisolated private static func isRunning(_ status: SessionStatus) -> Bool {
        if case .running = status { true } else { false }
    }

    /// projectID が未指定のセッション（従来の隔離 CWD など）。
    public var unassignedSessions: [SessionViewModel] {
        sessions.filter { $0.projectID == nil }
    }

    public var unassignedSessionNodes: [SessionNode] {
        sessionNodes.filter { $0.projectID == nil && Self.isVisibleInSidebar($0) }
    }

    /// サイドバー表示順のフラットなセッション ID 列（projects 順 → 各 project 内順 → 未割当）。
    public var sidebarOrderedSessionIDs: [SessionID] {
        projects.flatMap { sessionNodes(in: $0.id).map(\.id) } + unassignedSessionNodes.map(\.id)
    }

    /// 表示順で current の次/前のセッション ID。端では current を維持。
    /// current が nil・不明 ID なら forward は先頭、backward は末尾。0 件なら nil。
    public func adjacentSessionID(from current: SessionID?, forward: Bool) -> SessionID? {
        let ordered = sidebarOrderedSessionIDs
        guard !ordered.isEmpty else { return nil }

        guard let current else {
            return forward ? ordered.first : ordered.last
        }

        guard let index = ordered.firstIndex(of: current) else {
            return forward ? ordered.first : ordered.last
        }

        let nextIndex = forward ? index + 1 : index - 1
        guard ordered.indices.contains(nextIndex) else {
            return current
        }
        return ordered[nextIndex]
    }

    /// ユーザーが選択したフォルダをワークスペースとして追加する。重複ディレクトリは拒否する。
    @discardableResult
    public func addProject(name: String, directoryPath: String) -> ProjectID? {
        guard !isRuntimeProjection else {
            runtimeCommandError = "プロジェクトの追加には非同期の操作が必要です"
            return nil
        }
        let standardizedNew = Self.standardizedDirectoryPath(directoryPath)
        guard !projects.contains(where: { Self.standardizedDirectoryPath($0.directoryPath) == standardizedNew }) else {
            return nil
        }

        let project = Project(
            name: name,
            directoryPath: directoryPath,
            createdAt: Date(),
            isManagedDirectory: false
        )
        projects.append(project)
        persistProjects()
        return project.id
    }

    /// 空欄（空白だけ）で確定したら、追加したときと同じフォルダ名に戻す（03 F6・C-10。フォルダ名そのものは変えない）。
    public func renameProject(_ projectID: ProjectID, to name: String) {
        if isRuntimeProjection { enqueueProjectedAction(.renameProject(projectID, name)); return }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        projects[index].name = trimmed.isEmpty ? projects[index].directoryURL.lastPathComponent : name
        persistProjects()
    }

    public func clearWorkspaceCleanupWarning() {
        if isRuntimeProjection { enqueueProjectedAction(.clearWorkspaceCleanupWarning) }
        workspaceCleanupWarning = nil
        workspaceCleanupFailureReason = nil
    }

    /// git の失敗はその出力の 1 行目、それ以外はエラーの説明の 1 行目。
    static func cleanupFailureReason(_ error: Error) -> String? {
        let text: String
        if case WorktreeIsolationGitError.commandFailed(_, let output) = error {
            text = output
        } else if let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError,
                  posix.domain == NSPOSIXErrorDomain {
            // ファイルの削除失敗は、OS の短い理由（Permission denied など）を出す。
            text = String(cString: strerror(Int32(posix.code)))
        } else {
            text = error.localizedDescription
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// セッション名を変更する。空白のみの名前はトリムして空にする。
    public func renameSession(_ id: SessionID, to name: String) {
        if isRuntimeProjection { enqueueProjectedAction(.renameSession(id, name)); return }
        guard let node = sessionNodes.first(where: { $0.id == id }) else { return }
        node.name = name
        persistence.persistSessionName(id: id, name: node.titleState.name)
    }

    /// アゴラ討論の役割を descriptor に永続化する（ControlActionDashboard の witness。renameSession と同型）。
    public func persistSessionRole(id: SessionID, role: String) {
        if isRuntimeProjection { enqueueProjectedAction(.persistRole(id, role)); return }
        persistence.persistSessionRole(id: id, role: role)
    }

    /// Control API witness: 該当 appServer セッションへ AskUserQuestion 回答を転送する。
    public func respondToUserQuestion(
        id: SessionID,
        requestId: String,
        answers: [String: [String]]
    ) async -> Bool {
        guard let session = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return false
        }
        return await session.respondToUserQuestion(requestId: requestId, answers: answers)
    }

    /// グリッドのドラッグ&ドロップで source と target の2セッションだけを入れ替える（スワップ）。
    /// 間のセッションは動かさず、表示順と永続化配列の順を一致させて再起動後も並びを保持する。
    public func reorderSession(_ source: SessionID, with target: SessionID) {
        if isRuntimeProjection { enqueueProjectedAction(.reorderSession(source, target)); return }
        guard source != target,
              let sourceNodeIndex = sessionNodes.firstIndex(where: { $0.id == source }),
              let targetNodeIndex = sessionNodes.firstIndex(where: { $0.id == target }) else {
            return
        }

        sessionNodes.swapAt(sourceNodeIndex, targetNodeIndex)
        sessions = sessionNodes.compactMap(\.pty)
        persistence.persistSessionOrder { self.sessionNodes.map(\.id) }
    }

    /// ワークスペースを一覧から除去する。配下セッションは停止するがフォルダは削除しない。
    /// S2: サイドバー可視フィルタ（`sessionNodes(in:)`）に依存せず、当該 projectID の全セッション
    /// （不可視の orchestration 子を含む）を対象にする。`removeSession` は部分木単位で除去し、
    /// 既に他ルートの部分木として消えた ID は no-op になるため、スナップショットを走査すれば重複除去は起きない。
    public func removeProject(_ projectID: ProjectID) async {
        if isRuntimeProjection {
            FileTabDocumentRegistry.shared.beginProjectChanges(for: [projectID])
            defer { FileTabDocumentRegistry.shared.endProjectChanges(for: [projectID]) }
            await FileTabDocumentRegistry.shared.waitForPendingSaves(for: [projectID])
            do {
                _ = try await sendRuntimeCommand(.removeProject(projectID))
                await FileTabDocumentRegistry.shared.invalidateAndWait(for: [projectID])
            } catch { runtimeCommandError = error.localizedDescription }
            return
        }
        FileTabDocumentRegistry.shared.beginProjectChanges(for: [projectID])
        defer { FileTabDocumentRegistry.shared.endProjectChanges(for: [projectID]) }
        await FileTabDocumentRegistry.shared.invalidateAndWait(for: [projectID])
        let sessionIDs = sessionNodes
            .filter { $0.projectID == projectID }
            .map(\.id)
        for sessionID in sessionIDs {
            if sessionNode(id: sessionID) != nil, !(await removeSession(sessionID)) { return }
        }
        projects.removeAll { $0.id == projectID }
        persistProjects()
        // フィルタ中プロジェクトの削除で filteredGridSessionNodes がフォールバック（全表示）へ
        // 切り替わるため、新しい可視集合で配置を再整合する（イベント側の書き込み）。
        reconcilePaneLayout(persist: !layoutRestoreInProgress)
    }

    /// 指定 CLI の新規セッションを `sessions` に追加し、PTY を eager に即起動する。
    /// View 描画を待たずプロセスを起動するため、API 経由 spawn（非表示セッション）でも確実に起動する。
    /// 既定 winsize で起動し、View 出現後の sizeChanged で実サイズへ resize する。
    @discardableResult
    public func spawnNewSession(
        kind: AgentKind,
        projectID: ProjectID? = nil,
        from: SessionID? = nil,
        backend: SessionBackend = .pty,
        launchContext: SessionLaunchContext = .interactive,
        extraEnv: [String: String] = [:]
    ) async throws -> SessionID {
        try await spawnNewSession(
            ref: .builtin(kind),
            projectID: projectID,
            from: from,
            backend: backend,
            launchContext: launchContext,
            extraEnv: extraEnv
        )
    }

    /// - Parameter workingDirectoryOverride: 非 nil のとき、project から導出する CWD の代わりに
    ///   このパスで起動する（復元済みセッションの作業ディレクトリ再現などに使う）。
    @discardableResult
    public func spawnNewSession(
        ref: AgentRef,
        projectID: ProjectID? = nil,
        from: SessionID? = nil,
        backend: SessionBackend = .pty,
        launchContext: SessionLaunchContext = .interactive,
        extraEnv: [String: String] = [:],
        workingDirectoryOverride: String? = nil,
        isolationOverride: Bool? = nil,
        worktreeStartPoint: WorktreeStartPoint = .head,
        initialSettings: CodexAppServerSessionSettings? = nil,
        resumeHistoryEntry: ClaudeSessionHistoryEntry? = nil,
        keepsRowOnLaunchFailure: Bool = false,
        onRowAppended: (@MainActor (SessionID) -> Void)? = nil
    ) async throws -> SessionID {
        if isRuntimeProjection {
            let reply = try await sendRuntimeCommand(.spawn(.init(ref: ref, projectID: projectID,
                parentSessionID: from, backend: backend, launchContext: launchContext, extraEnv: extraEnv,
                workingDirectoryOverride: workingDirectoryOverride, isolationOverride: isolationOverride,
                worktreeStartPoint: worktreeStartPoint, initialSettings: initialSettings,
                resumeHistoryEntry: resumeHistoryEntry, keepsRowOnLaunchFailure: keepsRowOnLaunchFailure)))
            guard case .sessionID(let id) = reply else { throw DashboardRuntimeError.unexpectedReply }
            onRowAppended?(id)
            return id
        }
        return try await spawnNewSessionImpl(
            ref: ref,
            projectID: projectID,
            from: from,
            backend: backend,
            launchContext: launchContext,
            extraEnv: extraEnv,
            workingDirectoryOverride: workingDirectoryOverride,
            isolationOverride: isolationOverride,
            worktreeStartPoint: worktreeStartPoint,
            initialSettings: initialSettings,
            resumeHistoryEntry: resumeHistoryEntry,
            keepsRowOnLaunchFailure: keepsRowOnLaunchFailure,
            onRowAppended: onRowAppended,
            spawnLimitSource: .parent(from)
        )
    }

    public func launchNewChat(_ request: NewChatLaunchRequest,
                              onRowAppended: (@MainActor (SessionID) -> Void)? = nil) async throws -> SessionID {
        if isRuntimeProjection {
            guard case .acceptedSession(let id) = try await sendRuntimeCommand(.launchNewChat(request)) else {
                throw DashboardRuntimeError.unexpectedReply
            }
            onRowAppended?(id)
            return id
        }
        return try await launchNewChat(request, firstMessageDelivery: .awaitDelivery, onRowAppended: onRowAppended)
    }

    private func launchNewChat(_ request: NewChatLaunchRequest, firstMessageDelivery: FirstMessageDelivery,
                               onRowAppended: (@MainActor (SessionID) -> Void)? = nil) async throws -> SessionID {
        guard projects.contains(where: { $0.id == request.projectID }) else { throw AgentSpawnError.unknownProject }
        let historyEntry: ClaudeSessionHistoryEntry?
        if let resumeHistoryID = request.resumeHistoryID {
            guard request.agentRef == .builtin(.claudeCode) || request.agentRef == .builtin(.codex) else {
                throw AgentSpawnError.unsupportedBackend
            }
            historyEntry = try await newChatHistoryEntries(projectID: request.projectID, agentRef: request.agentRef)
                .first { $0.sessionID == resumeHistoryID }
            guard historyEntry != nil else { throw AgentSpawnError.historyNotFound }
        } else {
            historyEntry = nil
        }
        guard projects.contains(where: { $0.id == request.projectID }) else { throw AgentSpawnError.unknownProject }
        let id = try await spawnNewSession(ref: request.agentRef, projectID: request.projectID, backend: .appServer,
            workingDirectoryOverride: request.workingDirectoryOverride,
            isolationOverride: request.usesWorktree, worktreeStartPoint: request.worktreeStartPoint, initialSettings: request.settings,
            resumeHistoryEntry: historyEntry, keepsRowOnLaunchFailure: true,
            onRowAppended: { id in
                self.failedNewChatRequests[id] = request
                if historyEntry == nil {
                    self.sessionNode(id: id)?.appServer?.prepareFirstMessage(request.text, attachments: request.attachments)
                }
                onRowAppended?(id)
            })
        lastUsedChatSettingsStore.recordLastHarness(request.agentRef.id)
        guard let vm = sessionNode(id: id)?.appServer else { throw CancellationError() }
        if vm.launchFailure == nil, historyEntry == nil, !request.text.isEmpty || !request.attachments.isEmpty {
            switch firstMessageDelivery {
            case .awaitDelivery:
                await vm.sendFirstMessage(request.text, attachments: request.attachments, selectedSkill: request.selectedSkill)
            case .acceptIntoRuntime:
                retainRuntimeFirstMessage(request, session: vm)
            }
        }
        return id
    }

    private func retainRuntimeFirstMessage(_ request: NewChatLaunchRequest, session: ChatSessionViewModel) {
        let id = session.id
        let executionID = session.executionID
        let operationID = UUID()
        let task = Task { @MainActor [weak self, weak session] in
            defer {
                if self?.runtimeFirstMessages[id]?.operationID == operationID {
                    self?.runtimeFirstMessages.removeValue(forKey: id)
                }
            }
            guard !Task.isCancelled, let session else { return }
            await session.sendFirstMessage(request.text, attachments: request.attachments, selectedSkill: request.selectedSkill)
            guard !Task.isCancelled, session.executionID == executionID,
                  self?.sessionNode(id: id)?.appServer === session, session.launchFailure == nil else { return }
            let failure: String?
            if let sendFailure = session.sendFailure { failure = sendFailure.reason }
            else if case .error(let message) = session.status { failure = message }
            else { failure = nil }
            if let failure {
                session.markLaunchFailed(.processFailed(failure), restoringDraft: request.text)
            }
        }
        runtimeFirstMessages[id] = .init(operationID: operationID, task: task)
    }

    public func newChatHistoryEntries(projectID: ProjectID, agentRef: AgentRef) async throws -> [ClaudeSessionHistoryEntry] {
        if isRuntimeProjection {
            guard case .history(let entries) = try await sendRuntimeCommand(.history(projectID, agentRef)) else {
                throw DashboardRuntimeError.unexpectedReply
            }
            return availableHistoryEntries(entries, agentRef: agentRef)
        }
        guard let project = projects.first(where: { $0.id == projectID }) else { return [] }
        let directories = [project.directoryPath] + (project.worktreePaths ?? [])
        return try await loadHistoryEntries(agentRef: agentRef, workingDirectories: directories)
    }

    public func newChatStartPoints(projectID: ProjectID, commit: String? = nil) async throws -> [WorktreeStartPointItem] {
        guard let project = projects.first(where: { $0.id == projectID }) else { throw AgentSpawnError.unknownProject }
        let service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: project.directoryPath))
        var points = await service.worktreeStartPoints()
        if let commit, let point = try await service.worktreeCommit(matching: commit), !points.contains(where: { $0.point == point }) {
            points.append(.init(point: point))
        }
        guard projects.contains(where: { $0.id == projectID }) else { throw AgentSpawnError.unknownProject }
        return points
    }

    func availableHistoryEntries(_ entries: [ClaudeSessionHistoryEntry], agentRef: AgentRef) -> [ClaudeSessionHistoryEntry] {
        let open = Set(sessionNodes.filter { $0.agentRef == agentRef }.compactMap { node in
            (node.appServer?.threadId ?? node.pty?.nativeSessionID).map {
                SessionHistoryKey(agentRef: agentRef, nativeSessionID: $0)
            }
        })
        return entries.filter { !open.contains(SessionHistoryKey(agentRef: agentRef, nativeSessionID: $0.sessionID)) }.map { entry in
            var result = entry
            result.savedTitle = historyNames[SessionHistoryKey(agentRef: agentRef, nativeSessionID: entry.sessionID)] ?? entry.savedTitle
            return result
        }
    }

    private func synchronizeHistorySessionIDs() async {
        await persistence.waitForPendingWrites()
        for descriptor in await environment.sessions.load() {
            if let session = sessionNode(id: descriptor.id)?.pty, session.nativeSessionID == nil {
                session.nativeSessionID = descriptor.resumeID
            }
        }
    }

    private func loadHistoryEntries(agentRef: AgentRef, workingDirectories: [String]) async throws -> [ClaudeSessionHistoryEntry] {
        await synchronizeHistorySessionIDs()
        let limit = 20 + sessionNodes.filter { $0.agentRef == agentRef }.count
        guard let provider = Self.newChatHistoryLoader ?? environment.newChatSessionHistoryLoader(
            agentRef: agentRef, workingDirectories: workingDirectories, limit: limit
        ) else { return [] }
        let raw = try await Task.detached(priority: .userInitiated) { try provider() }.value
        let savedNames = await environment.sessionHistoryNames.names()
        historyNames.merge(savedNames, uniquingKeysWith: { current, _ in current })
        await synchronizeHistorySessionIDs()
        return Array(availableHistoryEntries(raw, agentRef: agentRef).prefix(20))
    }

    private func rememberHistoryName(_ node: SessionNode, name: String) async throws {
        guard node.agentRef == .builtin(.claudeCode) || node.agentRef == .builtin(.codex),
              let nativeID = node.appServer?.threadId ?? node.pty?.nativeSessionID else { return }
        let key = SessionHistoryKey(agentRef: node.agentRef, nativeSessionID: nativeID)
        try await environment.sessionHistoryNames.record(key: key, name: name)
        historyNames[key] = name
    }

    public func restartNewChat(_ id: SessionID,
                               onRowAppended: (@MainActor (SessionID) -> Void)? = nil) async throws -> SessionID {
        if isRuntimeProjection {
            guard case .sessionID(let newID) = try await sendRuntimeCommand(.restartNewChat(id)) else {
                throw DashboardRuntimeError.unexpectedReply
            }
            onRowAppended?(newID)
            return newID
        }
        guard restartingNewChatIDs.insert(id).inserted else { throw CancellationError() }
        defer { restartingNewChatIDs.remove(id) }
        guard let request = failedNewChatRequests[id], let vm = sessionNode(id: id)?.appServer,
              vm.launchFailure != nil else {
            throw ChatLaunchError.processFailed("起動に失敗したセッションが見つかりません")
        }
        let restart = NewChatLaunchRequest(projectID: request.projectID, agentRef: request.agentRef,
            settings: request.settings,
            usesWorktree: request.usesWorktree,
            text: "", attachments: [],
            workingDirectoryOverride: request.workingDirectoryOverride,
            resumeHistoryID: request.resumeHistoryID, worktreeStartPoint: request.worktreeStartPoint)
        let newID = try await launchNewChat(restart, onRowAppended: { newID in
            if request.resumeHistoryID == nil, let target = self.sessionNode(id: newID)?.appServer {
                let merged = ComposerAttachmentStore.mergingDrafts(text: vm.draft, attachments: vm.composerAttachments,
                    nextText: target.draft, nextAttachments: target.composerAttachments)
                target.restoreLaunchDraft(merged.text, attachments: merged.attachments)
            }
            onRowAppended?(newID)
        })
        await removeSession(id)
        return newID
    }

    private func spawnNewSessionImpl(
        ref: AgentRef,
        projectID: ProjectID? = nil,
        from: SessionID? = nil,
        backend: SessionBackend = .pty,
        launchContext: SessionLaunchContext = .interactive,
        extraEnv: [String: String] = [:],
        workingDirectoryOverride: String? = nil,
        isolationOverride: Bool? = nil,
        worktreeStartPoint: WorktreeStartPoint = .head,
        initialSettings: CodexAppServerSessionSettings? = nil,
        resumeHistoryEntry: ClaudeSessionHistoryEntry? = nil,
        keepsRowOnLaunchFailure: Bool = false,
        onRowAppended: (@MainActor (SessionID) -> Void)? = nil,
        spawnLimitSource: APISpawnLimitSource
    ) async throws -> SessionID {
        guard !isRuntimeProjection else { throw DashboardRuntimeError.ownedOperationUnavailable }
        let agentDescriptor = sessionSpawnService.descriptorForPresentation(ref: ref)
        // spawn 元（親）がチャット（appServer）セッションで、子の kind が structured chat 対応なら、
        // 子も appServer で起動し「チャットから spawn した子はチャットに揃える」。それ以外は要求どおり。
        // appServer への昇格のみ行い降格はしない（モバイル/UI が明示した backend を壊さない）。
        let resolvedBackend: SessionBackend = {
            guard let from,
                  let parentNode = sessionNode(id: from),
                  parentNode.appServer != nil,
                  agentDescriptor.supportsStructuredChat
            else { return backend }
            return .appServer
        }()
        if resolvedBackend == .appServer, !agentDescriptor.supportsStructuredChat {
            throw AgentSpawnError.unsupportedBackend
        }
        switch spawnLimitSource {
        case .parent(let parent):
            if let parent {
                try checkAPISpawnLimits(
                    requester: parent,
                    newDepth: depth(of: parent) + 1
                )
            }
        case .controlRequester(let requester):
            let newDepth = requester.map { depth(of: $0) + 1 } ?? 0
            try checkAPISpawnLimits(requester: requester, newDepth: newDepth)
        }

        // API 経由で projectID 未指定かつ親ありのとき、親と同じワークスペース（CWD）で子を起動する。
        let resolvedProjectID = sessionSpawnService.resolveProjectID(explicit: projectID, parentSessionID: from)
        let projectWasRegistered = resolvedProjectID.map { id in projects.contains { $0.id == id } } ?? false

        let sessionID = SessionID()
        let token = SessionSpawnService.makeToken()
        await environment.tokenStore.register(token, for: sessionID)

        // 明示の override を最優先し、無ければ project から CWD を導出する。
        let resolvedWorkingDirectory = workingDirectoryOverride
            ?? sessionSpawnService.resolvedWorkingDirectoryPath(projectID: resolvedProjectID, sessionID: sessionID)

        let resumeID = await sessionSpawnService.initialResumeID(for: ref, sessionID: sessionID)

        let plan: AgentLaunchPlan
        do {
            plan = try await sessionSpawnService.prepareSessionLaunchAsync(
                ref: ref,
                sessionID: sessionID,
                sessionToken: token,
                workingDirectoryOverride: resolvedWorkingDirectory,
                projectID: resolvedProjectID,
                launchMode: .newSession(resumeID: resumeID),
                backend: resolvedBackend,
                extraEnv: extraEnv,
                isolationOverride: isolationOverride,
                worktreeStartPoint: worktreeStartPoint
            )
        } catch AgentLaunchPlannerError.binaryNotFound(let k) {
            await environment.tokenStore.remove(session: sessionID)
            await cleanupOwnedWorkspace(for: sessionID)
            throw AgentSpawnError.binaryNotFound(k)
        } catch {
            await environment.tokenStore.remove(session: sessionID)
            await cleanupOwnedWorkspace(for: sessionID)
            throw error
        }

        if let resolvedProjectID,
           (projectWasRegistered && !projects.contains(where: { $0.id == resolvedProjectID }))
            || FileTabDocumentRegistry.shared.isChangingProject(resolvedProjectID) {
            await environment.tokenStore.remove(session: sessionID)
            await cleanupOwnedWorkspace(for: sessionID)
            throw AgentSpawnError.unknownProject
        }

        let usedNames = Set(sessionNodes.flatMap { node -> [String] in
            var names = [normalizeSessionNameForUniqueness(node.controllable.name)]
            if let flowerName = node.titleState.flowerName {
                names.append(normalizeSessionNameForUniqueness(flowerName))
            }
            return names
        })
        let generatedName = FlowerNameGenerator.random(avoiding: usedNames)
        let codexThreadId: String?
        let chatNativeSessionId: String?
        let appServerUserAgent: String?
        let persistedParentSessionID: SessionID?
        let persistedLaunchContext: SessionLaunchContext
        let spawnedSession: any ControllableSession

        switch resolvedBackend {
        case .pty:
            let sessionOrigin = sessionOriginForWrite(
                parentSessionID: from,
                launchContext: launchContext,
                spawnLimitSource: spawnLimitSource
            )
            let sessionVM = sessionSpawnService.makeSessionViewModel(
                id: sessionID,
                projectID: resolvedProjectID,
                parentSessionID: sessionOrigin.parentSessionID,
                name: generatedName,
                plan: plan,
                launchContext: sessionOrigin.launchContext,
                titleState: .generated(flowerName: generatedName)
            )

            sessionVM.nativeSessionID = resumeID

            observeUnseenCompletion(for: sessionVM)
            sessions.append(sessionVM)
            appendSessionNode(.pty(sessionVM))
            refreshUnseenCompletionCount()
            await sessionVM.start()

            let spawnTime = codexDiscoveryNow()
            let rolloutSnapshot = codexDiscoveryController.rolloutSnapshotIfNeeded(
                for: ref,
                resumeID: resumeID,
                around: spawnTime
            )
            // View の描画を待たず PTY を即起動する（API 経由 spawn など非表示セッションでも起動させる）。
            // View 出現後は handleResize が実サイズへ resize する。
            await sessionVM.spawnEager()
            if let rolloutSnapshot {
                codexDiscoveryController.configure(
                    for: sessionVM,
                    spawnTime: spawnTime,
                    workingDirectory: plan.workingDirectory ?? resolvedWorkingDirectory ?? "",
                    rolloutSnapshot: rolloutSnapshot
                )
            }
            codexThreadId = nil
            chatNativeSessionId = nil
            appServerUserAgent = nil
            persistedParentSessionID = sessionVM.parentSessionID
            persistedLaunchContext = sessionVM.launchContext
            spawnedSession = sessionVM
        case .appServer:
            let result = try await sessionSpawnService.startAppServerSession(
                id: sessionID,
                ref: ref,
                projectID: resolvedProjectID,
                parentSessionID: from,
                name: generatedName,
                plan: plan,
                launchContext: launchContext,
                titleState: .generated(flowerName: generatedName),
                initialSettings: initialSettings,
                resumeHistoryEntry: resumeHistoryEntry,
                keepsRowOnLaunchFailure: keepsRowOnLaunchFailure,
                sessionOriginForWrite: {
                    self.sessionOriginForWrite(
                        parentSessionID: from,
                        launchContext: launchContext,
                        spawnLimitSource: spawnLimitSource
                    )
                },
                registerSessionForWrite: { vm in
                    self.observeUnseenCompletion(for: vm)
                    self.appendSessionNode(.appServer(vm))
                    self.refreshUnseenCompletionCount()
                    onRowAppended?(vm.id)
                },
                unregisterFailedSession: { id in
                    guard let node = self.sessionNode(id: id) else { return }
                    node.controllable.unseenCompletionDidChange = nil
                    self.removeSessionNode(id: id)
                    self.refreshUnseenCompletionCount()
                }
            )
            codexThreadId = result.codexThreadId
            chatNativeSessionId = result.chatNativeSessionId
            appServerUserAgent = result.appServerUserAgent
            persistedParentSessionID = result.vm.parentSessionID
            persistedLaunchContext = result.vm.launchContext
            spawnedSession = result.vm
        }

        let livePID = await livePIDProvider(sessionID)
        // 一覧へ登録してからここへ到達するまでに cascade 削除された場合は、起動処理との
        // 競合後に backend を再停止し、削除済み descriptor を永続化しない。
        guard sessionNode(id: sessionID) != nil else {
            await spawnedSession.terminate()
            throw CancellationError()
        }
        if sessionNode(id: sessionID)?.appServer?.launchFailure != nil { return sessionID }

        // 再起動後の復元に備えてセッションメタを永続化する。
        // spawn 済みセッションの live pid を記録し、次回起動の reconcile（生存孤児 reap）に使う。
        let latestTitle = sessionNode(id: sessionID)?.titleState
            ?? .generated(flowerName: generatedName)
        let descriptor = PersistedSessionDescriptor(
            id: sessionID,
            agentRef: ref,
            workingDirectory: plan.workingDirectory ?? resolvedWorkingDirectory ?? "",
            name: latestTitle.name,
            projectID: resolvedProjectID,
            startedAt: Date(),
            command: plan.command,
            args: plan.args,
            env: plan.env,
            backend: resolvedBackend,
            codexThreadId: codexThreadId,
            chatNativeSessionId: chatNativeSessionId,
            appServerUserAgent: appServerUserAgent,
            codexSettings: sessionNodes.first(where: { $0.id == sessionID })?.appServer?.codexSettingsSnapshot,
            token: token,
            resumeID: resumeID,
            parentSessionID: persistedParentSessionID,
            pid: livePID,
            launchContext: persistedLaunchContext,
            titleSource: latestTitle.source,
            flowerName: latestTitle.flowerName,
            fullDerivedTitle: latestTitle.fullDerivedTitle
        )
        persistence.persistSession(descriptor)

        // 生成成功を App 層へ通知する（解析配線用、PII なし）。
        sessionDidSpawn?(ref)

        return sessionID
    }

    /// Control API 経由だけ要求元の実在を再評価する。
    /// 呼び出し側は、この戻り値の取得とセッションへの代入の間に await を置かない。
    private func sessionOriginForWrite(
        parentSessionID: SessionID?,
        launchContext: SessionLaunchContext,
        spawnLimitSource: APISpawnLimitSource
    ) -> SessionOrigin {
        switch spawnLimitSource {
        case .parent:
            return SessionOrigin(
                launchContext: launchContext,
                parentSessionID: parentSessionID
            )
        case .controlRequester(let requester):
            return SessionOriginPolicy.origin(
                requester: requester,
                requesterIsExistingSession: requester.map { sessionNode(id: $0) != nil } ?? false
            )
        }
    }

    /// Control API の要求元を、spawn 制限のキーとセッションツリーの親に分離して起動する。
    /// 実在しない要求元も制限には使うが、親リンクには書き込まない。
    @discardableResult
    public func spawnNewSessionFromControlAPI(
        ref: AgentRef,
        requester: SessionID?,
        backend: SessionBackend,
        workingDirectory: String?,
        projectID: ProjectID?,
        initialSettings: CodexAppServerSessionSettings?,
        usesWorktree: Bool? = nil,
        worktreeStartPoint: WorktreeStartPoint = .head,
        resumeHistoryID: String? = nil
    ) async throws -> SessionID {
        try await spawnNewSessionFromControlAPI(
            ref: ref,
            requester: requester,
            backend: backend,
            workingDirectory: workingDirectory,
            projectID: projectID,
            initialSettings: initialSettings,
            usesWorktree: usesWorktree,
            worktreeStartPoint: worktreeStartPoint,
            resumeHistoryID: resumeHistoryID,
            afterOriginResolution: {}
        )
    }

    @discardableResult
    func spawnNewSessionFromControlAPI(
        ref: AgentRef,
        requester: SessionID?,
        backend: SessionBackend,
        workingDirectory: String?,
        projectID: ProjectID?,
        initialSettings: CodexAppServerSessionSettings?,
        usesWorktree: Bool? = nil,
        worktreeStartPoint: WorktreeStartPoint = .head,
        resumeHistoryID: String? = nil,
        afterOriginResolution: @MainActor () async -> Void
    ) async throws -> SessionID {
        if let projectID, !projects.contains(where: { $0.id == projectID }) {
            throw AgentSpawnError.unknownProject
        }
        let historyEntry: ClaudeSessionHistoryEntry?
        if let resumeHistoryID {
            guard backend == .appServer, let projectID,
                  ref == .builtin(.claudeCode) || ref == .builtin(.codex) else { throw AgentSpawnError.unsupportedBackend }
            historyEntry = try await newChatHistoryEntries(projectID: projectID, agentRef: ref).first { $0.sessionID == resumeHistoryID }
            guard historyEntry != nil else { throw AgentSpawnError.historyNotFound }
        } else { historyEntry = nil }
        if usesWorktree != nil || resumeHistoryID != nil || worktreeStartPoint != .head {
            guard projectID != nil, backend == .appServer, workingDirectory == nil else { throw AgentSpawnError.unknownProject }
        }
        let requesterIsExistingSession = requester.map { sessionNode(id: $0) != nil } ?? false
        let origin = SessionOriginPolicy.origin(
            requester: requester,
            requesterIsExistingSession: requesterIsExistingSession
        )
        await afterOriginResolution()
        if let projectID, !projects.contains(where: { $0.id == projectID }) {
            throw AgentSpawnError.unknownProject
        }
        return try await spawnNewSessionImpl(
            ref: ref,
            projectID: projectID,
            from: origin.parentSessionID,
            backend: backend,
            launchContext: origin.launchContext,
            workingDirectoryOverride: workingDirectory,
            isolationOverride: usesWorktree,
            worktreeStartPoint: worktreeStartPoint,
            initialSettings: initialSettings,
            resumeHistoryEntry: historyEntry,
            spawnLimitSource: .controlRequester(requester)
        )
    }

    /// 指定セッションのワークスペース (CWD) を変更する。対象セッションを kill し、
    /// 新 directory を CWD として再起動する（進行中の作業は失われる）。
    /// hook stream は AsyncStream の単一コンシューマ前提を守るため finish→新規生成→差し替えする。
    public func changeWorkspace(_ id: SessionID, to directory: URL) async {
        if isRuntimeProjection { await performProjectedWorkspaceAction(.changeWorkspace(id, directory), sessionID: id); return }
        guard let vm = sessions.first(where: { $0.id == id }) else { return }
        await restartSession(vm, in: directory, errorContext: "Failed to reinstall hooks for \(id)")
    }

    /// セッションを別ワークスペース（Project）へ移動する。未割当のセッションの割り当て（03 F3）もこれで行う。
    /// 対象を kill し移動先フォルダで再起動する。
    /// `changeWorkspace` と同様に hook を再設置し stream を差し替える。`session.projectID` を更新する。
    public func moveSession(_ id: SessionID, to projectID: ProjectID) async {
        if isRuntimeProjection { await performProjectedWorkspaceAction(.moveSession(id, projectID), sessionID: id); return }
        guard let targetProject = projects.first(where: { $0.id == projectID }) else { return }
        // チャット型は所属だけを付け替える。作業フォルダと会話はそのまま（再起動すると再開条件が変わるため）。
        // 復元で移動先の worktree 設定が作業フォルダを変えないよう、隔離しない印も保存する。
        if case .appServer(let chat) = sessionNode(id: id) {
            guard chat.projectID != projectID, canMoveSession(id) else { return }
            chat.projectID = projectID
            reconcilePaneLayout()
            persistence.persistSessionWorkspace(id: id, workingDirectory: nil, projectID: projectID)
            return
        }
        guard let vm = sessions.first(where: { $0.id == id }) else { return }
        guard vm.projectID != projectID else { return }

        let directory = URL(fileURLWithPath: targetProject.directoryPath, isDirectory: true)
        await restartSession(
            vm,
            in: directory,
            movingTo: projectID,
            errorContext: "Failed to reinstall hooks for \(id) when moving to project \(projectID)"
        )
    }

    /// 別のプロジェクトへ移せるか。自分用の worktree で動くチャット型は移せない
    /// （worktree は元のプロジェクトのリポジトリのもので、再起動せずに付け替えられないため）。
    public func canMoveSession(_ id: SessionID) -> Bool {
        if let runtimeProjectionSnapshot { return !runtimeProjectionSnapshot.immovableSessionIDs.contains(id) }
        guard case .appServer = sessionNode(id: id) else { return true }
        return ownedWorkspaceDirectories[id]?.worktreeRepository == nil
    }

    public func worktreeBranchName(for id: SessionID) -> String? {
        if let runtimeProjectionSnapshot { return runtimeProjectionSnapshot.worktreeBranches[id] }
        guard ownedWorkspaceDirectories[id]?.worktreeRepository != nil else { return nil }
        return WorktreeIsolationPlanner.branchName(for: id)
    }

    /// changeWorkspace / moveSession 共通の再起動シーケンス（R2 で 1 本化）。
    /// hook 再設置 → hook stream 差し替え → 再起動 → descriptor 永続化（B10）の順で行う。
    /// hook stream は AsyncStream の単一コンシューマ前提を守るため finish→新規生成→差し替えする。
    /// `newProjectID` 指定時（moveSession）は再起動完了後に `vm.projectID` を更新する。
    /// hook 再設置に失敗した場合は何も変更せず中断する。
    private func restartSession(
        _ vm: SessionViewModel,
        in directory: URL,
        movingTo newProjectID: ProjectID? = nil,
        errorContext: String
    ) async {
        let id = vm.id
        let projectIDs = Set(vm.projectID.map { [$0] } ?? [])
        if let projectID = vm.projectID {
            guard FileTabDocumentRegistry.shared.beginWorkspaceChange(projectID) else { return }
        }
        defer { FileTabDocumentRegistry.shared.endProjectChanges(for: projectIDs) }
        // フック設定もファイルを書き換えるため、準備前に保存の完了を待つ。
        // 準備に失敗した場合は、既存の規則どおり下書きを維持する。
        await FileTabDocumentRegistry.shared.waitForPendingSaves(for: projectIDs)

        do {
            try sessionHooks.reinstall(
                descriptor: vm.agentDescriptor,
                sessionID: id,
                workingDirectory: directory
            )
        } catch {
            logError(error, context: errorContext)
            return
        }

        // 旧 stream を終端し、新 stream を生成して差し替える。
        // hookMultiplexTask は毎回 dictionary を lookup するため再生成は不要。
        sessionHookContinuations[id]?.finish()
        let (newStream, newContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        sessionHookContinuations[id] = newContinuation

        await vm.restart(workingDirectory: directory.path, hookEvents: newStream)
        if let newProjectID {
            vm.projectID = newProjectID
            reconcilePaneLayout()
        }

        // 再起動後の復元が新しい CWD / project で行われるよう descriptor を更新する（B10）。
        persistence.persistSessionWorkspace(id: id, workingDirectory: directory.path, projectID: vm.projectID)
    }

    /// M6a で実装。指定セッションを停止して `sessions` から除去する。
    @discardableResult
    public func removeSession(_ id: SessionID) async -> Bool {
        if isRuntimeProjection {
            do {
                guard case .bool(let removed) = try await sendRuntimeCommand(.removeSession(id)) else {
                    throw DashboardRuntimeError.unexpectedReply
                }
                return removed
            } catch { runtimeCommandError = error.localizedDescription; return false }
        }
        guard sessionNodes.contains(where: { $0.id == id }) else { return false }

        let affected = subtreeSessionIDsDeepestFirst(rootedAt: id)
        for sessionID in affected {
            guard await removeSingleSession(sessionID) else { return false }
        }
        return true
    }

    public func descendantCount(of id: SessionID) -> Int {
        max(subtreeSessionIDsDeepestFirst(rootedAt: id).count - 1, 0)
    }

    /// 削除で巻き込まれる子孫セッション（浅い順）。削除の確認に名前と状態を並べるために使う（09 D3）。
    public func descendantNodes(of id: SessionID) -> [SessionNode] {
        subtreeSessionIDsDeepestFirst(rootedAt: id).reversed().filter { $0 != id }.compactMap { sessionNode(id: $0) }
    }

    /// ワークスペース削除時にカスケードで波及する、当該ワークスペース外の子孫セッション件数。
    /// 集計は `subtreeSessionIDsDeepestFirst`（`descendantCount` と同根）を各配下セッションに適用し、
    /// ワークスペース内セッション ID を除いた重複なし件数とする。
    /// 削除（`removeProject`）と同じく、サイドバーに出ない内部セッションも含めて数える。
    public func projectDeletionDescendantCount(of projectID: ProjectID) -> Int {
        let projectSessionIDs = Set(gridSessionNodes(in: projectID).map(\.id))
        var affected: Set<SessionID> = []
        for sessionID in projectSessionIDs {
            affected.formUnion(subtreeSessionIDsDeepestFirst(rootedAt: sessionID))
        }
        return affected.subtracting(projectSessionIDs).count
    }

    private func subtreeSessionIDsDeepestFirst(rootedAt rootID: SessionID) -> [SessionID] {
        let existingIDs = Set(sessionNodes.map(\.id))
        guard existingIDs.contains(rootID) else { return [] }

        let childrenByParent = Dictionary(grouping: sessionNodes, by: { $0.controllable.parentSessionID })
        var visited: Set<SessionID> = []
        var result: [SessionID] = []

        func visit(_ id: SessionID) {
            guard existingIDs.contains(id), visited.insert(id).inserted else { return }
            for child in childrenByParent[id] ?? [] {
                visit(child.id)
            }
            result.append(id)
        }

        visit(rootID)
        return result
    }

    private func removeSingleSession(_ id: SessionID) async -> Bool {
        guard !removingSessionIDs.contains(id),
              let node = sessionNodes.first(where: { $0.id == id }) else { return false }
        let session = node.controllable
        let deletedName = node.displayName
        removingSessionIDs.insert(id)
        defer { removingSessionIDs.remove(id) }

        do {
            await synchronizeHistorySessionIDs()
            try await rememberHistoryName(node, name: deletedName)
        } catch {
            runtimeCommandError = "履歴の名前を保存できなかったため削除しませんでした。\(error.localizedDescription)"
            return false
        }

        let firstMessage = runtimeFirstMessages.removeValue(forKey: id)
        firstMessage?.task.cancel()
        sessionHooks.cleanup(for: id)
        await session.terminate()
        await firstMessage?.task.value
        do {
            await synchronizeHistorySessionIDs()
            try await rememberHistoryName(node, name: deletedName)
        } catch {
            runtimeCommandError = "履歴の名前を保存できなかったため登録を残しました。\(error.localizedDescription)"
            return false
        }
        failedNewChatRequests.removeValue(forKey: id)
        await cleanupOwnedWorkspace(for: id)
        sessionHookContinuations[id]?.finish()
        sessionHookContinuations.removeValue(forKey: id)
        codexDiscoveryController.cancel(for: id)
        node.controllable.unseenCompletionDidChange = nil
        sessions.removeAll { $0.id == id }
        removeSessionNode(id: id)
        refreshUnseenCompletionCount()
        spawnTimestamps.removeValue(forKey: id)
        await environment.tokenStore.remove(session: id)
        persistence.removeSession(id)
        normalizeGridSessionSelection()
        return true
    }

    /// MC-2b: モバイルトークンごとの安定 requester。集合の各要素は全 remove（cascade 含む）を
    /// 無条件許可する特権 requester として `SpawnPolicy.isAuthorizedToRemove` へ渡す。
    /// 既定の空集合では認可挙動は従来どおり（ancestor ベース）で不変。
    private var privilegedRequesters: Set<SessionID> = []

    /// 特権 requester 集合を注入する（CompositionRoot から端末ごとの requester SessionID を配線する）。
    /// 空集合を渡すと特権を解除し既定の ancestor ベース認可へ戻す。
    public func setPrivilegedRequesters(_ requesters: Set<SessionID>) {
        privilegedRequesters = requesters
    }

    /// kill(remove) 専用の認可。rename 等へ広げる時点で operation 付きの一般関数へ拡張する。
    public func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool {
        SpawnPolicy.isAuthorizedToRemove(
            id,
            requester: requester,
            parents: parentLinks(),
            privilegedRequesters: privilegedRequesters
        )
    }

    /// SpawnPolicy（pure）に渡す sessionID → parentSessionID の対応表。
    private func parentLinks() -> [SessionID: SessionID?] {
        Dictionary(uniqueKeysWithValues: sessionNodes.map { ($0.id, $0.controllable.parentSessionID) })
    }

    /// 指定セッションの現在のターミナル画面テキストを返す。セッションが存在しない場合は `nil`。
    public func sessionOutput(for id: SessionID) -> String? {
        guard let session = sessionNodes.first(where: { $0.id == id })?.controllable else { return nil }
        return session.readText(lines: 0)
    }

    /// 指定セッションの端末画面を SGR（色・装飾）付きで返す。端末を持たない構造化セッションと
    /// 不在は `nil`。モバイルはこれを端末エミュレータへ流して Mac と同じ見た目で描画する。
    public func sessionAnsiScreen(for id: SessionID) -> AnsiScreen? {
        guard let session = sessionNodes.first(where: { $0.id == id })?.controllable else { return nil }
        return session.readAnsiScreen()
    }

    /// 構造化（appServer）セッションのライブ transcript を返す。
    /// 非構造化（PTY）/不在は `nil`、構造化だが未生成は空配列。Mac GUI の描画元と同一状態。
    public func sessionChatMessages(for id: SessionID) -> [ChatItem]? {
        sessionNodes.first { $0.id == id }?.appServer?.transcript
    }

    public enum ReadinessResult: Sendable {
        case ready
        case timedOut
        case notFound
    }

    public func waitUntilReady(for id: SessionID, timeout: Duration) async -> ReadinessResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            guard let sessionVM = sessionNodes.first(where: { $0.id == id })?.controllable else {
                return .notFound
            }
            if sessionVM.isReadyForInput {
                return .ready
            }
            if clock.now >= deadline {
                return .timedOut
            }

            do {
                try await Task.sleep(for: Self.readinessPollInterval)
            } catch {
                return .timedOut
            }
        }
    }

    public enum DoneResult: Sendable, Equatable {
        case done(output: String)
        case timedOut(output: String)
        case notFound
    }

    public func waitUntilDone(
        for id: SessionID,
        timeout: Duration,
        sentinel: String?
    ) async -> DoneResult {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let deadline = startedAt.advanced(by: timeout)

        guard let initialSession = sessionNodes.first(where: { $0.id == id })?.controllable else {
            return .notFound
        }

        let baselineTurnSeq = initialSession.completedTurnSeq

        // sentinel 評価の再構築抑制用。画面は PTY 出力（= lastOutputAt 更新）でのみ変わるため、
        // 前回評価から lastOutputAt が変わっていなければ画面テキストを再構築しない（P3）。
        var hasEvaluatedSentinel = false
        var lastEvaluatedOutputAt: Date?

        while true {
            guard let sessionVM = sessionNodes.first(where: { $0.id == id })?.controllable else {
                return .notFound
            }

            // turn 完了判定に画面全文の再構築を伴わせない（P3）。output は確定時に 1 回だけ取得する。
            if sessionVM.completedTurnSeq > baselineTurnSeq,
               !dashboardSessionStatusIsAwaitingApproval(sessionVM.status) {
                sessionVM.consumeSubmitBaseline()
                return .done(output: sessionOutput(for: id) ?? "")
            }

            if let base = sessionVM.submitBaselineTurnSeq,
               sessionVM.completedTurnSeq > base,
               !dashboardSessionStatusIsAwaitingApproval(sessionVM.status) {
                sessionVM.consumeSubmitBaseline()
                return .done(output: sessionOutput(for: id) ?? "")
            }

            if let sentinel {
                let outputAt = sessionVM.lastOutputAt
                if !hasEvaluatedSentinel || outputAt != lastEvaluatedOutputAt {
                    hasEvaluatedSentinel = true
                    lastEvaluatedOutputAt = outputAt
                    let output = sessionOutput(for: id) ?? ""
                    if output.contains(sentinel) {
                        sessionVM.consumeSubmitBaseline()
                        return .done(output: output)
                    }
                }
            }

            if clock.now >= deadline {
                return .timedOut(output: sessionOutput(for: id) ?? "")
            }

            do {
                try await Task.sleep(for: Self.donePollInterval)
            } catch {
                return .timedOut(output: sessionOutput(for: id) ?? "")
            }
        }
    }

    public enum SendOutcome: Codable, Sendable, Equatable {
        case sent
        case notFound
        case ambiguous([SessionID])
        case rejected(reason: String)
        case notSpawned
        case deliveryFailed
        case rateLimited
        case imagesUnsupported
        case imageSendInProgress
    }

    public func sendMessage(
        to recipient: Recipient,
        text: String,
        submit: Bool,
        from: SessionID?,
        inReplyTo: UUID? = nil,
        images: [ControlImageAttachment] = []
    ) async -> SendOutcome {
        await sendMessageWithSkill(to: recipient, text: text, submit: submit, from: from,
            inReplyTo: inReplyTo, images: images, skill: nil)
    }

    public func sendMessageWithSkill(to recipient: Recipient, text: String, submit: Bool, from: SessionID?,
        inReplyTo: UUID?, images: [ControlImageAttachment], skill: AgentSkillSelection?) async -> SendOutcome {
        if isRuntimeProjection {
            let target: DashboardRuntimeMessageRequest.Recipient = switch recipient {
            case .id(let id): .id(id)
            case .name(let name): .name(name)
            }
            do {
                guard case .sendOutcome(let outcome) = try await sendRuntimeCommand(.message(.init(
                    recipient: target, text: text, submit: submit, from: from, inReplyTo: inReplyTo,
                    images: images.map { .init(mediaType: $0.mediaType, data: $0.data) }, skill: skill))) else {
                    throw DashboardRuntimeError.unexpectedReply
                }
                return outcome
            } catch {
                runtimeCommandError = error.localizedDescription
                return .deliveryFailed
            }
        }
        return await messaging.send(
            to: recipient,
            text: text,
            submit: submit,
            from: from,
            inReplyTo: inReplyTo,
            images: images,
            skill: skill,
            sessions: sessionNodes
        )
    }

    private func publishRestoredSessionPresentation() {
        guard let selected = sessions.max(by: { $0.startedAt < $1.startedAt }) else { return }
        restoredSessionPresentation = RestoredSessionPresentation(
            selectedSessionID: selected.id,
            expandedProjectIDs: Set(sessions.compactMap(\.projectID))
        )
    }

    private func normalizeSessionNameForUniqueness(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func depth(of id: SessionID) -> Int {
        SpawnPolicy.depth(of: id, parents: parentLinks())
    }

    /// レート制限の消費（タイムスタンプ追記）は上限検査の失敗時も保持する（従来挙動の維持）。
    private func checkAPISpawnLimits(requester: SessionID?, newDepth: Int) throws {
        if let requester {
            spawnTimestamps[requester] = try SpawnPolicy.recordingSpawnAttempt(
                timestamps: spawnTimestamps[requester] ?? [],
                now: rateLimitNow()
            )
        } else {
            unattributedControlAPISpawnTimestamps = try SpawnPolicy.recordingSpawnAttempt(
                timestamps: unattributedControlAPISpawnTimestamps,
                now: rateLimitNow()
            )
        }
        try SpawnPolicy.validateAPISpawn(newDepth: newDepth)
    }

    /// セッション永続化と同じ直列チェーンで保存する（B5）。
    /// 無管理 Task {} だと保存タスクの完了順が保証されず、古いスナップショットが後勝ちしうる。
    private func persistProjects() {
        persistence.persistProjects(projects)
    }

    private static func standardizedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func isContainedInWorkspaceDirectory(_ url: URL) -> Bool {
        let workspaceRoot = environment.workspaceDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let directoryComponents = url.pathComponents
        let rootComponents = workspaceRoot.pathComponents
        guard directoryComponents.count >= rootComponents.count else { return false }
        return Array(directoryComponents.prefix(rootComponents.count)) == rootComponents
    }

    private func cleanupOwnedWorkspace(for sessionID: SessionID) async {
        guard let ownedWorkspace = ownedWorkspaceDirectories[sessionID] else { return }
        let directory = ownedWorkspace.directory
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            ownedWorkspaceDirectories.removeValue(forKey: sessionID)
            return
        }

        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let expectedDirectory = environment.sessionWorkspaceDirectory(for: sessionID)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard normalizedDirectory == expectedDirectory else { return }
        guard isContainedInWorkspaceDirectory(normalizedDirectory) else { return }

        if let repository = ownedWorkspace.worktreeRepository {
            do {
                try await WorktreeIsolationGit.removeWorktree(
                    at: normalizedDirectory,
                    from: repository
                )
            } catch {
                workspaceCleanupWarning = .worktreeRetained(path: normalizedDirectory.path)
                workspaceCleanupFailureReason = Self.cleanupFailureReason(error)
                logError(error, context: "Failed to cleanup worktree for \(sessionID)")
                return
            }

            do {
                try await WorktreeIsolationGit.removeBranch(
                    WorktreeIsolationPlanner.branchName(for: sessionID),
                    from: repository,
                    force: false
                )
            } catch {
                workspaceCleanupWarning = .branchRetained(
                    branchName: WorktreeIsolationPlanner.branchName(for: sessionID)
                )
                workspaceCleanupFailureReason = Self.cleanupFailureReason(error)
                logError(error, context: "Failed to cleanup worktree branch for \(sessionID)")
            }
            ownedWorkspaceDirectories.removeValue(forKey: sessionID)
            return
        }

        do {
            try fm.removeItem(at: normalizedDirectory)
            ownedWorkspaceDirectories.removeValue(forKey: sessionID)
        } catch {
            // 09 D2: 消せなかったファイルとその理由（Permission denied など）を出す。エラーはフォルダしか指さないので、
            // 消し残ったファイルを探す（消せたものは消えている）。
            // ponytail: 最初に見つかった 1 つだけ出す。全部出すなら一覧にしてダイアログの等幅欄に並べる。
            let leftover = fm.enumerator(at: normalizedDirectory, includingPropertiesForKeys: [.isDirectoryKey])?
                .lazy
                .compactMap { $0 as? URL }
                .first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            workspaceCleanupWarning = .workspaceRetained(path: leftover?.path ?? normalizedDirectory.path)
            workspaceCleanupFailureReason = Self.cleanupFailureReason(error)
            logError(error, context: "Failed to cleanup workspace for \(sessionID)")
        }
    }

    private func logError(_ error: Error, context: String) {
        let message = "Phlox: \(context): \(error)\n"
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private func logWarning(_ message: String) {
        let line = "Phlox: [warning] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

extension DashboardViewModel {
    public convenience init(projection snapshot: DashboardRuntimeSnapshot,
                            paneLayoutStore: PaneLayoutStore? = nil,
                            commandHandler: @escaping DashboardRuntimeCommandHandler) throws {
        self.init(projectionCommandHandler: commandHandler, paneLayoutStore: paneLayoutStore)
        try applyRuntimeSnapshot(snapshot)
    }

    public func makeRuntimeSnapshot() throws -> DashboardRuntimeSnapshot {
        try DashboardRuntimeSnapshot(projects: projects, sessions: sessionNodes.map { node in
            switch node {
            case .pty(let session): .pty(try session.makeRuntimeSnapshot())
            case .appServer(let session): .chat(session.makeRuntimeSnapshot())
            }
        }, availableAgentKinds: availableAgentKinds, hasRestoredSessions: hasRestoredSessions,
            immovableSessionIDs: Set(sessionNodes.filter { !canMoveSession($0.id) }.map(\.id)),
            worktreeBranches: Dictionary(uniqueKeysWithValues: sessionNodes.compactMap { node in
                worktreeBranchName(for: node.id).map { (node.id, $0) }
            }), workspaceRoot: runtimeProjectionSnapshot?.workspaceRoot ?? ownedServices?.environment.workspaceDirectory,
            workspaceCleanupWarning: workspaceCleanupWarning, workspaceCleanupFailureReason: workspaceCleanupFailureReason,
            discardedSessionCount: discardedSessionCountNotice, worktreeCreationPath: worktreeCreationPath,
            restoredSessionPresentation: restoredSessionPresentation)
    }

    public func applyRuntimeSnapshot(_ snapshot: DashboardRuntimeSnapshot) throws {
        guard isRuntimeProjection else { throw DashboardRuntimeError.ownedOperationUnavailable }
        guard Set(snapshot.projects.map(\.id)).count == snapshot.projects.count,
              Set(snapshot.sessions.map(\.id)).count == snapshot.sessions.count else {
            throw DashboardRuntimeError.invalidSnapshot("識別子が重複しています")
        }
        for entry in snapshot.sessions {
            if let existing = sessionNodeIndex[entry.id] {
                switch (existing, entry) {
                case (.pty(let vm), .pty(let state)): try vm.validateRuntimeSnapshot(state)
                case (.appServer(let vm), .chat(let state)): try vm.validateRuntimeSnapshot(state)
                default: throw DashboardRuntimeError.invalidSnapshot("セッションの種類が一致しません")
                }
            }
        }
        var updated: [SessionNode] = []
        for entry in snapshot.sessions {
            let node: SessionNode
            let entryID = entry.id
            let handler: SessionRuntimeSessionCommandHandler = { [weak self] executionID, command in
                guard let self else { throw CancellationError() }
                guard case .session(let result) = try await self.sendRuntimeCommand(.session(entryID, executionID, command)) else {
                    throw DashboardRuntimeError.unexpectedReply
                }
                return result
            }
            switch entry {
            case .pty(let state):
                if let current = sessionNodeIndex[state.id]?.pty {
                    node = .pty(current)
                } else {
                    node = .pty(try SessionViewModel(projection: state, commandHandler: handler))
                }
            case .chat(let state):
                if let current = sessionNodeIndex[state.id]?.appServer {
                    node = .appServer(current)
                } else {
                    node = .appServer(ChatSessionViewModel(projection: state, commandHandler: handler))
                    node.appServer?.resumeConversationHandler = { [weak self] in
                        Task { await self?.resumeEndedChatSession(entryID) }
                    }
                }
            }
            updated.append(node)
        }
        for (node, entry) in zip(updated, snapshot.sessions) {
            guard sessionNodeIndex[entry.id] != nil else { continue }
            switch (node, entry) {
            case (.pty(let vm), .pty(let state)): try vm.applyRuntimeSnapshot(state)
            case (.appServer(let vm), .chat(let state)): try vm.applyRuntimeSnapshot(state)
            default: throw DashboardRuntimeError.invalidSnapshot("セッションの種類が一致しません")
            }
        }
        let addedIDs = Set(updated.map(\.id)).subtracting(sessionNodeIndex.keys)
        runtimeProjectionSnapshot = snapshot
        projects = snapshot.projects
        sessionNodes = updated
        sessions = updated.compactMap(\.pty)
        sessionNodeIndex = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        hasRestoredSessions = snapshot.hasRestoredSessions
        layoutRestoreInProgress = false
        workspaceCleanupWarning = snapshot.workspaceCleanupWarning
        workspaceCleanupFailureReason = snapshot.workspaceCleanupFailureReason
        discardedSessionCountNotice = snapshot.discardedSessionCount
        for id in addedIDs { gridSessionSelectionDidSpawn(id) }
        reconcilePaneLayout(persist: paneLayoutStore != nil)
        normalizeGridSessionSelection()
        refreshUnseenCompletionCount()
        if !hasAppliedInitialRuntimePresentation, snapshot.hasRestoredSessions {
            hasAppliedInitialRuntimePresentation = true
            let visible = sessionNodes.filter { isReachableFromUI($0.id, from: .desktop) }
            if let original = snapshot.restoredSessionPresentation,
               visible.contains(where: { $0.id == original.selectedSessionID }) {
                restoredSessionPresentation = original
            } else if let recent = visible.max(by: { $0.startedAt < $1.startedAt }) {
                restoredSessionPresentation = .init(selectedSessionID: recent.id,
                    expandedProjectIDs: Set(visible.compactMap(\.projectID)))
            }
        }
    }

    public func performRuntimeCommand(_ command: DashboardRuntimeCommand) async throws -> DashboardRuntimeReply {
        guard !isRuntimeProjection else { throw DashboardRuntimeError.ownedOperationUnavailable }
        switch command {
        case .session(let id, let executionID, let command):
            guard let node = sessionNode(id: id) else { throw DashboardRuntimeError.sessionNotFound }
            switch node {
            case .pty(let vm): return .session(try await vm.performRuntimeCommand(command, expectedExecutionID: executionID))
            case .appServer(let vm):
                guard vm.executionID == executionID else { throw SessionRuntimeProjectionError.staleExecution }
                switch command {
                case .interrupt, .terminate: runtimeFirstMessages[id]?.task.cancel()
                default: break
                }
                return .session(try await vm.performRuntimeCommand(command, expectedExecutionID: executionID))
            }
        case .spawn(let request):
            return .sessionID(try await spawnNewSession(ref: request.ref, projectID: request.projectID,
                from: request.parentSessionID, backend: request.backend, launchContext: request.launchContext,
                extraEnv: request.extraEnv, workingDirectoryOverride: request.workingDirectoryOverride,
                isolationOverride: request.isolationOverride, worktreeStartPoint: request.worktreeStartPoint,
                initialSettings: request.initialSettings, resumeHistoryEntry: request.resumeHistoryEntry,
                keepsRowOnLaunchFailure: request.keepsRowOnLaunchFailure))
        case .launchNewChat(let request):
            return .acceptedSession(try await Self.$reportsWorktreeCreation.withValue(true) {
                try await launchNewChat(request, firstMessageDelivery: .acceptIntoRuntime)
            })
        case .restartNewChat(let id):
            return .sessionID(try await Self.$reportsWorktreeCreation.withValue(true) {
                try await restartNewChat(id)
            })
        case .resumeChat(let id): await resumeEndedChatSession(id)
        case .addProject(let name, let path): return .projectID(addProject(name: name, directoryPath: path))
        case .renameProject(let id, let name): renameProject(id, to: name)
        case .renameSession(let id, let name): renameSession(id, to: name)
        case .reorderSession(let source, let target): reorderSession(source, with: target)
        case .moveSession(let id, let project): await moveSession(id, to: project)
        case .changeWorkspace(let id, let directory): await changeWorkspace(id, to: directory)
        case .removeSession(let id):
            runtimeCommandError = nil
            let removed = await removeSession(id)
            if !removed, let reason = runtimeCommandError { throw DashboardRuntimeError.removalFailed(reason) }
            return .bool(removed)
        case .removeProject(let id):
            runtimeCommandError = nil
            await removeProject(id)
            if let reason = runtimeCommandError { throw DashboardRuntimeError.removalFailed(reason) }
        case .history(let project, let ref): return .history(try await newChatHistoryEntries(projectID: project, agentRef: ref))
        case .persistRole(let id, let role): persistSessionRole(id: id, role: role)
        case .clearWorkspaceCleanupWarning: clearWorkspaceCleanupWarning()
        case .takeDiscardedSessionCountNotice: _ = takeDiscardedSessionCountNotice()
        case .usage: throw DashboardRuntimeError.ownedOperationUnavailable
        case .message(let request):
            let recipient: Recipient = switch request.recipient {
            case .id(let id): .id(id)
            case .name(let name): .name(name)
            }
            return .sendOutcome(await sendMessageWithSkill(to: recipient, text: request.text, submit: request.submit,
                from: request.from, inReplyTo: request.inReplyTo,
                images: request.images.map { .init(mediaType: $0.mediaType, data: $0.data) }, skill: request.skill))
        }
        return .none
    }

    public func addProjectFromRuntime(name: String, directoryPath: String) async throws -> ProjectID? {
        guard isRuntimeProjection else { return addProject(name: name, directoryPath: directoryPath) }
        guard case .projectID(let id) = try await sendRuntimeCommand(.addProject(name: name, directoryPath: directoryPath)) else {
            throw DashboardRuntimeError.unexpectedReply
        }
        return id
    }

    private func sendRuntimeCommand(_ command: DashboardRuntimeCommand) async throws -> DashboardRuntimeReply {
        try await beginRuntimeCommand(command).value
    }

    private func beginRuntimeCommand(_ command: DashboardRuntimeCommand) throws -> Task<DashboardRuntimeReply, Error> {
        guard let runtimeCommandHandler else { throw DashboardRuntimeError.ownedOperationUnavailable }
        let immediate = command.isImmediateSessionControl
        if immediate {
            guard pendingRuntimeControlCount < 32 else { throw DashboardRuntimeError.commandQueueFull }
            pendingRuntimeControlCount += 1
        } else {
            guard pendingRuntimeCommandCount < 256 else { throw DashboardRuntimeError.commandQueueFull }
            pendingRuntimeCommandCount += 1
        }
        let previous = immediate ? nil : runtimeCommandTail
        let request = Task { @MainActor [weak self] in
            defer {
                if immediate { self?.pendingRuntimeControlCount -= 1 }
                else { self?.pendingRuntimeCommandCount -= 1 }
            }
            await previous?.value
            do {
                let reply = try await runtimeCommandHandler(command)
                switch (command, reply) {
                case (.session, .session), (.spawn, .sessionID), (.launchNewChat, .acceptedSession),
                     (.restartNewChat, .sessionID), (.addProject, .projectID), (.removeSession, .bool),
                     (.history, .history), (.message, .sendOutcome): break
                case (.resumeChat, .none), (.renameProject, .none), (.renameSession, .none),
                     (.reorderSession, .none), (.moveSession, .none), (.changeWorkspace, .none),
                     (.removeProject, .none), (.persistRole, .none), (.clearWorkspaceCleanupWarning, .none),
                     (.takeDiscardedSessionCountNotice, .none), (.usage, .none): break
                default: throw DashboardRuntimeError.unexpectedReply
                }
                self?.runtimeCommandError = nil
                return reply
            } catch {
                self?.runtimeCommandError = error.localizedDescription
                throw error
            }
        }
        if !immediate { runtimeCommandTail = Task { _ = await request.result } }
        return request
    }

    private func enqueueProjectedAction(_ command: DashboardRuntimeCommand) {
        do { _ = try beginRuntimeCommand(command) }
        catch { runtimeCommandError = error.localizedDescription }
    }

    private func performProjectedAction(_ command: DashboardRuntimeCommand) async {
        do { _ = try await sendRuntimeCommand(command) }
        catch { runtimeCommandError = error.localizedDescription }
    }

    private func performProjectedWorkspaceAction(_ command: DashboardRuntimeCommand, sessionID: SessionID) async {
        let projectID = sessionNode(id: sessionID)?.projectID
        if let projectID, !FileTabDocumentRegistry.shared.beginWorkspaceChange(projectID) { return }
        let projects = Set(projectID.map { [$0] } ?? [])
        defer { FileTabDocumentRegistry.shared.endProjectChanges(for: projects) }
        await FileTabDocumentRegistry.shared.waitForPendingSaves(for: projects)
        await performProjectedAction(command)
    }

    public func clearRuntimeCommandError() { runtimeCommandError = nil }
}
