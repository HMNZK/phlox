import Foundation
import PhloxCore

/// UI テスト用 Composition Root。実 Keychain / 実ネットワークは使わない。
@MainActor
extension AppEnvironment {
    static func uiTesting(
        scenario: UITestingSupport.Scenario = UITestingSupport.scenario,
        screen: UITestingSupport.Screen? = UITestingSupport.screen
    ) -> AppEnvironment {
        if let screen {
            return environment(for: screen)
        }
        switch scenario {
        case .goldenPath:
            return goldenPath()
        case .empty:
            return AppEnvironment.stub(sessions: [])
        case .launchGate:
            return AppEnvironment(
                tokenStore: InMemoryTokenStore(),
                authenticator: StubAuthenticator(allows: false),
                apiClient: StubPhloxAPI(),
                reachability: StubReachability(.online),
                sessionRepository: StubSessionRepository(states: [.empty]),
                auditLog: InMemoryAuditLog()
            )
        }
    }

    private static func environment(for screen: UITestingSupport.Screen) -> AppEnvironment {
        switch screen {
        case .connectionSettings, .launchGate:
            return AppEnvironment(
                tokenStore: InMemoryTokenStore(),
                authenticator: StubAuthenticator(allows: screen != .launchGate),
                apiClient: StubPhloxAPI(),
                reachability: StubReachability(.online),
                sessionRepository: StubSessionRepository(states: [.empty]),
                auditLog: InMemoryAuditLog()
            )
        case .empty:
            return AppEnvironment.stub(sessions: [])
        case .unreachable:
            return AppEnvironment(
                tokenStore: InMemoryTokenStore(token: "ui-test-token"),
                authenticator: StubAuthenticator(allows: true),
                apiClient: StubPhloxAPI(),
                reachability: StubReachability(.unreachableHost),
                sessionRepository: StubSessionRepository(states: [.offline]),
                auditLog: InMemoryAuditLog()
            )
        case .codexApproval:
            return codexApprovalPath()
        case .chatAnswer:
            return chatAnswerPath()
        default:
            return goldenPath()
        }
    }

    private static func chatAnswerPath() -> AppEnvironment {
        let sessions = [
            Session(
                id: "sess-tulip",
                name: "add /approvals endpo…",
                agent: .codex,
                status: .awaitingApproval(
                    prompt: "/approvals のレスポンス契約は\nv2（id・session・kind・prompt を含む）で進めますか？\n最小の id だけにしますか？"
                ),
                subtitle: "回答待ち: 「v2 契約で進めますか？」",
                updatedAt: Date()
            ),
        ]
        return AppEnvironment(
            tokenStore: InMemoryTokenStore(token: "ui-test-token"),
            authenticator: StubAuthenticator(allows: true),
            apiClient: UITestPhloxAPI(sessions: sessions, approvals: []),
            reachability: StubReachability(.online),
            sessionRepository: StubSessionRepository(states: [.loaded(sessions)]),
            auditLog: InMemoryAuditLog()
        )
    }

    private static func goldenPath() -> AppEnvironment {
        let sessions = [
            Session(
                id: "sess-rose",
                name: "Rose",
                agent: .claudeCode,
                status: .awaitingApproval(prompt: "ControlServer.swift を削除して続行しますか？"),
                subtitle: "承認待ち",
                updatedAt: Date()
            ),
            Session(
                id: "sess-tulip",
                name: "Tulip",
                agent: .codex,
                status: .running,
                subtitle: "実行中",
                updatedAt: Date()
            ),
        ]
        let approvals = [
            Approval(
                id: "appr-1",
                sessionID: "sess-rose",
                kind: .claudeCode,
                prompt: "ControlServer.swift を削除して続行しますか？"
            ),
        ]
        return AppEnvironment(
            tokenStore: InMemoryTokenStore(token: "ui-test-token"),
            authenticator: StubAuthenticator(allows: true),
            apiClient: UITestPhloxAPI(sessions: sessions, approvals: approvals),
            reachability: StubReachability(.online),
            sessionRepository: StubSessionRepository(states: [.loaded(sessions)]),
            auditLog: InMemoryAuditLog()
        )
    }

    private static func codexApprovalPath() -> AppEnvironment {
        let sessions = [
            Session(
                id: "sess-codex",
                name: "Mint",
                agent: .codex,
                status: .awaitingApproval(prompt: "add /approvals endpoint · Codex"),
                subtitle: "承認待ち",
                updatedAt: Date()
            ),
        ]
        let approvals = [
            Approval(
                id: "appr-codex",
                sessionID: "sess-codex",
                kind: .codex,
                prompt: "add /approvals endpoint · Codex"
            ),
        ]
        return AppEnvironment(
            tokenStore: InMemoryTokenStore(token: "ui-test-token"),
            authenticator: StubAuthenticator(allows: true),
            apiClient: UITestPhloxAPI(sessions: sessions, approvals: approvals),
            reachability: StubReachability(.online),
            sessionRepository: StubSessionRepository(states: [.loaded(sessions)]),
            auditLog: InMemoryAuditLog()
        )
    }
}

/// spawn 時に安定 ID を返す UI テスト用 API スタブ。
private struct UITestPhloxAPI: PhloxAPI {
    let sessions: [Session]
    let approvals: [Approval]

    func listSessions() async throws -> [Session] { sessions }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func approvals() async throws -> [Approval] { approvals }
    func output(sessionID: String) async throws -> String { "› running tests...\nOK" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(
            id: "sess-spawned",
            name: "UITest Spawn",
            agent: request.agent,
            status: .running,
            subtitle: request.workspace,
            updatedAt: Date()
        )
    }
}
