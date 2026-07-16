import Foundation
import PhloxCore

/// Features の ViewModel テスト用に設定可能な PhloxAPI モック（actor で Sendable）。
actor MockAPI: PhloxAPI {
    var sessions: [Session]
    let approvalsList: [Approval]
    let spawnOutcome: Result<Session, PhloxError>
    let sendOutcome: Result<SendResult, PhloxError>
    var outputOutcome: Result<String, PhloxError>
    var messagesOutcome: Result<[ChatMessage], PhloxError>
    let removeError: PhloxError?
    let respondError: PhloxError?

    private(set) var spawnCount = 0
    private(set) var readyCount = 0
    private(set) var removeCount = 0
    private(set) var sendCount = 0
    private(set) var respondLog: [(String, ApprovalDecision)] = []

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
    /// subAgents の結果と呼び出し回数。
    var subAgentsOutcome: Result<[SubAgentSummary], PhloxError> = .success([])
    private(set) var subAgentsCount = 0
    /// subAgentMessages の結果と、渡された (sessionID, subAgentID) の記録。
    var subAgentMessagesOutcome: Result<[ChatMessage], PhloxError> = .success([])
    private(set) var subAgentMessagesLog: [(String, String)] = []

    static let defaultSession = Session(
        id: "new", name: "New", agent: .claudeCode, status: .starting,
        subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
    )

    init(
        sessions: [Session] = [],
        approvalsList: [Approval] = [],
        spawnOutcome: Result<Session, PhloxError> = .success(MockAPI.defaultSession),
        sendOutcome: Result<SendResult, PhloxError> = .success(SendResult(accepted: true)),
        outputOutcome: Result<String, PhloxError> = .success(""),
        messagesOutcome: Result<[ChatMessage], PhloxError> = .success([]),
        removeError: PhloxError? = nil,
        respondError: PhloxError? = nil
    ) {
        self.sessions = sessions
        self.approvalsList = approvalsList
        self.spawnOutcome = spawnOutcome
        self.sendOutcome = sendOutcome
        self.outputOutcome = outputOutcome
        self.messagesOutcome = messagesOutcome
        self.removeError = removeError
        self.respondError = respondError
    }

    func listSessions() async throws -> [Session] { sessions }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        spawnCount += 1
        return try spawnOutcome.get()
    }

    func waitUntilReady(sessionID: String) async throws -> Bool {
        readyCount += 1
        return true
    }

    func send(_ request: SendRequest) async throws -> SendResult {
        sendCount += 1
        lastSentRequest = request
        return try sendOutcome.get()
    }

    func output(sessionID: String) async throws -> String {
        try outputOutcome.get()
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        try messagesOutcome.get()
    }

    /// テストでポーリング更新を模すため、messages の結果を差し替える。
    func setMessagesOutcome(_ outcome: Result<[ChatMessage], PhloxError>) {
        messagesOutcome = outcome
    }

    /// テストで output の復帰（失敗→成功）を模すため、output の結果を差し替える。
    func setOutputOutcome(_ outcome: Result<String, PhloxError>) {
        outputOutcome = outcome
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

    // MARK: - API 拡張の実装（既定 501 を上書き。task-9 受け入れ用）

    /// listSessions の結果を差し替える（running→idle 遷移の模擬に使う）。
    func setSessions(_ newSessions: [Session]) {
        sessions = newSessions
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

    func setSubAgentsOutcome(_ outcome: Result<[SubAgentSummary], PhloxError>) {
        subAgentsOutcome = outcome
    }

    func setSubAgentMessagesOutcome(_ outcome: Result<[ChatMessage], PhloxError>) {
        subAgentMessagesOutcome = outcome
    }

    func subAgents(sessionID: String) async throws -> [SubAgentSummary] {
        subAgentsCount += 1
        return try subAgentsOutcome.get()
    }

    func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage] {
        subAgentMessagesLog.append((sessionID, subAgentID))
        return try subAgentMessagesOutcome.get()
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
        deltaSinceLog.append(since)
        guard !messagesDeltaScript.isEmpty else {
            throw PhloxError.server(status: 501, message: "messagesDelta: 旧サーバー（テスト既定）")
        }
        return try messagesDeltaScript.removeFirst().get()
    }
}
