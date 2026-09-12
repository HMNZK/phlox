/// 管理ウィンドウが面倒を見るエージェント。
public enum AgentConsoleAgent: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claude
    case codex
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    public var symbolName: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        }
    }

    /// 設定の実体がどこにあるか（状態ペインと案内文で使う）。
    public var configLocation: String {
        switch self {
        case .claude: return "~/.claude/settings.json"
        case .codex: return "~/.codex/config.toml"
        case .cursor: return "~/.cursor/cli-config.json"
        }
    }
}

/// サイドバーに並ぶ1項目。エージェントごとにグループ分けして並べる。
public enum AgentConsoleSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Claude Code — いずれも対話 TUI 専用のスラッシュコマンドの置き換え。
    case claudeStatus
    case claudePlugins
    case claudeSkills
    case claudePermissions
    case claudeMemory
    case claudeHooks
    case claudeStatusLine
    case claudeOutputStyle
    // Codex
    case codexStatus
    case codexSettings
    case codexPlugins
    case codexMCP
    case codexMemory
    case codexTrust
    // Cursor
    case cursorStatus
    case cursorPermissions
    case cursorModel
    case cursorMCP
    case cursorSettings

    public var id: String { rawValue }

    public var agent: AgentConsoleAgent {
        switch self {
        case .claudeStatus, .claudePlugins, .claudeSkills, .claudePermissions, .claudeMemory,
             .claudeHooks, .claudeStatusLine, .claudeOutputStyle:
            return .claude
        case .codexStatus, .codexSettings, .codexPlugins, .codexMCP, .codexMemory, .codexTrust:
            return .codex
        case .cursorStatus, .cursorPermissions, .cursorModel, .cursorMCP, .cursorSettings:
            return .cursor
        }
    }

    public var title: String {
        switch self {
        case .claudeStatus, .codexStatus, .cursorStatus: return "状態"
        case .claudePlugins, .codexPlugins: return "プラグイン"
        case .claudeSkills: return "スキル"
        case .claudePermissions, .cursorPermissions: return "権限"
        case .claudeMemory, .codexMemory: return "メモリ"
        case .claudeHooks: return "フック"
        case .claudeStatusLine: return "ステータスライン"
        case .claudeOutputStyle: return "出力スタイル"
        case .codexSettings, .cursorSettings: return "設定"
        case .codexMCP, .cursorMCP: return "MCP"
        case .codexTrust: return "信頼設定"
        case .cursorModel: return "モデル"
        }
    }

    /// 行の下に添える短い説明。Claude はもともとのスラッシュコマンド、
    /// Codex / Cursor は触る対象を示す。
    public var detail: String {
        switch self {
        case .claudeStatus: return "/status"
        case .claudePlugins: return "/plugin"
        case .claudeSkills: return "skills"
        case .claudePermissions: return "/permissions"
        case .claudeMemory: return "/memory"
        case .claudeHooks: return "/hooks"
        case .claudeStatusLine: return "/statusline"
        case .claudeOutputStyle: return "/output-style"
        case .codexStatus: return "config.toml"
        case .codexSettings: return "model / sandbox"
        case .codexPlugins: return "codex plugin"
        case .codexMCP: return "codex mcp"
        case .codexMemory: return "AGENTS.md"
        case .codexTrust: return "[projects]"
        case .cursorStatus: return "cli-config.json"
        case .cursorPermissions: return "permissions"
        case .cursorModel: return "model"
        case .cursorMCP: return "mcp.json"
        case .cursorSettings: return "display / git"
        }
    }

    public var symbolName: String {
        switch self {
        case .claudeStatus, .codexStatus, .cursorStatus: return "info.circle"
        case .claudePlugins, .codexPlugins: return "puzzlepiece.extension"
        case .claudeSkills: return "books.vertical"
        case .claudePermissions, .cursorPermissions: return "checkmark.shield"
        case .claudeMemory, .codexMemory: return "brain"
        case .claudeHooks: return "link"
        case .claudeStatusLine: return "text.line.first.and.arrowtriangle.forward"
        case .claudeOutputStyle: return "textformat"
        case .codexSettings, .cursorSettings: return "slider.horizontal.3"
        case .codexMCP, .cursorMCP: return "server.rack"
        case .codexTrust: return "folder.badge.person.crop"
        case .cursorModel: return "cpu"
        }
    }

    public static func sections(for agent: AgentConsoleAgent) -> [AgentConsoleSection] {
        allCases.filter { $0.agent == agent }
    }
}

/// 対象エージェントと、その対象に属する設定項目・現在地を束ねる。
public struct AgentConsoleNavigationModel: Equatable, Sendable {
    public let agent: AgentConsoleAgent
    public let sections: [AgentConsoleSection]
    public let selectedSection: AgentConsoleSection

    public var locationText: String {
        "\(agent.displayName) / \(selectedSection.title)"
    }

    public var agentPickerLabel: String {
        "対象エージェント"
    }

    public static func make(agent: AgentConsoleAgent, selection: AgentConsoleSection?) -> AgentConsoleNavigationModel {
        let sections = AgentConsoleSection.sections(for: agent)
        let selectedSection: AgentConsoleSection
        if let selection, selection.agent == agent {
            selectedSection = selection
        } else {
            selectedSection = statusSection(for: agent)
        }
        return AgentConsoleNavigationModel(
            agent: agent,
            sections: sections,
            selectedSection: selectedSection
        )
    }

    private static func statusSection(for agent: AgentConsoleAgent) -> AgentConsoleSection {
        switch agent {
        case .claude: return .claudeStatus
        case .codex: return .codexStatus
        case .cursor: return .cursorStatus
        }
    }
}
