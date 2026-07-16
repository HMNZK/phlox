import Observation

/// Composition Root（architecture.md §7）。アプリ全体の依存を 1 箇所で組み立てる。
///
/// - プロトコル（DI シーム）**のみ**に依存し、具象実装（Keychain / URLSession / actor）を知らない。
/// - 本番依存（`live`）の組み立ては App ターゲット（`App/AppEnvironment.swift`）が担う。
///   PhloxCore はテスト・Preview 用の `stub` を提供する。
/// - SwiftUI 環境へ注入できるよう `@Observable`。格納依存は不変（`let`）で、ライフタイム中に
///   差し替わらない。ビジネスロジックは持たない（配線のみ）。
@Observable
public final class AppEnvironment {
    public let tokenStore: TokenStore
    public let authenticator: Authenticating
    public let apiClient: PhloxAPI
    public let reachability: ReachabilityMonitoring
    public let sessionRepository: SessionRepositoryProtocol
    public let auditLog: AuditLogging

    public init(
        tokenStore: TokenStore,
        authenticator: Authenticating,
        apiClient: PhloxAPI,
        reachability: ReachabilityMonitoring,
        sessionRepository: SessionRepositoryProtocol,
        auditLog: AuditLogging
    ) {
        self.tokenStore = tokenStore
        self.authenticator = authenticator
        self.apiClient = apiClient
        self.reachability = reachability
        self.sessionRepository = sessionRepository
        self.auditLog = auditLog
    }
}

public extension AppEnvironment {
    /// テスト・Preview 用の完全インメモリ環境。
    /// 任意で初期セッション/承認を注入できる（一覧・承認画面の Preview 用）。
    static func stub(
        sessions: [Session] = [],
        approvals: [Approval] = []
    ) -> AppEnvironment {
        AppEnvironment(
            tokenStore: InMemoryTokenStore(),
            authenticator: StubAuthenticator(allows: true),
            apiClient: StubPhloxAPI(sessions: sessions, approvals: approvals),
            reachability: StubReachability(.online),
            sessionRepository: StubSessionRepository(snapshot: sessions),
            auditLog: InMemoryAuditLog()
        )
    }
}
