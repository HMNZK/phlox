import Foundation
import StructuredChatKit

public enum ThreadEvent: Equatable, Sendable {
    case agentMessageDelta(threadId: String, turnId: String, itemId: String, delta: String)
    case reasoningSummaryDelta(threadId: String, turnId: String, itemId: String, delta: String)
    case commandOutputDelta(threadId: String, turnId: String, itemId: String, delta: String)
    case filePatchUpdated(threadId: String, turnId: String, itemId: String, changes: [FilePatchChange])
    case itemStarted(threadId: String, turnId: String, item: ThreadItem)
    case itemCompleted(threadId: String, turnId: String, item: ThreadItem)
    case turnStarted(threadId: String, turn: TurnSummary)
    case turnCompleted(threadId: String, turn: TurnSummary)
    case turnInterrupted(threadId: String, turnId: String?)
    case planUpdated(threadId: String, turnId: String, plan: [TurnPlanStep], explanation: String?)
    case skillsChanged
    case tokenUsageUpdated(threadId: String, turnId: String, tokenUsage: ThreadTokenUsage)
    case threadStatusChanged(threadId: String, status: ThreadStatus)
    case threadSettingsUpdated(threadId: String, threadSettings: ThreadSettings)
    case error(threadId: String?, turnId: String?, message: String, willRetry: Bool?)
    case warning(threadId: String?, message: String)
}

/// Codex の wire event と正規化 event を同じ順序で配送するための共有ストリーム項目。
public enum CodexStructuredEvent: Equatable, Sendable {
    case thread(ThreadEvent)
    case normalized(NormalizedChatEvent)
    /// 正規化後も app-server の thread/turn identity を VM 境界まで保持する。
    case normalizedWithIdentity(
        threadId: String?,
        turnId: String?,
        event: NormalizedChatEvent
    )
}

public protocol CodexOrderedEventsProviding: Sendable {
    var orderedEvents: AsyncStream<CodexStructuredEvent> { get }
}

public enum CodexAppServerClientError: Error, Equatable, Sendable {
    case threadIDMismatch(requested: String, received: String)
}

public actor CodexAppServerClient {
    private struct TurnState {
        var activeTurnId: String?
        var closedTurnIds: Set<String> = []
        var pendingStartGeneration: UInt64?
        var hasObservedLifecycle = false
    }

    private let rpc: JSONRPCClient
    private var notificationTask: Task<Void, Never>?
    private var turnStates: [String: TurnState] = [:]
    private var nextTurnStartGeneration: UInt64 = 0
    private var closeRequested = false
    private let eventContinuation: AsyncStream<ThreadEvent>.Continuation
    public nonisolated let events: AsyncStream<ThreadEvent>

    public init(rpc: JSONRPCClient) {
        self.rpc = rpc
        var eventContinuation: AsyncStream<ThreadEvent>.Continuation?
        self.events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!
    }

    public init(
        transport: any AppServerTransport,
        serverRequestHandler: JSONRPCClient.ServerRequestHandler? = nil
    ) {
        self.init(rpc: JSONRPCClient(transport: transport, serverRequestHandler: serverRequestHandler))
    }

    deinit {
        notificationTask?.cancel()
        eventContinuation.finish()
    }

    public func start() async {
        await rpc.start()
        guard notificationTask == nil else { return }
        let notifications = rpc.notifications
        notificationTask = Task { [weak self] in
            for await notification in notifications {
                guard let event = Self.threadEvent(from: notification) else { continue }
                await self?.yield(event)
            }
            await self?.notificationStreamDidFinish()
        }
    }

    public func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try await rpc.request(method: "initialize", params: params)
    }

    public func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try await rpc.request(method: "thread/start", params: params)
    }

    public func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        let response: ThreadResponse = try await rpc.request(method: "thread/resume", params: params)
        guard response.thread.id == params.threadId else {
            throw CodexAppServerClientError.threadIDMismatch(
                requested: params.threadId,
                received: response.thread.id
            )
        }
        return response
    }

    public func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        let response: ThreadReadResponse = try await rpc.request(method: "thread/read", params: params)
        guard response.thread.id == params.threadId else {
            throw CodexAppServerClientError.threadIDMismatch(
                requested: params.threadId,
                received: response.thread.id
            )
        }
        return response
    }

    public func threadList(_ params: ThreadListParams = ThreadListParams()) async throws -> ThreadListResponse {
        try await rpc.request(method: "thread/list", params: params)
    }

    public func turnStart(_ params: TurnStartParams) async throws -> TurnStartResponse {
        let generation = markTurnStartPending(threadId: params.threadId)
        do {
            let response: TurnStartResponse = try await rpc.request(method: "turn/start", params: params)
            finishTurnStart(threadId: params.threadId, generation: generation)
            return response
        } catch {
            finishTurnStart(threadId: params.threadId, generation: generation)
            throw error
        }
    }

    public func turnStartNative(_ input: [UserInput], threadId: String) async throws {
        _ = try await turnStart(TurnStartParams(threadId: threadId, input: input))
    }

    public func turnInterrupt(_ params: TurnInterruptParams) async throws -> TurnInterruptResponse {
        try await rpc.request(method: "turn/interrupt", params: params)
    }

    public func skillsList(_ params: SkillsListParams = SkillsListParams()) async throws -> SkillsListResponse {
        try await rpc.request(method: "skills/list", params: params)
    }

    /// `turn/started` でサーバーが通知した ID だけを停止リクエストに使う。
    public func activeTurnId(for threadId: String) -> String? {
        turnStates[threadId]?.activeTurnId
    }

    public func listModels(_ params: ModelListParams = ModelListParams()) async throws -> ModelListResponse {
        try await rpc.request(method: "model/list", params: params)
    }

    public func listPermissionProfiles(
        _ params: PermissionProfileListParams = PermissionProfileListParams()
    ) async throws -> PermissionProfileListResponse {
        try await rpc.request(method: "permissionProfile/list", params: params)
    }

    public func listCollaborationModes(
        _ params: CollaborationModeListParams = CollaborationModeListParams()
    ) async throws -> CollaborationModeListResponse {
        try await rpc.request(method: "collaborationMode/list", params: params)
    }

    public func updateThreadSettings(
        _ params: ThreadSettingsUpdateParams
    ) async throws -> ThreadSettingsUpdateResponse {
        try await rpc.request(method: "thread/settings/update", params: params)
    }

    public func close() async {
        closeRequested = true
        notificationTask?.cancel()
        await rpc.close()
        eventContinuation.finish()
    }

    private func yield(_ event: ThreadEvent) {
        guard updateActiveTurns(for: event) else { return }
        eventContinuation.yield(event)
    }

    private func notificationStreamDidFinish() {
        guard !closeRequested else {
            eventContinuation.finish()
            return
        }

        for (threadId, state) in turnStates where
            state.activeTurnId != nil || state.pendingStartGeneration != nil {
            eventContinuation.yield(.error(
                threadId: threadId,
                turnId: state.activeTurnId,
                message: "Codex app-server process exited before the turn completed",
                willRetry: false
            ))
        }
        turnStates.removeAll()
        eventContinuation.finish()
    }

    /// turn identity を閉じた後は active=nil でも wildcard に戻さない。
    /// closedTurnIds は遅延した旧 turn の delta/plan/item を遮断し、新しい identity だけを再束縛する。
    private func updateActiveTurns(for event: ThreadEvent) -> Bool {
        switch event {
        case .turnStarted(let threadId, let turn):
            guard beginObservedTurn(threadId: threadId, turnId: turn.id) else { return false }
        case .turnCompleted(let threadId, let turn):
            guard acceptTurnEvent(threadId: threadId, turnId: turn.id) else { return false }
            closeTurn(threadId: threadId, turnId: turn.id)
        case .turnInterrupted(let threadId, let turnId):
            guard acceptTurnEvent(threadId: threadId, turnId: turnId) else { return false }
            closeTurn(threadId: threadId, turnId: turnId)
        case .agentMessageDelta(let threadId, let turnId, _, _),
             .reasoningSummaryDelta(let threadId, let turnId, _, _),
             .commandOutputDelta(let threadId, let turnId, _, _),
             .filePatchUpdated(let threadId, let turnId, _, _),
             .itemStarted(let threadId, let turnId, _),
             .itemCompleted(let threadId, let turnId, _),
             .planUpdated(let threadId, let turnId, _, _),
             .tokenUsageUpdated(let threadId, let turnId, _):
            guard acceptTurnEvent(threadId: threadId, turnId: turnId) else { return false }
        case .error(let threadId, let turnId, _, let willRetry):
            guard let threadId else { return true }
            guard acceptTurnEvent(threadId: threadId, turnId: turnId) else { return false }
            if willRetry != true {
                closeTurn(threadId: threadId, turnId: turnId)
            }
        default:
            return true
        }
        return true
    }

    @discardableResult
    private func markTurnStartPending(threadId: String) -> UInt64 {
        nextTurnStartGeneration &+= 1
        var state = turnStates[threadId, default: TurnState()]
        state.pendingStartGeneration = nextTurnStartGeneration
        turnStates[threadId] = state
        return nextTurnStartGeneration
    }

    private func finishTurnStart(threadId: String, generation: UInt64) {
        guard var state = turnStates[threadId], state.pendingStartGeneration == generation else { return }
        state.pendingStartGeneration = nil
        turnStates[threadId] = state
    }

    private func beginObservedTurn(threadId: String, turnId: String?) -> Bool {
        guard let turnId, !turnId.isEmpty else { return true }
        var state = turnStates[threadId, default: TurnState()]
        guard !state.closedTurnIds.contains(turnId) else { return false }
        // lifecycle event が見えている間は、別 identity の turn/started を旧 turn として捨てる。
        if let activeTurnId = state.activeTurnId, activeTurnId != turnId {
            return false
        }
        state.activeTurnId = turnId
        state.pendingStartGeneration = nil
        state.hasObservedLifecycle = true
        turnStates[threadId] = state
        return true
    }

    private func acceptTurnEvent(threadId: String, turnId: String?) -> Bool {
        guard let turnId, !turnId.isEmpty else { return true }
        var state = turnStates[threadId, default: TurnState()]
        guard !state.closedTurnIds.contains(turnId) else { return false }
        if let activeTurnId = state.activeTurnId, activeTurnId != turnId {
            // lifecycle 前の古い公開契約では turn/started 無しの複数 delta を許容していた。
            // lifecycle 後だけ identity を固定し、完了後の stale event は閉じた集合で拒否する。
            guard !state.hasObservedLifecycle else { return false }
        }
        state.activeTurnId = turnId
        turnStates[threadId] = state
        return true
    }

    private func closeTurn(threadId: String, turnId: String?) {
        guard var state = turnStates[threadId] else { return }
        state.hasObservedLifecycle = true
        if let turnId, !turnId.isEmpty {
            state.closedTurnIds.insert(turnId)
            if state.activeTurnId == turnId {
                state.activeTurnId = nil
            }
        } else if let activeTurnId = state.activeTurnId {
            state.closedTurnIds.insert(activeTurnId)
            state.activeTurnId = nil
        }
        turnStates[threadId] = state
    }

    private static func threadEvent(from notification: ServerNotification) -> ThreadEvent? {
        switch notification {
        case .agentMessageDelta(let value):
            return .agentMessageDelta(
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                delta: value.delta
            )
        case .reasoningSummaryTextDelta(let value):
            return .reasoningSummaryDelta(
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                delta: value.delta
            )
        case .commandExecutionOutputDelta(let value):
            return .commandOutputDelta(
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                delta: value.delta
            )
        case .fileChangePatchUpdated(let value):
            return .filePatchUpdated(
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                changes: value.changes
            )
        case .itemStarted(let value):
            return .itemStarted(threadId: value.threadId, turnId: value.turnId, item: value.item)
        case .itemCompleted(let value):
            return .itemCompleted(threadId: value.threadId, turnId: value.turnId, item: value.item)
        case .turnStarted(let value):
            return .turnStarted(threadId: value.threadId, turn: value.turn)
        case .turnCompleted(let value):
            return .turnCompleted(threadId: value.threadId, turn: value.turn)
        case .turnInterrupted(let value):
            return .turnInterrupted(threadId: value.threadId, turnId: value.turnId)
        case .turnPlanUpdated(let value):
            return .planUpdated(
                threadId: value.threadId,
                turnId: value.turnId,
                plan: value.plan,
                explanation: value.explanation
            )
        case .skillsChanged:
            return .skillsChanged
        case .threadTokenUsageUpdated(let value):
            return .tokenUsageUpdated(
                threadId: value.threadId,
                turnId: value.turnId,
                tokenUsage: value.tokenUsage
            )
        case .threadStatusChanged(let value):
            return .threadStatusChanged(threadId: value.threadId, status: value.status)
        case .threadSettingsUpdated(let value):
            return .threadSettingsUpdated(threadId: value.threadId, threadSettings: value.threadSettings)
        case .error(let value):
            return .error(
                threadId: value.threadId,
                turnId: value.turnId,
                message: value.error?.message ?? "Unknown app-server error",
                willRetry: value.willRetry
            )
        case .warning(let value):
            return .warning(threadId: value.threadId, message: value.message)
        case .unknown:
            return nil
        }
    }
}

public actor CodexStructuredAgentClient: StructuredAgentClient, CodexOrderedEventsProviding {
    private let client: CodexAppServerClient
    private var bridgeTask: Task<Void, Never>?
    private var currentThreadId: String?
    /// 切替中に `currentThreadId` を nil にしても、失敗時に戻せる最後の確定 identity。
    private var committedThreadId: String?
    /// 初回 thread 確立前は wire event を観測できる既存契約を保ち、確立後の切替中は fail closed にする。
    private var hasEstablishedThread = false
    /// 複数の resume/start が同時に返っても、最後に開始した操作だけが active thread を commit する。
    private var threadIdentityGeneration = 0
    /// 子 thread 停止を要求済みで、親 thread の filter を越えてよい完了だけを保持する。
    private var pendingChildInterrupts: [String: String] = [:]
    private var nativeImageInputEnabled = false
    /// 画像を含む turn/start の await 中は、モデル変更を受け付けない。
    /// actor は await 中に再入されるため、UI 側の再チェックだけではこの窓を塞げない。
    private var imageTurnInFlight = false
    private var modelChangeInFlight = false
    private var imageInputWriter: (@Sendable (Data, URL) throws -> Void)?
    /// materialize 済み画像ディレクトリ（セッション全体。履歴参照のため turn 終了では保持する）。
    private var materializedImageDirectories: Set<URL> = []
    /// resetConversation で新規 thread を開始し直すために、直近の thread/start 引数を保持する。
    private var lastThreadStartParams: ThreadStartParams?
    /// threadResume 単体で一時的に切り替えた active identity を read 失敗時に戻すための状態。
    private var pendingResumeRollback: (
        threadID: String,
        previousThreadID: String?,
        previousThreadStartParams: ThreadStartParams?,
        generation: Int
    )?
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    public nonisolated let events: AsyncStream<NormalizedChatEvent>
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    public nonisolated let threadEvents: AsyncStream<ThreadEvent>
    private let orderedEventContinuation: AsyncStream<CodexStructuredEvent>.Continuation
    public nonisolated let orderedEvents: AsyncStream<CodexStructuredEvent>

    public init(client: CodexAppServerClient) {
        self.client = client
        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!

        var threadEventContinuation: AsyncStream<ThreadEvent>.Continuation?
        self.threadEvents = AsyncStream { threadEventContinuation = $0 }
        self.threadEventContinuation = threadEventContinuation!

        var orderedEventContinuation: AsyncStream<CodexStructuredEvent>.Continuation?
        self.orderedEvents = AsyncStream { orderedEventContinuation = $0 }
        self.orderedEventContinuation = orderedEventContinuation!
    }

    deinit {
        bridgeTask?.cancel()
        eventContinuation.finish()
        threadEventContinuation.finish()
        orderedEventContinuation.finish()
    }

    public func start() async {
        await client.start()
        guard bridgeTask == nil else { return }
        let source = client.events
        bridgeTask = Task { [weak self] in
            for await event in source {
                await self?.yield(event)
            }
            await self?.finish()
        }
    }

    public func turnStart(_ input: [ChatInput]) async throws {
        guard let currentThreadId else {
            throw CodexStructuredClientError.threadNotStarted
        }
        let threadGeneration = threadIdentityGeneration
        pendingResumeRollback = nil
        let hasImages = input.contains { if case .image = $0 { true } else { false } }
        if hasImages {
            guard !imageTurnInFlight, !modelChangeInFlight else {
                throw CodexStructuredClientError.imageTurnInProgress
            }
            guard nativeImageInputEnabled else {
                throw CodexStructuredClientError.imageInputUnsupported
            }
            imageTurnInFlight = true
        }
        defer {
            if hasImages {
                imageTurnInFlight = false
            }
        }
        let materialized = try Self.materializeImageInputs(input, write: imageInputWriter)
        let imageDirectory = materialized.temporaryDirectory
        if let imageDirectory {
            registerImageDirectory(imageDirectory)
        }
        do {
            _ = try await client.turnStart(TurnStartParams(
                threadId: currentThreadId,
                input: materialized.inputs
            ))
        } catch {
            if let imageDirectory {
                deleteImageDirectory(imageDirectory)
            }
            throw error
        }
        guard threadGeneration == threadIdentityGeneration,
              self.currentThreadId == currentThreadId else {
            throw CodexStructuredClientError.staleThreadOperation
        }
    }

    /// Native Codex入力（skillを含む）をそのままapp-serverへ渡す。
    public func turnStartNative(_ input: [UserInput]) async throws {
        guard let currentThreadId else { throw CodexStructuredClientError.threadNotStarted }
        let threadGeneration = threadIdentityGeneration
        pendingResumeRollback = nil
        let hasImages = input.contains(where: Self.isImageInput)
        if hasImages {
            guard !imageTurnInFlight, !modelChangeInFlight else {
                throw CodexStructuredClientError.imageTurnInProgress
            }
            guard nativeImageInputEnabled else {
                throw CodexStructuredClientError.imageInputUnsupported
            }
            imageTurnInFlight = true
        }
        defer {
            if hasImages {
                imageTurnInFlight = false
            }
        }
        _ = try await client.turnStart(TurnStartParams(threadId: currentThreadId, input: input))
        guard threadGeneration == threadIdentityGeneration,
              self.currentThreadId == currentThreadId else {
            throw CodexStructuredClientError.staleThreadOperation
        }
    }

    public func setNativeImageInputEnabled(_ enabled: Bool) {
        guard !imageTurnInFlight, !modelChangeInFlight else { return }
        nativeImageInputEnabled = enabled
    }

    func setImageInputWriterForTesting(_ writer: (@Sendable (Data, URL) throws -> Void)?) {
        imageInputWriter = writer
    }

    public func resume(sessionRef: String) async throws {
        let params = ThreadResumeParams(threadId: sessionRef)
        threadIdentityGeneration += 1
        let generation = threadIdentityGeneration
        let previousThreadId = committedThreadId
        let previousThreadStartParams = lastThreadStartParams
        pendingChildInterrupts.removeAll()
        pendingResumeRollback = nil
        currentThreadId = nil
        do {
            let response = try await client.threadResume(params)
            guard generation == threadIdentityGeneration else { return }
            currentThreadId = response.thread.id
            committedThreadId = response.thread.id
            hasEstablishedThread = true
            lastThreadStartParams = Self.threadStartParams(from: params)
            pendingResumeRollback = (
                threadID: response.thread.id,
                previousThreadID: previousThreadId,
                previousThreadStartParams: previousThreadStartParams,
                generation: generation
            )
        } catch {
            if generation == threadIdentityGeneration {
                currentThreadId = previousThreadId
            }
            throw error
        }
    }

    /// 現在アクティブな thread id（resetConversation 後は新 thread）。VM が reset 直後に
    /// 新 threadId を採用し、旧 thread の遅延イベントと弁別するために参照する。
    public func activeThreadId() -> String? { currentThreadId }

    /// 再開（thread/resume）引数から、reset 時の thread/start に流用できる ThreadStartParams を作る。
    /// これにより復元セッションでも resetConversation が cwd 等を保った新 thread を開始できる。
    static func threadStartParams(from resume: ThreadResumeParams) -> ThreadStartParams {
        ThreadStartParams(
            cwd: resume.cwd,
            model: resume.model,
            modelProvider: resume.modelProvider,
            approvalPolicy: resume.approvalPolicy,
            approvalsReviewer: resume.approvalsReviewer,
            sandbox: resume.sandbox,
            baseInstructions: resume.baseInstructions,
            developerInstructions: resume.developerInstructions,
            serviceTier: resume.serviceTier,
            personality: resume.personality
        )
    }

    public func interrupt() async throws {
        guard let currentThreadId,
              let turnId = await client.activeTurnId(for: currentThreadId)
        else { return }
        _ = try await client.turnInterrupt(TurnInterruptParams(threadId: currentThreadId, turnId: turnId))
    }

    /// 会話文脈をリセットする。app-server は特定メッセージ時点への巻き戻し API を持たないため、
    /// 直近の thread/start 引数で「新しい thread」を開始し、以後の turnStart をそちらへ向ける。
    /// 新 threadId は turn/completed などのイベントで VM も観測できる。thread/start が未実施、
    /// または再開始に失敗した場合は currentThreadId を nil にし、次の turnStart を threadNotStarted
    /// で明示的に失敗させる（旧 thread への誤送信を避ける）。
    public func resetConversation() async {
        threadIdentityGeneration += 1
        let generation = threadIdentityGeneration
        pendingResumeRollback = nil
        guard let params = lastThreadStartParams else {
            currentThreadId = nil
            committedThreadId = nil
            pendingChildInterrupts.removeAll()
            return
        }
        pendingChildInterrupts.removeAll()
        pendingResumeRollback = nil
        currentThreadId = nil
        do {
            let response = try await client.threadStart(params)
            guard generation == threadIdentityGeneration else { return }
            currentThreadId = response.thread.id
            committedThreadId = response.thread.id
        } catch {
            if generation == threadIdentityGeneration {
                currentThreadId = nil
                committedThreadId = nil
            }
        }
    }

    public func close() async {
        bridgeTask?.cancel()
        bridgeTask = nil
        releaseAllImageDirectories()
        await client.close()
        finish()
    }

    private func yield(_ event: ThreadEvent) {
        // reset 後も app-server 上で生き残る旧 thread の遅延イベントを source で遮断する。
        // thread 切替中（currentThreadId == nil）は thread identity を持つイベントを流さない。
        // 現在の thread が確定していて、イベントの thread id がそれと異なるなら、旧 thread
        // 由来なので両ストリームへ流さない（normalized delta も含む）。
        // ただし子停止を要求済みの場合だけ、要求した turn の interrupted 完了を通す。
        let eventThreadId = Self.threadId(of: event)
        let childCompletionAccepted: Bool
        if let currentThreadId,
           let eventThreadId,
           !eventThreadId.isEmpty,
           eventThreadId != currentThreadId {
            childCompletionAccepted = acceptsPendingChildInterruptCompletion(
                event,
                threadId: eventThreadId
            )
            guard childCompletionAccepted else { return }
        } else if let eventThreadId, !eventThreadId.isEmpty {
            // 初回 thread/start 前の既存観測契約だけは維持する。いったん thread を確立した
            // 後の resume/reset 切替中は、nil を wildcard にしない。
            guard currentThreadId != nil || !hasEstablishedThread else { return }
            childCompletionAccepted = false
        } else {
            childCompletionAccepted = false
        }
        orderedEventContinuation.yield(.thread(event))
        threadEventContinuation.yield(event)
        if !childCompletionAccepted,
           let normalized = Self.normalizedEvent(from: event) {
            let turnId = Self.turnId(of: event)
            // threadId が無い retry/error も、生成時点の active thread を context identity として
            // 運ぶ。切替中は currentThreadId が nil なので VM 側で fail closed になる。
            let normalizedThreadId = eventThreadId ?? currentThreadId
            orderedEventContinuation.yield(.normalizedWithIdentity(
                threadId: normalizedThreadId,
                turnId: turnId,
                event: normalized
            ))
            eventContinuation.yield(normalized)
        }
    }

    private static func turnId(of event: ThreadEvent) -> String? {
        switch event {
        case .agentMessageDelta(_, let turnId, _, _),
             .reasoningSummaryDelta(_, let turnId, _, _),
             .commandOutputDelta(_, let turnId, _, _),
             .filePatchUpdated(_, let turnId, _, _),
             .itemStarted(_, let turnId, _),
             .itemCompleted(_, let turnId, _),
             .planUpdated(_, let turnId, _, _),
             .tokenUsageUpdated(_, let turnId, _):
            return turnId
        case .turnStarted(_, let turn), .turnCompleted(_, let turn):
            return turn.id
        case .turnInterrupted(_, let turnId):
            return turnId
        case .error(_, let turnId, _, _):
            return turnId
        case .threadStatusChanged, .threadSettingsUpdated, .warning, .skillsChanged:
            return nil
        }
    }

    private static func threadId(of event: ThreadEvent) -> String? {
        switch event {
        case .agentMessageDelta(let threadId, _, _, _),
             .reasoningSummaryDelta(let threadId, _, _, _),
             .commandOutputDelta(let threadId, _, _, _),
             .filePatchUpdated(let threadId, _, _, _),
             .itemStarted(let threadId, _, _),
             .itemCompleted(let threadId, _, _),
             .turnStarted(let threadId, _),
             .turnCompleted(let threadId, _),
             .tokenUsageUpdated(let threadId, _, _),
             .threadStatusChanged(let threadId, _),
             .threadSettingsUpdated(let threadId, _):
            return threadId
        case .turnInterrupted(let threadId, _):
            return threadId
        case .planUpdated(let threadId, _, _, _):
            return threadId
        case .skillsChanged:
            return nil
        case .error(let threadId, _, _, _):
            return threadId
        case .warning(let threadId, _):
            return threadId
        }
    }

    private func finish() {
        eventContinuation.finish()
        threadEventContinuation.finish()
        orderedEventContinuation.finish()
    }

    private func acceptsPendingChildInterruptCompletion(_ event: ThreadEvent, threadId: String) -> Bool {
        guard let expectedTurnId = pendingChildInterrupts[threadId] else { return false }
        switch event {
        case .turnCompleted(_, let turn):
            guard turn.id == expectedTurnId, turn.status == "interrupted" else { return false }
        case .turnInterrupted(_, let turnId):
            guard turnId == expectedTurnId else { return false }
        default:
            return false
        }

        pendingChildInterrupts.removeValue(forKey: threadId)
        return true
    }
}

public enum CodexStructuredClientError: Error, Equatable, Sendable {
    case threadNotStarted
    case staleThreadOperation
    case imageInputUnsupported
    case imageTurnInProgress
    case imageMaterializationFailed
}

public protocol CodexImageInputConfiguring: Sendable {
    func setNativeImageInputEnabled(_ enabled: Bool) async
}

extension CodexStructuredAgentClient: CodexImageInputConfiguring {}

private extension CodexStructuredAgentClient {
    struct MaterializedImageInputs {
        let inputs: [UserInput]
        let temporaryDirectory: URL?
    }

    static func materializeImageInputs(
        _ input: [ChatInput],
        write: (@Sendable (Data, URL) throws -> Void)? = nil
    ) throws -> MaterializedImageInputs {
        guard input.contains(where: { if case .image = $0 { true } else { false } }) else {
            let textInputs = input.compactMap { chatInput -> UserInput? in
                if case .text(let text) = chatInput { return .text(text) }
                return nil
            }
            return MaterializedImageInputs(
                inputs: textInputs,
                temporaryDirectory: nil
            )
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-codex-images-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var imageIndex = 0
            let inputs = try input.map { chatInput -> UserInput in
                switch chatInput {
                case .text(let text):
                    return .text(text)
                case .image(let data, _):
                    let imageURL = directory.appendingPathComponent("image-\(imageIndex)")
                    imageIndex += 1
                    if let write {
                        try write(data, imageURL)
                    } else {
                        try data.write(to: imageURL, options: .atomic)
                    }
                    guard FileManager.default.isReadableFile(atPath: imageURL.path) else {
                        throw CodexStructuredClientError.imageMaterializationFailed
                    }
                    return .localImage(path: imageURL.path, detail: nil)
                }
            }
            return MaterializedImageInputs(inputs: inputs, temporaryDirectory: directory)
        } catch let error as CodexStructuredClientError {
            _ = try? FileManager.default.removeItem(at: directory)
            throw error
        } catch {
            _ = try? FileManager.default.removeItem(at: directory)
            throw CodexStructuredClientError.imageMaterializationFailed
        }
    }

    static func isImageInput(_ input: UserInput) -> Bool {
        switch input {
        case .imageURL, .image, .localImage:
            true
        default:
            false
        }
    }

    func registerImageDirectory(_ directory: URL) {
        materializedImageDirectories.insert(directory)
    }

    func deleteImageDirectory(_ directory: URL) {
        materializedImageDirectories.remove(directory)
        _ = try? FileManager.default.removeItem(at: directory)
    }

    func releaseAllImageDirectories() {
        let directories = materializedImageDirectories
        materializedImageDirectories.removeAll()
        for directory in directories {
            _ = try? FileManager.default.removeItem(at: directory)
        }
    }
}

extension CodexStructuredAgentClient {
    public func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try await client.initialize(params)
    }

    public func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        threadIdentityGeneration += 1
        let generation = threadIdentityGeneration
        pendingChildInterrupts.removeAll()
        currentThreadId = nil
        do {
            let response = try await client.threadStart(params)
            guard generation == threadIdentityGeneration else { return response }
            currentThreadId = response.thread.id
            committedThreadId = response.thread.id
            hasEstablishedThread = true
            lastThreadStartParams = params
            pendingResumeRollback = nil
            return response
        } catch {
            if generation == threadIdentityGeneration {
                currentThreadId = nil
                committedThreadId = nil
            }
            throw error
        }
    }

    public func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        threadIdentityGeneration += 1
        let generation = threadIdentityGeneration
        let previousThreadId = committedThreadId
        let previousThreadStartParams = lastThreadStartParams
        pendingChildInterrupts.removeAll()
        pendingResumeRollback = nil
        currentThreadId = nil
        do {
            let response = try await client.threadResume(params)
            guard generation == threadIdentityGeneration else { return response }
            currentThreadId = response.thread.id
            committedThreadId = response.thread.id
            hasEstablishedThread = true
            // 復元セッションでも reset で新 thread を開始できるよう、再開始可能な引数を捕捉する。
            lastThreadStartParams = Self.threadStartParams(from: params)
            pendingResumeRollback = (
                threadID: response.thread.id,
                previousThreadID: previousThreadId,
                previousThreadStartParams: previousThreadStartParams,
                generation: generation
            )
            return response
        } catch {
            if generation == threadIdentityGeneration {
                currentThreadId = previousThreadId
            }
            throw error
        }
    }

    /// resume 成功後の read 失敗で active thread だけが切り替わらないよう、
    /// 詳細取得まで終わった時点で currentThreadId と再開始引数を commit する。
    public func threadResumeAndRead(_ params: ThreadResumeParams) async throws -> ThreadSummary {
        threadIdentityGeneration += 1
        let generation = threadIdentityGeneration
        let previousThreadId = committedThreadId
        pendingChildInterrupts.removeAll()
        pendingResumeRollback = nil
        currentThreadId = nil
        do {
            let response = try await client.threadResume(params)
            let read = try await client.threadRead(ThreadReadParams(threadId: params.threadId, includeTurns: true))
            guard read.thread.id == params.threadId else {
                throw CodexAppServerClientError.threadIDMismatch(
                    requested: params.threadId,
                    received: read.thread.id
                )
            }
            guard generation == threadIdentityGeneration else { return read.thread }
            currentThreadId = response.thread.id
            committedThreadId = response.thread.id
            hasEstablishedThread = true
            lastThreadStartParams = Self.threadStartParams(from: params)
            pendingResumeRollback = nil
            return read.thread
        } catch {
            if generation == threadIdentityGeneration {
                currentThreadId = previousThreadId
            }
            throw error
        }
    }

    public func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        let response = try await client.threadRead(params)
        if pendingResumeRollback?.threadID == params.threadId,
           pendingResumeRollback?.generation == threadIdentityGeneration {
            pendingResumeRollback = nil
        }
        return response
    }

    /// VM の Codex 復元で read が失敗したときだけ、同じ世代の resume を元へ戻す。
    public func rollbackThreadResumeIfCurrent(threadID: String) {
        guard let pendingResumeRollback,
              pendingResumeRollback.threadID == threadID,
              pendingResumeRollback.generation == threadIdentityGeneration,
              currentThreadId == threadID else { return }
        currentThreadId = pendingResumeRollback.previousThreadID
        committedThreadId = pendingResumeRollback.previousThreadID
        lastThreadStartParams = pendingResumeRollback.previousThreadStartParams
        self.pendingResumeRollback = nil
    }

    /// store から復元でき、thread/read を省略した resume を確定する。
    public func commitThreadResumeIfCurrent(threadID: String) {
        guard pendingResumeRollback?.threadID == threadID,
              pendingResumeRollback?.generation == threadIdentityGeneration,
              currentThreadId == threadID else { return }
        pendingResumeRollback = nil
    }

    public func threadList(_ params: ThreadListParams = ThreadListParams()) async throws -> ThreadListResponse {
        try await client.threadList(params)
    }

    /// 子 thread 専用。`interrupt()` は現在の親 thread 用なので流用しない。
    public func turnInterrupt(_ params: TurnInterruptParams) async throws -> TurnInterruptResponse {
        pendingChildInterrupts[params.threadId] = params.turnId
        do {
            return try await client.turnInterrupt(params)
        } catch {
            if pendingChildInterrupts[params.threadId] == params.turnId {
                pendingChildInterrupts.removeValue(forKey: params.threadId)
            }
            throw error
        }
    }

    public func skillsList(_ params: SkillsListParams = SkillsListParams()) async throws -> SkillsListResponse {
        try await client.skillsList(params)
    }

    public func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try await client.listModels(params)
    }

    public func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try await client.listPermissionProfiles(params)
    }

    public func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try await client.listCollaborationModes(params)
    }

    public func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        // `CodexStructuredAgentClient` は actor でも await 中に再入される。
        // モデル変更が先に入った場合は capability を即時無効化し、後続の画像 turn/start を拒否する。
        // 画像送信が先に入っていた場合は設定変更自体を拒否して、送信中のモデルを不変にする。
        let changesModel = params.model != nil || params.collaborationMode != nil
        if changesModel {
            guard !imageTurnInFlight else {
                throw CodexStructuredClientError.imageTurnInProgress
            }
            nativeImageInputEnabled = false
            modelChangeInFlight = true
        }
        defer {
            if changesModel {
                modelChangeInFlight = false
            }
        }
        return try await client.updateThreadSettings(params)
    }

    public static func normalizedEvent(from event: ThreadEvent) -> NormalizedChatEvent? {
        switch event {
        case .agentMessageDelta(_, _, let itemId, let delta):
            .agentMessageDelta(itemId: itemId, delta)
        case .reasoningSummaryDelta(_, _, let itemId, let delta):
            .reasoningDelta(itemId: itemId, delta)
        case .commandOutputDelta(_, _, let itemId, let delta):
            .commandExecution(itemId: itemId, command: nil, outputDelta: delta)
        case .filePatchUpdated(_, _, let itemId, let changes):
            .fileChange(itemId: itemId, changes.map {
                StructuredChatKit.FilePatchChange(path: $0.path, diff: $0.diff, kind: $0.kind?.stringValue)
            })
        case .turnStarted:
            .turnStarted
        case .turnCompleted(let threadId, let turn):
            turn.status == "interrupted"
                ? .turnInterrupted(nativeSessionId: threadId)
                : .turnCompleted(nativeSessionId: threadId)
        case .turnInterrupted(let threadId, _):
            .turnInterrupted(nativeSessionId: threadId)
        case .planUpdated(_, _, let plan, _):
            .taskListUpdated(tasks: plan.enumerated().compactMap { index, step in
                let status: AgentTaskStatus
                switch step.status {
                case .pending:
                    status = .pending
                case .inProgress:
                    status = .inProgress
                case .completed:
                    status = .completed
                case .unknown:
                    return nil
                }
                return AgentTaskItem(id: "codex-plan-\(index)-\(step.step)", title: step.step, status: status)
            })
        case .skillsChanged:
            nil
        case .error(_, _, let message, let willRetry):
            willRetry == true ? .warning(message: message) : .error(message: message)
        case .warning(_, let message):
            .warning(message: message)
        case .tokenUsageUpdated(_, _, let tokenUsage):
            {
                // Context occupancy is approximated by the most recent request,
                // so prefer last.totalTokens over cumulative total.totalTokens.
                let contextUsedTokens = tokenUsage.last?.totalTokens ?? tokenUsage.total?.totalTokens
                let contextWindowTokens = tokenUsage.modelContextWindow
                guard contextUsedTokens != nil || contextWindowTokens != nil else { return nil }
                return .turnUsage(TurnUsage(
                    contextUsedTokens: contextUsedTokens,
                    contextWindowTokens: contextWindowTokens
                ))
            }()
        case .itemStarted, .itemCompleted, .threadStatusChanged, .threadSettingsUpdated:
            nil
        }
    }
}
