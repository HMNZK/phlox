import Foundation

// テスト・Xcode Preview 用のインメモリスタブ実装群。
// 本番実装（実 Keychain / URLSession / NWPathMonitor）は E3-x で各モジュールに実装される。
// Swift 6 strict concurrency 準拠: 可変状態を持つものは actor、不変のものは Sendable struct。

/// インメモリ `TokenStore`。保存値を actor で保護する。
public actor InMemoryTokenStore: TokenStore {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func save(_ token: String) async throws { self.token = token }
    public func load() async throws -> String? { token }
    public func delete() async throws { token = nil }
}

/// 常に許可（または常に拒否）を返す生体認証スタブ。
public struct StubAuthenticator: Authenticating {
    public let allows: Bool

    public init(allows: Bool = true) {
        self.allows = allows
    }

    public func authenticate(reason: String) async throws -> Bool { allows }
}

/// 固定データを返す `PhloxAPI` スタブ。書き込み系は no-op。
public struct StubPhloxAPI: PhloxAPI {
    public let sessions: [Session]
    public let approvals: [Approval]
    public let outputText: String
    public let chatMessages: [ChatMessage]

    public init(
        sessions: [Session] = [],
        approvals: [Approval] = [],
        outputText: String = "",
        chatMessages: [ChatMessage] = []
    ) {
        self.sessions = sessions
        self.approvals = approvals
        self.outputText = outputText
        self.chatMessages = chatMessages
    }

    public func listSessions() async throws -> [Session] { sessions }
    public func waitUntilReady(sessionID: String) async throws -> Bool { true }
    public func approvals() async throws -> [Approval] { approvals }
    public func output(sessionID: String) async throws -> String { outputText }
    public func messages(sessionID: String) async throws -> [ChatMessage] { chatMessages }
    public func remove(sessionID: String) async throws {}
    public func rename(sessionID: String, name: String) async throws {}
    public func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    public func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }

    public func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(
            id: UUID().uuidString,
            name: "Stub",
            agent: request.agent,
            status: .starting,
            subtitle: request.workspace,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

/// 固定の到達性を返すスタブ。
public struct StubReachability: ReachabilityMonitoring {
    public let value: Reachability

    public init(_ value: Reachability = .online) {
        self.value = value
    }

    public var current: Reachability {
        get async { value }
    }

    public func refresh() async {}

    public func stream() -> AsyncStream<Reachability> {
        let value = value
        return AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }
}

/// 任意の `SessionsState` シーケンスを順に流して終了するスタブリポジトリ。
public struct StubSessionRepository: SessionRepositoryProtocol {
    public let states: [SessionsState]

    public init(states: [SessionsState]) {
        self.states = states
    }

    /// セッション配列スナップショットから 1 状態（空なら `.empty`、それ以外 `.loaded`）を作る簡便 init。
    public init(snapshot: [Session] = []) {
        self.states = [snapshot.isEmpty ? .empty : .loaded(snapshot)]
    }

    public func sessionStream(interval: Duration) -> AsyncStream<SessionsState> {
        let states = states
        return AsyncStream { continuation in
            for state in states {
                continuation.yield(state)
            }
            continuation.finish()
        }
    }

    public func refresh() async throws {}
}

/// インメモリ監査ログ。記録を actor で保護し、新しい順で返す。
public actor InMemoryAuditLog: AuditLogging {
    private var entries: [AuditEntry] = []

    public init() {}

    public func record(_ operation: AuditOperation) async {
        entries.append(AuditEntry(operation, at: Date()))
    }

    public func recentEntries(limit: Int) async -> [AuditEntry] {
        Array(entries.reversed().prefix(max(0, limit)))
    }
}
