import Foundation
import Observation
import AgentDomain
import CodexAppServerKit
import DesignSystem
import StructuredChatKit
private enum UserNotification {
    case completed
    case awaitingInput(SessionNotificationText.Kind)
    /// 無応答。スマホには直近の動作を渡さず、種類だけを送る。
    case stalled(lastAction: String?)
    /// プロセスが 0 以外の終了コードで終わった（11 通知「終了」）。
    case exited(code: Int32)
}

/// エージェントのプロセスが自分で終了したこと（04 B3）。終了コードが取れない transport では nil。
public struct ChatProcessExit: Equatable, Sendable {
    public let exitCode: Int32?
}

@MainActor
@Observable
public final class ChatSessionViewModel: Identifiable {
    public let id: SessionID
    public let startedAt: Date
    /// プロセスが自分で終了したら入る。入力欄の代わりに終了コードと「この会話から再開」を出す（04 B3）。
    public private(set) var processExit: ChatProcessExit?
    /// 直近のエラーを通知したか（プロセス終了で「終了」を重ねるかの判断に使う）。
    @ObservationIgnored private var lastErrorWasNotified = false
    /// 「この会話から再開」。新しいプロセスで同じ会話を開き直す。VM は自分の client を作り直せないので
    /// Dashboard が注入する（nil のあいだはボタンを出さない）。
    public var resumeConversationHandler: (@MainActor () -> Void)?
    public private(set) var status: SessionStatus = .starting {
        didSet {
            guard oldValue != status else { return }
            if !status.hasSameKind(as: oldValue) {
                statusEnteredAt = Date()
            }
            // 承認待ち・完了・エラーへ入ったら「未確認の停止」をラッチする（PTY 側 transitionStatus と同一）。
            // idle は完了通知経路（notifyCompletionIfNeeded）で扱い、turnInterrupted 等の
            // 非完了 idle を赤枠から除外する。
            if status.latchesUnseenAttentionOnEntry {
                hasUnseenCompletion = true
            }
            // 承認・質問待ちへ移ったら、その時点で無応答を解く（一覧で承認文より先に経過が出ないように）。
            if isStalled { updateStalled(now: Date()) }
        }
    }
    /// 今の状態の種類へ入った時刻（対応待ちの待ち時間の起点）。
    public private(set) var statusEnteredAt: Date?
    /// 実行中のまま 30 分反応がない（04 B5。`ChatHangPolicy.defaultWarnAfter`）。一覧・タブの「無応答」に使う。1 秒ごとに見直す。
    public private(set) var isStalled = false
    /// 無応答になった時刻（対応待ちの待ち時間の起点）。
    public private(set) var stalledSince: Date?
    @ObservationIgnored private var stallWatchTask: Task<Void, Never>?
    /// 未確認の停止（＝ユーザーの対応待ち）。停止状態へ入るとラッチし、選択（閲覧）で解除する。
    public var hasUnseenCompletion: Bool = false {
        didSet {
            guard oldValue != hasUnseenCompletion else { return }
            unseenCompletionDidChange?()
        }
    }
    @ObservationIgnored public var unseenCompletionDidChange: (() -> Void)?
    public var titleState: SessionTitleState = .legacy(name: "") {
        didSet {
            guard titleState != oldValue else { return }
            titleStateDidChange?(titleState)
        }
    }
    public var name: String {
        get { titleState.name }
        set { titleState = titleState.renamed(to: newValue) }
    }
    @ObservationIgnored public var titleStateDidChange: ((SessionTitleState) -> Void)?
    public var projectID: ProjectID?
    public var parentSessionID: SessionID?
    public var launchContext: SessionLaunchContext = .interactive
    public private(set) var threadId: String?
    public private(set) var chatNativeSessionId: String?
    public private(set) var appServerUserAgent: String?
    /// Codex 専用状態。既存の composer・transcript・plan/sub-agent surface から利用する。
    public private(set) var codexSkillSelectionState: CodexSkillSelectionState?
    public private(set) var codexPlanTaskState: CodexPlanTaskState?
    public private(set) var codexSubAgentState: CodexSubAgentState?
    public private(set) var codexSubAgentError: String?
    public private(set) var transcript: [ChatItem] = []
    public var inputHistoryEntries: [InputHistoryEntry] {
        InputHistoryPolicy.entries(from: transcript)
    }
    /// transcript の項目 ID 集合。契約（task-5）: 常に `Set(transcript.map(\.id))` と一致するよう
    /// 全変更経路で増分維持する（body 毎の全再構築を避けるための索引）。
    public private(set) var transcriptItemIDs: Set<String> = []
    @ObservationIgnored private var transcriptIndexByID: [String: Int] = [:]
    @ObservationIgnored private let transcriptStreamCoalescer = TranscriptStreamCoalescer()
    @ObservationIgnored private var midTurnPersistenceGate = MidTurnPersistenceGate()
    public private(set) var transcriptRevision: Int = 0
    public private(set) var rawEventLog: [String] = []
    public private(set) var pendingApprovals: [ChatApprovalRequest] = []
    /// 返答エリアの承認カードで表示中の要求（05 R6d「1 / 3」）。範囲外は `currentReplyApproval` で丸める。
    public var approvalPageIndex = 0
    /// 承認カード・質問カードへキーボードフォーカスを移す要求（入力欄の Tab）。値の変化だけを見る。
    public private(set) var replyCardFocusRequest = 0
    /// 承認カードが画面に出た時刻（05 R6c: 出た直後 0.5 秒は押せない）。
    @ObservationIgnored var approvalPresentedAt: [String: Date] = [:]
    /// 直近の送信の失敗（05 R9）。次の送信か「閉じる」で消える。
    public private(set) var sendFailure: SendFailure?

    public struct SendFailure: Equatable, Sendable {
        public let reason: String
        /// 送れなかった本文を入力欄に戻せたか。
        public let restoredDraft: Bool
    }
    /// 送信を受け付けてもらうまでの本文（05 R4: 入力欄に淡く残し、送信ボタンを「…」にする）。
    public private(set) var inFlightText: String?
    public private(set) var completedTurnSeq: Int = 0
    public private(set) var lastOutputAt: Date?
    public private(set) var lastTurnCompletedAt: Date?
    /// 直近ターンの API 使用量・コスト（task-2 契約。受け入れテスト TurnCostAccumulation が凍結）。
    public private(set) var lastTurnUsage: TurnUsage?
    /// ターン末尾の使用量行に出すトークン内訳（04: コストに加えてトークンとコンテキスト）。
    /// 項目の形は変えないため、turnCost（金額の無いターンは最後の応答）の項目 ID ごとに持つ。保存しないので、復元した会話はコストだけ。
    public private(set) var turnUsageByItemID: [String: TurnUsage] = [:]
    public private(set) var lastTurnCostUSD: Double?
    public private(set) var sessionTotalCostUSD: Double = 0
    /// 保存した総コストを読み込んだか（読めたら転写からの推定で上書きしない）。
    private var restoredSavedTotalCost = false
    /// Claude が直前に送った累計（`total_cost_usd`）。再開した会話では再開前の分も含むので保存した値から始める。nil はわからないとき（履歴から再開した直後）。
    private var claudeReportedTotalCostUSD: Double? = 0
    private var totalCostSave: Task<Void, Never>?
    /// composer 下書きの単一の正本（task-4 契約。受け入れテスト ComposerDraftPersistence が凍結）。
    /// View ローカル @State に持つとシングル⇄グリッド切替のビュー再生成で消える（F バグの根本原因）。
    public var draft: String = ""
    public private(set) var submitBaselineTurnSeq: Int?
    public private(set) var runningBackgroundTasks: [RunningBackgroundTask] = []
    public var showsProcessingIndicator: Bool {
        status == .running ||
            !runningBackgroundTasks.isEmpty ||
            subAgents.contains { $0.status == .running }
    }
    public var isProcessing: Bool { showsProcessingIndicator }
    public var subAgents: [SubAgentRef] {
        subAgentModel.subAgents
    }
    /// ストリップ表示用のサブエージェント一覧。処理が完了したものはストリップから外す。
    /// 完了後も本文のインラインマーカー（subAgents に残る）から閲覧できるよう、subAgents 本体
    /// からは消さない。実行中・失敗は残す（失敗は気付けるように残す）。
    public var stripSubAgents: [SubAgentRef] {
        subAgentModel.stripSubAgents
    }
    public var selectedSubAgentId: String? {
        subAgentModel.selectedSubAgentId
    }
    public private(set) var restoreState: ChatRestoreState = .notRestored
    public var shouldShowConnectingIndicator: Bool {
        Self.shouldShowConnectingIndicator(
            restoreState: restoreState,
            transcriptIsEmpty: transcript.isEmpty
        )
    }

    nonisolated static func shouldShowConnectingIndicator(
        restoreState: ChatRestoreState,
        transcriptIsEmpty: Bool
    ) -> Bool {
        restoreState == .restoring && transcriptIsEmpty
    }

    /// `/compact`（引数付き含む）の submit 送信か。前後空白は trim する。
    nonisolated static func isCompactCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "/compact" || trimmed.hasPrefix("/compact ")
    }
    public private(set) var availableModels: [AppServerModel] = [] { didSet { clearStaleImageErrorIfSendable() } }
    public private(set) var availableSlashCommands: [String]?
    /// init 未受領時に補完へ渡す種一覧（永続ストア由来）。生成時に1回だけ読む。
    public private(set) var seedSlashCommands: [String]?
    public private(set) var permissionProfiles: [PermissionProfileSummary] = []
    public private(set) var selectedModel: String? { didSet { clearStaleImageErrorIfSendable() } }
    public private(set) var selectedEffort: String?
    public private(set) var selectedPermissionProfile: String?
    public private(set) var isPlanMode = false
    public private(set) var isPlanModeAvailable = false
    /// Claude/Cursor（spawn 型）で選択可能な model 一覧。Codex の `availableModels`
    /// （app-server 由来の `AppServerModel`）とは別に、alias/取得結果を素の文字列で保持する。
    public private(set) var availableSpawnAgentModels: [String] = []
    /// 会話履歴の圧縮（compaction）が進行中か（phlox-ux-5fixes task-2 契約のスタブ。
    /// AcceptanceCompactingIndicatorTests が凍結。実装は task-2 が担う）。
    public private(set) var isCompacting = false
    /// esc 履歴リバートピッカーの表示状態（task-9）。View はこれを observe して overlay を出す。
    public private(set) var isHistoryPickerPresented = false
    /// リバート確定で復元する composer 下書き本文（task-9）。View が反映後 `consumeDraftRestoration()` でクリアする。
    public private(set) var draftRestoration: String?
    /// composer へフォーカスを戻す要求（esc-restore-input-focus task-1 契約の PM スタブ）。
    /// 受け入れテスト AcceptanceComposerFocusRestoreTests が凍結。発火は task-1、消費は task-2 が実装する。
    public private(set) var composerFocusRequest: ComposerFocusRequest = .none
    @ObservationIgnored public var codexSettingsDidChange: (@MainActor (CodexAppServerSessionSettings?) -> Void)?
    /// リモート通知系へのフック。nil なら呼ばれない（既存挙動と同一）。
    @ObservationIgnored public var remoteSessionNotifier: (any RemoteSessionNotifier)?
    /// チャネルごとのユーザー通知可否。nil は既存挙動を保つため全許可として扱う。
    @ObservationIgnored public var userNotificationGate: ((UserNotificationChannel) -> Bool)?

    private let client: any StructuredAgentClient
    private let approvalBroker: ChatApprovalBroker
    private let subAgentModel = ChatSubAgentModel()
    public let agentRef: AgentRef
    private let workingDirectory: String?
    private var eventTask: Task<Void, Never>?
    private var codexSettingsEventTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?
    private var userInputTask: Task<Void, Never>?
    /// Codex の wire request と質問カードを結び付ける。Claude の requestId はこの表に登録しない。
    private var codexUserInputRequestIDs: [String: UUID] = [:]
    private let transcriptPersistenceQueue: TranscriptPersistenceQueue?
    private var pendingInput = ""
    /// リバート後に予約される文脈リプレイのプリアンブル。次の submit 送信で client.turnStart の
    /// 入力にのみ 1 回だけ前置され、成功後にクリアされる（表示・store には載せない・二重付与しない）。
    private var pendingReplayContext: String?
    /// 直前の esc の時刻。次の esc がこの時刻から `doubleEscapeWindow` 秒以内なら「2連打」と判定する（task-9）。
    private var lastEscapeAt: Date?
    private var threadResponseModel: String?
    private var persistedSettingsForFallback: CodexAppServerSessionSettings?
    private var collaborationModeListAvailable = false
    private var shouldClearBackgroundTasksOnNextTurnStart = false
    private var turnStartedAt: Date?
    /// turnStartedAt が復元時の推定（applyRestoredThreadStatus）由来か。ライブの
    /// turnStarted イベント由来のターンは ADR 0064 の idle 無視ガードの対象になる。
    private var turnIsRestoredInference = false
    private var turnGeneration = 0
    /// ordered Codex event の turn identity。正規化で失われる identity を VM 境界で再検証する。
    private var codexEventTurnId: String?
    private var isAwaitingLocallyStartedTurnEvent = false
    private var activeInterruptTask: Task<Void, Never>?
    private var activeInterruptID: UUID?
    private var lastEventAt: Date?
    private var pendingTurnCostUSD: Double?
    private var pendingTurnUsage: TurnUsage?
    private var codexSurfaceRefreshTask: Task<Void, Never>?
    private var codexSubAgentRefreshPending = false
    private var codexSubAgentRefreshGeneration = 0
    private var codexRestoreGeneration = 0
    private let transcriptStore: (any TranscriptStore)?
    private let spawnAgentPermissionOverride: String?
    private let spawnAgentModelsProvider: SpawnAgentModelsProvider?
    /// 利用可能スラッシュコマンド一覧の永続ストア。生成時の読み出しと init 受領時の記録に使う。
    private let availableCommandsStore: AvailableCommandsStore

    /// Cursor の `cursor-agent models` 取得をセッションから注入するための供給源。
    /// 供給結果が空/未注入なら小さなハードコード fallback を使い、起動を妨げない。
    public typealias SpawnAgentModelsProvider = @Sendable () async -> [String]

    public init(
        id: SessionID,
        startedAt: Date = Date(),
        agentRef: AgentRef = .builtin(.codex),
        client: any StructuredAgentClient,
        approvalBroker: ChatApprovalBroker,
        workingDirectory: String?,
        transcriptStore: (any TranscriptStore)? = nil,
        spawnAgentPermissionOverride: String? = nil,
        spawnAgentModelsProvider: SpawnAgentModelsProvider? = nil,
        historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])? = nil,
        historyTranscriptLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])? = nil,
        availableCommandsStore: AvailableCommandsStore = AvailableCommandsStore(),
        titleState: SessionTitleState = .legacy(name: "")
    ) {
        self.id = id
        self.startedAt = startedAt
        self.agentRef = agentRef
        self.client = client
        self.approvalBroker = approvalBroker
        self.workingDirectory = workingDirectory
        if agentRef == .builtin(.codex), let codexClient = client as? any CodexSkillSelectionClient {
            self.codexSkillSelectionState = CodexSkillSelectionState(
                client: codexClient,
                sessionCWD: workingDirectory ?? ""
            )
        } else {
            self.codexSkillSelectionState = nil
        }
        self.codexSubAgentState = agentRef == .builtin(.codex) ? CodexSubAgentState(parentThreadId: "") : nil
        self.codexSubAgentError = nil
        self.codexPlanTaskState = agentRef == .builtin(.codex) ? CodexPlanTaskState() : nil
        self.transcriptStore = transcriptStore
        self.spawnAgentPermissionOverride = spawnAgentPermissionOverride
        self.transcriptPersistenceQueue = transcriptStore.map {
            TranscriptPersistenceQueue(sessionID: id, store: $0)
        }
        self.attachmentStore = ComposerAttachmentStore()
        self.spawnAgentModelsProvider = spawnAgentModelsProvider
        self.historyProvider = historyProvider
        self.historyTranscriptLoader = historyTranscriptLoader
        self.availableCommandsStore = availableCommandsStore
        self.seedSlashCommands = availableCommandsStore.commands(
            agentRef: agentRef,
            workingDirectory: workingDirectory
        )
        self.titleState = titleState
        configureSubAgentModel()
        configureTranscriptStreamCoalescer()
        configureMidTurnPersistenceGate()
        scheduleHistoryCacheLoadIfNeeded()
        startEventTasks()
    }

    init(
        id: SessionID,
        agentRef: AgentRef = .builtin(.codex),
        client: any StructuredAgentClient,
        approvalBroker: ChatApprovalBroker,
        workingDirectory: String?,
        attachmentStore: ComposerAttachmentStore,
        availableCommandsStore: AvailableCommandsStore = AvailableCommandsStore(),
        titleState: SessionTitleState = .legacy(name: "")
    ) {
        self.id = id
        self.startedAt = Date()
        self.agentRef = agentRef
        self.client = client
        self.approvalBroker = approvalBroker
        self.workingDirectory = workingDirectory
        if agentRef == .builtin(.codex), let codexClient = client as? any CodexSkillSelectionClient {
            self.codexSkillSelectionState = CodexSkillSelectionState(
                client: codexClient,
                sessionCWD: workingDirectory ?? ""
            )
        } else {
            self.codexSkillSelectionState = nil
        }
        self.codexSubAgentState = agentRef == .builtin(.codex) ? CodexSubAgentState(parentThreadId: "") : nil
        self.codexSubAgentError = nil
        self.codexPlanTaskState = agentRef == .builtin(.codex) ? CodexPlanTaskState() : nil
        self.transcriptStore = nil
        self.transcriptPersistenceQueue = nil
        self.attachmentStore = attachmentStore
        self.spawnAgentPermissionOverride = nil
        self.spawnAgentModelsProvider = nil
        self.historyProvider = nil
        self.historyTranscriptLoader = nil
        self.availableCommandsStore = availableCommandsStore
        self.seedSlashCommands = availableCommandsStore.commands(
            agentRef: agentRef,
            workingDirectory: workingDirectory
        )
        self.titleState = titleState
        configureSubAgentModel()
        configureTranscriptStreamCoalescer()
        configureMidTurnPersistenceGate()
        scheduleHistoryCacheLoadIfNeeded()
        startEventTasks()
    }

    private func configureSubAgentModel() {
        subAgentModel.configure(
            markerSink: { [weak self] item in
                self?.appendOrReplace(item)
            },
            outputTouched: { [weak self] in
                self?.touchOutput()
            }
        )
    }

    private func configureTranscriptStreamCoalescer() {
        transcriptStreamCoalescer.setScheduler { [weak self] delay, token in
            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                self?.flushScheduledStreamDeltas(token: token)
            }
        }
    }

    private func configureMidTurnPersistenceGate() {
        midTurnPersistenceGate.setScheduler { [weak self] delay, token in
            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                self?.flushScheduledMidTurnPersistence(token: token)
            }
        }
    }

    /// Whitebox / tests: replace the mid-turn gate with an injectable clock and scheduler.
    func installMidTurnPersistenceForTesting(
        interval: TimeInterval,
        eventThreshold: Int,
        now: @escaping MidTurnPersistenceGate.Clock,
        schedule: @escaping MidTurnPersistenceGate.Scheduler
    ) {
        midTurnPersistenceGate = MidTurnPersistenceGate(
            interval: interval,
            eventThreshold: eventThreshold,
            now: now,
            schedule: schedule
        )
    }

    /// Whitebox / tests: fire a previously scheduled trailing mid-turn flush token.
    func fireScheduledMidTurnPersistenceForTesting(token: UInt64) {
        flushScheduledMidTurnPersistence(token: token)
    }

    private func flushScheduledMidTurnPersistence(token: UInt64) {
        guard midTurnPersistenceGate.fireScheduled(token: token) else { return }
        performMidTurnTranscriptFlush()
    }

    private func requestMidTurnTranscriptFlush() {
        guard transcriptPersistenceQueue != nil else { return }
        if midTurnPersistenceGate.requestFlush() {
            performMidTurnTranscriptFlush()
        }
    }

    private func performMidTurnTranscriptFlush() {
        enqueueTranscriptUpsert(transcript.filter(shouldStoreInTranscript))
    }

    // task-9 契約（受け入れテスト ChatHistoryStart が凍結。実装契約の正本: tasks/task-9.md）
    @ObservationIgnored private let historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])?
    @ObservationIgnored private let historyTranscriptLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])?
    /// provider の結果を一度だけ格納（body 評価のたびに FS 走査しない）。SwiftUI 反応のため observable。
    private var cachedHistoryEntries: [ClaudeSessionHistoryEntry] = []
    @ObservationIgnored private var historyCacheLoaded = false
    @ObservationIgnored private var historyCacheLoadTask: Task<Void, Never>?
    @ObservationIgnored private var historySummaryTask: Task<Void, Never>?

    /// 新規 Claude/Codex チャットの中央に「履歴から再開」を出すか。
    public var shouldOfferHistoryStart: Bool {
        guard agentRef == .builtin(.claudeCode) || agentRef == .builtin(.codex) else { return false }
        guard historyProvider != nil else { return false }
        guard transcript.isEmpty, submitBaselineTurnSeq == nil else { return false }
        return !cachedHistoryEntries.isEmpty
    }

    /// 履歴カードの件数と最後の発言（履歴 ID ごと。読み終えたものから入る）。
    public private(set) var historySummaries: [String: ChatHistorySummary] = [:]

    /// 履歴一覧（最大 20 件・task-9 契約）。
    public var historyEntries: [ClaudeSessionHistoryEntry] {
        cachedHistoryEntries
    }

    /// UI 操作で発生した失敗を既存の ErrorMessageCell 経路へ載せる。
    func reportError(_ message: String) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if case .error(_, let previous, _) = transcript.last, previous == message {
            return
        }
        appendOrReplace(.error(
            id: "ui-error-\(UUID().uuidString)",
            message: message,
            timestamp: Date()
        ))
        touchOutput()
    }

    public var canStopCodexSubAgents: Bool {
        codexSubAgentState?.children.contains {
            codexSubAgentState?.stopState(for: $0.id) == .available
        } == true
    }

    /// 親 thread に属する child を取得する。`thread/list` の turns は空仕様のため、
    /// 実行中で turn ID が欠ける child だけ `thread/read(includeTurns: true)` で補完する。
    public func refreshCodexSubAgents() async {
        guard let parentThreadId = threadId,
              !parentThreadId.isEmpty,
              let client = client as? any CodexSubAgentProviding else { return }
        codexSubAgentRefreshGeneration += 1
        let generation = codexSubAgentRefreshGeneration
        do {
            let response = try await client.threadList(ThreadListParams(
                sourceKinds: Self.codexChildSourceKinds,
                parentThreadId: parentThreadId
            ))
            guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else { return }

            var latestByID: [String: ThreadSummary] = [:]
            var childOrder: [String] = []
            for thread in response.data where Self.isCodexChild(thread, parentThreadId: parentThreadId) {
                if latestByID[thread.id] == nil {
                    childOrder.append(thread.id)
                }
                latestByID[thread.id] = thread
            }
            var children = childOrder.compactMap { latestByID[$0].map(Self.codexChild) }
            var readFailures: [String: String] = [:]
            var validatedReadIDs: Set<String> = []
            for index in children.indices
                where Self.needsCodexSubAgentRead(children[index])
                    || codexSubAgentState?.controlState(for: children[index].id) == .stale {
                let child = children[index]
                do {
                    let read = try await client.threadRead(
                        ThreadReadParams(threadId: child.id, includeTurns: true)
                    )
                    guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else {
                        return
                    }
                    guard let expected = latestByID[child.id],
                          Self.isMatchingCodexChildRead(
                              read.thread,
                              expected: expected,
                              parentThreadId: parentThreadId
                          ) else {
                        readFailures[child.id] = Self.codexSubAgentReadMismatchMessage(
                            requestedThreadID: child.id,
                            receivedThreadID: read.thread.id
                        )
                        continue
                    }
                    children[index] = Self.codexChild(read.thread)
                    validatedReadIDs.insert(child.id)
                } catch {
                    guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else {
                        return
                    }
                    readFailures[child.id] = String(describing: error)
                }
            }
            guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else { return }
            codexSubAgentState?.apply(.available(children: children))
            for (threadID, reason) in readFailures {
                codexSubAgentState?.apply(.stale(threadId: threadID, reason: reason))
            }
            for threadID in validatedReadIDs {
                guard let child = children.first(where: { $0.id == threadID }) else { continue }
                codexSubAgentState?.apply(.validated(child: child))
            }
            codexSubAgentError = readFailures.first.map { "サブエージェント \($0.key): \($0.value)" }
        } catch {
            guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else { return }
            let message = String(describing: error)
            codexSubAgentState?.apply(.unavailable(reason: message))
            codexSubAgentError = message
        }
    }

    /// child の詳細を `thread/read(includeTurns: true)` から読み込む。
    public func loadCodexSubAgentDetail(threadID: String) async {
        guard let child = codexSubAgentState?.children.first(where: { $0.id == threadID }) else { return }
        guard let client = client as? any CodexSubAgentProviding else { return }
        guard let parentThreadId = threadId else { return }
        let generation = codexSubAgentRefreshGeneration
        do {
            let response = try await client.threadRead(ThreadReadParams(threadId: threadID, includeTurns: true))
            guard threadId == parentThreadId,
                  codexSubAgentState?.parentThreadId == parentThreadId,
                  generation == codexSubAgentRefreshGeneration else { return }
            guard Self.isMatchingCodexChildRead(
                response.thread,
                child: child,
                parentThreadId: parentThreadId
            ) else {
                let message = Self.codexSubAgentReadMismatchMessage(
                    requestedThreadID: threadID,
                    receivedThreadID: response.thread.id
                )
                codexSubAgentState?.apply(.stale(threadId: threadID, reason: message))
                codexSubAgentError = message
                return
            }
            let transcript = response.thread.turns?.flatMap { $0.items ?? [] }.compactMap(\.text) ?? []
            codexSubAgentState?.apply(.validated(child: Self.codexChild(response.thread)))
            codexSubAgentState?.apply(.detail(threadId: threadID, transcript: transcript))
            codexSubAgentError = nil
        } catch {
            guard threadId == parentThreadId,
                  codexSubAgentState?.parentThreadId == parentThreadId,
                  generation == codexSubAgentRefreshGeneration else { return }
            let message = String(describing: error)
            codexSubAgentState?.apply(.stale(threadId: threadID, reason: message))
            codexSubAgentError = "サブエージェント \(threadID): \(message)"
        }
    }

    /// child の active turn にだけ `turn/interrupt` を送り、完了は event で確定する。
    public func stopCodexSubAgent(threadID: String) async {
        guard var state = codexSubAgentState,
              let request = state.stopRequest(for: threadID),
              let client = client as? any CodexSubAgentProviding else { return }
        let generation = codexSubAgentRefreshGeneration
        let parentThreadId = request.parentThreadId
        codexSubAgentState = state
        do {
            _ = try await client.turnInterrupt(
                TurnInterruptParams(threadId: request.threadId, turnId: request.turnId)
            )
            guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else {
                return
            }
            codexSubAgentError = nil
        } catch {
            guard isCurrentCodexSubAgentRefresh(generation, parentThreadId: parentThreadId) else {
                return
            }
            state = codexSubAgentState ?? state
            state.rejectStop(for: threadID)
            codexSubAgentState = state
            codexSubAgentError = String(describing: error)
        }
    }

    /// init 時に off-main で一度だけ provider を呼び、完了時に MainActor で observable キャッシュへ格納する。
    private func scheduleHistoryCacheLoadIfNeeded() {
        guard let historyProvider, !historyCacheLoaded else { return }
        guard historyCacheLoadTask == nil else { return }
        historyCacheLoadTask = Task { [weak self, historyProvider] in
            let entries = await Task.detached {
                Array(historyProvider().prefix(20))
            }.value
            await MainActor.run { [weak self] in
                guard let self, !self.historyCacheLoaded else { return }
                self.cachedHistoryEntries = entries
                self.historyCacheLoaded = true
                // 要約は一覧と別のタスク（新規チャットの開始が本文の読み込みを待たないように）。
                self.historySummaryTask = Task { [weak self] in await self?.loadHistorySummaries(entries) }
            }
        }
    }

    /// 履歴カードの件数と最後の発言を、一覧を出したあとで 1 件ずつ埋める（会話ファイルを全部読むので一覧より遅い）。
    private func loadHistorySummaries(_ entries: [ClaudeSessionHistoryEntry]) async {
        guard let historyTranscriptLoader else { return }
        for entry in entries {
            let summary = await Task.detached { ChatHistorySummary(items: historyTranscriptLoader(entry)) }.value
            guard !Task.isCancelled, shouldOfferHistoryStart else { return }
            historySummaries[entry.id] = summary
        }
    }

    /// 選択した履歴から再開する（転写反映＋ client.resume・task-9 契約）。
    public func startFromHistory(_ entry: ClaudeSessionHistoryEntry) async {
        guard let historyTranscriptLoader else { return }
        startEventTasks()
        let loaded = historyTranscriptLoader(entry)
        setTranscript(loaded)
        // 履歴の JSONL にはコストが無く、再開前の累計がわからない。最初に届く累計を総コストにする。
        sessionTotalCostUSD = 0
        claudeReportedTotalCostUSD = nil
        touchOutput()
        // 履歴 JSONL 由来の表示のみ。起動時は Phlox transcriptStore へは書かない（二重永続化を避ける）。
        // 以降のターン境界 flush（`flushTranscriptAtTurnBoundary`）で loaded 履歴も store に載る（正規経路）。
        do {
            try await client.resume(sessionRef: entry.sessionID)
            updateNativeSessionId(entry.sessionID)
            if case .starting = status {
                status = .idle
            }
            adoptTitleFromHistoryResume(entry, loadedItems: loaded)
        } catch {
            setTranscript([])
            status = .error(message: "chat restore failed: \(error)")
            touchOutput()
        }
    }

    public var displayName: String {
        titleState.effectiveName(fallback: SessionViewModel.shortID(for: id))
    }

    /// trim 後が空なら nil（draft 不変）。非空なら trim 済みを返し draft をクリアする（task-4 契約）。
    @ObservationIgnored private var inputHistoryCursor = InputHistoryCursor()

    /// ↑↓ で過去の入力を下書きへ呼び戻す。呼び戻したら true。
    /// 画像を添付している間は呼ばない（本文の [Image #N] が消えると添付も外れ、戻しても画像は戻らない）。
    /// 画像つきで送った入力も呼び戻さない（会話には画像の本体が残らず、本文だけ戻すと画像なしで送ってしまう）。
    /// Codex の会話を読み直した入力は添付の記録を持たないので、本文の [Image #N] でも見分ける。
    func recallInputHistory(_ direction: InputHistoryCursor.Direction) -> Bool {
        guard attachmentStore.attachments.isEmpty else { return false }
        let entries = transcript.compactMap { item -> String? in
            guard case let .userMessage(_, text, _, attachments) = item, attachments.isEmpty,
                  text.range(of: #"\[Image #\d+\]"#, options: .regularExpression) == nil
            else { return nil }
            return text
        }
        guard let text = inputHistoryCursor.recall(direction, entries: entries, currentText: draft) else { return false }
        draft = text
        return true
    }

    public func consumeDraftForSend() -> String? {
        // 承認を待っている間は書けるが送らない（05 R6「送信は承認後」）。質問のカードは別の指示を送ってよい。
        guard inFlightText == nil, replyApprovals.isEmpty else { return nil }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard !attachmentStore.attachments.isEmpty else { return nil }
            draftClearedForSend = draft
            draft = ""
            return ""
        }
        draftClearedForSend = draft
        draft = ""
        return trimmed
    }

    /// 送信によるクリア直前の本文。composer の `.onChange` からは
    /// 「ユーザーがプレースホルダを消した」編集と区別がつかないため、ここで記録して読み飛ばす。
    /// 送信ペイロード（`buildChatInputs`）はライブの `attachmentStore` を読むので、
    /// ここで添付を外すと画像が送られない／失敗時に復元できない。
    private var draftClearedForSend: String?
    /// 送信成功した userMessage ID に対応する添付（プロセス内・セッション存続中のみ）。
    @ObservationIgnored private var sentRuntimeAttachmentsByUserMessageID: [String: [ComposerAttachment]] = [:]
    /// ローカル確定したユーザー本文。サーバー項目の補足付き text より優先する。
    /// インスタンス内のみ。terminate で解放する（プロセス横断の static は持たない）。
    @ObservationIgnored private var localOriginalUserTextByID: [String: String] = [:]
    /// Codex native skill + 画像経路で materialize した一時ディレクトリ（terminate まで保持）。
    @ObservationIgnored private var nativeSkillInputDirectories: Set<URL> = []

    /// composer 本文の編集を添付へ同期する（本文から `[Image #N]` が消えたら添付も外す）。
    /// 送信によるクリアは何度発火しても添付を外さない。
    func syncAttachmentsWithDraftEdit(oldText: String, newText: String) {
        if newText.isEmpty, oldText == draftClearedForSend { return }
        draftClearedForSend = nil
        attachmentStore.removeAttachmentsMissing(fromOldText: oldText, newText: newText)
    }

    /// composer の添付状態（task-8 契約。受け入れテスト ComposerAttachment が凍結）。
    var attachmentStore: ComposerAttachmentStore

    /// text（非空なら .text）＋添付画像を送信用 ChatInput 列へ（task-8 契約）。
    func buildChatInputs(text: String) -> [ChatInput] {
        var inputs: [ChatInput] = []
        if !text.isEmpty {
            inputs.append(.text(text))
        }
        inputs.append(contentsOf: attachmentStore.attachments.map { attachment in
            .image(data: attachment.data, mediaType: attachment.mediaType)
        })
        return inputs
    }

    private struct ImageSendSnapshot: Equatable {
        let model: String?
        let supportsImages: Bool
        let input: [ChatInput]
    }

    private func imageSendSnapshot(for input: [ChatInput]) -> ImageSendSnapshot {
        ImageSendSnapshot(
            model: selectedModel,
            supportsImages: supportsImageAttachments,
            input: input
        )
    }

    private var supportsImageAttachments: Bool {
        switch agentRef {
        case .builtin(.claudeCode):
            true
        case .builtin(.codex):
            client is any CodexImageInputConfiguring && CodexImageInputState.acceptsImageAttachments(
                selectedModel: selectedModel,
                availableModels: availableModels
            )
        default:
            false
        }
    }

    /// 画像を添付したときの扱い（05 R8）。貼り付け・＋・添付の見た目がこの 1 つの判定に従う。
    enum ImageAttachmentSupport: Equatable {
        case supported
        /// 添付はできるが、いまのモデルには送れない（Codex の画像非対応モデル）。
        case modelUnsupported
        /// 画像を送れないエージェント。＋ からはファイルの参照にする。
        case agentUnsupported
    }

    /// 送れないモデルで送ろうとしたときのエラーは、送れるモデルに替えたら消す（残すといまの可否と食い違う）。
    private func clearStaleImageErrorIfSendable() {
        guard attachmentStore.lastError == ControlImageSendError.imagesUnsupported.localizedDescription,
              imageAttachmentSupport == .supported else { return }
        attachmentStore.clearError()
    }

    var imageAttachmentSupport: ImageAttachmentSupport {
        if acceptsImageAttachments { return .supported }
        return agentRef == .builtin(.codex) ? .modelUnsupported : .agentUnsupported
    }

    /// Control API 経路の画像非対応判定用。
    public var acceptsImageAttachments: Bool {
        switch agentRef {
        case .builtin(.claudeCode):
            true
        case .builtin(.codex):
            client is any CodexImageInputConfiguring && CodexImageInputState.acceptsImageAttachments(
                selectedModel: selectedModel,
                availableModels: availableModels
            )
        default:
            false
        }
    }

    private func configureCodexImageInputIfNeeded(supportsImages: Bool) async {
        guard agentRef == .builtin(.codex),
              let configurable = client as? any CodexImageInputConfiguring
        else { return }
        await configurable.setNativeImageInputEnabled(supportsImages)
    }

    public enum ControlImageSendError: Error, Equatable, Sendable, LocalizedError {
        case imagesUnsupported
        case imageSendSnapshotChanged

        public var errorDescription: String? {
            switch self {
            case .imagesUnsupported:
                "画像添付は Claude と画像対応モデルの Codex に対応しています"
            case .imageSendSnapshotChanged:
                "画像対応モデルまたは添付が送信前に変更されたため、送信を中止しました"
            }
        }
    }

    /// Control API から画像付きで送信する。turnStart 失敗時は添付を残さない。
    public func sendTextWithControlImages(
        _ text: String,
        submit: Bool,
        images: [(mediaType: String, data: Data)]
    ) async throws {
        guard images.isEmpty || acceptsImageAttachments else {
            throw ControlImageSendError.imagesUnsupported
        }

        attachmentStore.clear()
        for image in images {
            attachmentStore.addImage(data: image.data, mediaType: image.mediaType)
        }

        do {
            try await sendText(text, submit: submit)
        } catch {
            if agentRef != .builtin(.codex) {
                attachmentStore.clear()
            }
            throw error
        }
    }

    /// 実行中ターンのハング評価（task-6 契約。受け入れテスト ChatHangDetection が凍結）。
    /// 実行中（turnStartedAt 非 nil）のみ非 nil。呼び出しは読み取り専用（状態を書かない）。
    func hangAssessment(now: Date) -> ChatHangAssessment? {
        guard let turnStartedAt else { return nil }
        return ChatHangPolicy.assess(
            now: now,
            turnStartedAt: turnStartedAt,
            lastEventAt: lastEventAt
        )
    }

    /// 思考中インジケータの下段の要約（実行中ターンだけ）。
    func thinkingRecap(now: Date) -> ChatRecap.Summary? {
        guard let assessment = hangAssessment(now: now) else { return nil }
        return ChatRecap.summary(transcript: transcript, elapsed: assessment.elapsed)
    }

    /// Thinking インジケータに出す活動状態。表示すべきものが無ければ nil。
    /// 承認・回答待ちは処理中でなくても待機として出す（orb の 6 状態のうち waiting）。
    public var activityState: AgentActivityState? {
        if let waiting = AgentActivityClassifier.waitingState(for: status) { return waiting }
        guard showsProcessingIndicator else { return nil }
        return ChatRecap.deriveActivityState(transcript: transcript, status: status)
    }

    /// 実行中ターンの最新 reasoning テキスト末尾3行（task-5 契約。受け入れテスト ReasoningPreview が凍結）。
    public var runningReasoningPreview: String? {
        guard status == .running else { return nil }
        guard let lastUserIndex = transcript.lastIndex(where: { item in
            if case .userMessage = item { return true }
            return false
        }) else { return nil }

        var latestReasoningText: String?
        for item in transcript[(lastUserIndex + 1)...] {
            if case .reasoning(_, let text, _) = item {
                latestReasoningText = text
            }
        }
        guard let latestReasoningText else { return nil }
        let preview = ReasoningPreview.tail(latestReasoningText, maxLines: 3)
        return preview.isEmpty ? nil : preview
    }

    public var workspaceName: String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "" }
        return (workingDirectory as NSString).lastPathComponent
    }

    public var workspacePath: String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "" }
        return (workingDirectory as NSString).abbreviatingWithTildeInPath
    }

    /// 現在のワークスペース (CWD) の生パス。衝突判定など、表示用に短縮しない用途で使う。
    public var rawWorkspacePath: String {
        workingDirectory ?? ""
    }

    public var isReadyForInput: Bool {
        switch status {
        case .starting:
            false
        case .idle, .running, .awaitingApproval, .awaitingUserQuestion, .completed, .error:
            true
        }
    }

    public func startNew(
        approvalPolicy: ApprovalPolicy,
        sandbox: SandboxPolicy,
        persistedSettings: CodexAppServerSessionSettings? = nil
    ) async throws {
        codexRestoreGeneration += 1
        scheduleHistoryCacheLoadIfNeeded()
        await historyCacheLoadTask?.value
        clearRunningBackgroundTasks()
        startEventTasks()
        await client.start()
        guard let codexClient else {
            await loadSpawnAgentSettings(persistedSettings: persistedSettings)
            status = .idle
            return
        }
        let initialized = try await codexClient.initialize(Self.initializeParams)
        appServerUserAgent = initialized.userAgent
        let response = try await codexClient.threadStart(ThreadStartParams(
            cwd: workingDirectory,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            threadSource: ThreadSource.user.rawValue,
            sessionStartSource: SessionStartSource.startup.rawValue
        ))
        updateNativeSessionId(response.thread.id)
        status = response.thread.status?.sessionStatus ?? .idle
        syncSettings(from: response)
        await loadAvailableSettings(persistedSettings: persistedSettings)
        if let persistedSettings, persistedSettings.hasAnyValue {
            await reapplyPersistedSettings(persistedSettings)
        }
    }

    public func restore(
        threadId: String,
        approvalPolicy: ApprovalPolicy,
        sandbox: SandboxPolicy,
        persistedSettings: CodexAppServerSessionSettings? = nil
    ) async {
        restoreState = .restoring
        codexRestoreGeneration += 1
        let restoreGeneration = codexRestoreGeneration
        clearRunningBackgroundTasks()
        startEventTasks()
        guard let codexClient else {
            _ = await restoreTranscriptFromStore()
            await restoreTurnUsageFromStore()
            do {
                try await client.resume(sessionRef: threadId)
                updateNativeSessionId(threadId)
                await loadSpawnAgentSettings(persistedSettings: persistedSettings)
                status = .idle
                restoreState = .restored
            } catch {
                updateNativeSessionId(threadId)
                status = .error(message: "chat restore failed: \(error)")
                restoreState = .failed(message: String(describing: error))
                if transcript.isEmpty {
                    appendOrReplace(.error(id: "restore-error-\(id.rawValue)", message: "chat restore failed: \(error)", timestamp: Date()))
                }
                logRestoreFailure(error)
            }
            return
        }

        await client.start()
        do {
            let initialized = try await codexClient.initialize(Self.initializeParams)
            guard restoreGeneration == codexRestoreGeneration else { return }
            appServerUserAgent = initialized.userAgent
            let response = try await codexClient.threadResume(ThreadResumeParams(
                threadId: threadId,
                cwd: workingDirectory,
                approvalPolicy: approvalPolicy,
                sandbox: sandbox
            ))
            guard restoreGeneration == codexRestoreGeneration else { return }
            syncSettings(from: response)
            await loadAvailableSettings(persistedSettings: persistedSettings)
            guard restoreGeneration == codexRestoreGeneration else { return }
            if let persistedSettings, persistedSettings.hasAnyValue {
                await reapplyPersistedSettings(persistedSettings, threadID: threadId)
            }
            guard restoreGeneration == codexRestoreGeneration else { return }
            await restoreTurnUsageFromStore()
            guard restoreGeneration == codexRestoreGeneration else { return }
            let storedTranscript = await loadTranscriptFromStore()
            guard restoreGeneration == codexRestoreGeneration else { return }
            if let storedTranscript {
                applyRestoredTranscript(storedTranscript)
                guard restoreGeneration == codexRestoreGeneration else { return }
                updateNativeSessionId(response.thread.id)
                applyRestoredThreadStatus(response.thread.status?.sessionStatus ?? .idle)
                await codexClient.commitThreadResumeIfCurrent(threadID: threadId)
            } else {
                let read = try await codexClient.threadRead(ThreadReadParams(threadId: threadId, includeTurns: true))
                guard restoreGeneration == codexRestoreGeneration,
                      read.thread.id == threadId else {
                    if restoreGeneration == codexRestoreGeneration {
                        throw CodexAppServerClientError.threadIDMismatch(
                            requested: threadId,
                            received: read.thread.id
                        )
                    }
                    return
                }
                updateNativeSessionId(read.thread.id)
                rebuildTranscript(from: read.thread)
                applyRestoredThreadStatus(read.thread.status?.sessionStatus ?? .idle)
            }
            guard restoreGeneration == codexRestoreGeneration else { return }
            restoreState = .restored
        } catch {
            guard restoreGeneration == codexRestoreGeneration else { return }
            await codexClient.rollbackThreadResumeIfCurrent(threadID: threadId)
            status = .error(message: "chat restore failed: \(error)")
            restoreState = .failed(message: String(describing: error))
            if transcript.isEmpty {
                appendOrReplace(.error(id: "restore-error-\(id.rawValue)", message: "chat restore failed: \(error)", timestamp: Date()))
            }
            logRestoreFailure(error)
        }
    }

    public func markRestoreFailed(_ message: String) {
        status = .error(message: message)
        restoreState = .failed(message: message)
        appendOrReplace(.error(id: "restore-error-\(id.rawValue)", message: message, timestamp: Date()))
        touchOutput()
    }

    public func turnInterrupt() async {
        flushPendingStreamDeltasBarrier()
        if let activeInterruptTask {
            await activeInterruptTask.value
            return
        }

        let interruptID = UUID()
        let startedGeneration = turnGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.expireAllPendingUserQuestions()
            do {
                try await self.client.interrupt()
            } catch {
                // await 中に届いた delta を先に確定してからエラー項目を追加する
                // （barrier 無しだとエラー項目が先着 delta より前へ挿入され順序契約を破る。stage2 指摘）。
                self.flushPendingStreamDeltasBarrier()
                self.appendOrReplace(.error(
                    id: "interrupt-error-\(UUID().uuidString)",
                    message: "中止リクエストに失敗しました: \(error)",
                    timestamp: Date()
                ))
                self.touchOutput()
            }

            guard self.turnGeneration == startedGeneration else { return }
            self.flushPendingStreamDeltasBarrier()
            self.clearRunningTurn()
            self.clearRunningBackgroundTasks()
            self.subAgentModel.failRunningSubAgents()
            self.status = .idle
        }
        activeInterruptID = interruptID
        activeInterruptTask = task
        await task.value
        if activeInterruptID == interruptID {
            activeInterruptID = nil
            activeInterruptTask = nil
        }
    }

    // MARK: - esc ホットキー状態機械（task-9）

    /// 2連打と判定する猶予（秒）。直前 esc からこの秒数「以内」の次 esc が 2連打。
    static let doubleEscapeWindow = EscapeRevertPolicy.doubleEscapeWindow

    /// リバート候補（transcript の userMessage のみ・新しい順）。
    /// ピッカーが新しい依頼を先頭に表示できるよう、transcript 末尾（＝直近）を先頭に並べ替える。
    public var revertCandidates: [ChatItem] {
        EscapeRevertPolicy.revertCandidates(from: transcript)
    }

    /// esc 押下を状態機械で処理する（task-9）。時刻は注入可能（テスト用）。
    /// 分岐は排他・この順:
    /// 1. ピッカー表示中 → 閉じる（interrupt/ピッカー再開へ落ちない）。
    /// 2. 直前 esc から `doubleEscapeWindow` 秒以内（2連打）→ 候補が空でなければピッカーを開く（status 非依存）。
    /// 3. 単発 esc かつ処理中 → `turnInterrupt()` を Task で発火（完了を待たない）し時刻記録。
    /// 4. 単発 esc かつ完全 idle → 時刻記録のみ。
    public func handleEscapeKey(now: Date = Date()) {
        if isHistoryPickerPresented {
            isHistoryPickerPresented = false
            // 閉じた esc は次の 2連打シーケンスの起点にしない（閉じた直後の esc で再度開くのを防ぐ）。
            lastEscapeAt = nil
            // ピッカーが奪ったフォーカスの返却先を composer に定義する。本文は復元していないので
            // キャレット・選択範囲は動かさない。
            requestComposerFocus(movesCaretToEnd: false)
            return
        }
        if EscapeRevertPolicy.isDoubleEscape(lastEscapeAt: lastEscapeAt, now: now) {
            lastEscapeAt = now
            if !revertCandidates.isEmpty {
                isHistoryPickerPresented = true
            }
            return
        }
        lastEscapeAt = now
        if showsProcessingIndicator {
            // interrupt の非同期完了を待たない（待つと 2連打でピッカーを開けなくなる＝ハザード3）。
            Task { await self.turnInterrupt() }
        }
    }

    /// ピッカーで選んだ userMessage までリバートし、返り値本文を `draftRestoration` に載せてピッカーを閉じる（task-9）。
    /// 実リバートは task-8 の `revert(toUserMessageID:)`（running 中は自身が拒否＝nil を返す）。
    /// 履歴を選んだ時点で「実行中ターンの放棄」がユーザー意図なので、running が残っていれば
    /// 先に中断を完了させてからリバートする（esc 1回目の interrupt が未収束の窓で選択が
    /// 無音 no-op になるのを防ぐ。turnInterrupt は非スローで必ず idle 復帰する）。
    public func confirmRevert(toUserMessageID id: String) async {
        if status == .running {
            await turnInterrupt()
        }
        let restored = await revert(toUserMessageID: id)
        // 復元本文は ViewModel 自身が `draft` へ書く。View 側の `draftRestoration` 監視経由にすると
        // 本文がフォーカス要求より 1 更新パス遅れて届き、「末尾化すべき本文がまだ無い」状態を
        // View 側で保留・再適用する機構が必要になる。同じ代入の中で両方を確定させて遅れ自体を無くす。
        if let restored {
            draft = restored
        }
        draftRestoration = restored
        isHistoryPickerPresented = false
        lastEscapeAt = nil
        // ピッカーは閉じるのでフォーカスは必ず composer へ返す。本文を復元できたときだけ
        // キャレットを末尾へ動かす（先頭のままだと打った文字が復元本文の前に入る）。
        requestComposerFocus(movesCaretToEnd: restored != nil)
    }

    /// composer へのフォーカス復帰要求を 1 段だけ進める。token は狭義単調増加で、
    /// 同じ値を再発行しない（View は値の変化だけを見てフォーカスを動かす）。
    public func dismissSendFailure() {
        sendFailure = nil
    }

    /// 承認カードから入力欄へ戻る（カードで Tab）。
    public func returnFocusToComposer() {
        requestComposerFocus(movesCaretToEnd: false)
    }

    /// 入力欄から承認カード・質問カードへ移る（入力欄で Tab）。
    public func requestReplyCardFocus() {
        replyCardFocusRequest += 1
    }

    private func requestComposerFocus(movesCaretToEnd: Bool) {
        composerFocusRequest = ComposerFocusRequest(
            token: composerFocusRequest.token + 1,
            movesCaretToEnd: movesCaretToEnd
        )
    }

    /// View が `draftRestoration` を composer へ反映したあとに呼び、復元本文を消費する（task-9）。
    public func consumeDraftRestoration() {
        draftRestoration = nil
    }

    /// 会話履歴を「指定した過去のユーザーメッセージの直前」まで巻き戻す（リバート）。
    /// - ローカル transcript を当該メッセージ以降を除去して切り詰める。
    /// - TranscriptStore の内容も同一に置換する（進行中の追記キューを flush してから replace）。
    /// - `client.resetConversation()` をちょうど 1 回呼び、CLI 側会話をリセットして native id を破棄。
    /// - 次の submit 送信へ「保持転写からの文脈リプレイ（上限 12,000 文字・古い側から切り捨て）」を
    ///   1 回だけ予約する（表示・store には新規入力のみ、CLI へはプリアンブル付き）。
    /// - 戻り値は当該ユーザーメッセージの本文（View が composer 入力欄へ復元する）。
    /// - 事前条件: 該当 id の userMessage が存在し、status が .running でないこと。満たさなければ nil。
    public func revert(toUserMessageID id: String) async -> String? {
        // running 中は禁止（先に interrupt が完了していること）。何も変更せず拒否する。
        guard status != .running else { return nil }

        guard let index = transcript.firstIndex(where: { item in
            if case .userMessage(let itemID, _, _, _) = item { return itemID == id }
            return false
        }) else { return nil }
        guard case .userMessage(_, let userText, _, _) = transcript[index] else { return nil }

        // 該当メッセージ自身と以降を除去し、直前までを保持転写とする。
        let retained = Array(transcript[..<index])
        setTranscript(retained)

        // store も同一内容へ置換する。追記キュー（enqueueTranscriptUpsert）と同じ直列チェーンに
        // 載せることで「進行中の追記を flush してから replace」の順序を保証する（item の復活を防ぐ）。
        enqueueTranscriptReplace(retained)

        // CLI 側会話をリセット（ちょうど 1 回）し、旧 native id を破棄する。
        await client.resetConversation()
        // 新しい CLI の会話は累計を 0 から数える。
        claudeReportedTotalCostUSD = 0
        // Codex は reset で新 thread が確定するので、それを採用して以後のイベント弁別に使う
        // （threadId が旧 thread のまま/nil のままだと、旧 thread の遅延イベント遮断や新 thread の
        // イベント採用が成立しない）。spawn 型（Codex 以外）は新 native id を CLI が後から通知するため
        // ここでは nil にクリアする。
        if let codexClient {
            updateNativeSessionId(await codexClient.activeThreadId())
        } else {
            updateNativeSessionId(nil)
        }

        // 文脈リプレイを 1 回だけ予約する（保持分が空なら nil＝素の新規会話）。
        pendingReplayContext = EscapeRevertPolicy.replayContext(from: retained)

        restoreRuntimeAttachmentsForRevert(userMessageID: id)

        return userText
    }

    static let replayContextCharacterLimit = EscapeRevertPolicy.replayContextCharacterLimit

    /// store 内容を `items` で置換する。追記キューと同一チェーンに載せて FIFO を守り、
    /// 先行の upsert を必ず flush してから replace が走る（順序保証）。
    private func enqueueTranscriptReplace(_ items: [ChatItem]) {
        transcriptPersistenceQueue?.enqueueReplace(items)
    }

    public func respondToApproval(_ approvalID: UUID, decision: ApprovalDecision) async {
        pendingApprovals.removeAll { $0.id == approvalID }
        await approvalBroker.respond(to: approvalID, decision: decision)
        if pendingApprovals.isEmpty, case .awaitingApproval = status {
            status = .running
        }
    }

    /// AskUserQuestion の回答を CLI へ返送し、質問カードを answered へ遷移させる（task-0 契約）。
    /// 戻り値: requestId が pending の質問カードに一致し回答を受理したら true。
    /// 一致しない・既に answered/expired・同一質問への回答送信中なら false（no-op）。
    /// pending 判定は client 呼び出しの await をまたいで有効でないため、送信中の
    /// requestId を記録して真の同時二重回答（両方 true・answers の競合上書き）を防ぐ。
    private var respondingUserQuestionIds: Set<String> = []

    /// Codex 質問への回答を拒否し、wire を決着させてからターンを中断する（決定 D4）。
    /// 戻り値: 拒否を受理したら true。
    @discardableResult
    public func declineUserQuestion(requestId: String) async -> Bool {
        guard let index = userQuestionCardIndex(requestId: requestId),
              case .userQuestion(_, _, _, _, .pending, _) = transcript[index],
              codexUserInputRequestIDs[requestId] != nil
        else {
            return false
        }

        await turnInterrupt()
        return true
    }

    public func respondToUserQuestion(requestId: String, answers: [String: [String]]) async -> Bool {
        guard !respondingUserQuestionIds.contains(requestId),
              let index = userQuestionCardIndex(requestId: requestId),
              case .userQuestion(let id, let rid, let questions, _, .pending, let timestamp) = transcript[index]
        else {
            return false
        }

        respondingUserQuestionIds.insert(requestId)
        defer { respondingUserQuestionIds.remove(requestId) }

        if let userInputID = codexUserInputRequestIDs.removeValue(forKey: requestId) {
            await approvalBroker.answerUserInput(id: userInputID, answers: answers)
            applyUserQuestionResolution(
                requestId: requestId,
                outcome: .answered(answers: answers)
            )
            touchOutput()
            return true
        }

        // 既知の制約: answered 表示と actor の実送信がずれうるが、未承認ツールは実行されず表示上のずれに留まる。
        await client.respondToUserQuestion(requestId: requestId, answers: answers)
        let persistedAnswers = ChatUserQuestion.persistedAnswers(from: answers, for: questions)
        appendOrReplace(.userQuestion(
            id: id,
            requestId: rid,
            questions: questions,
            answers: persistedAnswers,
            state: .answered,
            timestamp: timestamp
        ))
        touchOutput()
        return true
    }

    public var codexSettingsSnapshot: CodexAppServerSessionSettings? {
        let settings = CodexAppServerSessionSettings(
            selectedModel: selectedModel,
            selectedEffort: selectedEffort,
            selectedPermissionProfile: selectedPermissionProfile,
            isPlanMode: isPlanMode
        )
        return settings.hasAnyValue ? settings : nil
    }

    public func selectSubAgent(_ id: String?) {
        subAgentModel.selectSubAgent(id)
    }

    public func dismissSubAgent(_ id: String) {
        subAgentModel.dismissSubAgent(id)
    }

    public func subAgentTranscript(for id: String) -> [ChatItem] {
        subAgentModel.transcript(for: id)
    }

    var subAgentDedupScanMetricsForTesting: ChatSubAgentModel.DedupScanMetrics {
        subAgentModel.dedupScanMetricsForTesting
    }

    func resetSubAgentDedupScanMetricsForTesting() {
        subAgentModel.resetDedupScanMetricsForTesting()
    }

    var hasPendingTranscriptStreamDeltasForTesting: Bool {
        transcriptStreamCoalescer.hasPendingDeltasForTesting
    }

    var lastRunningEventAtForTesting: Date? {
        lastEventAt
    }

    public func subAgentControlSummaries() -> [SubAgentControlSummary] {
        subAgents.map { ref in
            let markerMessageId = transcript.first { item in
                if case .subAgentMarker(let markerId, _, _, _) = item {
                    return markerId == ref.id
                }
                return false
            }?.id
            return SubAgentControlSummary(
                id: ref.id,
                name: ref.subagentType,
                status: ref.status,
                messageCount: subAgentTranscript(for: ref.id).count,
                markerMessageId: markerMessageId
            )
        }
    }

    /// 送った Codex の設定変更の通し番号と、画面に反映した最後の番号。応答が前後しても、
    /// 後から送った変更の結果より古いものは画面に戻さない（⇧Tab とメニューを続けて使ったときなど）。
    private var codexSettingsRequestCount = 0
    private var codexSettingsAppliedRequest = 0
    /// 応答を待っている設定変更の数。待っている間に届いた設定の通知では、モデルと深さを変えない
    /// （通知はどの変更の結果か分からない。待っている変更の応答が画面に反映する）。
    private var codexSettingsRequestsInFlight = 0

    public func setModel(model: String, effort: String?) async throws {
        guard let threadId else { throw ChatSettingsUpdateError.threadNotStarted }
        guard let codexClient else { throw ChatSettingsUpdateError.codexSettingsUnavailable }
        let resolvedEffort = effort ?? defaultEffort(for: model)
        let collaborationMode = isPlanMode
            ? try makeCollaborationMode(on: true, model: model, effort: resolvedEffort)
            : nil
        let params = ThreadSettingsUpdateParams(
            threadId: threadId,
            model: model,
            effort: resolvedEffort,
            collaborationMode: collaborationMode
        )
        codexSettingsRequestCount += 1
        let request = codexSettingsRequestCount
        codexSettingsRequestsInFlight += 1
        defer { codexSettingsRequestsInFlight -= 1 }
        do {
            _ = try await codexClient.updateThreadSettings(params)
        } catch where collaborationMode != nil && !isTerminating && request == codexSettingsRequestCount {
            // プラン モードを外して送り直すのは、後から別の変更を送っていないときだけ（新しい設定を古い値で上書きしない）。
            isPlanMode = false
            isPlanModeAvailable = false
            _ = try await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: threadId,
                model: model,
                effort: resolvedEffort
            ))
        }
        guard request > codexSettingsAppliedRequest else { return }
        codexSettingsAppliedRequest = request
        selectedModel = model
        selectedEffort = resolvedEffort
        notifyCodexSettingsChanged()
    }

    // MARK: - Control API からのモデル変更（2系統の窓口をここへ集約する）

    /// Control API が広告するモデル候補。spawn 型（Claude/Cursor）は CLI フラグのカタログ値、
    /// codex は app-server の `listModels` ライブ値（＝アプリ UI と同じ出所）を返す。
    public var controlModelChoices: [ControlModelChoice] {
        if canApplySpawnAgentSettings {
            return availableSpawnAgentModels.map {
                ControlModelChoice(id: $0, displayName: spawnAgentModelDisplayName($0))
            }
        }
        if codexClient != nil {
            return availableModels.map { ControlModelChoice(id: $0.id, displayName: $0.displayName) }
        }
        return []
    }

    /// Control API からのモデル適用。throws を outcome へ写像し、失敗理由を握りつぶさない。
    public func applyControlModel(_ model: String) async -> ControlModelApplyOutcome {
        if canApplySpawnAgentSettings {
            guard availableSpawnAgentModels.contains(model) else { return .unknownModel }
            await setSpawnAgentModel(model)
            return .applied
        }
        guard codexClient != nil else { return .unsupported }
        // UI のモデル選択と同じ突き合わせ規則（id または model のどちらかに一致）。
        guard let resolved = availableModels.first(where: { $0.id == model || $0.model == model })?.id else {
            return availableModels.isEmpty ? .unsupported : .unknownModel
        }
        do {
            try await setModel(model: resolved, effort: nil)
            return .applied
        } catch ChatSettingsUpdateError.threadNotStarted {
            return .notReady
        } catch ChatSettingsUpdateError.codexSettingsUnavailable {
            return .unsupported
        } catch {
            return .failed
        }
    }

    public func setPermissionProfile(id: String) async throws {
        guard let threadId else { throw ChatSettingsUpdateError.threadNotStarted }
        guard let codexClient else { throw ChatSettingsUpdateError.codexSettingsUnavailable }
        _ = try await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
            threadId: threadId,
            permissions: id
        ))
        selectedPermissionProfile = id
        notifyCodexSettingsChanged()
    }

    public func setPlanMode(_ on: Bool) async throws {
        if isSpawnAgent {
            guard on ? isPlanModeAvailable : true else {
                throw ChatSettingsUpdateError.planModeUnavailable
            }
            isPlanMode = on
            await applySpawnAgentSettings()
            return
        }
        guard let threadId else { throw ChatSettingsUpdateError.threadNotStarted }
        guard let codexClient else { throw ChatSettingsUpdateError.codexSettingsUnavailable }
        let collaborationMode = try makeCollaborationMode(on: on)
        codexSettingsRequestCount += 1
        let request = codexSettingsRequestCount
        codexSettingsRequestsInFlight += 1
        defer { codexSettingsRequestsInFlight -= 1 }
        do {
            _ = try await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: threadId,
                collaborationMode: collaborationMode
            ))
        } catch {
            // 後から送った変更がもう画面に出ていれば、その結果を残す。
            if on, request > codexSettingsAppliedRequest {
                isPlanMode = false
                isPlanModeAvailable = false
                notifyCodexSettingsChanged()
            }
            throw error
        }
        guard request > codexSettingsAppliedRequest else { return }
        codexSettingsAppliedRequest = request
        isPlanMode = on
        if on {
            // 前の切り替えの失敗で選べない扱いになっていても、通ったので選べる。
            isPlanModeAvailable = true
            selectedModel = collaborationMode.settings.model
            selectedEffort = collaborationMode.settings.reasoningEffort
        }
        notifyCodexSettingsChanged()
    }

    // MARK: - Spawn agent (Claude/Cursor) settings

    /// Claude spawn セッションで選択可能な effort（CLI `--effort` の有効値）。
    static let claudeEffortLevelOptions = ["low", "medium", "high", "xhigh", "max"]

    /// effort 非対応モデルの denylist（denylist に無ければ effort 対応とみなす）。
    nonisolated static let claudeEffortUnsupportedModelAliases: Set<String> = [
        "haiku", // effort 非対応（将来追加時はここへ）
    ]

    /// Claude spawn セッションの既定 effort。
    static let defaultClaudeEffort = "high"

    /// 選択モデルが effort をサポートするか（nil は非対応扱い）。
    nonisolated static func claudeModelSupportsEffort(_ alias: String?) -> Bool {
        guard let alias else { return false }
        // Dynamic aliases such as haiku[1m] inherit the base model's capability.
        let baseAlias = alias.split(separator: "[", maxSplits: 1).first.map(String.init) ?? alias
        return !claudeEffortUnsupportedModelAliases.contains(baseAlias)
    }

    /// Claude セッションかつ effort 対応モデルでは effort 候補を返し、非対応モデル・Cursor 等では空（メニュー非表示）。
    public var claudeEffortLevels: [String] {
        switch agentRef {
        case .builtin(.claudeCode):
            guard Self.claudeModelSupportsEffort(selectedModel) else { return [] }
            return Self.claudeEffortLevelOptions
        default:
            return []
        }
    }

    /// モデル表示名は agent 種別に関わらず共有カタログから探す。履歴やカスタム agent でも
    /// 既知 alias の装飾を失わず、未知 ID はそのまま表示する。
    public func spawnAgentModelDisplayName(_ alias: String) -> String {
        AgentKind.allCases.lazy.compactMap { kind in
            AgentModelCatalog.models(for: kind).first(where: { $0.id == alias })?.displayName
        }.first ?? alias
    }

    /// task-11 が呼ぶ model 変更ハンドラ。選択を保持し、フルスナップショットで actor へ反映する。
    public func setSpawnAgentModel(_ model: String?) async {
        guard canApplySpawnAgentSettings else { return }
        selectedModel = model
        if agentRef == .builtin(.claudeCode) {
            if Self.claudeModelSupportsEffort(model) {
                if selectedEffort == nil {
                    selectedEffort = Self.defaultClaudeEffort
                }
            } else {
                selectedEffort = nil
            }
        }
        await applySpawnAgentSettings()
    }

    /// task-11 が呼ぶ permission(Claude)/mode(Cursor) 変更ハンドラ。
    public func setSpawnAgentPermission(_ permissionOrMode: String?) async {
        guard isSpawnAgent else { return }
        if permissionOrMode == "plan" {
            isPlanMode = true
            await applySpawnAgentSettings()
            return
        }
        isPlanMode = false
        selectedPermissionProfile = permissionOrMode
        await applySpawnAgentSettings()
    }

    /// 入力欄の ⇧Tab で回す推論の深さの段（いまのエージェントとモデルで選べるもの。メニューと同じ並び）。
    public var cyclableEfforts: [String] {
        guard agentRef == .builtin(.codex) else { return claudeEffortLevels }
        guard let selectedCodexModel else { return [] }
        return selectedCodexModel.supportedReasoningEfforts.map(\.reasoningEffort)
    }

    private var selectedCodexModel: AppServerModel? {
        guard let selectedModel else { return nil }
        return availableModels.first { $0.id == selectedModel || $0.model == selectedModel }
    }

    /// 次の段。最後の次は最初へ戻り、いまの値が段に無ければ最初。回す段が 2 つ未満なら nil。
    static func nextEffort(after current: String?, in levels: [String]) -> String? {
        guard levels.count > 1 else { return nil }
        guard let current, let index = levels.firstIndex(of: current) else { return levels[0] }
        return levels[(index + 1) % levels.count]
    }

    /// 前の ⇧Tab の反映。続けて押したときは前の反映を待ってから次の段を数える（2 回とも同じ段にならないように）。
    private var effortCycleTail: Task<Void, Never>?
    /// 終了し始めたら ⇧Tab の変更を送らない。
    public private(set) var isTerminating = false

    /// ⇧Tab: 推論の深さを次の段へ回す。変えた段を返す（変えられなかったら nil）。
    @discardableResult
    public func cycleEffort() async -> String? {
        let previous = effortCycleTail
        let cycle = Task { @MainActor () -> String? in
            await previous?.value
            guard !self.isTerminating else { return nil }
            return await self.applyNextEffort()
        }
        effortCycleTail = Task { _ = await cycle.value }
        let result = await cycle.value
        return isTerminating ? nil : result
    }

    private func applyNextEffort() async -> String? {
        guard let next = Self.nextEffort(after: selectedEffort, in: cyclableEfforts) else { return nil }
        if agentRef == .builtin(.codex) {
            guard let model = selectedCodexModel else { return nil }
            // 送れたら成功（応答待ちの間にメニューで選び直していれば、画面にはそちらが残る）。
            do { try await setModel(model: model.id, effort: next) } catch { return nil }
            return next
        }
        await setSpawnAgentEffort(next)
        return selectedEffort == next ? next : nil
    }

    /// task-22: Claude spawn セッションの effort 変更ハンドラ。
    public func setSpawnAgentEffort(_ effort: String?) async {
        guard isSpawnAgent else { return }
        selectedEffort = effort
        await applySpawnAgentSettings()
    }

    /// Claude / Cursor のモデル一覧が CLI から取れず、内蔵の一覧になっているか（05 O3）。
    public var isUsingBuiltinModelList: Bool {
        guard spawnAgentModelsProvider == nil, let kind = agentRef.builtinKind, kind != .codex else { return false }
        return AgentModelCatalog.kindsUsingFallback().contains(kind)
    }

    /// CLI からのモデル一覧の取得をやり直し、選択肢を差し替える。
    public func retryModelListFetch() async {
        await AgentModelCatalog.refresh()
        availableSpawnAgentModels = await resolveSpawnAgentModels()
    }

    private func loadSpawnAgentSettings(persistedSettings: CodexAppServerSessionSettings?) async {
        availableSpawnAgentModels = await resolveSpawnAgentModels()
        let persistedPermissionOrMode = spawnAgentPermissionOverride
            ?? persistedSettings?.selectedPermissionProfile
        let persistedPlanMode = persistedSettings?.isPlanMode ?? (persistedPermissionOrMode == "plan")

        switch agentRef {
        case .builtin(.claudeCode):
            selectedModel = persistedSettings?.selectedModel
                ?? selectedModel
                ?? AgentModelCatalog.defaultModel(for: .claudeCode)
            if Self.claudeModelSupportsEffort(selectedModel) {
                selectedEffort = persistedSettings?.selectedEffort
                    ?? selectedEffort
                    ?? Self.defaultClaudeEffort
            } else {
                selectedEffort = nil
            }
            // permission 未変更時も現在値（既定 bypassPermissions）を明示的に保持する。さもないと
            // 置換セマンティクスの updateSettings で --permission-mode が外れ、task-8 の
            // ツール権限付与が失われる。
            if persistedPermissionOrMode == "plan" {
                selectedPermissionProfile = selectedPermissionProfile ?? defaultClaudeSpawnPermission
            } else {
                selectedPermissionProfile = persistedPermissionOrMode
                    ?? selectedPermissionProfile
                    ?? defaultClaudeSpawnPermission
            }
        case .builtin(.cursor):
            selectedModel = persistedSettings?.selectedModel
                ?? selectedModel
                ?? AgentModelCatalog.defaultModel(for: .cursor)
            selectedPermissionProfile = persistedPermissionOrMode == "plan"
                ? selectedPermissionProfile
                : persistedPermissionOrMode ?? selectedPermissionProfile
        default:
            break
        }
        isPlanMode = persistedPlanMode
        isPlanModeAvailable = isSpawnAgent

        // 起動直後から model/permission(mode) をフルスナップショットで actor へ反映する。
        await applySpawnAgentSettings(clearBackgroundTasksOnNextTurnStart: false)
    }

    private var defaultClaudeSpawnPermission: String {
        "bypassPermissions"
    }

    private func resolveSpawnAgentModels() async -> [String] {
        // This explicit seam is used by deterministic callers (not by the production
        // composition root). A non-empty injected snapshot must be honoured; otherwise
        // the shared live catalog remains the single production source of truth.
        if let spawnAgentModelsProvider {
            let injected = await spawnAgentModelsProvider()
            if !injected.isEmpty { return injected }
        }
        switch agentRef {
        case .builtin(.claudeCode):
            return AgentModelCatalog.models(for: .claudeCode).map(\.id)
        case .builtin(.cursor):
            return AgentModelCatalog.models(for: .cursor).map(\.id)
        default:
            return []
        }
    }

    /// 選択中の model/permission(mode) を毎回そろえて actor へ渡し、永続コールバックを叩く。
    private func applySpawnAgentSettings(clearBackgroundTasksOnNextTurnStart: Bool = true) async {
        guard let controller = spawnSettingsClient else { return }
        let effectivePermissionOrMode = isPlanMode ? "plan" : selectedPermissionProfile
        let effort: String? = agentRef == .builtin(.claudeCode)
            && Self.claudeModelSupportsEffort(selectedModel)
            ? selectedEffort
            : nil
        await controller.applySpawnAgentSettings(
            model: selectedModel,
            permissionOrMode: effectivePermissionOrMode,
            effort: effort
        )
        if clearBackgroundTasksOnNextTurnStart {
            shouldClearBackgroundTasksOnNextTurnStart = true
        }
        notifyCodexSettingsChanged()
    }

    public var usageQuerying: (any UsageQuerying)? {
        client as? any UsageQuerying
    }

    private var spawnSettingsClient: (any SpawnAgentSettingsControlling)? {
        client as? any SpawnAgentSettingsControlling
    }

    /// spawn 型エージェント設定を実際の CLI 制御クライアントへ適用できるか。
    public var canApplySpawnAgentSettings: Bool {
        spawnSettingsClient != nil
    }

    private var isSpawnAgent: Bool {
        canApplySpawnAgentSettings
    }

    private static var initializeParams: InitializeParams {
        InitializeParams(
            clientInfo: ClientInfo(name: "phlox", title: "Phlox", version: "1"),
            capabilities: InitializeCapabilities(experimentalApi: true)
        )
    }

    private func startEventTasks() {
        if eventTask == nil, let orderedCodexClient = client as? any CodexOrderedEventsProviding {
            let events = orderedCodexClient.orderedEvents
            eventTask = Task { @MainActor [weak self] in
                for await event in events {
                    guard let self else { return }
                    switch event {
                    case .thread(let threadEvent):
                        self.handleCodexSettingsEvent(threadEvent)
                    case .normalized(let normalizedEvent):
                        await self.handle(normalizedEvent)
                    case .normalizedWithIdentity(let eventThreadId, let eventTurnId, let normalizedEvent):
                        guard self.acceptsCodexNormalizedEvent(
                            threadId: eventThreadId,
                            turnId: eventTurnId
                        ) else { continue }
                        await self.handle(normalizedEvent)
                    }
                }
            }
        } else if eventTask == nil {
            let events = client.events
            eventTask = Task { @MainActor [weak self] in
                for await event in events {
                    await self?.handle(event)
                }
            }
        }
        if codexSettingsEventTask == nil,
           let codexClient,
           !(client is any CodexOrderedEventsProviding) {
            let events = codexClient.threadEvents
            codexSettingsEventTask = Task { @MainActor [weak self] in
                for await event in events {
                    self?.handleCodexSettingsEvent(event)
                }
            }
        }
        if approvalTask == nil {
            let approvals = approvalBroker.requests
            approvalTask = Task { @MainActor [weak self] in
                for await approval in approvals {
                    // プロセスが終わった後に届いた分は答えられない（broker 側は否認で決着済み）。
                    guard self?.processExit == nil else { continue }
                    self?.pendingApprovals.append(approval)
                    self?.enterAwaitingApproval(
                        prompt: approval.prompt,
                        notifying: .awaitingApproval(prompt: approval.command ?? approval.permissionsText ?? approval.prompt)
                    )
                    self?.touchOutput()
                }
            }
        }
        if userInputTask == nil {
            let userInputRequests = approvalBroker.userInputRequests
            userInputTask = Task { @MainActor [weak self] in
                for await request in userInputRequests {
                    guard let self else { return }
                    guard self.processExit == nil else { continue }
                    let requestId = request.id.uuidString
                    self.codexUserInputRequestIDs[requestId] = request.id
                    self.receiveUserQuestion(
                        requestId: requestId,
                        questions: request.questions,
                        timestamp: Date()
                    )
                }
            }
        }
    }

    private func beginRunningTurn(at date: Date) {
        if isAwaitingLocallyStartedTurnEvent {
            isAwaitingLocallyStartedTurnEvent = false
        } else {
            turnGeneration += 1
        }
        turnStartedAt = date
        turnIsRestoredInference = false
        lastEventAt = nil
        pendingTurnCostUSD = nil
        pendingTurnUsage = nil
        startStallWatch()
    }

    private func markRunningEventReceived(at date: Date) {
        guard turnStartedAt != nil else { return }
        lastEventAt = date
        // 反応が届いたら次の 1 秒周期を待たずに無応答を解く。
        if isStalled { updateStalled(now: date) }
    }

    private func clearRunningTurn() {
        turnStartedAt = nil
        turnIsRestoredInference = false
        lastEventAt = nil
        pendingTurnCostUSD = nil
        pendingTurnUsage = nil
        stallWatchTask?.cancel()
        stallWatchTask = nil
        updateStalled(now: Date())
    }

    /// 実行中ターンの間だけ、無応答の判定を 1 秒ごとに見直す（変わったときだけ書く）。
    private func startStallWatch() {
        stallWatchTask?.cancel()
        stallWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.updateStalled(now: Date())
            }
        }
    }

    func updateStalled(now: Date) {
        // 承認・質問待ちの間は反応が無くて当然なので数えない（一覧ではそちらの状態が勝つ）。
        let stalled = status == .running && (hangAssessment(now: now)?.isStalled ?? false)
        guard stalled != isStalled else { return }
        isStalled = stalled
        stalledSince = stalled ? now : nil
        // 復元時に実行中と推定しただけのターンは、本当に止まっているか分からないので知らせない。
        if stalled, !turnIsRestoredInference {
            notifyUser(.stalled(lastAction: thinkingRecap(now: now).map(Self.notificationText)))
        }
    }

    /// 最後のユーザー入力以降の、最後の返答（完了の通知の本文に使う）。
    private var lastAgentReply: String? {
        for item in transcript.reversed() {
            switch item {
            case .agentMessage(_, let text, _): return text
            case .userMessage: return nil
            default: continue
            }
        }
        return nil
    }

    /// 思考中インジケータの下段と同じ要約を、通知の表示言語で組む。
    private static func notificationText(_ summary: ChatRecap.Summary) -> String {
        let locale = SessionCompletionNotifier.locale()
        func format(_ key: String, _ value: String) -> String {
            String(format: AppLocalizedString.string(key, locale: locale), ThinkingRecap.clamp(value))
        }
        return switch summary {
        case .activity(.reading(let x)): format("%@ を読み込み中", x)
        case .activity(.running(let x)): format("%@ を実行中", x)
        case .activity(.editing(let x)): format("%@ を編集中", x)
        case .headline(let x): x
        }
    }

    /// 復元時にすでに実行中だったターンを、復元リプレイではなく実ターンとして追跡する。
    /// これにより、その後に届く terminal status で完了通知を判定できる。
    private func applyRestoredThreadStatus(_ restoredStatus: SessionStatus) {
        status = restoredStatus
        guard restoredStatus == .running else { return }
        turnStartedAt = Date()
        turnIsRestoredInference = true
        lastEventAt = nil
        startStallWatch()
    }

    /// ターミナル型と同じポリシーで完了を通知する。待機状態は実行中ターンに限って完了対象にし、
    /// 復元リプレイ・interrupt 由来の idle 遷移では呼ばない。
    @discardableResult
    private func notifyCompletionIfNeeded(from previousStatus: SessionStatus, hadActiveTurn: Bool) -> Bool {
        guard SessionCompletionNotificationPolicy.shouldNotifyCompletion(
            previous: previousStatus,
            next: status,
            hasActiveTurn: hadActiveTurn
        ) else { return false }
        // 本物のターン完了を未確認の停止としてラッチする（turnInterrupted はこの経路を通らない）。
        hasUnseenCompletion = true
        notifyUser(.completed)
        return true
    }

    /// 承認待ちへ遷移し、非承認待ちからの遷移時のみ通知する（連続する承認要求での多重通知を防ぐ）。
    /// `notifying` は通知に出す種類と対象（既定は承認待ちで、対象は `prompt`）。
    func enterAwaitingApproval(prompt: String, notifying kind: SessionNotificationText.Kind? = nil) {
        let previousStatus = status
        status = .awaitingApproval(prompt: prompt)
        if case .awaitingApproval = previousStatus { return }
        notifyUser(.awaitingInput(kind ?? .awaitingApproval(prompt: prompt)))
    }

    /// AskUserQuestion 到着時に入力待ちへ遷移し、非入力待ちからの遷移時のみ通知する。
    private func enterAwaitingUserQuestion(notifying kind: SessionNotificationText.Kind) {
        let previousStatus = status
        status = .awaitingUserQuestion
        if case .awaitingUserQuestion = previousStatus { return }
        notifyUser(.awaitingInput(kind))
    }

    private func notifyUser(_ notification: UserNotification) {
        let allowsLocalNotification = userNotificationGate?(.local) ?? true
        let allowsRemoteNotification = userNotificationGate?(.remote) ?? true
        switch notification {
        case .completed:
            if allowsLocalNotification {
                SessionCompletionNotifier.notifyCompleted(sessionID: id, sessionName: displayName, status: status, lastReply: lastAgentReply)
            }
            if allowsRemoteNotification {
                let kind: RemoteSessionNotification = if case .error = status { .error } else { .completed }
                remoteSessionNotifier?.notify(kind, sessionId: id.description, sessionName: displayName)
            }
        case .awaitingInput(let kind):
            if allowsLocalNotification {
                SessionCompletionNotifier.notifyAwaitingInput(sessionID: id, sessionName: displayName, kind: kind)
            }
            if allowsRemoteNotification {
                // B5: 質問は承認と分けて送る。
                let remote: RemoteSessionNotification = if case .awaitingQuestion = kind { .question } else { .approval }
                remoteSessionNotifier?.notify(remote, sessionId: id.description, sessionName: displayName)
            }
        case .stalled(let lastAction):
            if allowsLocalNotification {
                SessionCompletionNotifier.notifyAwaitingInput(sessionID: id, sessionName: displayName, kind: .stalled(lastAction: lastAction))
            }
            if allowsRemoteNotification {
                remoteSessionNotifier?.notify(.stalled, sessionId: id.description, sessionName: displayName)
            }
        case .exited(let code):
            if allowsLocalNotification {
                SessionCompletionNotifier.notifyExited(sessionID: id, sessionName: displayName, code: code)
            }
            if allowsRemoteNotification {
                remoteSessionNotifier?.notify(.exited(code: code), sessionId: id.description, sessionName: displayName)
            }
        }
    }

    private func appendPendingTurnCostIfNeeded(timestamp: Date) {
        guard let pendingTurnCostUSD else {
            // 金額を持たない使用量（Codex）は、そのターン最後の応答の下に内訳だけ出す。
            if let pendingTurnUsage,
               TurnCostCell.tokenText(pendingTurnUsage) != nil || TurnCostCell.contextPercent(pendingTurnUsage) != nil,
               let id = lastAgentMessageIDInCurrentTurn() {
                turnUsageByItemID[id] = pendingTurnUsage
            }
            return
        }
        let id = "turn-cost-\(completedTurnSeq + 1)-\(UUID().uuidString)"
        if let pendingTurnUsage {
            turnUsageByItemID[id] = pendingTurnUsage
        }
        appendOrReplace(.turnCost(
            id: id,
            costUSD: pendingTurnCostUSD,
            timestamp: timestamp
        ))
    }

    private func lastAgentMessageIDInCurrentTurn() -> String? {
        for item in transcript.reversed() {
            switch item {
            case .agentMessage(let id, _, _): return id
            case .userMessage: return nil
            default: continue
            }
        }
        return nil
    }

    private static func warningItemID(for message: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in message.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return "warning-\(String(hash, radix: 16))"
    }

    private static let rawEventLogCap = 500

    private func appendRawEventLog(_ eventDescription: String) {
        rawEventLog.append(eventDescription)
        let overflow = rawEventLog.count - Self.rawEventLogCap
        if overflow > 0 {
            rawEventLog.removeFirst(overflow)
        }
    }

    private func appendRawEventLogs(_ eventDescriptions: [String]) {
        guard !eventDescriptions.isEmpty else { return }
        rawEventLog.append(contentsOf: eventDescriptions)
        let overflow = rawEventLog.count - Self.rawEventLogCap
        if overflow > 0 {
            rawEventLog.removeFirst(overflow)
        }
    }

    /// Codex の normalized event は本文型だけでは thread/turn を表せないため、ordered stream
    /// の identity をここで検証する。thread 切替失敗で current id が nil の場合も受け付けない。
    private func acceptsCodexNormalizedEvent(
        threadId eventThreadId: String?,
        turnId eventTurnId: String?
    ) -> Bool {
        guard codexClient != nil else { return true }
        guard let expectedThreadId = threadId,
              !expectedThreadId.isEmpty,
              let eventThreadId,
              !eventThreadId.isEmpty,
              eventThreadId == expectedThreadId else {
            return false
        }
        guard let eventTurnId, !eventTurnId.isEmpty else { return true }
        if let codexEventTurnId {
            return codexEventTurnId == eventTurnId
        }
        codexEventTurnId = eventTurnId
        return true
    }

    private func handle(_ event: NormalizedChatEvent) async {
        let rawEvent = String(describing: event)
        if enqueueStreamDeltaIfNeeded(event, rawEvent: rawEvent) {
            return
        }

        // 全ての非 delta イベントは順序バリア。switch に case が増えてもこの位置を通る。
        flushPendingStreamDeltasBarrier()
        let eventDate = Date()
        appendRawEventLog(rawEvent)
        switch event {
        case .agentMessageDelta, .reasoningDelta:
            break
        case .taskListUpdated(let tasks):
            appendOrReplace(.taskList(id: "task-list", tasks: tasks, timestamp: eventDate))
            touchOutput()
        case .commandExecution(let itemId, let command, let delta):
            markRunningEventReceived(at: eventDate)
            if let command, !command.isEmpty {
                appendCommandExecution(itemId: itemId, command: command, outputDelta: delta)
            }
        case .fileChange(let itemId, let changes):
            markRunningEventReceived(at: eventDate)
            appendOrReplace(.fileChange(id: itemId, changes: changes, timestamp: eventDate))
            touchOutput()
        case .turnStarted:
            beginRunningTurn(at: eventDate)
            if shouldClearBackgroundTasksOnNextTurnStart {
                clearRunningBackgroundTasks()
                shouldClearBackgroundTasksOnNextTurnStart = false
            }
            status = .running
        case .turnUsage(let usage):
            markRunningEventReceived(at: eventDate)
            lastTurnUsage = usage
            let cost = turnCost(from: usage.costUSD)
            lastTurnCostUSD = cost.turn
            pendingTurnCostUSD = cost.turn
            pendingTurnUsage = usage
            sessionTotalCostUSD += cost.addedToTotal
            persistTurnUsageSnapshot(usage)
            if usage.costUSD != nil { persistSessionTotalCost() }
        case .availableCommandsUpdated(let commands):
            availableSlashCommands = commands
            // 次回セッションの init 到着前に補完へ渡す種として永続化する。
            availableCommandsStore.record(
                agentRef: agentRef,
                workingDirectory: workingDirectory,
                commands: commands
            )
        case .turnCompleted(let nativeSessionId):
            if let nativeSessionId, shouldAdoptNativeSessionId(nativeSessionId) {
                updateNativeSessionId(nativeSessionId)
            }
            if codexClient != nil {
                codexEventTurnId = nil
            }
            await expireAllPendingUserQuestions()
            appendPendingTurnCostIfNeeded(timestamp: eventDate)
            let previousStatus = status
            let hadActiveTurn = turnStartedAt != nil
            isCompacting = false
            clearRunningTurn()
            status = .idle
            completedTurnSeq += 1
            lastTurnCompletedAt = eventDate
            notifyCompletionIfNeeded(from: previousStatus, hadActiveTurn: hadActiveTurn)
            touchOutput()
            flushTranscriptAtTurnBoundary()
            midTurnPersistenceGate.noteExternalFlush()
        case .turnInterrupted(let nativeSessionId):
            if let nativeSessionId, shouldAdoptNativeSessionId(nativeSessionId) {
                updateNativeSessionId(nativeSessionId)
            }
            if codexClient != nil {
                codexEventTurnId = nil
            }
            await expireAllPendingUserQuestions()
            isCompacting = false
            clearRunningTurn()
            clearRunningBackgroundTasks()
            subAgentModel.failRunningSubAgents()
            status = .idle
            flushTranscriptAtTurnBoundary()
            midTurnPersistenceGate.noteExternalFlush()
        case .error(let message):
            if codexClient != nil {
                codexEventTurnId = nil
            }
            await expireAllPendingUserQuestions()
            isCompacting = false
            let previousStatus = status
            let hadActiveTurn = turnStartedAt != nil
            clearRunningTurn()
            appendOrReplace(.error(id: "error-\(UUID().uuidString)", message: message, timestamp: eventDate))
            clearRunningBackgroundTasks()
            subAgentModel.failRunningSubAgents()
            status = .error(message: message)
            lastErrorWasNotified = notifyCompletionIfNeeded(from: previousStatus, hadActiveTurn: hadActiveTurn)
            touchOutput()
            flushTranscriptAtTurnBoundary()
            midTurnPersistenceGate.noteExternalFlush()
        case .processExited(let exitCode):
            guard processExit == nil else { break }
            // 先に立てる（下の await の間に届いた承認・質問を積まないように）。
            processExit = ChatProcessExit(exitCode: exitCode)
            // 承認を待っていたプロセスはもう無いので、答えられないカードを残さない（下の await の間も出さない）。
            pendingApprovals.removeAll()
            await expireAllPendingUserQuestions()
            await approvalBroker.cancelAll()
            isCompacting = false
            let previousStatus = status
            let hadActiveTurn = turnStartedAt != nil
            clearRunningTurn()
            clearRunningBackgroundTasks()
            subAgentModel.failRunningSubAgents()
            let isAfterError: Bool = if case .error = previousStatus { true } else { false }
            if let exitCode, exitCode != 0 {
                // PTY と同じく 0 以外はエラー。実行中でなくても終了コードを添えて知らせる。
                // 死因のエラー（Claude の途中終了など）が先に届いていれば、その表示を残し、
                // エラーとして通知済みなら同じ出来事で 2 回鳴らさない。
                if !isAfterError {
                    status = .error(message: "exit code \(exitCode)")
                }
                if !(isAfterError && lastErrorWasNotified) {
                    notifyUser(.exited(code: exitCode))
                }
            } else if exitCode == nil {
                // 終了コードが取れないときは成功とは言えないので、完了にはしない。
                if !isAfterError {
                    status = .error(message: "process exited")
                    notifyCompletionIfNeeded(from: previousStatus, hadActiveTurn: hadActiveTurn)
                }
            } else if !isAfterError {
                status = .completed(exitCode: 0)
                notifyCompletionIfNeeded(from: previousStatus, hadActiveTurn: hadActiveTurn)
            }
            touchOutput()
            flushTranscriptAtTurnBoundary()
            midTurnPersistenceGate.noteExternalFlush()
        case .warning(let message):
            markRunningEventReceived(at: eventDate)
            appendOrReplace(.error(id: Self.warningItemID(for: message), message: message, timestamp: eventDate))
            touchOutput()
        case .backgroundTaskStarted(let taskId, let taskType, let description, let toolUseId):
            markRunningEventReceived(at: eventDate)
            upsertRunningBackgroundTask(
                taskId: taskId,
                taskType: taskType,
                description: description,
                toolUseId: toolUseId
            )
        case .backgroundTaskCompleted(let taskId, _, _):
            markRunningEventReceived(at: eventDate)
            removeRunningBackgroundTask(taskId: taskId)
        case .subAgentStarted(let toolUseId, let subagentType, let description):
            markRunningEventReceived(at: eventDate)
            subAgentModel.upsertSubAgent(
                toolUseId: toolUseId,
                subagentType: subagentType,
                description: description,
                status: .running,
                summary: nil,
                outputFile: nil
            )
        case .subAgentActivity(let toolUseId, let kind, let itemId, let text):
            markRunningEventReceived(at: eventDate)
            subAgentModel.appendSubAgentActivity(toolUseId: toolUseId, kind: kind, itemId: itemId, text: text)
        case .subAgentOutput(let toolUseId, let text):
            markRunningEventReceived(at: eventDate)
            subAgentModel.appendSubAgentOutput(toolUseId: toolUseId, text: text)
        case .subAgentCompleted(let toolUseId, let status, let summary, let outputFile):
            markRunningEventReceived(at: eventDate)
            subAgentModel.completeSubAgent(
                toolUseId: toolUseId,
                status: status,
                summary: summary,
                outputFile: outputFile
            )
        case .compactionBoundary:
            markRunningEventReceived(at: eventDate)
            isCompacting = false
        case .userQuestionRequested(let requestId, let questions):
            markRunningEventReceived(at: eventDate)
            receiveUserQuestion(requestId: requestId, questions: questions, timestamp: eventDate)
        case .userQuestionResolved(let requestId, let outcome):
            markRunningEventReceived(at: eventDate)
            codexUserInputRequestIDs.removeValue(forKey: requestId)
            applyUserQuestionResolution(requestId: requestId, outcome: outcome)
            touchOutput()
        }

        switch event {
        case .agentMessageDelta, .reasoningDelta, .turnCompleted, .turnInterrupted, .error:
            break
        case .turnStarted, .turnUsage:
            break
        default:
            requestMidTurnTranscriptFlush()
        }
    }

    private func userQuestionCardIndex(requestId: String) -> Int? {
        transcript.firstIndex { item in
            guard case .userQuestion(_, let rid, _, _, _, _) = item else { return false }
            return rid == requestId
        }
    }

    /// Claude と Codex の質問を同じ質問カード経路へ載せる。
    private func receiveUserQuestion(
        requestId: String,
        questions: [ChatUserQuestion],
        timestamp: Date
    ) {
        appendOrReplace(.userQuestion(
            id: "question-\(requestId)",
            requestId: requestId,
            questions: questions,
            answers: nil,
            state: .pending,
            timestamp: timestamp
        ))
        // ツールの使用許可は画面では承認カードなので、通知も承認待ちにする（11）。
        let first = questions.first
        if let permission = first?.permission {
            enterAwaitingUserQuestion(notifying: .awaitingApproval(prompt: permission.detail.isEmpty ? first?.question : permission.detail))
        } else {
            enterAwaitingUserQuestion(notifying: .awaitingQuestion(question: first?.question, isSecret: first?.isSecret ?? false))
        }
        touchOutput()
    }

    private func applyUserQuestionResolution(requestId: String, outcome: ChatUserQuestionOutcome) {
        guard let index = userQuestionCardIndex(requestId: requestId),
              case .userQuestion(let id, let rid, let questions, let answers, let state, let timestamp) = transcript[index]
        else {
            return
        }

        switch outcome {
        case .answered(let resolvedAnswers):
            // カードは respondToUserQuestion がローカルで先に answered 化していることがある。
            // status の復帰はカードの重複ガードに巻き込まれると飛ばされるため、先に行う。
            if status == .awaitingUserQuestion {
                status = .running
            }
            guard state != .answered else { return }
            let persistedAnswers = ChatUserQuestion.persistedAnswers(
                from: resolvedAnswers,
                for: questions
            )
            appendOrReplace(.userQuestion(
                id: id,
                requestId: rid,
                questions: questions,
                answers: persistedAnswers,
                state: .answered,
                timestamp: timestamp
            ))
        case .expired:
            guard state == .pending else { return }
            appendOrReplace(.userQuestion(
                id: id,
                requestId: rid,
                questions: questions,
                answers: answers,
                state: .expired,
                timestamp: timestamp
            ))
        }
    }

    private func expireAllPendingUserQuestions() async {
        let pendingCodexUserInputIDs = Set(codexUserInputRequestIDs.values)
        codexUserInputRequestIDs.removeAll()

        var didChange = false
        for index in transcript.indices {
            guard case .userQuestion(let id, let requestId, let questions, let answers, .pending, let timestamp) = transcript[index]
            else {
                continue
            }
            transcript[index] = .userQuestion(
                id: id,
                requestId: requestId,
                questions: questions,
                answers: answers,
                state: .expired,
                timestamp: timestamp
            )
            didChange = true
        }
        if didChange {
            markTranscriptChanged()
        }

        for userInputID in pendingCodexUserInputIDs {
            await approvalBroker.declineUserInput(id: userInputID)
        }
    }

    private func enqueueStreamDeltaIfNeeded(_ event: NormalizedChatEvent, rawEvent: String) -> Bool {
        switch event {
        case .agentMessageDelta(let itemId, let delta):
            transcriptStreamCoalescer.enqueue(itemId: itemId, kind: .agent, delta: delta, rawEvent: rawEvent)
            return true
        case .reasoningDelta(let itemId, let delta):
            transcriptStreamCoalescer.enqueue(itemId: itemId, kind: .reasoning, delta: delta, rawEvent: rawEvent)
            return true
        case .commandExecution(let itemId, let command, let delta) where command?.isEmpty != false:
            transcriptStreamCoalescer.enqueue(itemId: itemId, kind: .command, delta: delta, rawEvent: rawEvent)
            return true
        case .subAgentActivity(let toolUseId, let kind, let itemId, let text)
            where kind == .message || kind == .reasoning:
            guard let itemId else { return false }
            transcriptStreamCoalescer.enqueue(
                itemId: itemId,
                kind: kind == .message ? .agent : .reasoning,
                delta: text,
                rawEvent: rawEvent,
                subAgentToolUseId: toolUseId
            )
            return true
        default:
            return false
        }
    }

    private func handleCodexSettingsEvent(_ event: ThreadEvent) {
        appendRawEventLog(String(describing: event))
        switch event {
        case .turnStarted(let updatedThreadId, let turn):
            guard updatedThreadId == threadId else { return }
            codexEventTurnId = turn.id
            codexPlanTaskState?.reset(
                threadId: updatedThreadId,
                turnId: turn.id ?? ""
            )
        case .turnCompleted(let updatedThreadId, let turn):
            codexSubAgentState?.apply(.turnCompleted(
                threadId: updatedThreadId,
                turnId: turn.id ?? "",
                status: turn.status ?? ""
            ))
            guard updatedThreadId == threadId else { return }
            scheduleCodexSurfaceRefresh()
        case .turnInterrupted(let updatedThreadId, let turnId):
            codexSubAgentState?.apply(.turnCompleted(
                threadId: updatedThreadId,
                turnId: turnId ?? "",
                status: "interrupted"
            ))
            guard updatedThreadId == threadId else { return }
            scheduleCodexSurfaceRefresh()
        case .threadSettingsUpdated(let updatedThreadId, let settings):
            guard updatedThreadId == threadId else { return }
            let pending = codexSettingsRequestsInFlight > 0 ? (selectedModel, selectedEffort, isPlanMode) : nil
            syncSettings(from: settings)
            if let pending {
                (selectedModel, selectedEffort, isPlanMode) = pending
                refreshPlanModeAvailability()
            }
            notifyCodexSettingsChanged()
        case .threadStatusChanged(let updatedThreadId, let threadStatus):
            // reset 後に生き残る旧 thread の遅延イベントで status を汚染しない
            // （threadSettingsUpdated と同じ threadId 一致 guard）。
            guard updatedThreadId == threadId else { return }
            if threadStatus.isWaitingOnApproval, pendingApprovals.isEmpty {
                enterAwaitingApproval(prompt: "Approval requested", notifying: .awaitingApproval(prompt: nil))
            } else if turnStartedAt != nil, !turnIsRestoredInference, threadStatus == .idle {
                // ADR 0064: ライブターン進行中の非同期 idle 報告は無視する（完了は
                // turnCompleted が正）。復元推定ターンだけは idle での終端＋通知を許す。
                return
            } else {
                let previousStatus = status
                let hadActiveTurn = turnStartedAt != nil
                status = threadStatus.sessionStatus
                if threadStatus == .idle || threadStatus == .systemError {
                    clearRunningTurn()
                    notifyCompletionIfNeeded(from: previousStatus, hadActiveTurn: hadActiveTurn)
                }
            }
        case .itemStarted(let updatedThreadId, _, let item), .itemCompleted(let updatedThreadId, _, let item):
            // 旧 thread の遅延 item で transcript / store を汚染しない。
            guard updatedThreadId == threadId else { return }
            flushPendingStreamDeltasBarrier()
            if let chatItem = chatItem(from: item) {
                appendOrReplace(chatItem)
                adoptTitleFromThreadItem(item, chatItem: chatItem)
                if case .itemCompleted = event {
                    enqueueTranscriptUpsert([chatItem])
                }
                touchOutput()
            }
            if case .itemStarted = event {
                let type = item.type?.lowercased() ?? ""
                if type.contains("collabagent") || type.contains("subagent") {
                    scheduleCodexSurfaceRefresh()
                }
            }
        case .planUpdated(let updatedThreadId, let turnId, _, _):
            if codexPlanTaskState?.apply(event: event) == true,
               updatedThreadId == threadId {
                codexEventTurnId = turnId
            }
        default:
            break
        }
    }

    /// turnCompleted / turnInterrupted の nativeSessionId を採用してよいか。
    /// Codex は app-server の thread が reset 後も生き残るため、現在の threadId と一致する
    /// （＝現行 thread の）イベントのみ採用し、旧 thread 由来の native id 逆行を防ぐ。
    /// spawn 型（Claude/Cursor）は旧プロセスを close 済みで、self-heal 等で native id が正当に
    /// 変わるため従来どおり無条件採用する。
    private func shouldAdoptNativeSessionId(_ nativeSessionId: String) -> Bool {
        guard codexClient != nil else { return true }
        return nativeSessionId == threadId
    }

    private func loadAvailableSettings(persistedSettings: CodexAppServerSessionSettings?) async {
        guard let codexClient else { return }
        persistedSettingsForFallback = persistedSettings
        let defaultPermissionProfileID = ":danger-full-access"
        do {
            let response = try await codexClient.listModels(ModelListParams())
            availableModels = response.data
            if selectedModel == nil {
                selectedModel = response.data.first(where: \.isDefault)?.id ?? persistedSettings?.selectedModel
            }
            if selectedEffort == nil, let selectedModel {
                selectedEffort = defaultEffort(for: selectedModel) ?? persistedSettings?.selectedEffort
            }
        } catch {
            availableModels = []
            if selectedModel == nil {
                selectedModel = persistedSettings?.selectedModel
            }
            if selectedEffort == nil {
                selectedEffort = persistedSettings?.selectedEffort
            }
        }

        do {
            let response = try await codexClient.listPermissionProfiles(
                PermissionProfileListParams(cwd: workingDirectory)
            )
            permissionProfiles = response.data
            if selectedPermissionProfile == nil {
                selectedPermissionProfile = persistedSettings?.selectedPermissionProfile
                    ?? response.data.first { $0.id == defaultPermissionProfileID }?.id
            }
        } catch {
            permissionProfiles = []
            if selectedPermissionProfile == nil {
                selectedPermissionProfile = persistedSettings?.selectedPermissionProfile
            }
        }

        do {
            let response = try await codexClient.listCollaborationModes(CollaborationModeListParams())
            collaborationModeListAvailable = response.data.contains { $0.mode == .plan }
        } catch {
            collaborationModeListAvailable = false
        }
        refreshPlanModeAvailability()
    }

    private func syncSettings(from response: ThreadResponse) {
        threadResponseModel = response.model
        if let model = response.model {
            selectedModel = model
        }
        if let effort = response.reasoningEffort {
            selectedEffort = effort
        }
        if let profile = response.activePermissionProfile?.id {
            selectedPermissionProfile = profile
        }
        refreshPlanModeAvailability()
    }

    private func syncSettings(from settings: ThreadSettings) {
        threadResponseModel = settings.model
        isPlanMode = settings.collaborationMode.mode == .plan
        if isPlanMode {
            selectedModel = settings.collaborationMode.settings.model
            selectedEffort = settings.collaborationMode.settings.reasoningEffort ?? settings.effort
        } else {
            selectedModel = settings.model
            selectedEffort = settings.effort
        }
        selectedPermissionProfile = settings.activePermissionProfile?.id
        refreshPlanModeAvailability()
    }

    private func reapplyPersistedSettings(
        _ settings: CodexAppServerSessionSettings,
        threadID: String? = nil
    ) async {
        guard let threadId = threadID ?? self.threadId else { return }
        guard let codexClient else { return }
        let model = settings.selectedModel ?? selectedModel
        let effort = settings.selectedEffort ?? selectedEffort
        let planEnabled = settings.isPlanMode ?? false
        let collaborationMode = planEnabled && collaborationModeListAvailable
            ? try? makeCollaborationMode(
                on: true,
                model: model ?? fallbackModelForPlan(),
                effort: effort
            )
            : nil

        let params = ThreadSettingsUpdateParams(
            threadId: threadId,
            model: model,
            effort: effort,
            permissions: settings.selectedPermissionProfile,
            collaborationMode: collaborationMode
        )
        codexSettingsRequestCount += 1
        let request = codexSettingsRequestCount
        codexSettingsRequestsInFlight += 1
        defer { codexSettingsRequestsInFlight -= 1 }
        var sent = true
        do {
            _ = try await codexClient.updateThreadSettings(params)
        } catch {
            sent = false
            if collaborationMode != nil {
                isPlanMode = false
                isPlanModeAvailable = false
            }
            if collaborationMode != nil, !isTerminating, request == codexSettingsRequestCount {
                sent = (try? await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                    threadId: threadId,
                    model: model,
                    effort: effort,
                    permissions: settings.selectedPermissionProfile
                ))) != nil
            }
        }

        // 再適用の間に ⇧Tab やメニューで変えたモデル・深さ・プラン モードは、その結果を残す。
        // 再適用が通らなかったときは、画面をいまのまま（先に通った変更の結果）にする。
        if sent, request > codexSettingsAppliedRequest {
            codexSettingsAppliedRequest = request
            selectedModel = model ?? selectedModel
            selectedEffort = effort ?? selectedEffort
            isPlanMode = collaborationMode?.mode == .plan
        }
        selectedPermissionProfile = settings.selectedPermissionProfile ?? selectedPermissionProfile
        refreshPlanModeAvailability()
        notifyCodexSettingsChanged()
    }

    private func makeCollaborationMode(
        on: Bool,
        model: String? = nil,
        effort: String? = nil
    ) throws -> CollaborationMode {
        guard let resolvedModel = model ?? fallbackModelForPlan() else {
            isPlanModeAvailable = false
            throw ChatSettingsUpdateError.planModeUnavailable
        }
        guard on ? isPlanModeAvailable : true else {
            throw ChatSettingsUpdateError.planModeUnavailable
        }
        return CollaborationMode(
            mode: on ? .plan : .default,
            settings: CollaborationModeSettings(
                model: resolvedModel,
                reasoningEffort: effort ?? selectedEffort ?? defaultEffort(for: resolvedModel),
                developerInstructions: nil
            )
        )
    }

    private func fallbackModelForPlan() -> String? {
        selectedModel
            ?? threadResponseModel
            ?? availableModels.first(where: \.isDefault)?.id
            ?? persistedSettingsForFallback?.selectedModel
    }

    private func defaultEffort(for model: String) -> String? {
        availableModels.first { $0.id == model || $0.model == model }?.defaultReasoningEffort
    }

    private func refreshPlanModeAvailability() {
        isPlanModeAvailable = collaborationModeListAvailable && fallbackModelForPlan() != nil
        if !isPlanModeAvailable {
            isPlanMode = false
        }
    }

    private func notifyCodexSettingsChanged() {
        codexSettingsDidChange?(codexSettingsSnapshot)
    }

    private func markTranscriptChanged() {
        transcriptRevision += 1
    }

    /// transcript 全体を置換し、ID 索引を同一ターンで再構築する（task-5 契約: 常に
    /// `transcriptItemIDs == Set(transcript.map(\.id))`）。transcript を丸ごと差し替える
    /// 全経路（history 反映・revert 切詰め・restore/rebuild のクリア）はこれを通す。
    private func setTranscript(_ items: [ChatItem]) {
        if let discardedBatch = transcriptStreamCoalescer.invalidate() {
            appendRawEventLogs(discardedBatch.rawEvents)
            subAgentModel.appendSubAgentActivities(subAgentActivities(from: discardedBatch))
        }
        transcript = items
        transcriptItemIDs = Set(items.map(\.id))
        transcriptIndexByID = Dictionary(
            items.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
        markTranscriptChanged()
    }

    /// transcript へ1件追加し、ID 索引へも同期して追加する。
    private func appendToTranscript(_ item: ChatItem) {
        transcript.append(item)
        transcriptItemIDs.insert(item.id)
        transcriptIndexByID[item.id] = transcript.endIndex - 1
    }

    /// 指定 id の項目を transcript から除去し、ID 索引からも同期して除去する。
    private func removeFromTranscript(id: String) {
        transcript.removeAll { $0.id == id }
        transcriptItemIDs.remove(id)
        transcriptIndexByID = Dictionary(
            transcript.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func flushScheduledStreamDeltas(token: UInt64) {
        guard let batch = transcriptStreamCoalescer.flushScheduled(token: token) else { return }
        applyStreamBatch(batch)
    }

    private func flushPendingStreamDeltasBarrier() {
        guard let batch = transcriptStreamCoalescer.flushBarrier() else { return }
        applyStreamBatch(batch)
    }

    private func subAgentActivities(
        from batch: TranscriptStreamCoalescer.Batch
    ) -> [ChatSubAgentModel.StreamActivity] {
        batch.deltas.compactMap { pending in
            guard let toolUseId = pending.subAgentToolUseId else { return nil }
            return ChatSubAgentModel.StreamActivity(
                toolUseId: toolUseId,
                kind: pending.kind == .agent ? .message : .reasoning,
                itemId: pending.itemId,
                text: pending.delta
            )
        }
    }

    private func applyStreamBatch(_ batch: TranscriptStreamCoalescer.Batch) {
        markRunningEventReceived(at: batch.latestEventAt)
        appendRawEventLogs(batch.rawEvents)
        var didChange = false
        let subAgentActivities = subAgentActivities(from: batch)
        for pending in batch.deltas {
            guard pending.subAgentToolUseId == nil else { continue }
            if let index = transcriptIndexByID[pending.itemId] {
                switch (pending.kind, transcript[index]) {
                case (.agent, .agentMessage(let id, let text, let timestamp)):
                    transcript[index] = .agentMessage(id: id, text: text + pending.delta, timestamp: timestamp)
                    didChange = true
                case (.reasoning, .reasoning(let id, let text, let timestamp)):
                    transcript[index] = .reasoning(id: id, text: text + pending.delta, timestamp: timestamp)
                    didChange = true
                case (.command, .commandExecution(let id, let command, let output, let timestamp)):
                    transcript[index] = .commandExecution(
                        id: id,
                        command: command,
                        output: output + pending.delta,
                        timestamp: timestamp
                    )
                    didChange = true
                default:
                    break
                }
                continue
            }

            let newItem: ChatItem?
            switch pending.kind {
            case .agent:
                newItem = pending.delta.isEmpty ? nil : .agentMessage(
                    id: pending.itemId,
                    text: pending.delta,
                    timestamp: pending.receivedAt
                )
            case .reasoning:
                newItem = pending.delta.isEmpty ? nil : .reasoning(
                    id: pending.itemId,
                    text: pending.delta,
                    timestamp: pending.receivedAt
                )
            case .command:
                newItem = .commandExecution(
                    id: pending.itemId,
                    command: nil,
                    output: pending.delta,
                    timestamp: pending.receivedAt
                )
            }
            if let newItem {
                appendToTranscript(newItem)
                didChange = true
            }
        }

        subAgentModel.appendSubAgentActivities(subAgentActivities)

        if didChange {
            markTranscriptChanged()
        }
        lastOutputAt = batch.latestEventAt
    }

    private func appendCommandExecution(itemId: String, command: String, outputDelta: String) {
        if let index = transcriptIndexByID[itemId],
           case .commandExecution(let id, let existingCommand, let output, let timestamp) = transcript[index] {
            transcript[index] = .commandExecution(
                id: id,
                command: command.isEmpty ? existingCommand : command,
                output: output + outputDelta,
                timestamp: timestamp
            )
        } else {
            appendToTranscript(.commandExecution(
                id: itemId,
                command: command,
                output: outputDelta,
                timestamp: Date()
            ))
        }
        markTranscriptChanged()
        touchOutput()
    }

    private func appendOrReplace(_ item: ChatItem) {
        guard shouldStoreInTranscript(item) else {
            if let index = transcriptIndexByID[item.id],
               shouldStoreInTranscript(transcript[index]) {
                return
            }
            let previousCount = transcript.count
            removeFromTranscript(id: item.id)
            if transcript.count != previousCount {
                markTranscriptChanged()
            }
            return
        }
        if let index = transcriptIndexByID[item.id] {
            let replacement = item.withTimestamp(transcript[index].timestamp)
            if replacement != transcript[index] {
                transcript[index] = replacement
                markTranscriptChanged()
            }
        } else {
            appendToTranscript(item)
            markTranscriptChanged()
        }
    }

    private func loadTranscriptFromStore() async -> [ChatItem]? {
        guard let transcriptStore else { return nil }
        do {
            let persisted = try await transcriptStore.loadTranscript(for: id)
            return persisted.isEmpty ? nil : persisted
        } catch {
            logRestoreFailure(error)
            return nil
        }
    }

    private func applyRestoredTranscript(_ persisted: [ChatItem]) {
        setTranscript([])
        for item in persisted {
            appendOrReplace(item)
        }
        if !restoredSavedTotalCost {
            sessionTotalCostUSD = Self.legacyTotalCostUSD(of: persisted)
            claudeReportedTotalCostUSD = sessionTotalCostUSD
        }
        touchOutput()
        adoptTitleFromLocalTranscript(persisted)
    }

    /// 1 ターンのコストと総コストに足す額。Claude の `total_cost_usd` はセッションの累計（再開前の分も含む）なので
    /// 直前の累計との差にする。累計が減ったとき（別の会話として始まった）は届いた値をそのまま 1 ターン分とみなす。
    /// 直前の累計がわからないとき（履歴から再開した直後）は、ターンのコストを出さず累計をそのまま総コストに足す。
    /// ほかのエージェントは届いた値のまま。
    private func turnCost(from reported: Double?) -> (turn: Double?, addedToTotal: Double) {
        guard let reported else { return (nil, 0) }
        guard case .builtin(.claudeCode) = agentRef else { return (reported, reported) }
        defer { claudeReportedTotalCostUSD = reported }
        guard let previous = claudeReportedTotalCostUSD else { return (nil, reported) }
        let turn = reported >= previous ? reported - previous : reported
        return (turn, turn)
    }

    /// 総コストを保存する前の会話の総コスト。以前は Claude の累計（`total_cost_usd`）をそのままターンのコストに
    /// 入れていたので、最後の項目が総額になる（コストを送るのは Claude だけ）。保存した総コストがあればそちらを使う。
    static func legacyTotalCostUSD(of items: [ChatItem]) -> Double {
        for item in items.reversed() {
            if case .turnCost(_, let costUSD, _) = item { return costUSD }
        }
        return 0
    }

    private func restoreTranscriptFromStore() async -> Bool {
        guard let persisted = await loadTranscriptFromStore() else { return false }
        applyRestoredTranscript(persisted)
        return true
    }

    private func restoreTurnUsageFromStore() async {
        guard let transcriptStore else { return }
        do {
            if let snapshot = try await transcriptStore.loadTurnUsageSnapshot(for: id) {
                lastTurnUsage = snapshot
            }
        } catch {
            logRestoreFailure(error)
        }
        do {
            if let saved = try await transcriptStore.loadSessionTotalCost(for: id) {
                sessionTotalCostUSD = saved.totalUSD
                claudeReportedTotalCostUSD = saved.lastReportedUSD
                restoredSavedTotalCost = true
            }
        } catch {
            logRestoreFailure(error)
        }
        do {
            if let saved = try await transcriptStore.loadDisplayState(for: id) {
                turnUsageByItemID.merge(saved.turnUsageByItemID) { current, _ in current }
                lastTurnCompletedAt = lastTurnCompletedAt ?? saved.lastTurnCompletedAt
                subAgentModel.restore(saved.subAgents)
            }
        } catch {
            logRestoreFailure(error)
        }
    }

    /// 表示の状態をターンの境目で、本文の保存と同じ列に続けて保存する。
    private func persistDisplayState() {
        transcriptPersistenceQueue?.enqueueDisplayState(ChatDisplayState(
            turnUsageByItemID: turnUsageByItemID,
            lastTurnCompletedAt: lastTurnCompletedAt,
            subAgents: subAgentModel.subAgents
        ))
    }

    /// 総コストの保存は直列にする（連続したターンの保存が逆順に終わって古い額が残らないように）。
    private func persistSessionTotalCost() {
        guard let transcriptStore else { return }
        let cost = SessionTotalCost(totalUSD: sessionTotalCostUSD, lastReportedUSD: claudeReportedTotalCostUSD ?? 0)
        let sessionID = id
        let previous = totalCostSave
        totalCostSave = Task {
            await previous?.value
            do {
                try await transcriptStore.saveSessionTotalCost(cost, for: sessionID)
            } catch {
                await MainActor.run {
                    logRestoreFailure(error)
                }
            }
        }
    }

    private func persistTurnUsageSnapshot(_ usage: TurnUsage) {
        guard let transcriptStore else { return }
        let sessionID = id
        Task {
            do {
                try await transcriptStore.saveTurnUsageSnapshot(usage, for: sessionID)
            } catch {
                await MainActor.run {
                    logRestoreFailure(error)
                }
            }
        }
    }

    private func enqueueTranscriptUpsert(_ items: [ChatItem]) {
        transcriptPersistenceQueue?.enqueueUpsert(items)
    }

    private func flushTranscriptAtTurnBoundary() {
        enqueueTranscriptUpsert(transcript.filter(shouldStoreInTranscript))
        persistDisplayState()
    }

    private func shouldStoreInTranscript(_ item: ChatItem) -> Bool {
        switch item {
        case .userMessage(_, let text, _, let attachments):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        case .agentMessage(_, let text, _), .reasoning(_, let text, _):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .subAgentMarker:
            true
        default:
            true
        }
    }

    private func rebuildTranscript(from thread: ThreadSummary) {
        let items = thread.turns?
            .flatMap { $0.items ?? [] }
            .compactMap { chatItem(from: $0) } ?? []
        setTranscript(items)
        completedTurnSeq = 0
        for turn in thread.turns ?? [] {
            if turn.status == "completed" || turn.status == "idle" || turn.status == nil {
                completedTurnSeq += 1
            }
        }
        if !transcript.isEmpty {
            touchOutput()
        }
        adoptTitleFromServerThread(thread)
    }

    private func chatItem(from item: ThreadItem) -> ChatItem? {
        let id = item.itemId ?? item.id ?? UUID().uuidString
        let type = item.type ?? ""
        let textKeys = ["text", "message", "summary", "content", "reasoning", "thinking"]
        let text = item.text?.isEmpty == false ? item.text! : item.raw?.firstString(for: textKeys) ?? item.text ?? ""

        if type.contains("user") {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .userMessage(id: id, text: text, timestamp: Date())
        }
        if type.contains("reasoning") {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .reasoning(id: id, text: text, timestamp: Date())
        }
        if type.contains("command") {
            let command = item.raw?.firstString(for: ["command", "cmd"])
            // Codex の commandExecution は出力を aggregatedOutput、終了コードを exitCode に持つ（app-server v2 のスキーマ）。
            var output = item.raw?["aggregatedOutput"]?.stringValue ?? text
            // C-22: 失敗したコマンドを開いておけるよう、Claude と同じ「Exit code N」行を先頭に置く。
            // 出力に別の値の「Exit code」行があれば、構造化された値の行を先に置いて食い違いを消す（成功も含む）。
            if case .number(let value)? = item.raw?["exitCode"] {
                let code = Int(value)
                let written = CommandExitCode.parse(output)
                if written != code, code != 0 || written != nil {
                    output = "Exit code \(code)\n" + output
                }
            }
            return .commandExecution(id: id, command: command, output: output, timestamp: Date())
        }
        if type.contains("file") || type.contains("patch") {
            let changes = item.fileChanges
            if !changes.isEmpty {
                return .fileChange(
                    id: id,
                    changes: changes.map { StructuredChatKit.FilePatchChange(path: $0.path, diff: $0.unifiedDiff, kind: $0.kindName) },
                    timestamp: Date()
                )
            }
            if let diff = item.raw?.firstString(for: ["diff", "patch"]) {
                let path = item.raw?.firstString(for: ["path"]) ?? "unknown"
                return .fileChange(
                    id: id,
                    changes: [StructuredChatKit.FilePatchChange(path: path, diff: diff, kind: nil)],
                    timestamp: Date()
                )
            }
            return nil
        }
        if type.contains("error") {
            return .error(id: id, message: text, timestamp: Date())
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .agentMessage(id: id, text: text, timestamp: Date())
    }

    private func adoptTitleFromOriginalUserText(_ text: String) {
        guard titleState.source == .flower else { return }
        titleState = titleState.receivingUserMessage(text)
    }

    private func adoptTitleFromHistoryResume(
        _ entry: ClaudeSessionHistoryEntry,
        loadedItems: [ChatItem]
    ) {
        guard titleState.source == .flower else { return }
        if let messages = entry.titleUserMessages {
            for text in messages {
                guard titleState.source == .flower else { return }
                guard let candidate = unknownOriginTitleCandidate(text) else { continue }
                titleState = titleState.receivingUserMessage(candidate)
            }
            return
        }
        adoptTitleFromLocalTranscript(loadedItems)
    }

    private func adoptTitleFromLocalTranscript(_ items: [ChatItem]) {
        guard titleState.source == .flower else { return }
        let entries = InputHistoryPolicy.entries(from: items)
        for entry in entries {
            guard titleState.source == .flower else { return }
            guard let original = originalUserTextForTitle(
                entryID: entry.id,
                displayedText: entry.text
            ) else { continue }
            titleState = titleState.receivingUserMessage(original)
        }
    }

    private func adoptTitleFromServerThread(_ thread: ThreadSummary) {
        guard titleState.source == .flower else { return }
        let items = thread.turns?.flatMap { $0.items ?? [] } ?? []
        for item in items {
            let type = item.type ?? ""
            guard type.contains("user") else { continue }
            guard let original = identifiableOriginalText(from: item) else { continue }
            titleState = titleState.receivingUserMessage(original)
            if titleState.source != .flower { return }
        }
    }

    private func adoptTitleFromThreadItem(_ item: ThreadItem, chatItem: ChatItem) {
        guard titleState.source == .flower else { return }
        guard case .userMessage(let id, _, _, _) = chatItem else { return }
        let original = localOriginalUserTextByID[id] ?? identifiableOriginalText(from: item)
        guard let original else { return }
        titleState = titleState.receivingUserMessage(original)
    }

    private func identifiableOriginalText(from item: ThreadItem) -> String? {
        if case .bool(true) = item.raw?["isMeta"] {
            return nil
        }
        return item.raw?["originalText"]?.stringValue
    }

    /// ライブ確定本文があればそれを使う。それ以外の由来不明項目は先頭行だけを候補にする。
    private func originalUserTextForTitle(entryID: String, displayedText: String) -> String? {
        if let original = localOriginalUserTextByID[entryID] {
            return original
        }
        return unknownOriginTitleCandidate(displayedText)
    }

    /// 復元・履歴再開の由来不明ユーザー項目: 先頭行だけを候補。先頭行が `/` 始まりなら不採用。
    /// ChatItem は isMeta を持たないため、履歴再開では `titleUserMessages`（isMeta 除外済み）を優先する。
    private func unknownOriginTitleCandidate(_ text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let firstLine = normalized.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? normalized
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/") else { return nil }
        return firstLine
    }

    private func touchOutput() {
        lastOutputAt = Date()
    }


    private var shouldTrackBackgroundTasks: Bool {
        agentRef == .builtin(.claudeCode) || agentRef == .builtin(.codex)
    }

    private func upsertRunningBackgroundTask(
        taskId: String,
        taskType: String,
        description: String,
        toolUseId: String?
    ) {
        guard shouldTrackBackgroundTasks else {
            clearRunningBackgroundTasks()
            return
        }
        let task = RunningBackgroundTask(
            taskId: taskId,
            taskType: taskType,
            description: description,
            startedAt: Date(),
            toolUseId: toolUseId
        )
        if let index = runningBackgroundTasks.firstIndex(where: { $0.taskId == taskId }) {
            runningBackgroundTasks[index] = task
        } else {
            runningBackgroundTasks.append(task)
        }
    }

    private func removeRunningBackgroundTask(taskId: String) {
        guard shouldTrackBackgroundTasks else {
            clearRunningBackgroundTasks()
            return
        }
        runningBackgroundTasks.removeAll { $0.taskId == taskId }
    }

    private func clearRunningBackgroundTasks() {
        guard !runningBackgroundTasks.isEmpty else { return }
        runningBackgroundTasks.removeAll()
    }

    private func logRestoreFailure(_ error: Error) {
        let message = "Phlox: chat restore failed for \(id): \(error)\n"
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private var codexClient: (any CodexSettingsProviding)? {
        client as? any CodexSettingsProviding
    }

    private func updateNativeSessionId(_ id: String?) {
        let previous = chatNativeSessionId
        if id != previous {
            codexSubAgentRefreshGeneration += 1
        }
        threadId = id
        chatNativeSessionId = id
        if agentRef == .builtin(.codex), let id, id != codexSubAgentState?.parentThreadId {
            codexSubAgentState = CodexSubAgentState(parentThreadId: id)
        }
        if agentRef == .builtin(.codex), id != previous {
            codexEventTurnId = nil
            codexPlanTaskState?.reset(threadId: id ?? "")
        }
        if let id, let previous, id != previous {
            clearRunningBackgroundTasks()
        }
        if let id, id != previous {
            NotificationCenter.default.post(
                name: ChatNativeSessionIDNotification.name,
                object: nil,
                userInfo: [
                    ChatNativeSessionIDNotification.sessionIDKey: self.id.rawValue.uuidString,
                    ChatNativeSessionIDNotification.nativeSessionIDKey: id,
                ]
            )
            if agentRef == .builtin(.codex) {
                Task { @MainActor [weak self] in
                    await self?.codexSkillSelectionState?.refresh()
                }
            }
        }
    }

    private static func codexChild(_ thread: ThreadSummary) -> CodexChildThread {
        let activeTurn = thread.turns?.last { turn in
            guard let status = turn.status?.lowercased() else { return false }
            return ["inprogress", "in_progress", "running", "active"].contains(status)
        }
        let status: String
        switch thread.status {
        case .active: status = "active"
        case .idle: status = "idle"
        case .systemError: status = "error"
        case .notLoaded: status = "unknown"
        case .unknown(let value): status = value.stringValue ?? "unknown"
        case nil: status = "unknown"
        }
        return CodexChildThread(
            id: thread.id,
            parentThreadId: thread.parentThreadId ?? "",
            ancestorThreadId: codexSubAgentAncestorThreadID(thread.source),
            sourceIdentity: codexSubAgentSourceIdentity(thread.source),
            activeTurnId: activeTurn?.id,
            status: status,
            summary: thread.preview,
            canAcceptDirectInput: thread.canAcceptDirectInput
        )
    }

    private static let codexChildSourceKinds: [ThreadSourceKind] = [
        .subAgent,
        .subAgentReview,
        .subAgentCompact,
        .subAgentThreadSpawn,
        .subAgentOther,
    ]

    /// `parentThreadId` は direct-parent の正式 filter。source も sub-agent の
    /// 正式 variant に限定し、server が filter を緩く実装しても root/history を通さない。
    private static func isCodexChild(
        _ thread: ThreadSummary,
        parentThreadId: String
    ) -> Bool {
        guard thread.parentThreadId == parentThreadId else { return false }
        let source: JSONValue?
        switch thread.source {
        case .subAgent(let value):
            guard isKnownCodexSubAgentSource(value) else { return false }
            source = value
        case .unknownRaw(.null):
            // 旧 app-server の thread/list は source を省略することがある。
            source = nil
        default:
            return false
        }
        guard let source, let sourceParent = codexSubAgentParentThreadID(source) else { return true }
        guard sourceParent == parentThreadId else { return false }
        if let sourceAncestor = codexSubAgentAncestorThreadID(source) {
            return sourceAncestor == parentThreadId
        }
        return true
    }

    private static func isMatchingCodexChildRead(
        _ read: ThreadSummary,
        expected: ThreadSummary,
        parentThreadId: String
    ) -> Bool {
        guard read.id == expected.id,
              read.parentThreadId == expected.parentThreadId,
              read.parentThreadId == parentThreadId,
              codexSubAgentSourceIdentity(read.source) == codexSubAgentSourceIdentity(expected.source),
              codexSubAgentAncestorThreadID(read.source)
                == codexSubAgentAncestorThreadID(expected.source),
              isCodexChild(read, parentThreadId: parentThreadId) else { return false }
        return true
    }

    private static func isMatchingCodexChildRead(
        _ read: ThreadSummary,
        child: CodexChildThread,
        parentThreadId: String
    ) -> Bool {
        guard read.id == child.id,
              read.parentThreadId == child.parentThreadId,
              read.parentThreadId == parentThreadId,
              codexSubAgentAncestorThreadID(read.source) == child.ancestorThreadId,
              isCodexChild(read, parentThreadId: parentThreadId) else { return false }
        if let sourceIdentity = child.sourceIdentity {
            guard codexSubAgentSourceIdentity(read.source) == sourceIdentity else { return false }
        }
        return true
    }

    private static func codexSubAgentReadMismatchMessage(
        requestedThreadID: String,
        receivedThreadID: String
    ) -> String {
        "サブエージェント \(requestedThreadID) の thread/read identity が不一致です (received: \(receivedThreadID))"
    }

    private static func isKnownCodexSubAgentSource(_ source: JSONValue) -> Bool {
        if let value = source.stringValue {
            return ["review", "compact", "memory_consolidation"].contains(value)
        }
        if let threadSpawn = source["thread_spawn"] {
            return threadSpawn["parent_thread_id"]?.stringValue != nil
                || threadSpawn["parentThreadId"]?.stringValue != nil
        }
        if source["other"]?.stringValue != nil {
            return true
        }
        // Older app-server fixtures used a parent-only object. Keep accepting it
        // while still requiring the source to carry a parent identity below.
        return source["parentThreadId"]?.stringValue != nil
            || source["parent_thread_id"]?.stringValue != nil
    }

    private static func codexSubAgentSourceIdentity(_ source: ThreadSessionSource) -> String? {
        switch source {
        case .subAgent(let value):
            if let kind = value.stringValue { return "subAgent:\(kind)" }
            if value["thread_spawn"] != nil { return "subAgent:thread_spawn" }
            if value["other"] != nil { return "subAgent:other" }
            if codexSubAgentParentThreadID(value) != nil { return "subAgent:parent" }
            return nil
        case .unknownRaw(.null):
            return "legacy:none"
        default:
            return nil
        }
    }

    private static func codexSubAgentParentThreadID(_ source: JSONValue) -> String? {
        source["parentThreadId"]?.stringValue
            ?? source["parent_thread_id"]?.stringValue
            ?? source["thread_spawn"]?["parent_thread_id"]?.stringValue
            ?? source["thread_spawn"]?["parentThreadId"]?.stringValue
    }

    private static func codexSubAgentAncestorThreadID(_ source: JSONValue) -> String? {
        source["ancestorThreadId"]?.stringValue
            ?? source["ancestor_thread_id"]?.stringValue
            ?? source["thread_spawn"]?["ancestor_thread_id"]?.stringValue
            ?? source["thread_spawn"]?["ancestorThreadId"]?.stringValue
    }

    private static func codexSubAgentAncestorThreadID(_ source: ThreadSessionSource) -> String? {
        guard case .subAgent(let value) = source else { return nil }
        return codexSubAgentAncestorThreadID(value)
    }

    private static func needsCodexSubAgentRead(_ child: CodexChildThread) -> Bool {
        guard child.activeTurnId == nil else { return false }
        return ["active", "running", "inprogress", "in_progress"].contains(child.status.lowercased())
    }

    private func isCurrentCodexSubAgentRefresh(
        _ generation: Int,
        parentThreadId: String
    ) -> Bool {
        generation == codexSubAgentRefreshGeneration
            && threadId == parentThreadId
            && codexSubAgentState?.parentThreadId == parentThreadId
    }

    /// 子 thread は親 turn の item event・完了 event を契機に一覧を再取得する。
    /// 常駐ポーリングはせず、同時に複数 signal が来ても1本へまとめる。
    private func scheduleCodexSurfaceRefresh() {
        codexSubAgentRefreshPending = true
        if codexSurfaceRefreshTask != nil {
            return
        }
        codexSurfaceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.codexSubAgentRefreshPending = false
                await self.refreshCodexSubAgents()
            } while self.codexSubAgentRefreshPending
            self.codexSurfaceRefreshTask = nil
        }
    }
}

extension ChatSessionViewModel: ControllableSession {
    /// 未確認停止を「確認済み」にする（選択・閲覧時に呼ぶ）。
    public func markCompletionSeen() {
        hasUnseenCompletion = false
    }

    public func sendText(_ text: String, submit: Bool) async throws {
        if submit {
            sendFailure = nil
            let input = pendingInput + text
            // 入力欄は送信を受け付けてもらうまで書けない（画像の設定待ちも含む）。失敗時に戻す本文と新しい下書きがぶつからないように。
            inFlightText = input
            defer { inFlightText = nil }
            let clientInput: String
            if let preamble = pendingReplayContext {
                clientInput = preamble + "\n\n---\n\n" + input
            } else {
                clientInput = input
            }
            let nativeSkillInputs: [UserInput]?
            if agentRef == .builtin(.codex), codexSkillSelectionState?.selectedSkill != nil {
                nativeSkillInputs = codexSkillSelectionState?.nativeInputs(for: clientInput)
                guard nativeSkillInputs != nil else {
                    restoreDraftAfterRejectedSend(input)
                    reportError(
                        codexSkillSelectionState?.invalidSelectionMessage
                            ?? "Codex skill の候補が更新されたため、送信前に skill を再選択してください。"
                    )
                    return
                }
            } else {
                nativeSkillInputs = nil
            }
            submitBaselineTurnSeq = completedTurnSeq
            clearRunningTurn()
            let hasAttachments = !attachmentStore.attachments.isEmpty
            if hasAttachments && !attachmentStore.isWithinTotalRawBytesLimit {
                attachmentStore.setError("画像は合計8MiBまでです")
                restoreDraftAfterRejectedSend(input)
                return
            }
            let sendInputs = buildChatInputs(text: clientInput)
            let imageSnapshot = hasAttachments ? imageSendSnapshot(for: sendInputs) : nil
            if let imageSnapshot {
                guard imageSnapshot.supportsImages else {
                    attachmentStore.setError(ControlImageSendError.imagesUnsupported.localizedDescription)
                    restoreDraftAfterRejectedSend(input)
                    return
                }
                await configureCodexImageInputIfNeeded(supportsImages: imageSnapshot.supportsImages)
                guard imageSnapshot == imageSendSnapshot(for: buildChatInputs(text: clientInput)) else {
                    attachmentStore.setError(ControlImageSendError.imageSendSnapshotChanged.localizedDescription)
                    restoreDraftAfterRejectedSend(input)
                    throw ControlImageSendError.imageSendSnapshotChanged
                }
            }
            pendingInput = ""
            let sentAttachments = attachmentStore.attachments
            let userAttachments = sentAttachments.map {
                ChatUserAttachment(filename: $0.filename, mediaType: $0.mediaType)
            }
            let item = ChatItem.userMessage(
                id: "user-\(UUID().uuidString)",
                text: input,
                timestamp: Date(),
                attachments: userAttachments
            )
            // 表示・store には新規入力のみを記録する（プリアンブルは載せない）。
            appendOrReplace(item)
            localOriginalUserTextByID[item.id] = input
            adoptTitleFromOriginalUserText(input)
            enqueueTranscriptUpsert([item])
            turnGeneration += 1
            isAwaitingLocallyStartedTurnEvent = true
            if Self.isCompactCommand(input) {
                isCompacting = true
            }
            status = .running
            do {
                if agentRef == .builtin(.codex),
                   let native = client as? any CodexNativeSkillInputSending,
                   let skillInputs = nativeSkillInputs,
                   skillInputs.contains(where: { if case .skill = $0 { true } else { false } }) {
                    let nativeInputs = try materializeNativeSkillInputs(
                        skillInputs,
                        chatInputs: sendInputs
                    )
                    do {
                        try await native.turnStartNative(nativeInputs.inputs)
                        if let directory = nativeInputs.temporaryDirectory {
                            nativeSkillInputDirectories.insert(directory)
                        }
                    } catch {
                        Self.removeNativeSkillInputDirectory(nativeInputs.temporaryDirectory)
                        throw error
                    }
                } else {
                    try await client.turnStart(sendInputs)
                }
            } catch {
                // A3: turnStart 失敗時は status を .idle に戻す（.running 固着を防ぐ）。
                // reservation（pendingReplayContext）・添付・記録済み userMessage は
                // 変更せず残す（再送でプリアンブルをちょうど1回適用する既存セマンティクス）。
                isAwaitingLocallyStartedTurnEvent = false
                status = .idle
                sendFailure = SendFailure(
                    reason: Self.sendFailureReason(error),
                    restoredDraft: restoreDraftAfterRejectedSend(input)
                )
                if hasAttachments,
                   let codexError = error as? CodexStructuredClientError,
                   codexError == .imageInputUnsupported || codexError == .imageTurnInProgress {
                    let snapshotError = ControlImageSendError.imageSendSnapshotChanged
                    attachmentStore.setError(snapshotError.localizedDescription)
                    reportError("ターン開始に失敗しました: \(snapshotError)")
                    throw snapshotError
                }
                reportError("ターン開始に失敗しました: \(error)")
                throw error
            }
            // 単一適用: 送信成功後にクリアする。throw 時は予約を残し、再送で二重付与しない。
            pendingReplayContext = nil
            codexSkillSelectionState?.clearSelection()
            cacheSentAttachments(sentAttachments, forUserMessageID: item.id)
            attachmentStore.clear()
        } else {
            pendingInput += text
            touchOutput()
        }
    }

    /// 通知に出す短い理由（1 行目だけ）。
    static func sendFailureReason(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        return firstLine.count > 120 ? String(firstLine.prefix(119)) + "…" : firstLine
    }

    @discardableResult
    private func restoreDraftAfterRejectedSend(_ text: String) -> Bool {
        guard draftClearedForSend != nil else { return false }
        draft = text
        draftClearedForSend = text
        return true
    }

    private struct MaterializedNativeSkillInputs {
        let inputs: [UserInput]
        let temporaryDirectory: URL?
    }

    private func materializeNativeSkillInputs(
        _ skillInputs: [UserInput],
        chatInputs: [ChatInput]
    ) throws -> MaterializedNativeSkillInputs {
        let images = chatInputs.compactMap { input -> (Data, String)? in
            guard case .image(let data, let mediaType) = input else { return nil }
            return (data, mediaType)
        }
        guard !images.isEmpty else {
            return MaterializedNativeSkillInputs(inputs: skillInputs, temporaryDirectory: nil)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-codex-images-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let localImages = try images.enumerated().map { index, image -> UserInput in
                let path = directory.appendingPathComponent("image-\(index)")
                try image.0.write(to: path, options: .atomic)
                guard FileManager.default.isReadableFile(atPath: path.path) else {
                    throw CodexStructuredClientError.imageMaterializationFailed
                }
                return .localImage(path: path.path, detail: nil)
            }
            return MaterializedNativeSkillInputs(
                inputs: skillInputs + localImages,
                temporaryDirectory: directory
            )
        } catch let error as CodexStructuredClientError {
            Self.removeNativeSkillInputDirectory(directory)
            throw error
        } catch {
            Self.removeNativeSkillInputDirectory(directory)
            throw CodexStructuredClientError.imageMaterializationFailed
        }
    }

    private static func removeNativeSkillInputDirectory(_ directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func cacheSentAttachments(_ attachments: [ComposerAttachment], forUserMessageID id: String) {
        guard !attachments.isEmpty else { return }
        sentRuntimeAttachmentsByUserMessageID[id] = attachments
    }

    private func restoreRuntimeAttachmentsForRevert(userMessageID id: String) {
        if let cached = sentRuntimeAttachmentsByUserMessageID[id], !cached.isEmpty {
            attachmentStore.restore(cached)
        } else {
            attachmentStore.clear()
        }
    }

    private func clearSentRuntimeAttachmentCache() {
        sentRuntimeAttachmentsByUserMessageID.removeAll()
    }

    private func releaseNativeSkillInputDirectories() {
        for directory in nativeSkillInputDirectories {
            Self.removeNativeSkillInputDirectory(directory)
        }
        nativeSkillInputDirectories.removeAll()
    }

    /// サブエージェントタブからのフォローアップ送信（task-3 契約。
    /// AcceptanceSubAgentFollowUpTests が凍結）。
    public func sendSubAgentFollowUp(subAgent: SubAgentRef, text: String) async throws {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        submitBaselineTurnSeq = completedTurnSeq
        clearRunningTurn()

        let item = ChatItem.userMessage(
            id: "user-\(UUID().uuidString)",
            text: input,
            timestamp: Date(),
            attachments: []
        )
        appendOrReplace(item)
        localOriginalUserTextByID[item.id] = input
        adoptTitleFromOriginalUserText(input)
        enqueueTranscriptUpsert([item])
        turnGeneration += 1
        isAwaitingLocallyStartedTurnEvent = true
        status = .running

        let composedPrompt = Self.composeSubAgentFollowUpPrompt(subAgent: subAgent, userText: input)
        let clientInput: String
        if let preamble = pendingReplayContext {
            clientInput = preamble + "\n\n---\n\n" + composedPrompt
        } else {
            clientInput = composedPrompt
        }
        do {
            try await client.turnStart([.text(clientInput)])
        } catch {
            // sendText の A3 と同型: turnStart 失敗時は .running 固着を防ぐ。
            isAwaitingLocallyStartedTurnEvent = false
            status = .idle
            reportError("サブエージェントへの送信に失敗しました: \(error)")
            throw error
        }
        pendingReplayContext = nil
    }

    /// メインの Claude が対象サブエージェントを特定して SendMessage 相当の継続ができるよう、
    /// id・description・ユーザー本文を明示したプロンプトを合成する（task-3）。
    static func composeSubAgentFollowUpPrompt(subAgent: SubAgentRef, userText: String) -> String {
        let description = subAgent.description.isEmpty ? "(no description)" : subAgent.description
        return """
        以下はサブエージェントへのフォローアップです。対象サブエージェントを特定し、ユーザーの意図に沿って SendMessage 相当で継続・回答してください。

        - sub-agent id: \(subAgent.id)
        - description: \(description)

        ユーザーからのメッセージ:
        \(userText)
        """
    }

    /// 現在の transcript を即時に永続化キューへ書き出し、書き込み完了まで待つ
    /// （アプリ終了経路から呼ぶ。保留中ストリーム delta はバリア flush してから upsert する）。
    public func flushTranscriptNow() async {
        midTurnPersistenceGate.cancelPending()
        flushPendingStreamDeltasBarrier()
        enqueueTranscriptUpsert(transcript.filter(shouldStoreInTranscript))
        persistDisplayState()
        midTurnPersistenceGate.noteExternalFlush()
        await transcriptPersistenceQueue?.waitForPendingWrites()
        await totalCostSave?.value
    }

    public func readText(lines: Int) -> String {
        let allLines = transcript.flatMap {
            $0.plainText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        guard lines > 0 else { return allLines.joined(separator: "\n") }
        return allLines.suffix(lines).joined(separator: "\n")
    }

    public func consumeSubmitBaseline() {
        submitBaselineTurnSeq = nil
    }

    public func terminate() async {
        isTerminating = true
        flushPendingStreamDeltasBarrier()
        eventTask?.cancel()
        codexSettingsEventTask?.cancel()
        approvalTask?.cancel()
        userInputTask?.cancel()
        eventTask = nil
        codexSettingsEventTask = nil
        approvalTask = nil
        userInputTask = nil
        // 承認待ちで await 中の continuation を全て否認で解決する（リーク防止・S1）。冪等。
        await expireAllPendingUserQuestions()
        await approvalBroker.cancelAll()
        clearRunningBackgroundTasks()
        subAgentModel.failRunningSubAgents()
        await transcriptPersistenceQueue?.waitForPendingWrites()
        await totalCostSave?.value
        clearSentRuntimeAttachmentCache()
        localOriginalUserTextByID.removeAll()
        releaseNativeSkillInputDirectories()
        await client.close()
        status = .completed(exitCode: 0)
    }
}
