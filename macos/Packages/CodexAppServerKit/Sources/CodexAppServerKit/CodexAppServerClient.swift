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
    case tokenUsageUpdated(threadId: String, turnId: String, tokenUsage: ThreadTokenUsage)
    case threadStatusChanged(threadId: String, status: ThreadStatus)
    case threadSettingsUpdated(threadId: String, threadSettings: ThreadSettings)
    case error(threadId: String?, turnId: String?, message: String, willRetry: Bool?)
    case warning(threadId: String?, message: String)
}

public actor CodexAppServerClient {
    private struct ActiveTurn: Hashable {
        let threadId: String
        let turnId: String?
    }

    private let rpc: JSONRPCClient
    private var notificationTask: Task<Void, Never>?
    private var activeTurns: Set<ActiveTurn> = []
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
        try await rpc.request(method: "thread/resume", params: params)
    }

    public func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        try await rpc.request(method: "thread/read", params: params)
    }

    public func turnStart(_ params: TurnStartParams) async throws -> TurnStartResponse {
        markTurnActive(threadId: params.threadId, turnId: nil)
        do {
            return try await rpc.request(method: "turn/start", params: params)
        } catch {
            activeTurns = activeTurns.filter { $0.threadId != params.threadId }
            throw error
        }
    }

    public func turnInterrupt(_ params: TurnInterruptParams) async throws -> TurnInterruptResponse {
        try await rpc.request(method: "turn/interrupt", params: params)
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
        updateActiveTurns(for: event)
        eventContinuation.yield(event)
    }

    private func notificationStreamDidFinish() {
        guard !closeRequested else {
            eventContinuation.finish()
            return
        }

        for turn in activeTurns {
            eventContinuation.yield(.error(
                threadId: turn.threadId,
                turnId: turn.turnId,
                message: "Codex app-server process exited before the turn completed",
                willRetry: false
            ))
        }
        activeTurns.removeAll()
        eventContinuation.finish()
    }

    private func updateActiveTurns(for event: ThreadEvent) {
        switch event {
        case .turnStarted(let threadId, let turn):
            markTurnActive(threadId: threadId, turnId: turn.id)
        case .turnCompleted(let threadId, _), .turnInterrupted(let threadId, _):
            activeTurns = activeTurns.filter { $0.threadId != threadId }
        case .error(let threadId, let turnId, _, let willRetry):
            if willRetry == true {
                if let threadId {
                    markTurnActive(threadId: threadId, turnId: turnId)
                }
            } else if let threadId {
                activeTurns = activeTurns.filter { $0.threadId != threadId }
            } else {
                activeTurns.removeAll()
            }
        default:
            break
        }
    }

    private func markTurnActive(threadId: String, turnId: String?) {
        activeTurns = activeTurns.filter { $0.threadId != threadId }
        activeTurns.insert(ActiveTurn(threadId: threadId, turnId: turnId))
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

public actor CodexStructuredAgentClient: StructuredAgentClient {
    private let client: CodexAppServerClient
    private var bridgeTask: Task<Void, Never>?
    private var currentThreadId: String?
    /// resetConversation で新規 thread を開始し直すために、直近の thread/start 引数を保持する。
    private var lastThreadStartParams: ThreadStartParams?
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    public nonisolated let events: AsyncStream<NormalizedChatEvent>
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    public nonisolated let threadEvents: AsyncStream<ThreadEvent>

    public init(client: CodexAppServerClient) {
        self.client = client
        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!

        var threadEventContinuation: AsyncStream<ThreadEvent>.Continuation?
        self.threadEvents = AsyncStream { threadEventContinuation = $0 }
        self.threadEventContinuation = threadEventContinuation!
    }

    deinit {
        bridgeTask?.cancel()
        eventContinuation.finish()
        threadEventContinuation.finish()
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
        if input.contains(where: { chatInput in
            if case .image = chatInput { return true }
            return false
        }) {
            eventContinuation.yield(.warning(message: "画像添付は Claude のみ対応"))
        }
        _ = try await client.turnStart(TurnStartParams(
            threadId: currentThreadId,
            input: input.compactMap { chatInput in
                switch chatInput {
                case .text(let text):
                    return .text(text)
                case .image:
                    return nil
                }
            }
        ))
    }

    public func resume(sessionRef: String) async throws {
        let params = ThreadResumeParams(threadId: sessionRef)
        let response = try await client.threadResume(params)
        currentThreadId = response.thread.id
        lastThreadStartParams = Self.threadStartParams(from: params)
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
        guard let currentThreadId else { return }
        _ = try await client.turnInterrupt(TurnInterruptParams(threadId: currentThreadId))
    }

    /// 会話文脈をリセットする。app-server は特定メッセージ時点への巻き戻し API を持たないため、
    /// 直近の thread/start 引数で「新しい thread」を開始し、以後の turnStart をそちらへ向ける。
    /// 新 threadId は turn/completed などのイベントで VM も観測できる。thread/start が未実施、
    /// または再開始に失敗した場合は currentThreadId を nil にし、次の turnStart を threadNotStarted
    /// で明示的に失敗させる（旧 thread への誤送信を避ける）。
    public func resetConversation() async {
        guard let params = lastThreadStartParams else {
            currentThreadId = nil
            return
        }
        do {
            let response = try await client.threadStart(params)
            currentThreadId = response.thread.id
        } catch {
            currentThreadId = nil
        }
    }

    public func close() async {
        bridgeTask?.cancel()
        bridgeTask = nil
        await client.close()
        finish()
    }

    private func yield(_ event: ThreadEvent) {
        // reset 後も app-server 上で生き残る旧 thread の遅延イベントを source で遮断する。
        // 現在の thread が確定していて（currentThreadId != nil）、イベントの thread id が
        // それと異なるなら、旧 thread 由来なので両ストリームへ流さない（normalized delta も含む）。
        // currentThreadId 未確定（起動直後）や thread id を持たないイベントは通す（正常経路を壊さない）。
        if let currentThreadId,
           let eventThreadId = Self.threadId(of: event),
           !eventThreadId.isEmpty,
           eventThreadId != currentThreadId {
            return
        }
        threadEventContinuation.yield(event)
        if let normalized = Self.normalizedEvent(from: event) {
            eventContinuation.yield(normalized)
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
        case .error(let threadId, _, _, _):
            return threadId
        case .warning(let threadId, _):
            return threadId
        }
    }

    private func finish() {
        eventContinuation.finish()
        threadEventContinuation.finish()
    }
}

public enum CodexStructuredClientError: Error, Equatable, Sendable {
    case threadNotStarted
}

extension CodexStructuredAgentClient {
    public func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try await client.initialize(params)
    }

    public func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        let response = try await client.threadStart(params)
        currentThreadId = response.thread.id
        lastThreadStartParams = params
        return response
    }

    public func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        let response = try await client.threadResume(params)
        currentThreadId = response.thread.id
        // 復元セッションでも reset で新 thread を開始できるよう、再開始可能な引数を捕捉する。
        lastThreadStartParams = Self.threadStartParams(from: params)
        return response
    }

    public func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        let response = try await client.threadRead(params)
        currentThreadId = response.thread.id
        return response
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
        try await client.updateThreadSettings(params)
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
        case .turnCompleted(let threadId, _):
            .turnCompleted(nativeSessionId: threadId)
        case .turnInterrupted(let threadId, _):
            .turnInterrupted(nativeSessionId: threadId)
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
