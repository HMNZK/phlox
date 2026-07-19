import Foundation
import Observation
import AgentDomain
import CodexAppServerKit
import StructuredChatKit


@MainActor
@Observable
public final class ChatSessionViewModel: Identifiable {
    public let id: SessionID
    public let startedAt: Date
    public private(set) var status: SessionStatus = .starting {
        didSet {
            guard oldValue != status else { return }
            // 承認待ち・完了・エラーへ入ったら「未確認の停止」をラッチする（PTY 側 transitionStatus と同一）。
            // idle は完了通知経路（notifyCompletionIfNeeded）で扱い、turnInterrupted 等の
            // 非完了 idle を赤枠から除外する。
            if status.latchesUnseenAttentionOnEntry {
                hasUnseenCompletion = true
            }
        }
    }
    /// 未確認の停止（＝ユーザーの対応待ち）。停止状態へ入るとラッチし、選択（閲覧）で解除する。
    public var hasUnseenCompletion: Bool = false {
        didSet {
            guard oldValue != hasUnseenCompletion else { return }
            unseenCompletionDidChange?()
        }
    }
    @ObservationIgnored public var unseenCompletionDidChange: (() -> Void)?
    public var name: String = ""
    public var projectID: ProjectID?
    public var parentSessionID: SessionID?
    public var launchContext: SessionLaunchContext = .interactive
    public private(set) var threadId: String?
    public private(set) var chatNativeSessionId: String?
    public private(set) var appServerUserAgent: String?
    public private(set) var transcript: [ChatItem] = []
    /// transcript の項目 ID 集合。契約（task-5）: 常に `Set(transcript.map(\.id))` と一致するよう
    /// 全変更経路で増分維持する（body 毎の全再構築を避けるための索引）。
    public private(set) var transcriptItemIDs: Set<String> = []
    @ObservationIgnored private var transcriptIndexByID: [String: Int] = [:]
    @ObservationIgnored private let transcriptStreamCoalescer = TranscriptStreamCoalescer()
    public private(set) var transcriptRevision: Int = 0
    public private(set) var rawEventLog: [String] = []
    public private(set) var pendingApprovals: [ChatApprovalRequest] = []
    public private(set) var completedTurnSeq: Int = 0
    public private(set) var lastOutputAt: Date?
    public private(set) var lastTurnCompletedAt: Date?
    /// 直近ターンの API 使用量・コスト（task-2 契約。受け入れテスト TurnCostAccumulation が凍結）。
    public private(set) var lastTurnUsage: TurnUsage?
    public private(set) var lastTurnCostUSD: Double?
    public private(set) var sessionTotalCostUSD: Double = 0
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
    public private(set) var availableModels: [AppServerModel] = []
    public private(set) var permissionProfiles: [PermissionProfileSummary] = []
    public private(set) var selectedModel: String?
    public private(set) var selectedEffort: String?
    public private(set) var selectedPermissionProfile: String?
    public private(set) var isPlanMode = false
    public private(set) var isPlanModeAvailable = false
    /// Claude/Cursor（spawn 型）で選択可能な model 一覧。Codex の `availableModels`
    /// （app-server 由来の `AppServerModel`）とは別に、alias/取得結果を素の文字列で保持する。
    public private(set) var availableSpawnAgentModels: [String] = []
    /// esc 履歴リバートピッカーの表示状態（task-9）。View はこれを observe して overlay を出す。
    public private(set) var isHistoryPickerPresented = false
    /// リバート確定で復元する composer 下書き本文（task-9）。View が反映後 `consumeDraftRestoration()` でクリアする。
    public private(set) var draftRestoration: String?
    @ObservationIgnored public var codexSettingsDidChange: (@MainActor (CodexAppServerSessionSettings?) -> Void)?
    /// リモート通知系へのフック。nil なら呼ばれない（既存挙動と同一）。
    @ObservationIgnored public var remoteSessionNotifier: (any RemoteSessionNotifier)?

    private let client: any StructuredAgentClient
    private let approvalBroker: ChatApprovalBroker
    private let subAgentModel = ChatSubAgentModel()
    public let agentRef: AgentRef
    private let workingDirectory: String?
    private var eventTask: Task<Void, Never>?
    private var codexSettingsEventTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?
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
    private var turnGeneration = 0
    private var isAwaitingLocallyStartedTurnEvent = false
    private var activeInterruptTask: Task<Void, Never>?
    private var activeInterruptID: UUID?
    private var lastEventAt: Date?
    private var pendingTurnCostUSD: Double?
    private let transcriptStore: (any TranscriptStore)?
    private let spawnAgentModelsProvider: SpawnAgentModelsProvider?

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
        spawnAgentModelsProvider: SpawnAgentModelsProvider? = nil,
        historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])? = nil,
        historyTranscriptLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.agentRef = agentRef
        self.client = client
        self.approvalBroker = approvalBroker
        self.workingDirectory = workingDirectory
        self.transcriptStore = transcriptStore
        self.transcriptPersistenceQueue = transcriptStore.map {
            TranscriptPersistenceQueue(sessionID: id, store: $0)
        }
        self.attachmentStore = ComposerAttachmentStore()
        self.spawnAgentModelsProvider = spawnAgentModelsProvider
        self.historyProvider = historyProvider
        self.historyTranscriptLoader = historyTranscriptLoader
        configureSubAgentModel()
        configureTranscriptStreamCoalescer()
        scheduleHistoryCacheLoadIfNeeded()
        startEventTasks()
    }

    init(
        id: SessionID,
        agentRef: AgentRef = .builtin(.codex),
        client: any StructuredAgentClient,
        approvalBroker: ChatApprovalBroker,
        workingDirectory: String?,
        attachmentStore: ComposerAttachmentStore
    ) {
        self.id = id
        self.startedAt = Date()
        self.agentRef = agentRef
        self.client = client
        self.approvalBroker = approvalBroker
        self.workingDirectory = workingDirectory
        self.transcriptStore = nil
        self.transcriptPersistenceQueue = nil
        self.attachmentStore = attachmentStore
        self.spawnAgentModelsProvider = nil
        self.historyProvider = nil
        self.historyTranscriptLoader = nil
        configureSubAgentModel()
        configureTranscriptStreamCoalescer()
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

    // task-9 契約（受け入れテスト ChatHistoryStart が凍結。実装契約の正本: tasks/task-9.md）
    @ObservationIgnored private let historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])?
    @ObservationIgnored private let historyTranscriptLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])?
    /// provider の結果を一度だけ格納（body 評価のたびに FS 走査しない）。SwiftUI 反応のため observable。
    private var cachedHistoryEntries: [ClaudeSessionHistoryEntry] = []
    @ObservationIgnored private var historyCacheLoaded = false
    @ObservationIgnored private var historyCacheLoadTask: Task<Void, Never>?

    /// 新規 Claude チャットの中央に「履歴から再開」を出すか（task-9 契約）。
    public var shouldOfferHistoryStart: Bool {
        guard agentRef == .builtin(.claudeCode) else { return false }
        guard historyProvider != nil else { return false }
        guard transcript.isEmpty, submitBaselineTurnSeq == nil else { return false }
        return !cachedHistoryEntries.isEmpty
    }

    /// 履歴一覧（最大 20 件・task-9 契約）。
    public var historyEntries: [ClaudeSessionHistoryEntry] {
        cachedHistoryEntries
    }

    /// init 時に off-main で一度だけ provider を呼び、完了時に MainActor で observable キャッシュへ格納する。
    private func scheduleHistoryCacheLoadIfNeeded() {
        guard let historyProvider, !historyCacheLoaded else { return }
        guard historyCacheLoadTask == nil else { return }
        historyCacheLoadTask = Task { [historyProvider] in
            let entries = await Task.detached {
                Array(historyProvider().prefix(20))
            }.value
            await MainActor.run { [weak self] in
                guard let self, !self.historyCacheLoaded else { return }
                self.cachedHistoryEntries = entries
                self.historyCacheLoaded = true
            }
        }
    }

    /// 選択した履歴から再開する（転写反映＋ client.resume・task-9 契約）。
    public func startFromHistory(_ entry: ClaudeSessionHistoryEntry) async {
        guard let historyTranscriptLoader else { return }
        startEventTasks()
        let loaded = historyTranscriptLoader(entry)
        setTranscript(loaded)
        touchOutput()
        // 履歴 JSONL 由来の表示のみ。起動時は Phlox transcriptStore へは書かない（二重永続化を避ける）。
        // 以降のターン境界 flush（`flushTranscriptAtTurnBoundary`）で loaded 履歴も store に載る（正規経路）。
        do {
            try await client.resume(sessionRef: entry.sessionID)
            updateNativeSessionId(entry.sessionID)
            if case .starting = status {
                status = .idle
            }
        } catch {
            setTranscript([])
            status = .error(message: "chat restore failed: \(error)")
            touchOutput()
        }
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? SessionViewModel.shortID(for: id) : trimmed
    }

    /// trim 後が空なら nil（draft 不変）。非空なら trim 済みを返し draft をクリアする（task-4 契約）。
    public func consumeDraftForSend() -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard !attachmentStore.attachments.isEmpty else { return nil }
            draft = ""
            return ""
        }
        draft = ""
        return trimmed
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

    private var supportsImageAttachments: Bool {
        agentRef == .builtin(.claudeCode)
    }

    /// Control API 経路の画像非対応判定用。
    public var acceptsImageAttachments: Bool {
        supportsImageAttachments
    }

    public enum ControlImageSendError: Error, Sendable {
        case imagesUnsupported
    }

    /// Control API から画像付きで送信する。turnStart 失敗時は添付を残さない。
    public func sendTextWithControlImages(
        _ text: String,
        submit: Bool,
        images: [(mediaType: String, data: Data)]
    ) async throws {
        guard images.isEmpty || supportsImageAttachments else {
            throw ControlImageSendError.imagesUnsupported
        }

        attachmentStore.clear()
        for image in images {
            attachmentStore.addImage(data: image.data, mediaType: image.mediaType)
        }

        do {
            try await sendText(text, submit: submit)
        } catch {
            attachmentStore.clear()
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

    public var isReadyForInput: Bool {
        switch status {
        case .starting:
            false
        case .idle, .running, .awaitingApproval, .completed, .error:
            true
        }
    }

    public func startNew(
        approvalPolicy: ApprovalPolicy,
        sandbox: SandboxPolicy,
        persistedSettings: CodexAppServerSessionSettings? = nil
    ) async throws {
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
            appServerUserAgent = initialized.userAgent
            let response = try await codexClient.threadResume(ThreadResumeParams(
                threadId: threadId,
                cwd: workingDirectory,
                approvalPolicy: approvalPolicy,
                sandbox: sandbox
            ))
            updateNativeSessionId(response.thread.id)
            syncSettings(from: response)
            await loadAvailableSettings(persistedSettings: persistedSettings)
            if let persistedSettings, persistedSettings.hasAnyValue {
                await reapplyPersistedSettings(persistedSettings)
            }
            await restoreTurnUsageFromStore()
            if await restoreTranscriptFromStore() {
                status = response.thread.status?.sessionStatus ?? .idle
            } else {
                let read = try await codexClient.threadRead(ThreadReadParams(threadId: threadId, includeTurns: true))
                updateNativeSessionId(read.thread.id)
                rebuildTranscript(from: read.thread)
                status = read.thread.status?.sessionStatus ?? .idle
            }
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
        draftRestoration = restored
        isHistoryPickerPresented = false
        lastEscapeAt = nil
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
    /// 一致しない・既に answered/expired なら false（no-op）。
    public func respondToUserQuestion(requestId: String, answers: [String: [String]]) async -> Bool {
        guard let index = userQuestionCardIndex(requestId: requestId),
              case .userQuestion(let id, let rid, let questions, _, .pending, let timestamp) = transcript[index]
        else {
            return false
        }

        await client.respondToUserQuestion(requestId: requestId, answers: answers)
        appendOrReplace(.userQuestion(
            id: id,
            requestId: rid,
            questions: questions,
            answers: answers,
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

    public func subAgentTranscript(for id: String) -> [ChatItem] {
        subAgentModel.transcript(for: id)
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
        do {
            _ = try await codexClient.updateThreadSettings(params)
        } catch where collaborationMode != nil {
            isPlanMode = false
            isPlanModeAvailable = false
            _ = try await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: threadId,
                model: model,
                effort: resolvedEffort
            ))
        }
        selectedModel = model
        selectedEffort = resolvedEffort
        notifyCodexSettingsChanged()
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
        do {
            _ = try await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: threadId,
                collaborationMode: collaborationMode
            ))
        } catch {
            if on {
                isPlanMode = false
                isPlanModeAvailable = false
                notifyCodexSettingsChanged()
            }
            throw error
        }
        isPlanMode = on
        if on {
            selectedModel = collaborationMode.settings.model
            selectedEffort = collaborationMode.settings.reasoningEffort
        }
        notifyCodexSettingsChanged()
    }

    // MARK: - Spawn agent (Claude/Cursor) settings

    /// Claude の固定 model alias。実 CLI の `--model`（opus/sonnet/fable/haiku）に対応（D2）。
    /// haiku は 2026-07-03 に `--model haiku` の実応答（claude-haiku-4-5）を実測確認して追加。
    static let claudeModelAliases = ["opus", "sonnet", "fable", "haiku"]

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
        return !claudeEffortUnsupportedModelAliases.contains(alias)
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

    /// alias → 表示名（バージョン付き）。CLI からバージョンを動的取得する手段が無いため
    /// 手動対応表とする（公式ピッカーの表記に追随。モデル更新時はここを更新する）。
    /// 未知の alias（Cursor のモデル名等）はそのまま表示する。
    static let spawnAgentModelDisplayNames: [String: String] = [
        "opus": "Opus 4.8",
        "sonnet": "Sonnet 5",
        "fable": "Fable 5",
        "haiku": "Haiku 4.5",
    ]

    /// モデル alias の表示名を返す（対応表に無ければ alias をそのまま返す）。
    public func spawnAgentModelDisplayName(_ alias: String) -> String {
        Self.spawnAgentModelDisplayNames[alias] ?? alias
    }
    /// Cursor の `cursor-agent models` 取得に失敗した/未注入のときに使う小さな fallback（起動を妨げない）。
    static let cursorFallbackModels = ["gpt-5", "sonnet-4.5", "opus-4.1"]

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

    /// task-22: Claude spawn セッションの effort 変更ハンドラ。
    public func setSpawnAgentEffort(_ effort: String?) async {
        guard isSpawnAgent else { return }
        selectedEffort = effort
        await applySpawnAgentSettings()
    }

    private func loadSpawnAgentSettings(persistedSettings: CodexAppServerSessionSettings?) async {
        availableSpawnAgentModels = await resolveSpawnAgentModels()
        let persistedPermissionOrMode = persistedSettings?.selectedPermissionProfile
        let persistedPlanMode = persistedSettings?.isPlanMode ?? (persistedPermissionOrMode == "plan")

        switch agentRef {
        case .builtin(.claudeCode):
            selectedModel = persistedSettings?.selectedModel
                ?? selectedModel
                ?? Self.claudeModelAliases.first
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
                ?? defaultCursorSpawnAgentModel()
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
        switch agentRef {
        case .builtin(.claudeCode):
            return Self.claudeModelAliases
        case .builtin(.cursor):
            if let spawnAgentModelsProvider {
                let fetched = await spawnAgentModelsProvider()
                if !fetched.isEmpty { return fetched }
            }
            return Self.cursorFallbackModels
        default:
            return []
        }
    }

    private func defaultCursorSpawnAgentModel() -> String? {
        if availableSpawnAgentModels.contains("composer-2.5") {
            return "composer-2.5"
        }
        return availableSpawnAgentModels.first
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
        if eventTask == nil {
            let events = client.events
            eventTask = Task { @MainActor [weak self] in
                for await event in events {
                    self?.handle(event)
                }
            }
        }
        if codexSettingsEventTask == nil, let codexClient {
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
                    self?.pendingApprovals.append(approval)
                    self?.enterAwaitingApproval(prompt: approval.prompt)
                    self?.touchOutput()
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
        lastEventAt = nil
        pendingTurnCostUSD = nil
    }

    private func markRunningEventReceived(at date: Date) {
        guard turnStartedAt != nil else { return }
        lastEventAt = date
    }

    private func clearRunningTurn() {
        turnStartedAt = nil
        lastEventAt = nil
        pendingTurnCostUSD = nil
    }

    /// ターミナル型（SessionViewModel.notifyCompletionIfNeeded）と同じ判定で完了を通知する。
    /// running からの turnCompleted だけを対象にし、復元リプレイ・interrupt 由来の idle 遷移では鳴らさない。
    private func notifyCompletionIfNeeded(from previousStatus: SessionStatus) {
        guard previousStatus == .running else { return }
        // 本物のターン完了を未確認の停止としてラッチする（turnInterrupted はこの経路を通らない）。
        hasUnseenCompletion = true
        SessionCompletionNotifier.notifyCompleted(sessionName: displayName)
        remoteSessionNotifier?.sessionCompleted(
            sessionId: id.description,
            sessionName: displayName
        )
    }

    /// 承認待ちへ遷移し、非承認待ちからの遷移時のみ通知する（連続する承認要求での多重通知を防ぐ）。
    func enterAwaitingApproval(prompt: String) {
        let previousStatus = status
        status = .awaitingApproval(prompt: prompt)
        if case .awaitingApproval = previousStatus { return }
        SessionCompletionNotifier.notifyAwaitingInput(sessionName: displayName)
        remoteSessionNotifier?.approvalPending(
            sessionId: id.description,
            sessionName: displayName
        )
    }

    private func appendPendingTurnCostIfNeeded(timestamp: Date) {
        guard let pendingTurnCostUSD else { return }
        appendOrReplace(.turnCost(
            id: "turn-cost-\(completedTurnSeq + 1)-\(UUID().uuidString)",
            costUSD: pendingTurnCostUSD,
            timestamp: timestamp
        ))
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

    private func handle(_ event: NormalizedChatEvent) {
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
            lastTurnCostUSD = usage.costUSD
            pendingTurnCostUSD = usage.costUSD
            sessionTotalCostUSD += usage.costUSD ?? 0
            persistTurnUsageSnapshot(usage)
        case .turnCompleted(let nativeSessionId):
            if let nativeSessionId, shouldAdoptNativeSessionId(nativeSessionId) {
                updateNativeSessionId(nativeSessionId)
            }
            appendPendingTurnCostIfNeeded(timestamp: eventDate)
            let previousStatus = status
            clearRunningTurn()
            status = .idle
            completedTurnSeq += 1
            lastTurnCompletedAt = eventDate
            notifyCompletionIfNeeded(from: previousStatus)
            touchOutput()
            flushTranscriptAtTurnBoundary()
        case .turnInterrupted(let nativeSessionId):
            if let nativeSessionId, shouldAdoptNativeSessionId(nativeSessionId) {
                updateNativeSessionId(nativeSessionId)
            }
            expireAllPendingUserQuestions()
            clearRunningTurn()
            clearRunningBackgroundTasks()
            subAgentModel.failRunningSubAgents()
            status = .idle
            flushTranscriptAtTurnBoundary()
        case .error(let message):
            expireAllPendingUserQuestions()
            clearRunningTurn()
            appendOrReplace(.error(id: "error-\(UUID().uuidString)", message: message, timestamp: eventDate))
            clearRunningBackgroundTasks()
            subAgentModel.failRunningSubAgents()
            status = .error(message: message)
            touchOutput()
            flushTranscriptAtTurnBoundary()
        case .warning(let message):
            markRunningEventReceived(at: eventDate)
            appendOrReplace(.error(id: "warning-\(UUID().uuidString)", message: message, timestamp: eventDate))
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
        case .userQuestionRequested(let requestId, let questions):
            markRunningEventReceived(at: eventDate)
            appendOrReplace(.userQuestion(
                id: "question-\(requestId)",
                requestId: requestId,
                questions: questions,
                answers: nil,
                state: .pending,
                timestamp: eventDate
            ))
            touchOutput()
        case .userQuestionResolved(let requestId, let outcome):
            markRunningEventReceived(at: eventDate)
            applyUserQuestionResolution(requestId: requestId, outcome: outcome)
            touchOutput()
        }
    }

    private func userQuestionCardIndex(requestId: String) -> Int? {
        transcript.firstIndex { item in
            guard case .userQuestion(_, let rid, _, _, _, _) = item else { return false }
            return rid == requestId
        }
    }

    private func applyUserQuestionResolution(requestId: String, outcome: ChatUserQuestionOutcome) {
        guard let index = userQuestionCardIndex(requestId: requestId),
              case .userQuestion(let id, let rid, let questions, let answers, let state, let timestamp) = transcript[index]
        else {
            return
        }

        switch outcome {
        case .answered(let resolvedAnswers):
            guard state != .answered else { return }
            appendOrReplace(.userQuestion(
                id: id,
                requestId: rid,
                questions: questions,
                answers: resolvedAnswers,
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

    private func expireAllPendingUserQuestions() {
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
        default:
            return false
        }
    }

    private func handleCodexSettingsEvent(_ event: ThreadEvent) {
        appendRawEventLog(String(describing: event))
        switch event {
        case .threadSettingsUpdated(let updatedThreadId, let settings):
            guard updatedThreadId == threadId else { return }
            syncSettings(from: settings)
            notifyCodexSettingsChanged()
        case .threadStatusChanged(let updatedThreadId, let threadStatus):
            // reset 後に生き残る旧 thread の遅延イベントで status を汚染しない
            // （threadSettingsUpdated と同じ threadId 一致 guard）。
            guard updatedThreadId == threadId else { return }
            if threadStatus.isWaitingOnApproval, pendingApprovals.isEmpty {
                enterAwaitingApproval(prompt: "Approval requested")
            } else if turnStartedAt != nil, threadStatus == .idle {
                return
            } else {
                status = threadStatus.sessionStatus
            }
        case .itemStarted(let updatedThreadId, _, let item), .itemCompleted(let updatedThreadId, _, let item):
            // 旧 thread の遅延 item で transcript / store を汚染しない。
            guard updatedThreadId == threadId else { return }
            flushPendingStreamDeltasBarrier()
            if let chatItem = chatItem(from: item) {
                appendOrReplace(chatItem)
                if case .itemCompleted = event {
                    enqueueTranscriptUpsert([chatItem])
                }
                touchOutput()
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

    private func reapplyPersistedSettings(_ settings: CodexAppServerSessionSettings) async {
        guard let threadId else { return }
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
        do {
            _ = try await codexClient.updateThreadSettings(params)
        } catch {
            if collaborationMode != nil {
                isPlanMode = false
                isPlanModeAvailable = false
                _ = try? await codexClient.updateThreadSettings(ThreadSettingsUpdateParams(
                    threadId: threadId,
                    model: model,
                    effort: effort,
                    permissions: settings.selectedPermissionProfile
                ))
            }
        }

        selectedModel = model ?? selectedModel
        selectedEffort = effort ?? selectedEffort
        selectedPermissionProfile = settings.selectedPermissionProfile ?? selectedPermissionProfile
        isPlanMode = collaborationMode?.mode == .plan
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

    private func applyStreamBatch(_ batch: TranscriptStreamCoalescer.Batch) {
        appendRawEventLogs(batch.rawEvents)
        var didChange = false
        for pending in batch.deltas {
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

        if didChange {
            markTranscriptChanged()
        }
        markRunningEventReceived(at: batch.latestEventAt)
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

    private func restoreTranscriptFromStore() async -> Bool {
        guard let transcriptStore else { return false }
        do {
            let persisted = try await transcriptStore.loadTranscript(for: id)
            guard !persisted.isEmpty else { return false }
            setTranscript([])
            for item in persisted {
                appendOrReplace(item)
            }
            touchOutput()
            return true
        } catch {
            logRestoreFailure(error)
            return false
        }
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
        setTranscript([])
        completedTurnSeq = 0
        for turn in thread.turns ?? [] {
            for item in turn.items ?? [] {
                if let chatItem = chatItem(from: item) {
                    appendOrReplace(chatItem)
                }
            }
            if turn.status == "completed" || turn.status == "idle" || turn.status == nil {
                completedTurnSeq += 1
            }
        }
        if !transcript.isEmpty {
            touchOutput()
        }
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
            return .commandExecution(id: id, command: command, output: text, timestamp: Date())
        }
        if type.contains("file") || type.contains("patch") {
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

    private func touchOutput() {
        lastOutputAt = Date()
    }


    private var shouldTrackBackgroundTasks: Bool {
        agentRef == .builtin(.claudeCode)
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
        threadId = id
        chatNativeSessionId = id
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
            submitBaselineTurnSeq = completedTurnSeq
            clearRunningTurn()
            let input = pendingInput + text
            let hasAttachments = !attachmentStore.attachments.isEmpty
            if hasAttachments && !attachmentStore.isWithinTotalRawBytesLimit {
                attachmentStore.setError("画像は合計8MiBまでです")
                return
            }
            if hasAttachments && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !supportsImageAttachments {
                attachmentStore.setError("画像添付は Claude のみ対応です")
                return
            }
            pendingInput = ""
            let userAttachments = attachmentStore.attachments.map {
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
            enqueueTranscriptUpsert([item])
            turnGeneration += 1
            isAwaitingLocallyStartedTurnEvent = true
            status = .running
            // リバートで予約された文脈リプレイがあれば、CLI 入力にのみプリアンブルを前置する。
            let clientInput: String
            if let preamble = pendingReplayContext {
                clientInput = preamble + "\n\n---\n\n" + input
            } else {
                clientInput = input
            }
            do {
                try await client.turnStart(buildChatInputs(text: clientInput))
            } catch {
                // A3: turnStart 失敗時は status を .idle に戻す（.running 固着を防ぐ）。
                // reservation（pendingReplayContext）・添付・記録済み userMessage は
                // 変更せず残す（再送でプリアンブルをちょうど1回適用する既存セマンティクス）。
                isAwaitingLocallyStartedTurnEvent = false
                status = .idle
                throw error
            }
            // 単一適用: 送信成功後にクリアする。throw 時は予約を残し、再送で二重付与しない。
            pendingReplayContext = nil
            attachmentStore.clear()
        } else {
            pendingInput += text
            touchOutput()
        }
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
        flushPendingStreamDeltasBarrier()
        eventTask?.cancel()
        codexSettingsEventTask?.cancel()
        approvalTask?.cancel()
        eventTask = nil
        codexSettingsEventTask = nil
        approvalTask = nil
        // 承認待ちで await 中の continuation を全て否認で解決する（リーク防止・S1）。冪等。
        await approvalBroker.cancelAll()
        clearRunningBackgroundTasks()
        await transcriptPersistenceQueue?.waitForPendingWrites()
        await client.close()
        status = .completed(exitCode: 0)
    }
}
