import Foundation

/// CLI ごとの起動戦略を表現する値型。AgentKind 単体では表現しきれない
/// 「起動引数 / 環境変数 / hook 統合方式 / scrollback ポリシー / 状態遷移モード」をまとめる。
///
/// この型は Sendable で、AgentLaunchPlanner（Phase 2 で追加予定）が生成して
/// DashboardViewModel / SessionViewModel に渡す。
public struct AgentLaunchProfile: Sendable, Equatable {
    public let extraArgs: [String]
    public let extraEnv: [String: String]
    public let hookIntegration: HookIntegration
    public let scrollbackPolicy: ScrollbackPolicy
    public let statusBootstrap: StatusBootstrap
    public let postSpawnReset: PostSpawnReset?
    /// デバッグ用 viewport dump を spawn 直後に 3 回書き出す (既定 OFF)。
    public let debugDump: Bool
    public let newSessionResumeArgument: AgentResumeArgument?
    public let resumeArgument: AgentResumeArgument?

    public init(
        extraArgs: [String] = [],
        extraEnv: [String: String] = [:],
        hookIntegration: HookIntegration = .none,
        scrollbackPolicy: ScrollbackPolicy = .keep,
        statusBootstrap: StatusBootstrap = .viaHook,
        postSpawnReset: PostSpawnReset? = nil,
        debugDump: Bool = false,
        newSessionResumeArgument: AgentResumeArgument? = nil,
        resumeArgument: AgentResumeArgument? = nil
    ) {
        self.extraArgs = extraArgs
        self.extraEnv = extraEnv
        self.hookIntegration = hookIntegration
        self.scrollbackPolicy = scrollbackPolicy
        self.statusBootstrap = statusBootstrap
        self.postSpawnReset = postSpawnReset
        self.debugDump = debugDump
        self.newSessionResumeArgument = newSessionResumeArgument
        self.resumeArgument = resumeArgument
    }
}

/// PTY spawn 完了後にターミナル側で行うリセット・再描画トリガ。
/// Cursor 等の 2 段階描画 TUI のロゴ崩れ対策。
public enum PostSpawnReset: Sendable, Equatable {
    /// PTY spawn 完了から指定遅延後に、
    /// (1) SwiftTerm 内部バッファをクリアし
    /// (2) PTY に同サイズ resize を発行して子に SIGWINCH を送り、
    /// 子プロセスが現在のサイズで再描画するよう促す。
    ///
    /// 子プロセスに直接制御列を書き込むのではなく、ターミナル側 + 再描画トリガで完結させる。
    /// Cursor のような「起動時に 2 段階描画する通常バッファ TUI」のロゴ崩れ対策。
    case refreshTerminalAndSIGWINCH(delay: Duration)
}

/// 状態通知を hooks 経由で受け取るか、PTY spawn 完了をもって idle と見なすか。
/// Claude Code は前者、Codex / Cursor は後者。
public enum StatusBootstrap: Sendable, Equatable {
    /// HookServer 経由の Notification/Stop イベントで status を遷移させる。
    case viaHook
    /// PTY spawn 完了をもって即 status = .idle と見なす。
    case idleOnSpawnComplete
}

/// scrollback 無効化は履歴スクロールを不能にする副作用があり、実機検証で起動時 reflow による
/// ゴースト残留は現行 Cursor/Codex では再現しないことを確認したため、既定の .keep を用いる。
/// .disableBeforeSpawn は将来 TUI 側がゴーストを再発させた場合のフォールバックとして残す。
public enum ScrollbackPolicy: Sendable, Equatable {
    case keep
    case disableBeforeSpawn
}

/// Claude Code の `--settings` フラグ + `CLAUDE_HOOKS_URL` env のような統合方式。
public enum HookIntegration: Sendable, Equatable {
    case claudeSettings(settingsPath: String, hookURL: URL)
    /// Codex は CWD 配下の `.codex/hooks.json` を自動ロードする。ファイルは spawn 時にセッション単位で生成する。
    case codexHooks(hookURL: URL)
    /// Cursor は CWD 配下の `.cursor/hooks.json` を自動ロードする。hook サブプロセスは親 env を継承する。
    case cursorHooks(hookURL: URL)
    case none
}
