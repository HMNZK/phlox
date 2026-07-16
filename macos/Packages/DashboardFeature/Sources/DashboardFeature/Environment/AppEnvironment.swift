import Foundation
import AgentDomain
import HookServer
import MessageStore
import PTYKit
import CodexAppServerKit
import StructuredChatKit
import ClaudeAgentKit
import CursorAgentKit
import SessionFeature

/// アプリ全体で共有する依存をまとめる Composition Root の値型。
/// View 階層には @Environment 経由で配布する。
public struct AppEnvironment: Sendable {
    public typealias StructuredClientFactory = @Sendable (
        _ agentRef: AgentRef,
        _ command: String,
        _ workingDirectory: String?,
        _ environment: [String: String],
        _ approvalHandler: JSONRPCClient.ServerRequestHandler?
    ) async throws -> any StructuredAgentClient
    public typealias AppServerClientFactory = StructuredClientFactory

    public let pty: any PTYManagerProtocol
    public let hook: any HookServerProtocol

    /// Claude Code の子プロセスに環境変数 CLAUDE_HOOKS_URL として渡す URL。
    /// HookServer.start() で取得したポートをもとに `http://127.0.0.1:<port>/hook` を構築。
    public let hookURL: URL

    /// `claude --settings <path>` に渡す hooks 設定ファイルのパス。
    /// CompositionRoot が起動時に生成する。
    public let claudeSettingsURL: URL

    /// bypass 無効時に `claude --settings <path>` に渡す hooks 設定ファイルのパス。
    /// 既存テスト構築コードでは claudeSettingsURL にフォールバックする。
    public let claudeSettingsRestrictedURL: URL

    /// `hook-dispatcher.sh` の絶対パス。Codex の CWD 配下 hooks.json の command に埋め込む。
    public let hookDispatcherPath: String

    /// claude バイナリの絶対パス。CompositionRoot が `which claude` 相当で起動時に解決する。
    /// 絶対パスで直接 spawn することで `/bin/zsh -l` を経由せず、
    /// login shell の startup script による不要な TCC 権限要求を排除する。
    public let claudeBinaryPath: String

    /// claude プロセスに与える PATH 環境変数（git 等の依存ツールの解決用）。
    public let pathEnvironment: String

    /// Claude Code statusLine ラッパーが保存する rate_limits キャッシュ。
    public let claudeUsageRateLimitsURL: URL

    /// Codex のホームディレクトリ（`~/.codex`）。rollout 走査で native session id を取得する。
    public let codexHome: URL

    /// セッション用 CWD を配置するルートディレクトリ。
    /// 各セッションはこの配下の専用サブディレクトリで起動する。
    public let workspaceDirectory: URL

    /// claudeCode 以外の CLI の解決済み絶対パス。起動時に best-effort で解決し、見つかったものだけ入る。
    public let agentBinaryPaths: [AgentKind: String]
    /// JSON 由来カスタム CLI の解決済み絶対パス。
    public let customAgentBinaryPaths: [String: String]
    /// 組込 + JSON 由来カスタム CLI の実行時 catalog。
    public let agentCatalog: AgentCatalog

    public let controlURL: URL
    public let tokenStore: SessionTokenStore
    public let messages: any MessageStoreProtocol
    /// UI 上のワークスペース一覧の永続化（内部型名は Project）。
    public let projects: any ProjectStoreProtocol
    /// アプリ再起動後にセッションを復元するための永続化ストア。
    public let sessions: any SessionStoreProtocol
    /// 全 appServer セッションの表示用 transcript を Phlox 側に保存するストア。
    public let transcriptStore: any TranscriptStore
    public let cliPath: String
    public let structuredClientFactory: StructuredClientFactory

    public init(
        pty: any PTYManagerProtocol,
        hook: any HookServerProtocol,
        hookURL: URL,
        claudeSettingsURL: URL,
        claudeSettingsRestrictedURL: URL? = nil,
        hookDispatcherPath: String,
        claudeBinaryPath: String,
        pathEnvironment: String,
        claudeUsageRateLimitsURL: URL = AppSupportLocator.appSupportDirectoryURL(
            home: FileManager.default.homeDirectoryForCurrentUser
        ).appending(path: "claude-usage-rate-limits.json"),
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        workspaceDirectory: URL,
        agentBinaryPaths: [AgentKind: String] = [:],
        customAgentBinaryPaths: [String: String] = [:],
        agentCatalog: AgentCatalog = .builtins,
        controlURL: URL,
        tokenStore: SessionTokenStore,
        messages: any MessageStoreProtocol,
        projects: any ProjectStoreProtocol = NoOpProjectStore(),
        sessions: any SessionStoreProtocol = NoOpSessionStore(),
        transcriptStore: any TranscriptStore = NoOpTranscriptStore(),
        cliPath: String,
        structuredClientFactory: StructuredClientFactory? = nil,
        appServerClientFactory: AppServerClientFactory? = nil
    ) {
        self.pty = pty
        self.hook = hook
        self.hookURL = hookURL
        self.claudeSettingsURL = claudeSettingsURL
        self.claudeSettingsRestrictedURL = claudeSettingsRestrictedURL ?? claudeSettingsURL
        self.hookDispatcherPath = hookDispatcherPath
        self.claudeBinaryPath = claudeBinaryPath
        self.pathEnvironment = pathEnvironment
        self.claudeUsageRateLimitsURL = claudeUsageRateLimitsURL
        self.codexHome = codexHome
        self.workspaceDirectory = workspaceDirectory
        self.agentBinaryPaths = agentBinaryPaths
        self.customAgentBinaryPaths = customAgentBinaryPaths
        self.agentCatalog = agentCatalog
        self.controlURL = controlURL
        self.tokenStore = tokenStore
        self.messages = messages
        self.projects = projects
        self.sessions = sessions
        self.transcriptStore = transcriptStore
        self.cliPath = cliPath
        self.structuredClientFactory = structuredClientFactory ?? appServerClientFactory ?? Self.defaultStructuredClientFactory
    }

    /// 指定 CLI の実行ファイル絶対パス。claudeCode は既存の claudeBinaryPath を返す。
    public func binaryPath(for kind: AgentKind) -> String? {
        if kind == .claudeCode { return claudeBinaryPath }
        return agentBinaryPaths[kind]
    }

    public func binaryPath(for ref: AgentRef) -> String? {
        switch ref {
        case .builtin(let kind):
            return binaryPath(for: kind)
        case .custom(let id):
            return customAgentBinaryPaths[id]
        }
    }

    /// 初回 spawn 用のセッション専用 workspace。
    public func sessionWorkspaceDirectory(for sessionID: SessionID) -> URL {
        workspaceDirectory.appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
    }

    /// Claude Code の履歴 JSONL ルート（`~/.claude/projects`）。
    static var claudeProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Claude チャット用の履歴一覧 provider と転写 loader（task-9）。
    /// Claude 以外・cwd 未設定では nil（既存セッション生成はデフォルト引数のまま無変更）。
    func claudeSessionHistoryProviders(
        workingDirectory: String?
    ) -> (
        historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
        historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
    )? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: Self.claudeProjectsRoot)
        let loader = ClaudeSessionTranscriptLoader()
        let listLimit = 20
        let transcriptItemLimit = 500
        return (
            historyProvider: {
                discovery.entries(forWorkingDirectory: workingDirectory, limit: listLimit)
            },
            historyTranscriptLoader: { entry in
                loader.load(fileURL: entry.fileURL, maxItems: transcriptItemLimit)
            }
        )
    }

    /// Codex `app-server` 子プロセス起動時の arguments。
    /// `model_reasoning_summary=detailed` を config override で渡し、Reasoning サマリを有効化する。
    static func codexAppServerProcessArguments() -> [String] {
        ["app-server", "-c", "model_reasoning_summary=detailed"]
    }

    private static var defaultStructuredClientFactory: StructuredClientFactory {
        { agentRef, command, workingDirectory, environment, handler in
            switch agentRef {
            case .builtin(.codex):
                let transport = ProcessTransport(
                    command: command,
                    arguments: Self.codexAppServerProcessArguments(),
                    environment: environment,
                    workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
                )
                try transport.start()
                let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                return CodexStructuredAgentClient(client: client)
            case .builtin(.claudeCode):
                return ClaudeChatClient(
                    command: command,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    preApprovalPolicy: claudeAutoApprovePolicy
                )
            case .builtin(.cursor):
                return CursorChatClient(
                    command: command,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    preApprovalPolicy: cursorAutoApprovePolicy
                )
            default:
                throw AppEnvironmentError.unsupportedStructuredAgent(agentRef.id)
            }
        }
    }

    /// Claude/Cursor 送信時のバナーを出さずに常に承認する auto-approve policy。
    /// handler（ChatApprovalBroker 経由でバナーを出す経路）を呼ばないためバナーは表示されない。
    /// 一方で policy が非 nil であることにより、ClaudeChatClient は acceptEdits +
    /// defaultAllowedTools を、CursorChatClient は `-f`（force）をそれぞれ維持する。
    private static let claudeAutoApprovePolicy: ClaudeChatClient.PreApprovalPolicy = { _ in .approve }
    private static let cursorAutoApprovePolicy: CursorChatClient.PreApprovalPolicy = { _ in .approve }
}

public enum AppEnvironmentError: Error, Equatable, Sendable {
    case unsupportedStructuredAgent(String)
}

// ClaudeChatClient/CursorChatClient（Kit パッケージの型）を AgentDomain の protocol へ
// 適合させるため retroactive。この適合の所有は当パッケージ（Composition Root）にある。
extension ClaudeChatClient: @retroactive SpawnAgentSettingsControlling {
    public func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        await updateSettings(model: model, permissionMode: permissionOrMode, effort: effort)
    }
}

extension CursorChatClient: @retroactive SpawnAgentSettingsControlling {
    public func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        await updateSettings(model: model, mode: permissionOrMode)
    }
}
