import Foundation
import PhloxCore

/// Features の ViewModel テスト用に設定可能な PhloxAPI モック（actor で Sendable）。
actor MockAPI: PhloxAPI {
    var sessions: [Session]
    var listSessionsError: PhloxError?
    let approvalsList: [Approval]
    let spawnOutcome: Result<Session, PhloxError>
    let sendOutcome: Result<SendResult, PhloxError>
    var messagesOutcome: Result<[ChatMessage], PhloxError>
    var agentSettingsOutcome: Result<AgentSettings?, PhloxError> = .success(nil)
    var projectsOutcome: Result<[ProjectSummary]?, PhloxError> = .success(nil)
    var cliUsageOutcome: Result<[CLIUsage], PhloxError> = .success([])
    let removeError: PhloxError?
    let respondError: PhloxError?
    var respondToQuestionError: PhloxError?

    private(set) var spawnCount = 0
    private(set) var readyCount = 0
    private(set) var removeCount = 0
    private(set) var sendCount = 0
    private(set) var messagesCount = 0
    private(set) var messagesDeltaCount = 0
    private(set) var listSessionsCount = 0
    private(set) var projectsCount = 0
    private(set) var cliUsageCount = 0
    private(set) var respondLog: [(String, ApprovalDecision)] = []
    private(set) var respondToQuestionLog: [(sessionID: String, requestId: String, answers: [String: [String]])] = []

    // MARK: - API 拡張（task-9 の受け入れ用ハーネス。additive）
    /// interrupt の結果と呼び出し回数。
    var interruptOutcome: Result<Void, PhloxError> = .success(())
    private(set) var interruptCount = 0
    /// usage の結果と呼び出し回数。
    var usageOutcome: Result<TurnUsage?, PhloxError> = .success(nil)
    private(set) var usageCount = 0
    /// messagesDelta の応答を FIFO で消費するスクリプト。空なら 501（旧サーバー）を投げ、
    /// クライアント側フォールバック（messages 全量取得）を誘発する。
    var messagesDeltaScript: [Result<MessagesDelta, PhloxError>] = []
    /// messagesDelta に渡された since を記録（cursor 引き継ぎ検証用）。
    private(set) var deltaSinceLog: [String?] = []
    /// 直近の send リクエスト（images 添付の検証用）。
    private(set) var lastSentRequest: SendRequest?
    private var pausesSend = false
    private var sendContinuation: CheckedContinuation<Void, Never>?
    private var sendWaiters: [CheckedContinuation<Void, Never>] = []

    func pauseNextSend() { pausesSend = true }
    func waitForSend() async {
        if sendCount > 0 { return }
        await withCheckedContinuation { sendWaiters.append($0) }
    }
    func resumeSend() {
        sendContinuation?.resume()
        sendContinuation = nil
    }
    /// 直近の spawn リクエスト（projectID の伝搬検証用）。
    private(set) var lastSpawnRequest: SpawnRequest?

    static let defaultSession = Session(
        id: "new", name: "New", agent: .claudeCode, status: .starting,
        subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
    )

    init(
        sessions: [Session] = [],
        approvalsList: [Approval] = [],
        spawnOutcome: Result<Session, PhloxError> = .success(MockAPI.defaultSession),
        sendOutcome: Result<SendResult, PhloxError> = .success(SendResult(accepted: true)),
        messagesOutcome: Result<[ChatMessage], PhloxError> = .success([]),
        removeError: PhloxError? = nil,
        respondError: PhloxError? = nil,
        respondToQuestionError: PhloxError? = nil
    ) {
        self.sessions = sessions
        self.approvalsList = approvalsList
        self.spawnOutcome = spawnOutcome
        self.sendOutcome = sendOutcome
        self.messagesOutcome = messagesOutcome
        self.removeError = removeError
        self.respondError = respondError
        self.respondToQuestionError = respondToQuestionError
    }

    func listSessions() async throws -> [Session] {
        listSessionsCount += 1
        if let listSessionsError { throw listSessionsError }
        return sessions
    }
    func agentSettings(kind: AgentKind) async throws -> AgentSettings? {
        try agentSettingsOutcome.get()
    }
    func projects() async throws -> [ProjectSummary]? {
        projectsCount += 1
        return try projectsOutcome.get()
    }

    func cliUsage() async throws -> [CLIUsage] {
        cliUsageCount += 1
        return try cliUsageOutcome.get()
    }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        spawnCount += 1
        lastSpawnRequest = request
        return try spawnOutcome.get()
    }

    func waitUntilReady(sessionID: String) async throws -> Bool {
        readyCount += 1
        return true
    }

    func send(_ request: SendRequest) async throws -> SendResult {
        sendCount += 1
        lastSentRequest = request
        if pausesSend {
            pausesSend = false
            await withCheckedContinuation { continuation in
                sendContinuation = continuation
                sendWaiters.forEach { $0.resume() }
                sendWaiters.removeAll()
            }
        }
        return try sendOutcome.get()
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        messagesCount += 1
        return try messagesOutcome.get()
    }

    /// テストでポーリング更新を模すため、messages の結果を差し替える。
    func setMessagesOutcome(_ outcome: Result<[ChatMessage], PhloxError>) {
        messagesOutcome = outcome
    }

    func remove(sessionID: String) async throws {
        removeCount += 1
        if let removeError { throw removeError }
    }

    func approvals() async throws -> [Approval] { approvalsList }

    func respond(approvalID: String, decision: ApprovalDecision) async throws {
        respondLog.append((approvalID, decision))
        if let respondError { throw respondError }
    }

    func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws {
        respondToQuestionLog.append((sessionID, requestId, answers))
        if let respondToQuestionError { throw respondToQuestionError }
    }

    // MARK: - API 拡張の実装（既定 501 を上書き。task-9 受け入れ用）

    /// listSessions の結果を差し替える（running→idle 遷移の模擬に使う）。
    func setSessions(_ newSessions: [Session]) {
        sessions = newSessions
    }

    func setListSessionsError(_ error: PhloxError?) {
        listSessionsError = error
    }

    func setInterruptOutcome(_ outcome: Result<Void, PhloxError>) {
        interruptOutcome = outcome
    }

    func setUsageOutcome(_ outcome: Result<TurnUsage?, PhloxError>) {
        usageOutcome = outcome
    }

    func setMessagesDeltaScript(_ script: [Result<MessagesDelta, PhloxError>]) {
        messagesDeltaScript = script
    }

    func setAgentSettingsOutcome(_ outcome: Result<AgentSettings?, PhloxError>) {
        agentSettingsOutcome = outcome
    }

    func setProjectsOutcome(_ outcome: Result<[ProjectSummary]?, PhloxError>) {
        projectsOutcome = outcome
    }

    func setCLIUsageOutcome(_ outcome: Result<[CLIUsage], PhloxError>) {
        cliUsageOutcome = outcome
    }

    func interrupt(sessionID: String) async throws {
        interruptCount += 1
        try interruptOutcome.get()
    }

    func usage(sessionID: String) async throws -> TurnUsage? {
        usageCount += 1
        return try usageOutcome.get()
    }

    func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta {
        messagesDeltaCount += 1
        deltaSinceLog.append(since)
        guard !messagesDeltaScript.isEmpty else {
            throw PhloxError.server(status: 501, message: "messagesDelta: 旧サーバー（テスト既定）")
        }
        return try messagesDeltaScript.removeFirst().get()
    }
}
