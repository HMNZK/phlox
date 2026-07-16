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

/// セッション一覧と新規作成・削除を担当する。
///
/// API 契約 (M6a で本実装、M6b は本シグネチャに依存):
/// - `init` の引数を変更しないこと
/// - public プロパティ / メソッドの追加は可、削除・名称変更は不可
@MainActor
@Observable
public final class DashboardViewModel {
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
    public private(set) var restoredSessionPresentation: RestoredSessionPresentation?

    /// グリッドに表示するセッションの選択（nil = 全表示）。永続化しない。
    public var gridSessionSelection: Set<SessionID>? {
        didSet {
            guard oldValue != gridSessionSelection else { return }
            reconcileGridArrangements()
        }
    }
    /// グリッドのワークスペース絞り込み（`AppRouter.gridFilterProjectID` の写し。候補算出用）。
    var gridSessionFilterProjectID: ProjectID? {
        didSet {
            guard oldValue != gridSessionFilterProjectID else { return }
            reconcileGridArrangements()
        }
    }

    private static let readinessPollInterval: Duration = .milliseconds(20)
    private static let donePollInterval: Duration = .milliseconds(100)
    private static let agoraDiscussionPollInterval: Duration = .milliseconds(350)
    /// API 経由 spawn の制限値（実体は SpawnPolicy、R2）。
    static let maxAPISpawnDepth = SpawnPolicy.maxAPISpawnDepth
    static let maxAPISpawnCountPerSecond = SpawnPolicy.maxAPISpawnCountPerSecond
    static let apiSpawnRateLimitWindowSeconds = SpawnPolicy.apiSpawnRateLimitWindowSeconds

    private let environment: AppEnvironment
    @ObservationIgnored private let gridArrangementStore: GridArrangementStore
    private var gridArrangements: [Int: SessionGridArrangement]
    @ObservationIgnored private var gridArrangementRestoreInProgress = true
    private var hookMultiplexTask: Task<Void, Never>?
    private var sessionHookContinuations: [SessionID: AsyncStream<(SessionID, HookEvent)>.Continuation] = [:]
    private var spawnTimestamps: [SessionID: [Date]] = [:]
    private let sessionHooks: SessionHookInstaller
    private var ownedWorkspaceDirectories: [SessionID: URL] = [:]
    /// 永続化の直列実行キュー。すべての保存はこの coordinator 経由で行う。
    private let persistence: SessionPersistenceCoordinator
    /// エージェント間メッセージング（送信・レート制限・記録）。
    private let messaging: MessagingService
    /// アゴラ討論の実セッション配線。UI はここから phase/participants などを読む。
    public private(set) var agoraDiscussionCoordinator: AgoraDiscussionCoordinator?
    @ObservationIgnored private var agoraDiscussionPollTask: Task<Void, Never>?
    @ObservationIgnored private var spawnService: SessionSpawnService?
    @ObservationIgnored private var restoreCoordinator: SessionRestoreCoordinator?
    private let codexUserHooksEnabledProvider: @MainActor () -> Bool
    private let codexDiscoveryNow: @Sendable () -> Date
    /// spawn 後に当該セッションの live pid を引くための seam。永続化する pid の取得元。
    /// 既定は nil（pid 未捕捉＝従来挙動。descriptor の pid は nil のまま）。
    /// PTYManager は actor で pid アクセサが actor 隔離 async のため、seam も async とし
    /// CompositionRoot で `{ id in await pty.pid(for: id) }` を渡す。pid 未取得時は nil
    /// フォールバック（後方互換）。
    private let livePIDProvider: @MainActor @Sendable (SessionID) async -> pid_t?
    /// rollout 走査で claim 済みの native id（永続化完了前の二重割当防止）。
    @ObservationIgnored private var codexDiscovery: CodexNativeSessionDiscoveryController?
    private var lastUsedChatSettingsStore = LastUsedChatSettingsStore()

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

    public init(
        environment: AppEnvironment,
        codexUserHooksEnabledProvider: @escaping @MainActor () -> Bool = {
            CodexUserHooksSettings.isEnabled()
        },
        codexDiscoveryRetryInterval: Duration = .milliseconds(500),
        codexDiscoveryMaxRetryDuration: Duration = .seconds(120),
        codexDiscoveryNow: @escaping @Sendable () -> Date = Date.init,
        orphanReaper: any OrphanReaper = PosixOrphanReaper(),
        livePIDProvider: @escaping @MainActor @Sendable (SessionID) async -> pid_t? = { _ in nil },
        gridArrangementStore: GridArrangementStore = GridArrangementStore(userDefaults: .standard)
    ) {
        self.environment = environment
        self.gridArrangementStore = gridArrangementStore
        self.gridArrangements = Dictionary(uniqueKeysWithValues: (1...4).map { size in
            (size, gridArrangementStore.load(size: size) ?? SessionGridArrangement(size: size))
        })
        self.codexUserHooksEnabledProvider = codexUserHooksEnabledProvider
        self.codexDiscoveryNow = codexDiscoveryNow
        self.livePIDProvider = livePIDProvider
        self.sessionHooks = SessionHookInstaller(
            dispatcherPath: environment.hookDispatcherPath,
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        self.persistence = SessionPersistenceCoordinator(
            sessionStore: environment.sessions,
            projectStore: environment.projects,
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
        self.messaging = MessagingService(
            pty: environment.pty,
            messages: environment.messages
        )
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
            registerOwnedWorkspace: { [weak self] sessionID, url in
                self?.ownedWorkspaceDirectories[sessionID] = url
            },
            cleanupOwnedWorkspace: { [weak self] sessionID in
                self?.cleanupOwnedWorkspace(for: sessionID)
            },
            lastUsedChatSettings: { [weak self] agentID in
                self?.lastUsedChatSettingsStore.lastUsed(agentID: agentID)
            },
            recordLastUsedChatSettings: { [weak self] agentID, model, effort in
                self?.lastUsedChatSettingsStore.record(
                    agentID: agentID,
                    model: model,
                    effort: effort
                )
            },
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
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
                self?.appendSessionNode(.appServer(vm))
                self?.refreshUnseenCompletionCount()
            },
            refreshUnseenCompletionCount: { [weak self] in
                self?.refreshUnseenCompletionCount()
            },
            publishRestoredSessionPresentation: { [weak self] in
                self?.publishRestoredSessionPresentation()
            },
            logError: { error, context in
                let message = "Phlox: \(context): \(error)\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        )
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

    private func observeUnseenCompletion(for session: SessionViewModel) {
        session.unseenCompletionDidChange = { [weak self] in
            self?.refreshUnseenCompletionCount()
        }
    }

    private func refreshUnseenCompletionCount() {
        let count = sessions.filter { $0.hasUnseenCompletion }.count
        guard count != unseenCompletionCount else { return }
        unseenCompletionCount = count
        unseenCompletionCountDidChange?(count)
    }

    /// M6a で実装。HookServer の events ストリームを購読し、SessionViewModel へディスパッチする。
    /// セッション復元: 保存 descriptor を現在の環境で再 plan し、アプリ内蔵 PTY で再 spawn する。
    public func start() async {
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
        gridArrangementRestoreInProgress = false
        reloadAndReconcileGridArrangements()
    }

    /// 新規セッションで選択できる CLI。起動時に解決できたものだけを返す（Claude Code は常に先頭）。
    public var availableAgentKinds: [AgentKind] {
        [.claudeCode] + AgentRegistry.optionalBinaryKinds.filter {
            environment.binaryPath(for: $0) != nil
        }
    }

    /// 新規セッションで選択できる CLI descriptor。組込互換 API とは別に custom も含める。
    public var availableAgentDescriptors: [AgentDescriptor] {
        [AgentRegistry.descriptor(for: .claudeCode)]
            + environment.agentCatalog.optionalDescriptors.filter {
                environment.binaryPath(for: $0.ref) != nil
            }
    }

    /// 新規セッションの既定ワークスペース。選択中セッションの project、なければ先頭プロジェクト。
    public func defaultProjectID(forSelectedSession selectedSessionID: SessionID?) -> ProjectID? {
        if let selectedID = selectedSessionID,
           let session = sessions.first(where: { $0.id == selectedID }),
           let projectID = session.projectID {
            return projectID
        }
        return projects.first?.id
    }

    /// メニュー・ショートカット向け: 既定ワークスペースを解決して `spawnNewSession` する。
    @discardableResult
    public func spawnNewSessionUsingDefaultProject(
        kind: AgentKind,
        selectedSessionID: SessionID?,
        selectedProjectID: ProjectID? = nil
    ) async throws -> SessionID {
        try await spawnNewSessionUsingDefaultProject(
            ref: .builtin(kind),
            selectedSessionID: selectedSessionID,
            selectedProjectID: selectedProjectID
        )
    }

    @discardableResult
    public func spawnNewSessionUsingDefaultProject(
        ref: AgentRef,
        selectedSessionID: SessionID?,
        selectedProjectID: ProjectID? = nil
    ) async throws -> SessionID {
        guard let projectID = selectedProjectID ?? defaultProjectID(forSelectedSession: selectedSessionID) else {
            throw AgentSpawnError.noProject
        }
        let descriptor = sessionSpawnService.descriptorForPresentation(ref: ref)
        let backend = DefaultSessionBackendPreference.stored()
            .resolveBackend(supportsStructuredChat: descriptor.supportsStructuredChat)
        return try await spawnNewSession(ref: ref, projectID: projectID, backend: backend)
    }

    /// GUI の対話的 spawn（メニュー等）向けに、設定とエージェント能力から backend を解決する。
    public func defaultBackendForGUISpawn(ref: AgentRef) -> SessionBackend {
        let descriptor = sessionSpawnService.descriptorForPresentation(ref: ref)
        return DefaultSessionBackendPreference.stored()
            .resolveBackend(supportsStructuredChat: descriptor.supportsStructuredChat)
    }

    /// 指定ワークスペース（Project）に属するセッション一覧。
    public func sessions(in projectID: ProjectID) -> [SessionViewModel] {
        sessions.filter { $0.projectID == projectID }
    }

    public func sessionNodes(in projectID: ProjectID) -> [SessionNode] {
        sessionNodes.filter { $0.projectID == projectID && Self.isVisibleInSidebar($0) }
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
        let sidebarNodeIDs = Set(sessionForest(in: projectID).flatMap(Self.sessionTreeNodeIDs))
        return sessionNodes.contains { node in
            sidebarNodeIDs.contains(node.id) && node.pty?.hasUnseenCompletion == true
        }
    }

    public func sessionNode(id: SessionID) -> SessionNode? {
        sessionNodeIndex[id]
    }

    /// `sessionNodes` への追加は必ずこのヘルパー経由で行い、`sessionNodeIndex` の同期漏れを防ぐ。
    private func appendSessionNode(_ node: SessionNode) {
        sessionNodes.append(node)
        sessionNodeIndex[node.id] = node
        reconcileGridArrangements(persist: !gridArrangementRestoreInProgress)
    }

    /// `sessionNodes` からの単一 ID 除去は必ずこのヘルパー経由で行い、`sessionNodeIndex` の同期漏れを防ぐ。
    private func removeSessionNode(id: SessionID) {
        sessionNodes.removeAll { $0.id == id }
        sessionNodeIndex.removeValue(forKey: id)
        reconcileGridArrangements(persist: !gridArrangementRestoreInProgress)
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

    /// プロジェクト絞り込み無しグリッドに表示するセッション（内部 orchestration を除外）。
    public var gridVisibleSessionNodes: [SessionNode] {
        sessionNodes.filter { Self.isVisibleInGrid(launchContext: $0.launchContext) }
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
        return GridSessionSelectionFilter.apply(wrapped, selection: gridSessionSelection).map(\.node)
    }

    /// イベント側で reconcile 済みの保持配置を返す。読み取り中に状態更新や永続化は行わない。
    public func gridArrangement(size: Int) -> SessionGridArrangement {
        precondition((1...4).contains(size))
        return gridArrangements[size] ?? SessionGridArrangement(size: size)
    }

    /// 固定グリッドの操作を配置モデルへ委譲し、成功時だけ状態と永続化を更新する。
    public func handleGridAction(_ action: SessionGridAction, size: Int) {
        precondition((1...4).contains(size))
        guard let current = gridArrangements[size] else { return }

        let updated: SessionGridArrangement?
        switch action {
        case .moveToCell(let id, let cell):
            updated = current.move(id, toCell: cell)
        case .swap(let first, let second):
            updated = current.swap(first, second)
        case .mergeRight(let id):
            updated = current.mergeRight(id)
        case .mergeDown(let id):
            updated = current.mergeDown(id)
        case .unmerge(let id):
            updated = current.unmerge(id)
        }

        guard let updated else { return }
        let reconciled = updated.reconciled(with: visibleGridSessionIDs())
        gridArrangements[size] = reconciled
        gridArrangementStore.save(reconciled, size: size)
    }

    private func visibleGridSessionIDs() -> [SessionID] {
        filteredGridSessionNodes(projectID: gridSessionFilterProjectID).map(\.id)
    }

    private func reconcileGridArrangements(persist: Bool = true) {
        let visibleIDs = visibleGridSessionIDs()
        for size in 1...4 {
            let current = gridArrangements[size] ?? SessionGridArrangement(size: size)
            let reconciled = current.reconciled(with: visibleIDs)
            gridArrangements[size] = reconciled
            if persist {
                gridArrangementStore.save(reconciled, size: size)
            }
        }
    }

    private func reloadAndReconcileGridArrangements() {
        for size in 1...4 {
            gridArrangements[size] = gridArrangementStore.load(size: size)
                ?? SessionGridArrangement(size: size)
        }
        reconcileGridArrangements()
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

    private func gridSessionSelectionDidSpawn(_ id: SessionID) {
        guard gridSessionSelection != nil else { return }
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
        for session in sessions {
            session.terminalCoordinator.applyActivePalette()
        }
    }

    /// 文字サイズを delta だけ増減し、全セッションへ即時適用して永続化する。
    public func adjustTerminalFontSize(by delta: CGFloat) {
        let newSize = TerminalFontSettings.adjusted(
            from: TerminalFontSettings.currentSize(),
            by: delta
        )
        TerminalFontSettings.save(newSize)

        let chatDelta = delta / TerminalFontSettings.step * ChatFontSettings.step
        let newChatScale = ChatFontSettings.adjusted(
            from: ChatFontSettings.currentScale(),
            by: chatDelta
        )
        ChatFontSettings.save(newChatScale)

        for session in sessions {
            session.terminalCoordinator.applyFontSize(newSize)
        }
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
            if isRunning(node.status) {
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
                    agentRef: node.agentRef
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

    public func renameProject(_ projectID: ProjectID, to name: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].name = name
        persistProjects()
    }

    /// セッション名を変更する。空白のみの名前はトリムして空にする。
    public func renameSession(_ id: SessionID, to name: String) {
        guard let vm = sessionNodes.first(where: { $0.id == id })?.controllable else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        vm.name = trimmed
        persistence.persistSessionName(id: id, name: trimmed)
    }

    /// アゴラ討論の役割を descriptor に永続化する（ControlActionDashboard の witness。renameSession と同型）。
    public func persistSessionRole(id: SessionID, role: String) {
        persistence.persistSessionRole(id: id, role: role)
    }

    /// spawn の着地 witness（ControlActionDashboard）。討論進行中で、role 付き spawn
    /// または討論参加者（ファシリテーター等）からの spawn なら討論参加者として登録する
    /// （--role 忘れでもリレーが成立するように要求者ベースでも拾う。登録可否の最終判断
    /// ＝maxAgents 上限と参加プロンプト注入は coordinator/engine 側が担う）。
    public func agoraParticipantLanded(id: SessionID, role: String?, requester: SessionID?) {
        guard let coordinator = agoraDiscussionCoordinator, !coordinator.phase.isEnded else { return }
        let requesterIsParticipant = requester.map { r in
            coordinator.participants.contains { $0.id == r }
        } ?? false
        guard role != nil || requesterIsParticipant else { return }
        Task { await self.addAgoraDiscussionParticipant(id: id, role: role) }
    }

    /// グリッドのドラッグ&ドロップで source と target の2セッションだけを入れ替える（スワップ）。
    /// 間のセッションは動かさず、表示順と永続化配列の順を一致させて再起動後も並びを保持する。
    public func reorderSession(_ source: SessionID, with target: SessionID) {
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
        let sessionIDs = sessionNodes
            .filter { $0.projectID == projectID }
            .map(\.id)
        for sessionID in sessionIDs {
            await removeSession(sessionID)
        }
        projects.removeAll { $0.id == projectID }
        persistProjects()
        // フィルタ中プロジェクトの削除で filteredGridSessionNodes がフォールバック（全表示）へ
        // 切り替わるため、新しい可視集合で配置を再整合する（イベント側の書き込み）。
        reconcileGridArrangements(persist: !gridArrangementRestoreInProgress)
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
        workingDirectoryOverride: String? = nil
    ) async throws -> SessionID {
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
        let newDepth = from.map { depth(of: $0) + 1 } ?? 0
        if let from {
            try checkAPISpawnLimits(from: from, newDepth: newDepth)
        }

        // API 経由で projectID 未指定かつ親ありのとき、親と同じワークスペース（CWD）で子を起動する。
        let resolvedProjectID = sessionSpawnService.resolveProjectID(explicit: projectID, parentSessionID: from)

        let sessionID = SessionID()
        let token = SessionSpawnService.makeToken()
        await environment.tokenStore.register(token, for: sessionID)

        // 明示の override を最優先し、無ければ project から CWD を導出する。
        let resolvedWorkingDirectory = workingDirectoryOverride
            ?? sessionSpawnService.resolvedWorkingDirectoryPath(projectID: resolvedProjectID, sessionID: sessionID)

        let resumeID = await sessionSpawnService.initialResumeID(for: ref, sessionID: sessionID)

        let plan: AgentLaunchPlan
        do {
            plan = try sessionSpawnService.prepareSessionLaunch(
                ref: ref,
                sessionID: sessionID,
                sessionToken: token,
                workingDirectoryOverride: resolvedWorkingDirectory,
                projectID: resolvedProjectID,
                launchMode: .newSession(resumeID: resumeID),
                backend: resolvedBackend,
                extraEnv: extraEnv
            )
        } catch AgentLaunchPlannerError.binaryNotFound(let k) {
            await environment.tokenStore.remove(session: sessionID)
            cleanupOwnedWorkspace(for: sessionID)
            throw AgentSpawnError.binaryNotFound(k)
        } catch AgentLaunchPlannerError.customBinaryNotFound(let id) {
            await environment.tokenStore.remove(session: sessionID)
            cleanupOwnedWorkspace(for: sessionID)
            throw AgentSpawnError.customBinaryNotFound(id)
        } catch {
            await environment.tokenStore.remove(session: sessionID)
            cleanupOwnedWorkspace(for: sessionID)
            throw error
        }

        let usedNames = Set(sessionNodes.map { normalizeSessionNameForUniqueness($0.controllable.name) })
        let generatedName = FlowerNameGenerator.random(avoiding: usedNames)
        let codexThreadId: String?
        let chatNativeSessionId: String?
        let appServerUserAgent: String?
        let sessionName: String

        switch resolvedBackend {
        case .pty:
            let sessionVM = sessionSpawnService.makeSessionViewModel(
                id: sessionID,
                projectID: resolvedProjectID,
                parentSessionID: from,
                name: "",
                plan: plan,
                launchContext: launchContext
            )
            sessionVM.name = generatedName

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
            sessionName = sessionVM.name
        case .appServer:
            let result = try await sessionSpawnService.startAppServerSession(
                id: sessionID,
                ref: ref,
                projectID: resolvedProjectID,
                parentSessionID: from,
                name: generatedName,
                plan: plan,
                launchContext: launchContext
            )
            appendSessionNode(.appServer(result.vm))
            refreshUnseenCompletionCount()
            codexThreadId = result.codexThreadId
            chatNativeSessionId = result.chatNativeSessionId
            appServerUserAgent = result.appServerUserAgent
            sessionName = result.sessionName
        }

        // 再起動後の復元に備えてセッションメタを永続化する。
        // spawn 済みセッションの live pid を記録し、次回起動の reconcile（生存孤児 reap）に使う。
        let descriptor = PersistedSessionDescriptor(
            id: sessionID,
            agentRef: ref,
            workingDirectory: plan.workingDirectory ?? resolvedWorkingDirectory ?? "",
            name: sessionName,
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
            parentSessionID: from,
            pid: await livePIDProvider(sessionID),
            launchContext: launchContext
        )
        persistence.persistSession(descriptor)

        // 生成成功を App 層へ通知する（解析配線用、PII なし）。
        sessionDidSpawn?(ref)

        gridSessionSelectionDidSpawn(sessionID)

        return sessionID
    }

    /// M6a で実装。新規 Claude Code セッションをプレースホルダとして `sessions` に追加する。
    public func spawnNewClaudeCodeSession() async throws {
        try await spawnNewSession(kind: .claudeCode)
    }

    /// 指定セッションのワークスペース (CWD) を変更する。対象セッションを kill し、
    /// 新 directory を CWD として再起動する（進行中の作業は失われる）。
    /// hook stream は AsyncStream の単一コンシューマ前提を守るため finish→新規生成→差し替えする。
    public func changeWorkspace(_ id: SessionID, to directory: URL) async {
        guard let vm = sessions.first(where: { $0.id == id }) else { return }
        await restartSession(vm, in: directory, errorContext: "Failed to reinstall hooks for \(id)")
    }

    /// セッションを別ワークスペース（Project）へ移動する。対象を kill し移動先フォルダで再起動する。
    /// `changeWorkspace` と同様に hook を再設置し stream を差し替える。`session.projectID` を更新する。
    public func moveSession(_ id: SessionID, to projectID: ProjectID) async {
        guard let vm = sessions.first(where: { $0.id == id }) else { return }
        guard vm.projectID != nil else { return }
        guard vm.projectID != projectID else { return }
        guard let targetProject = projects.first(where: { $0.id == projectID }) else { return }

        let directory = URL(fileURLWithPath: targetProject.directoryPath, isDirectory: true)
        await restartSession(
            vm,
            in: directory,
            movingTo: projectID,
            errorContext: "Failed to reinstall hooks for \(id) when moving to project \(projectID)"
        )
    }

    /// changeWorkspace / moveSession 共通の再起動シーケンス（R2 で 1 本化）。
    /// hook 再設置 → hook stream 差し替え → 再起動 → descriptor 永続化（B10）の順で行う。
    /// hook stream は AsyncStream の単一コンシューマ前提を守るため finish→新規生成→差し替えする。
    /// `newProjectID` 指定時（moveSession）は再起動前に `vm.projectID` を更新する。
    /// hook 再設置に失敗した場合は何も変更せず中断する。
    private func restartSession(
        _ vm: SessionViewModel,
        in directory: URL,
        movingTo newProjectID: ProjectID? = nil,
        errorContext: String
    ) async {
        let id = vm.id

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

        if let newProjectID {
            vm.projectID = newProjectID
            reconcileGridArrangements()
        }
        await vm.restart(workingDirectory: directory.path, hookEvents: newStream)

        // 再起動後の復元が新しい CWD / project で行われるよう descriptor を更新する（B10）。
        persistence.persistSessionWorkspace(id: id, workingDirectory: directory.path, projectID: vm.projectID)
    }

    /// M6a で実装。指定セッションを停止して `sessions` から除去する。
    @discardableResult
    public func removeSession(_ id: SessionID) async -> Bool {
        guard sessionNodes.contains(where: { $0.id == id }) else { return false }

        for sessionID in subtreeSessionIDsDeepestFirst(rootedAt: id) {
            await removeSingleSession(sessionID)
        }
        return true
    }

    public func descendantCount(of id: SessionID) -> Int {
        max(subtreeSessionIDsDeepestFirst(rootedAt: id).count - 1, 0)
    }

    /// ワークスペース削除時にカスケードで波及する、当該ワークスペース外の子孫セッション件数。
    /// 集計は `subtreeSessionIDsDeepestFirst`（`descendantCount` と同根）を各配下セッションに適用し、
    /// ワークスペース内セッション ID を除いた重複なし件数とする。
    public func projectDeletionDescendantCount(of projectID: ProjectID) -> Int {
        let projectSessionIDs = Set(sessionNodes(in: projectID).map(\.id))
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

    private func removeSingleSession(_ id: SessionID) async {
        guard let node = sessionNodes.first(where: { $0.id == id }) else { return }
        let session = node.controllable

        sessionHooks.cleanup(for: id)
        await session.terminate()
        cleanupOwnedWorkspace(for: id)
        sessionHookContinuations[id]?.finish()
        sessionHookContinuations.removeValue(forKey: id)
        codexDiscoveryController.cancel(for: id)
        node.pty?.unseenCompletionDidChange = nil
        sessions.removeAll { $0.id == id }
        removeSessionNode(id: id)
        refreshUnseenCompletionCount()
        spawnTimestamps.removeValue(forKey: id)
        await environment.tokenStore.remove(session: id)
        persistence.removeSession(id)
        normalizeGridSessionSelection()
    }

    /// MC-2b: モバイルトークンの安定 requester。設定時は全 remove（cascade 含む）を
    /// 無条件許可する特権 requester として `SpawnPolicy.isAuthorizedToRemove` へ渡す。
    /// 既定 nil では認可挙動は従来どおり（ancestor ベース）で不変。
    private var privilegedRequester: SessionID?

    /// 特権 requester を注入する（CompositionRoot から mobileRequesterSessionID を配線する）。
    /// nil を渡すと特権を解除し既定の ancestor ベース認可へ戻す。
    public func setPrivilegedRequester(_ requester: SessionID?) {
        privilegedRequester = requester
    }

    /// kill(remove) 専用の認可。rename 等へ広げる時点で operation 付きの一般関数へ拡張する。
    public func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool {
        SpawnPolicy.isAuthorizedToRemove(
            id,
            requester: requester,
            parents: parentLinks(),
            privilegedRequester: privilegedRequester
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

    public enum SendOutcome: Sendable, Equatable {
        case sent
        case notFound
        case ambiguous([SessionID])
        case rejected(reason: String)
        case notSpawned
        case deliveryFailed
        case rateLimited
        case imagesUnsupported
    }

    public func sendMessage(
        to recipient: Recipient,
        text: String,
        submit: Bool,
        from: SessionID?,
        inReplyTo: UUID? = nil,
        images: [ControlImageAttachment] = []
    ) async -> SendOutcome {
        await messaging.send(
            to: recipient,
            text: text,
            submit: submit,
            from: from,
            inReplyTo: inReplyTo,
            images: images,
            sessions: sessionNodes
        )
    }

    @discardableResult
    public func startAgoraDiscussion(
        agenda: String,
        config: AgoraDiscussionConfig? = nil,
        selectedSessionID: SessionID? = nil
    ) async -> Bool {
        stopAgoraDiscussionPolling()
        let resolvedConfig = config ?? AgoraDiscussionSettings(defaults: .standard).config
        let projectID = selectedSessionID.flatMap { sessionNode(id: $0)?.projectID }
            ?? defaultProjectID(forSelectedSession: selectedSessionID)
        let coordinator = AgoraDiscussionCoordinator(
            config: resolvedConfig,
            effects: makeAgoraDiscussionEffects(projectID: projectID)
        )
        agoraDiscussionCoordinator = coordinator
        await coordinator.start(agenda: agenda, now: Date())

        guard coordinator.phase == .discussing else {
            agoraDiscussionCoordinator = nil
            return false
        }

        if let facilitator = coordinator.participants.first(where: \.isFacilitator) {
            renameAgoraParticipantIfRegistered(in: coordinator, id: facilitator.id, role: facilitator.role)
        }

        startAgoraDiscussionPolling()
        return true
    }

    public func stopAgoraDiscussion() async {
        guard let coordinator = agoraDiscussionCoordinator else { return }
        await coordinator.stop(now: Date())
        stopAgoraDiscussionPolling()
    }

    public func submitAgoraUserUtterance(_ text: String) async {
        guard let coordinator = agoraDiscussionCoordinator else { return }
        await coordinator.submitUserUtterance(text, now: Date())
        startAgoraDiscussionPolling()
    }

    public func addAgoraDiscussionParticipant(id: SessionID, role: String?) async {
        guard let coordinator = agoraDiscussionCoordinator else { return }
        persistAgoraRoleIfNeeded(id: id, role: role)
        await coordinator.addParticipant(id: id, role: role, now: Date())
        renameAgoraParticipantIfRegistered(in: coordinator, id: id, role: role)
        startAgoraDiscussionPolling()
    }

    private func makeAgoraDiscussionEffects(projectID: ProjectID?) -> AgoraDiscussionCoordinator.Effects {
        AgoraDiscussionCoordinator.Effects(
            send: { [weak self] from, to, text, submit in
                guard let self else { return false }
                let outcome = await self.messaging.send(
                    to: .id(to),
                    text: text,
                    submit: submit,
                    from: from,
                    inReplyTo: nil,
                    images: [],
                    sessions: self.sessionNodes
                )
                // v1 は best-effort（リトライ・cursor ロールバック無し）。ただし送信失敗を無言にしない:
                // engine は deliver 生成時点で cursor を前進済みのため .sent 以外は当該発言が再配送されない。
                if outcome != .sent {
                    self.logWarning("Agora relay to \(to) was not delivered (outcome: \(outcome))")
                }
                return outcome == .sent
            },
            injectPrompt: { [weak self] to, prompt, submit in
                guard let session = self?.sessionNode(id: to)?.controllable else { return false }
                do {
                    try await session.sendText(prompt, submit: submit)
                    return true
                } catch {
                    return false
                }
            },
            summon: { [weak self] role in
                guard let self else { return nil }
                do {
                    let id = try await self.spawnNewSession(
                        ref: .builtin(.claudeCode),
                        projectID: projectID,
                        backend: .appServer,
                        launchContext: .interactive
                    )
                    self.persistAgoraRoleIfNeeded(id: id, role: role)
                    return id
                } catch {
                    self.logError(error, context: "Failed to summon agora participant")
                    return nil
                }
            }
        )
    }

    private func startAgoraDiscussionPolling() {
        guard agoraDiscussionPollTask == nil else { return }
        // 生成した Task を捕捉し、末尾では「自分自身がまだ現役の場合のみ」nil にする。
        // 旧 Task の resume が新 Task の参照を無条件に潰すと、再開ガード `guard == nil` が破れて
        // 二重ポーリングになる。比較対象は closure がキャプチャする Task 値（self 経由の再読みでは
        // 新旧を区別できない）。Task は Equatable（同一 underlying task で ==）。
        var mine: Task<Void, Never>?
        mine = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let coordinator = self.agoraDiscussionCoordinator else { break }
                if coordinator.phase.isEnded {
                    break
                }

                await coordinator.tick(now: Date(), snapshots: self.agoraParticipantSnapshots(for: coordinator))

                guard !coordinator.phase.isEnded else { break }
                do {
                    try await Task.sleep(for: Self.agoraDiscussionPollInterval)
                } catch {
                    break
                }
            }
            if self?.agoraDiscussionPollTask == mine {
                self?.agoraDiscussionPollTask = nil
            }
        }
        agoraDiscussionPollTask = mine
    }

    private func stopAgoraDiscussionPolling() {
        agoraDiscussionPollTask?.cancel()
        agoraDiscussionPollTask = nil
    }

    private func agoraParticipantSnapshots(
        for coordinator: AgoraDiscussionCoordinator
    ) -> [AgoraDiscussionCoordinator.ParticipantSnapshot] {
        coordinator.participants.compactMap { participant in
            guard let node = sessionNode(id: participant.id) else { return nil }
            return AgoraDiscussionCoordinator.ParticipantSnapshot(
                id: participant.id,
                isIdle: node.status == .idle,
                completedTurnSeq: node.controllable.completedTurnSeq,
                transcript: node.appServer?.transcript ?? []
            )
        }
    }

    private func persistAgoraRoleIfNeeded(id: SessionID, role: String?) {
        guard let role = role?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty else {
            return
        }
        persistSessionRole(id: id, role: role)
    }

    private func existingSessionNamesForAgoraNaming(excluding sessionID: SessionID? = nil) -> Set<String> {
        var names = Set<String>()
        for session in sessions {
            if session.id == sessionID { continue }
            names.insert(session.name)
            names.insert(session.displayName)
        }
        return names
    }

    private func renameAgoraParticipantIfRegistered(
        in coordinator: AgoraDiscussionCoordinator,
        id: SessionID,
        role: String?
    ) {
        guard coordinator.participants.contains(where: { $0.id == id }) else { return }
        guard let newName = AgoraParticipantNaming.name(
            forRole: role,
            existingNames: existingSessionNamesForAgoraNaming(excluding: id)
        ) else { return }
        guard sessions.first(where: { $0.id == id })?.name != newName else { return }
        renameSession(id, to: newName)
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
    private func checkAPISpawnLimits(from: SessionID, newDepth: Int) throws {
        spawnTimestamps[from] = try SpawnPolicy.recordingSpawnAttempt(
            timestamps: spawnTimestamps[from] ?? [],
            now: Date()
        )
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

    private func cleanupOwnedWorkspace(for sessionID: SessionID) {
        guard let directory = ownedWorkspaceDirectories.removeValue(forKey: sessionID) else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }

        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let expectedDirectory = environment.sessionWorkspaceDirectory(for: sessionID)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard normalizedDirectory == expectedDirectory else { return }
        guard isContainedInWorkspaceDirectory(normalizedDirectory) else { return }

        do {
            try fm.removeItem(at: normalizedDirectory)
        } catch {
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

private extension AgoraDiscussionPhase {
    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
}
