import Foundation

/// セッション起動経路。サイドバー表示と app-server ポリシー切替に使う。
public enum SessionLaunchContext: String, Codable, Sendable, Equatable {
    case interactive
    case orchestration
}

/// アプリ再起動後にセッションを復元するために永続化する最小メタ情報。
/// ライブ状態（pid/masterFD/出力バッファ）はデーモンメモリに残り、
/// ここには VM 再構築に必要な静的情報のみ保存する。
public struct PersistedSessionDescriptor: Identifiable, Hashable, Sendable, Codable {
    public let id: SessionID
    public let agentRef: AgentRef
    public let workingDirectory: String
    public var name: String
    public let projectID: ProjectID?
    public let startedAt: Date
    /// cold restart（デーモンも死んでいた）場合に同じ環境で再 spawn するための情報。
    public let command: String
    public let args: [String]
    public let env: [String: String]
    /// セッション実体の backend。旧 descriptor は pty として復元する。
    public let backend: SessionBackend
    /// app-server backend の Codex thread id。PTY backend では nil。
    public private(set) var codexThreadId: String?
    /// structured chat backend の native session id。旧 Codex descriptor は codexThreadId へフォールバックする。
    public private(set) var chatNativeSessionId: String?
    /// app-server initialize で返る Codex user agent。復元互換性診断用。
    public private(set) var appServerUserAgent: String?
    /// app-server backend のセッション途中変更可能な Codex 設定。
    public private(set) var codexSettings: CodexAppServerSessionSettings?
    /// CLI 子プロセスの認証トークン（インメモリ専用）。encode では出力しない（ADR 0047:
    /// 機密の平文永続化をしない）。decode は旧バージョンが保存したファイルとの互換のため
    /// 読み続ける。nil の場合、復元側（restoreSession）が新トークンを発行して再登録する。
    public let token: String?
    /// CLI の会話履歴を復元するための ID。nil は旧 descriptor または捕捉失敗時のフォールバック。
    public private(set) var resumeID: String?
    /// API spawn の親セッション。nil は UI/内部生成または旧 descriptor。
    public private(set) var parentSessionID: SessionID?
    /// アゴラ討論での役割名（例「批判者」「ファシリテーター」）。nil は役割なし・旧 descriptor。
    public private(set) var role: String?
    /// 前回起動時のセッション実体（CLI 子プロセス）の OS プロセス pid。
    /// アプリ再起動後の復元で「前回プロセスの生存孤児を reap してから再 spawn」する
    /// reconcile に使う。SETSID 起動のため pgid == pid。
    /// nil は旧 descriptor／pid 捕捉失敗時で、従来どおり reap せず再 spawn する（後方互換）。
    /// 前提: 二重起動（複数 Phlox 同時稼働）は未サポート＝スコープ外。pid 再利用の理論的
    /// リスクも既知制約として残す（本フィールドでの対策はしない）。
    public private(set) var pid: pid_t?
    /// 起動経路。orchestration は $PHLOX_CLI 経由の非表示 spawn。旧 descriptor は interactive 扱い。
    public let launchContext: SessionLaunchContext

    public var kind: AgentKind {
        guard let kind = agentRef.builtinKind else {
            preconditionFailure("Custom persisted session has no AgentKind: \(agentRef.id)")
        }
        return kind
    }

    public init(
        id: SessionID,
        kind: AgentKind,
        workingDirectory: String,
        name: String,
        projectID: ProjectID?,
        startedAt: Date,
        command: String,
        args: [String],
        env: [String: String],
        backend: SessionBackend = .pty,
        codexThreadId: String? = nil,
        chatNativeSessionId: String? = nil,
        appServerUserAgent: String? = nil,
        codexSettings: CodexAppServerSessionSettings? = nil,
        token: String? = nil,
        resumeID: String? = nil,
        parentSessionID: SessionID? = nil,
        pid: pid_t? = nil,
        launchContext: SessionLaunchContext = .interactive,
        role: String? = nil
    ) {
        self.init(
            id: id,
            agentRef: .builtin(kind),
            workingDirectory: workingDirectory,
            name: name,
            projectID: projectID,
            startedAt: startedAt,
            command: command,
            args: args,
            env: env,
            backend: backend,
            codexThreadId: codexThreadId,
            chatNativeSessionId: chatNativeSessionId,
            appServerUserAgent: appServerUserAgent,
            codexSettings: codexSettings,
            token: token,
            resumeID: resumeID,
            parentSessionID: parentSessionID,
            pid: pid,
            launchContext: launchContext,
            role: role
        )
    }

    public init(
        id: SessionID,
        agentRef: AgentRef,
        workingDirectory: String,
        name: String,
        projectID: ProjectID?,
        startedAt: Date,
        command: String,
        args: [String],
        env: [String: String],
        backend: SessionBackend = .pty,
        codexThreadId: String? = nil,
        chatNativeSessionId: String? = nil,
        appServerUserAgent: String? = nil,
        codexSettings: CodexAppServerSessionSettings? = nil,
        token: String? = nil,
        resumeID: String? = nil,
        parentSessionID: SessionID? = nil,
        pid: pid_t? = nil,
        launchContext: SessionLaunchContext = .interactive,
        role: String? = nil
    ) {
        self.id = id
        self.agentRef = agentRef
        self.workingDirectory = workingDirectory
        self.name = name
        self.projectID = projectID
        self.startedAt = startedAt
        self.command = command
        self.args = args
        self.env = env
        self.backend = backend
        self.codexThreadId = codexThreadId
        self.chatNativeSessionId = chatNativeSessionId ?? codexThreadId
        self.appServerUserAgent = appServerUserAgent
        self.codexSettings = codexSettings
        self.token = token
        self.resumeID = resumeID
        self.parentSessionID = parentSessionID
        self.pid = pid
        self.launchContext = launchContext
        self.role = role
    }

    /// 1 フィールドだけ変えたコピーを返す共通ヘルパー。
    /// 値型のコピーに mutate を適用するだけなので、フィールド追加時の転記漏れが起きない。
    private func copying(_ mutate: (inout PersistedSessionDescriptor) -> Void) -> PersistedSessionDescriptor {
        var copy = self
        mutate(&copy)
        return copy
    }

    public func updating(name: String) -> PersistedSessionDescriptor {
        copying { $0.name = name }
    }

    public func updating(resumeID: String?) -> PersistedSessionDescriptor {
        copying { $0.resumeID = resumeID }
    }

    public func updating(parentSessionID: SessionID?) -> PersistedSessionDescriptor {
        copying { $0.parentSessionID = parentSessionID }
    }

    public func updating(role: String?) -> PersistedSessionDescriptor {
        copying { $0.role = role }
    }

    public func updating(pid: pid_t?) -> PersistedSessionDescriptor {
        copying { $0.pid = pid }
    }

    public func updating(codexThreadId: String?, appServerUserAgent: String?) -> PersistedSessionDescriptor {
        copying {
            $0.codexThreadId = codexThreadId
            $0.chatNativeSessionId = codexThreadId
            $0.appServerUserAgent = appServerUserAgent
        }
    }

    public func updating(chatNativeSessionId: String?) -> PersistedSessionDescriptor {
        copying { $0.chatNativeSessionId = chatNativeSessionId }
    }

    public func updating(codexSettings: CodexAppServerSessionSettings?) -> PersistedSessionDescriptor {
        copying { $0.codexSettings = codexSettings }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case workingDirectory
        case name
        case projectID
        case startedAt
        case command
        case args
        case env
        case backend
        case codexThreadId
        case chatNativeSessionId
        case appServerUserAgent
        case codexSettings
        case token
        case resumeID
        case parentSessionID
        case pid
        case launchContext
        case role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(SessionID.self, forKey: .id)
        self.agentRef = try container.decode(AgentRef.self, forKey: .kind)
        self.workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        self.name = try container.decode(String.self, forKey: .name)
        self.projectID = try container.decodeIfPresent(ProjectID.self, forKey: .projectID)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decode([String].self, forKey: .args)
        self.env = try container.decode([String: String].self, forKey: .env)
        self.backend = try container.decodeIfPresent(SessionBackend.self, forKey: .backend) ?? .pty
        self.codexThreadId = try container.decodeIfPresent(String.self, forKey: .codexThreadId)
        self.chatNativeSessionId = try container.decodeIfPresent(String.self, forKey: .chatNativeSessionId)
            ?? self.codexThreadId
        self.appServerUserAgent = try container.decodeIfPresent(String.self, forKey: .appServerUserAgent)
        self.codexSettings = try container.decodeIfPresent(CodexAppServerSessionSettings.self, forKey: .codexSettings)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.resumeID = try container.decodeIfPresent(String.self, forKey: .resumeID)
        self.parentSessionID = try container.decodeIfPresent(SessionID.self, forKey: .parentSessionID)
        self.pid = try container.decodeIfPresent(pid_t.self, forKey: .pid)
        self.launchContext = try container.decodeIfPresent(SessionLaunchContext.self, forKey: .launchContext) ?? .interactive
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(agentRef, forKey: .kind)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(Self.scrubbingSecretEnvKeys(env), forKey: .env)
        try container.encode(backend, forKey: .backend)
        try container.encodeIfPresent(codexThreadId, forKey: .codexThreadId)
        try container.encodeIfPresent(chatNativeSessionId, forKey: .chatNativeSessionId)
        try container.encodeIfPresent(appServerUserAgent, forKey: .appServerUserAgent)
        try container.encodeIfPresent(codexSettings, forKey: .codexSettings)
        // token は CLI 認証トークンであり、平文 JSON (sessions.json) へは一切出力しない
        // (CWE-312 相当の監査所見への対応・案A)。再起動後の再登録は SessionTokenStore が
        // インメモリで担う想定で、永続化側からは意図的に欠落させる。
        try container.encodeIfPresent(resumeID, forKey: .resumeID)
        try container.encodeIfPresent(parentSessionID, forKey: .parentSessionID)
        try container.encodeIfPresent(pid, forKey: .pid)
        if launchContext != .interactive {
            try container.encode(launchContext, forKey: .launchContext)
        }
        try container.encodeIfPresent(role, forKey: .role)
    }

    /// 大文字化したキー名の接尾辞または完全一致で秘密系とみなし、`env` から除外した辞書を返す。
    /// **書き込み（encode）時のみ**適用する。decode 側では適用しない
    /// （旧 sessions.json からの後方互換読み取りを壊さないため）。
    ///
    /// 除外規則:
    /// - 接尾辞一致: `_TOKEN` / `_KEY` / `_SECRET` / `_PASSWORD` / `_CREDENTIAL` / `_CREDENTIALS` / `_PASSPHRASE`
    /// - 完全一致: `TOKEN` / `KEY` / `SECRET` / `PASSWORD` / `PASSPHRASE` / `CREDENTIALS` / `AUTHORIZATION`
    private static func scrubbingSecretEnvKeys(_ env: [String: String]) -> [String: String] {
        env.filter { !isSecretEnvKey($0.key) }
    }

    private static let secretEnvKeySuffixes = [
        "_TOKEN", "_KEY", "_SECRET", "_PASSWORD", "_CREDENTIAL", "_CREDENTIALS", "_PASSPHRASE",
    ]

    private static let secretEnvKeyExactMatches: Set<String> = [
        "TOKEN", "KEY", "SECRET", "PASSWORD", "PASSPHRASE", "CREDENTIALS", "AUTHORIZATION",
    ]

    private static func isSecretEnvKey(_ key: String) -> Bool {
        let uppercased = key.uppercased()
        if secretEnvKeyExactMatches.contains(uppercased) {
            return true
        }
        return secretEnvKeySuffixes.contains { uppercased.hasSuffix($0) }
    }
}

public struct CodexAppServerSessionSettings: Hashable, Sendable, Codable {
    public var selectedModel: String?
    public var selectedEffort: String?
    public var selectedPermissionProfile: String?
    public var isPlanMode: Bool?

    public init(
        selectedModel: String? = nil,
        selectedEffort: String? = nil,
        selectedPermissionProfile: String? = nil,
        isPlanMode: Bool? = nil
    ) {
        self.selectedModel = selectedModel
        self.selectedEffort = selectedEffort
        self.selectedPermissionProfile = selectedPermissionProfile
        self.isPlanMode = isPlanMode
    }

    public var hasAnyValue: Bool {
        selectedModel != nil
            || selectedEffort != nil
            || selectedPermissionProfile != nil
            || isPlanMode != nil
    }
}
