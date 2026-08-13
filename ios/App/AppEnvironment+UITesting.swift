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
                // 実環境の再現: 承認は保留中でもチャットのポーリング状態は running に戻りうる。
                status: .running,
                subtitle: "実行中",
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

    /// Mac が色つきの端末画面を配信できたときの経路。UI テストで実描画を確かめるため、
    /// SGR 入りの本文と Mac 側の桁数を返す。
    func terminalScreen(sessionID: String) async throws -> TerminalScreen {
        TerminalScreen(
            text: "\u{1B}[0;32m›\u{1B}[0m running tests...\n\u{1B}[0;1;33mOK\u{1B}[0m",
            cols: 80
        )
    }
    /// スクリーンショット・目視確認用の代表的な transcript。
    /// ツール実行グループ（コマンド原文の見出し）・ファイル変更の diff コードビュー・Reasoning を 1 画面に含める。
    func messages(sessionID: String) async throws -> [ChatMessage] {
        [
            .user(id: "m1", text: "チャットのツール表示をモバイルにも入れて"),
            .reasoning(id: "m2", text: "既存の器を確認する"),
            .reasoning(
                id: "m3",
                text: "# 方針\nデスクトップと同じ規則を共有パッケージから呼び、モバイルの余白は保つ。"
            ),
            .command(id: "m4", command: "Read ios/Packages/PhloxKit/Package.swift", output: "// swift-tools-version: 6.0"),
            .command(
                id: "m5",
                command: "swift test --package-path ios/Packages/PhloxKit",
                output: "Test run with 693 tests in 135 suites passed after 0.19 seconds."
            ),
            .fileChange(
                id: "m6",
                changes: [
                    ChatFileChange(
                        path: "ios/Packages/PhloxKit/Sources/Features/SessionDetail/SessionDetailFileChangeCard.swift",
                        diff: """
                        --- a/SessionDetailFileChangeCard.swift
                        +++ b/SessionDetailFileChangeCard.swift
                        @@ -12,6 +12,8 @@
                         struct SessionDetailFileChangeCard: View {
                             let data: SessionDetailDiffCodeViewData
                        -    let isExpanded: Bool
                        +    /// 既定は折りたたみ。行数に依存した自動展開はしない（ADR 0147）。
                        +    @State private var userExpandedOverride: Bool?
                        +    @ScaledMetric private var lineNumberWidth: CGFloat = 8
                             var body: some View {
                        """,
                        kind: "edit"
                    ),
                ]
            ),
            .agent(id: "m7", text: "モバイルにも同じ表示を入れました。"),
        ]
    }
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
