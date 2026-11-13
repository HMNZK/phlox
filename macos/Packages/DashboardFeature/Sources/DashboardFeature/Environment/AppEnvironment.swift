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
    /// 旧ホストから引き継いだ実行（holder経由の子）へつなぐクライアントを作る。新しい子は作らない。
    public typealias AdoptClientFactory = @Sendable (
        _ agentRef: AgentRef,
        _ session: HandoverSession,
        _ command: String,
        _ workingDirectory: String?,
        _ environment: [String: String],
        _ approvalHandler: JSONRPCClient.ServerRequestHandler?
    ) async throws -> any StructuredAgentClient

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

    /// Claude Code 以外の組込 CLI の解決済み絶対パス。
    public let agentBinaryPaths: [AgentKind: String]

    public let controlURL: URL
    public let tokenStore: SessionTokenStore
    public let messages: any MessageStoreProtocol
    /// UI 上のワークスペース一覧の永続化（内部型名は Project）。
    public let projects: any ProjectStoreProtocol
    /// アプリ再起動後にセッションを復元するための永続化ストア。
    public let sessions: any SessionStoreProtocol
    public let sessionHistoryNames: JSONSessionHistoryNameStore
    /// 全 appServer セッションの表示用 transcript を Phlox 側に保存するストア。
    public let transcriptStore: any TranscriptStore
    public let cliPath: String
    public let isFullAccessEnabled: @Sendable (AgentRef) -> Bool
    public let structuredClientFactory: StructuredClientFactory
    /// 子CLIの寿命を別プロセス（holder）へ分ける設定。常駐プロセスだけが指定する。nilなら従来どおり直接起動する。
    public let processHolder: ProcessHolderPolicy?
    /// 計画的なホスト更新で旧ホストが残した引き継ぎ対象（セッションID → 採用先）。復元走査はこれにあるセッションを
    /// 再起動せず引き継ぐ。空なら従来どおり。
    public let handoverAdoptions: [SessionID: HandoverSession]
    public let adoptClientFactory: AdoptClientFactory
    /// 計画的なホスト更新の間、新しいセッションの起動を止める門。
    public let handoverGate: HandoverGate

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
        controlURL: URL,
        tokenStore: SessionTokenStore,
        messages: any MessageStoreProtocol,
        projects: any ProjectStoreProtocol = NoOpProjectStore(),
        sessions: any SessionStoreProtocol = NoOpSessionStore(),
        sessionHistoryNames: JSONSessionHistoryNameStore = JSONSessionHistoryNameStore(),
        transcriptStore: any TranscriptStore = NoOpTranscriptStore(),
        cliPath: String,
        fullAccessProvider: (@Sendable (AgentRef) -> Bool)? = nil,
        structuredClientFactory: StructuredClientFactory? = nil,
        appServerClientFactory: AppServerClientFactory? = nil,
        processHolder: ProcessHolderPolicy? = nil,
        handoverAdoptions: [SessionID: HandoverSession] = [:],
        adoptClientFactory: AdoptClientFactory? = nil
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
        self.controlURL = controlURL
        self.tokenStore = tokenStore
        self.messages = messages
        self.projects = projects
        self.sessions = sessions
        self.sessionHistoryNames = sessionHistoryNames
        self.transcriptStore = transcriptStore
        self.cliPath = cliPath
        let resolvedFullAccessProvider = fullAccessProvider ?? { ref in
            BypassSettings.isEnabled(for: ref)
        }
        self.isFullAccessEnabled = resolvedFullAccessProvider
        // holderを起動する入口にも同じ門を結びつける（計画時に開いていても、起動の直前に閉じていれば起動しない）。
        let gate = HandoverGate()
        self.handoverGate = gate
        let gatedHolder = processHolder?.gated(by: gate)
        self.processHolder = gatedHolder
        self.handoverAdoptions = handoverAdoptions
        self.adoptClientFactory = adoptClientFactory
            ?? Self.defaultAdoptClientFactory(fullAccessProvider: resolvedFullAccessProvider, holder: gatedHolder)
        self.structuredClientFactory = structuredClientFactory
            ?? appServerClientFactory
            ?? Self.defaultStructuredClientFactory(fullAccessProvider: resolvedFullAccessProvider, holder: gatedHolder)
    }

    /// 指定 CLI の実行ファイル絶対パス。claudeCode は既存の claudeBinaryPath を返す。
    public func binaryPath(for kind: AgentKind) -> String? {
        if kind == .claudeCode { return claudeBinaryPath }
        return agentBinaryPaths[kind]
    }

    public func binaryPath(for ref: AgentRef) -> String? {
        switch ref { case .builtin(let kind): binaryPath(for: kind) }
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
    /// cwd 未設定では nil（既存セッション生成はデフォルト引数のまま無変更）。
    func claudeSessionHistoryProviders(
        workingDirectory: String?
    ) -> (
        historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
        historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
    )? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        return claudeSessionHistoryProviders(workingDirectories: [workingDirectory])
    }

    func claudeSessionHistoryProviders(
        workingDirectories: [String]
    ) -> (
        historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
        historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
    )? {
        guard !workingDirectories.isEmpty else { return nil }
        let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: Self.claudeProjectsRoot)
        let loader = ClaudeSessionTranscriptLoader()
        let listLimit = 20
        let transcriptItemLimit = ClaudeSessionHistoryEntry.transcriptItemLimit
        return (
            historyProvider: {
                discovery.entries(forWorkingDirectories: workingDirectories, limit: listLimit)
            },
            historyTranscriptLoader: { entry in
                loader.load(fileURL: entry.fileURL, maxItems: transcriptItemLimit)
            }
        )
    }

    /// Codex チャット用の履歴一覧 provider と転写 loader。
    func codexSessionHistoryProviders(
        workingDirectory: String?
    ) -> (
        historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
        historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
    )? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        return codexSessionHistoryProviders(workingDirectories: [workingDirectory])
    }

    func codexSessionHistoryProviders(
        workingDirectories: [String]
    ) -> (
        historyProvider: @Sendable () -> [ClaudeSessionHistoryEntry],
        historyTranscriptLoader: @Sendable (ClaudeSessionHistoryEntry) -> [ChatItem]
    )? {
        guard !workingDirectories.isEmpty else { return nil }
        let discovery = CodexSessionHistoryDiscovery(codexHome: codexHome)
        let loader = CodexSessionTranscriptLoader()
        let listLimit = 20
        let transcriptItemLimit = ClaudeSessionHistoryEntry.transcriptItemLimit
        return (
            historyProvider: {
                discovery.entries(forWorkingDirectories: workingDirectories, limit: listLimit)
            },
            historyTranscriptLoader: { entry in
                loader.load(fileURL: entry.fileURL, maxItems: transcriptItemLimit)
            }
        )
    }

    func newChatSessionHistoryLoader(
        agentRef: AgentRef,
        workingDirectories: [String],
        limit: Int = 20
    ) -> (@Sendable () throws -> [ClaudeSessionHistoryEntry])? {
        switch agentRef {
        case .builtin(.claudeCode):
            let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: Self.claudeProjectsRoot)
            return { try discovery.loadEntries(forWorkingDirectories: workingDirectories, limit: limit) }
        case .builtin(.codex):
            let discovery = CodexSessionHistoryDiscovery(codexHome: codexHome)
            return { try discovery.loadEntries(forWorkingDirectories: workingDirectories, limit: limit) }
        default:
            return nil
        }
    }

    private static func makeClaudeClient(
        command: String, workingDirectory: String?, environment: [String: String], fullAccess: Bool,
        holder: ProcessHolderPolicy?
    ) -> ClaudeChatClient {
        let permissionMode = fullAccess ? "bypassPermissions" : "auto"
        guard let holder else {
            return ClaudeChatClient(
                command: command, workingDirectory: workingDirectory, environment: environment,
                permissionMode: permissionMode)
        }
        let metadata = Self.holderMetadata(agent: "claudeCode", environment: environment)
        return ClaudeChatClient(
            command: command,
            workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) },
            environment: environment,
            permissionMode: permissionMode,
            transportFactory: { command, arguments, environment, directory in
                holder.transport(
                    command: command, arguments: arguments, environment: environment,
                    workingDirectory: directory?.path, metadata: metadata)
            }
        )
    }

    /// 引き継ぎ用のクライアント。holder経由の子へ接続するだけで、子は起動しない。Claudeのみ対応（Codexは未対応）。
    private static func defaultAdoptClientFactory(
        fullAccessProvider: @escaping @Sendable (AgentRef) -> Bool,
        holder: ProcessHolderPolicy?
    ) -> AdoptClientFactory {
        { agentRef, session, command, workingDirectory, environment, handler in
            guard holder != nil else {
                throw HandoverError.adoptionFailed("この実行環境はholderを使いません")
            }
            switch agentRef {
            case .builtin(.claudeCode):
                let client = Self.makeClaudeClient(
                    command: command, workingDirectory: workingDirectory, environment: environment,
                    fullAccess: fullAccessProvider(agentRef), holder: holder)
                let transport = HolderTransport(source: .adopt(record: session.holder, fromSeq: session.appliedSeq))
                await client.prepareAdoption(state: session.clientState, transport: transport)
                return client
            case .builtin(.codex):
                // 新しい子は作らない。initialize・thread/*・turn/startは再発行せず、holderの子へつなぐだけ（接続は`completeAdoption`）。
                let transport = HolderTransport(source: .adopt(record: session.holder, fromSeq: session.appliedSeq))
                let client = CodexStructuredAgentClient(client: CodexAppServerClient(
                    transport: transport, serverRequestHandler: handler,
                    additionalDeveloperInstructions: CodexQuestionPolicy.instructions))
                await client.prepareAdoption(state: session.clientState, transport: transport)
                return client
            default:
                throw HandoverError.adoptionFailed("このエージェントは実行の引き継ぎに未対応です")
            }
        }
    }

    /// holderの探索記録に残す、セッションとの対応づけ（新しい常駐プロセスが採用先を決める）。
    static func holderMetadata(agent: String, environment: [String: String]) -> [String: String] {
        var metadata = ["agent": agent]
        if let session = environment["PHLOX_SESSION_ID"], !session.isEmpty { metadata["session"] = session }
        return metadata
    }

    /// Codex `app-server` 子プロセス起動時の arguments。
    /// `model_reasoning_summary=detailed` を config override で渡し、Reasoning サマリを有効化する。
    /// `tools.update_plan.enabled=true` で計画の道具 `update_plan` を使えるようにする（使用は強制しない。ADR 0228）。
    static func codexAppServerProcessArguments() -> [String] {
        [
            "app-server", "-c", "model_reasoning_summary=detailed", "-c", "features.default_mode_request_user_input=true",
            "-c", "tools.update_plan.enabled=true",
        ]
    }

    private static func defaultStructuredClientFactory(
        fullAccessProvider: @escaping @Sendable (AgentRef) -> Bool,
        holder: ProcessHolderPolicy?
    ) -> StructuredClientFactory {
        { agentRef, command, workingDirectory, environment, handler in
            switch agentRef {
            case .builtin(.codex):
                let transport: any (LineDelimitedTransport & AppServerTransport)
                if let holder {
                    transport = holder.transport(
                        command: command, arguments: Self.codexAppServerProcessArguments(), environment: environment,
                        workingDirectory: workingDirectory, metadata: Self.holderMetadata(agent: "codex", environment: environment))
                } else {
                    transport = LineDelimitedProcessTransport(
                        command: command,
                        arguments: Self.codexAppServerProcessArguments(),
                        environment: environment,
                        workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    )
                }
                try transport.start()
                let client = CodexAppServerClient(
                    transport: transport,
                    serverRequestHandler: handler,
                    additionalDeveloperInstructions: CodexQuestionPolicy.instructions
                )
                return CodexStructuredAgentClient(client: client)
            case .builtin(.claudeCode):
                return Self.makeClaudeClient(
                    command: command, workingDirectory: workingDirectory, environment: environment,
                    fullAccess: fullAccessProvider(agentRef), holder: holder)
            case .builtin(.cursor):
                let fullAccess = fullAccessProvider(agentRef)
                return CursorChatClient(
                    command: command,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    runMode: fullAccess ? .runEverything : .autoReview
                )
            }
        }
    }

}

// ClaudeChatClient/CursorChatClient（Kit パッケージの型）を AgentDomain の protocol へ
// 適合させるため retroactive。この適合の所有は当パッケージ（Composition Root）にある。
extension ClaudeChatClient: @retroactive SpawnAgentSettingsControlling {
    public func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        await updateSettings(model: model, permissionMode: permissionOrMode, effort: effort)
    }
}

extension ClaudeChatClient: @retroactive SpawnAgentPermissionControlling {
    public func setSpawnAgentPermission(_ permission: String?) async throws {
        try await setPermissionMode(permission ?? "manual")
    }
}

extension CursorChatClient: @retroactive SpawnAgentSettingsControlling {
    public func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        await updateSettings(model: model, mode: permissionOrMode)
    }
}
