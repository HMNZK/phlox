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
        case .sessionShell, .sessionShellDetail:
            return shellEnvironment(sessions: shellSessions)
        case .sessionShellNoAttention:
            return shellEnvironment(sessions: shellSessions.filter { !$0.needsAttention })
        case .sessionShellScrolled:
            return shellEnvironment(sessions: scrolledShellSessions)
        case .sessionShellOffline:
            return shellEnvironment(sessions: shellSessions, reachability: .unreachableHost)
        case .list, .listCollapsed, .listChildrenExpanded, .listSE, .listDT:
            return listEnvironment(sessions: listSessions, state: .loaded(listSessions))
        case .listMulti:
            return listEnvironment(sessions: listMultiSessions, state: .loaded(listMultiSessions))
        case .listAllAttention:
            return listEnvironment(sessions: listAttentionSessions, state: .loaded(listAttentionSessions))
        case .listLoading:
            return listEnvironment(sessions: [], state: .loading)
        case .listJudging:
            return listEnvironment(sessions: [], state: .loading, reachability: .unknown)
        case .listEmpty:
            return listEnvironment(sessions: [], state: .empty)
        case .listOffNet:
            return listEnvironment(sessions: [], state: .offline, reachability: .offlineNetwork)
        case .listOffHost:
            return listEnvironment(sessions: [], state: .offline, reachability: .unreachableHost)
        case .listOffUnknown:
            return listEnvironment(sessions: [], state: .offline, reachability: .unknown)
        case .listError:
            return listEnvironment(sessions: [], state: .error(.server(status: 500, message: "Internal Server Error")))
        case .listError401:
            return listEnvironment(sessions: [], state: .error(.unauthorized))
        default:
            return goldenPath()
        }
    }

    private static func shellEnvironment(
        sessions: [Session],
        reachability: Reachability = .online
    ) -> AppEnvironment {
        AppEnvironment(
            tokenStore: InMemoryTokenStore(token: "ui-test-token"),
            authenticator: StubAuthenticator(allows: true),
            apiClient: UITestPhloxAPI(sessions: sessions, approvals: []),
            reachability: StubReachability(reachability),
            sessionRepository: StubSessionRepository(snapshot: sessions),
            auditLog: InMemoryAuditLog()
        )
    }

    private static func listEnvironment(
        sessions: [Session],
        state: SessionsState,
        reachability: Reachability = .online
    ) -> AppEnvironment {
        AppEnvironment(
            tokenStore: InMemoryTokenStore(token: "ui-test-token"),
            authenticator: StubAuthenticator(allows: true),
            apiClient: UITestPhloxAPI(sessions: sessions, approvals: [], projectList: listProjects),
            reachability: StubReachability(reachability),
            sessionRepository: StubSessionRepository(states: [state]),
            auditLog: InMemoryAuditLog()
        )
    }

    private static var shellSessions: [Session] {
        [
            Session(
                id: "attention-approval", name: "add /approvals endpoint", agent: .codex,
                status: .awaitingApproval(prompt: "Run tests?"), subtitle: "承認待ち",
                projectName: "phlox", updatedAt: Date()
            ),
            Session(
                id: "attention-question", name: "Tulip", agent: .claudeCode,
                status: .awaitingUserQuestion, subtitle: "質問あり",
                projectName: "garden", updatedAt: Date()
            ),
            Session(
                id: "shell-running", name: "Design polish", agent: .codex,
                status: .running, subtitle: "実行中", projectName: "phlox", updatedAt: Date()
            ),
            Session(
                id: "shell-running-2", name: "Release checklist", agent: .claudeCode,
                status: .running, subtitle: "実行中", projectName: "garden", updatedAt: Date()
            ),
            Session(
                id: "shell-running-3", name: "Snapshot updates", agent: .codex,
                status: .running, subtitle: "実行中", projectName: "phlox", updatedAt: Date()
            ),
        ]
    }

    private static var scrolledShellSessions: [Session] {
        shellSessions + (1...20).map { index in
            Session(
                id: "shell-running-\(index)", name: "Session \(index)", agent: .claudeCode,
                status: .running, subtitle: "実行中", projectName: index.isMultiple(of: 2) ? "phlox" : "garden",
                updatedAt: Date()
            )
        }
    }

    /// `List` / `ListMulti` / `ListCollapsed` の見本データ。
    private static var listProjects: [ProjectSummary] {
        [
            ProjectSummary(id: "phlox", name: "Phlox"),
            ProjectSummary(id: "simple-budget", name: "SimpleBudget"),
        ]
    }

    private static var listSessions: [Session] {
        [
            Session(
                id: "list-approval", name: "add /approvals endpoint", agent: .codex,
                status: .awaitingApproval(prompt: "Run tests?"), subtitle: "承認待ち",
                projectId: "phlox", projectName: "Phlox",
                statusEnteredAt: Date(timeIntervalSince1970: 100), updatedAt: Date()
            ),
            Session(
                id: "list-question", name: "Tulip", agent: .claudeCode,
                status: .awaitingUserQuestion, subtitle: "質問あり",
                projectId: "phlox", projectName: "Phlox",
                statusEnteredAt: Date(timeIntervalSince1970: 200), updatedAt: Date()
            ),
            Session(
                id: "refactor", name: "refactor: ControlServer proxy", agent: .codex,
                status: .running, subtitle: "実行中",
                projectId: "phlox", projectName: "Phlox", hasUnseenCompletion: true, updatedAt: Date()
            ),
            Session(
                id: "proxy-tests", name: "ProxyRouter のテストを追加", agent: .claudeCode,
                status: .running, subtitle: "実行中", projectId: "phlox", projectName: "Phlox",
                parentSessionId: "refactor", updatedAt: Date()
            ),
            Session(
                id: "routing-table", name: "ルーティング表の整理", agent: .codex,
                status: .completed(exitCode: 0), subtitle: "完了", projectId: "phlox", projectName: "Phlox",
                hasUnseenCompletion: true, parentSessionId: "refactor", updatedAt: Date()
            ),
            Session(
                id: "rose-error", name: "Rose", agent: .claudeCode,
                status: .error(message: "Request failed"), subtitle: "エラー",
                projectId: "phlox", projectName: "Phlox", hasUnseenCompletion: true,
                statusEnteredAt: Date(timeIntervalSince1970: 300), updatedAt: Date()
            ),
            Session(
                id: "write-unit-tests", name: "write unit tests", agent: .codex,
                status: .idle, subtitle: "", projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "adr-0044", name: "docs: ADR 0044", agent: .claudeCode,
                status: .completed(exitCode: 0), subtitle: "完了", projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "csv-import", name: "CSV 取り込みの重複判定を修正", agent: .codex,
                status: .running, subtitle: "実行中",
                projectId: "simple-budget", projectName: "SimpleBudget", updatedAt: Date()
            ),
            Session(
                id: "test-data-generation", name: "テストデータの生成", agent: .claudeCode,
                status: .completed(exitCode: 0), subtitle: "完了",
                projectId: "simple-budget", projectName: "SimpleBudget", parentSessionId: "csv-import", updatedAt: Date()
            ),
            Session(
                id: "duplicate-key-investigation", name: "重複キーの調査", agent: .codex,
                status: .idle, subtitle: "",
                projectId: "simple-budget", projectName: "SimpleBudget", parentSessionId: "csv-import", updatedAt: Date()
            ),
            Session(
                id: "log-formatting", name: "ログの整形", agent: .claudeCode,
                status: .completed(exitCode: 0), subtitle: "完了",
                projectId: "simple-budget", projectName: "SimpleBudget", parentSessionId: "csv-import", updatedAt: Date()
            ),
            Session(
                id: "clover", name: "Clover", agent: .claudeCode,
                status: .running, subtitle: "無応答",
                projectId: "simple-budget", projectName: "SimpleBudget", isStalled: true, hasUnseenCompletion: true,
                statusEnteredAt: Date(timeIntervalSince1970: 400), updatedAt: Date()
            ),
            Session(
                id: "mint", name: "Mint", agent: .codex,
                status: .idle, subtitle: "", projectId: "simple-budget", projectName: "SimpleBudget", updatedAt: Date()
            ),
            Session(
                id: "daisy", name: "Daisy", agent: .codex,
                status: .starting, subtitle: "起動中", updatedAt: Date()
            ),
            Session(
                id: "ivy", name: "Ivy", agent: .claudeCode,
                status: .completed(exitCode: 0), subtitle: "完了", updatedAt: Date()
            ),
        ]
    }

    private static var listMultiSessions: [Session] {
        listSessions + [
            Session(
                id: "list-approval-2", name: "Lily", agent: .codex,
                status: .awaitingApproval(prompt: "Apply patch?"), subtitle: "承認待ち",
                projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "list-question-2", name: "migrate Usage API to v2 contract", agent: .claudeCode,
                status: .awaitingUserQuestion, subtitle: "質問あり",
                projectId: "simple-budget", projectName: "SimpleBudget", updatedAt: Date()
            ),
        ]
    }

    private static var listAttentionSessions: [Session] {
        [
            Session(
                id: "list-approval", name: "add /approvals endpoint", agent: .codex,
                status: .awaitingApproval(prompt: "Run tests?"), subtitle: "承認待ち",
                projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "list-question", name: "Tulip", agent: .claudeCode,
                status: .awaitingUserQuestion, subtitle: "質問あり",
                projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "list-error", name: "Rose", agent: .claudeCode,
                status: .error(message: "Request failed"), subtitle: "エラー",
                projectId: "phlox", projectName: "Phlox", updatedAt: Date()
            ),
            Session(
                id: "list-stalled", name: "Clover", agent: .codex,
                status: .running, subtitle: "無応答", projectId: "simple-budget", projectName: "SimpleBudget",
                isStalled: true, updatedAt: Date()
            ),
        ]
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

}

/// spawn 時に安定 ID を返す UI テスト用 API スタブ。
private struct UITestPhloxAPI: PhloxAPI {
    let sessions: [Session]
    let approvals: [Approval]
    let projectList: [ProjectSummary]?

    init(sessions: [Session], approvals: [Approval], projectList: [ProjectSummary]? = nil) {
        self.sessions = sessions
        self.approvals = approvals
        self.projectList = projectList
    }

    func listSessions() async throws -> [Session] { sessions }
    func agentSettings(kind: AgentKind) async throws -> AgentSettings? { nil }
    func projects() async throws -> [ProjectSummary]? { projectList }
    func cliUsage() async throws -> [CLIUsage] { UITestUsageFixtures.values(for: .normal) }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func approvals() async throws -> [Approval] { approvals }
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

enum UITestUsageFixtures {
    enum Style {
        case normal
        case low
        case unavailable
    }

    static let asOfDate = date(day: 17, hour: 16, minute: 12)

    static func values(for style: Style) -> [CLIUsage] {
        let asOf = asOfDate
        let fiveHourReset = date(day: 17, hour: 19, minute: 24)
        let claudeWeeklyReset = date(day: 20, hour: 14, minute: 0)
        let codexFiveHourReset = date(day: 17, hour: 20, minute: 17)
        let codexWeeklyReset = date(day: 23, hour: 9, minute: 0)

        switch style {
        case .normal:
            return [
                agent(.claudeCode, asOf: asOf, buckets: [
                    bucket("5h", "5時間", used: 28, resetsAt: fiveHourReset),
                    bucket("weekly", "週次", used: 60, resetsAt: claudeWeeklyReset),
                ]),
                agent(.codex, asOf: asOf, buckets: [
                    bucket("5h", "5時間", used: 1, resetsAt: codexFiveHourReset),
                    bucket("weekly", "週次", used: 15, resetsAt: codexWeeklyReset),
                ]),
                agent(.cursor, asOf: asOf, buckets: [
                    bucket("auto", "Auto", used: 20),
                    bucket("api", "API", used: 5),
                ]),
            ]
        case .low:
            return [
                agent(.claudeCode, asOf: asOf, buckets: [
                    bucket("5h", "5時間", used: 88, resetsAt: fiveHourReset),
                    bucket("weekly", "週次", used: 82, resetsAt: claudeWeeklyReset),
                ]),
                agent(.codex, asOf: asOf, buckets: [
                    bucket("5h", "5時間", used: 1, resetsAt: codexFiveHourReset),
                    bucket("weekly", "週次", used: 15, resetsAt: codexWeeklyReset),
                ]),
                agent(.cursor, asOf: asOf, buckets: [
                    bucket("auto", "Auto", used: 85),
                    bucket("api", "API", used: 96),
                ]),
            ]
        case .unavailable:
            return [
                agent(.claudeCode, asOf: asOf, buckets: [
                    bucket("5h", "5時間", used: 28, resetsAt: fiveHourReset),
                ]),
                unavailableAgent(.codex, asOf: asOf),
                unavailableAgent(.cursor, asOf: asOf),
            ]
        }
    }

    private static func agent(_ kind: AgentKind, asOf: Date, buckets: [UsageBucket]) -> CLIUsage {
        CLIUsage(kind: kind, state: .ok, buckets: buckets, updatedAt: asOf, dataAsOf: nil)
    }

    private static func unavailableAgent(_ kind: AgentKind, asOf: Date) -> CLIUsage {
        CLIUsage(kind: kind, state: .unavailable, buckets: [], updatedAt: asOf, dataAsOf: nil)
    }

    private static func bucket(_ id: String, _ label: String, used: Double, resetsAt: Date? = nil) -> UsageBucket {
        UsageBucket(id: id, label: label, usedPercent: used, resetsAt: resetsAt)
    }

    private static func date(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60) ?? .current
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: day,
            hour: hour,
            minute: minute
        )) ?? Date(timeIntervalSince1970: 0)
    }
}
