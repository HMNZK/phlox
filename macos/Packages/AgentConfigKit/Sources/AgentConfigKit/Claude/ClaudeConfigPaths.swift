import Foundation

/// Claude Code の設定資産の置き場所。テストから差し替えられるよう、ホームディレクトリを注入で受ける。
public struct ClaudeConfigPaths: Sendable, Equatable {
    /// ユーザーのホーム（`~`）。`~/.claude` の親。
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: ClaudeConfigPaths {
        ClaudeConfigPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `~/.claude`
    public var claudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    /// `~/.claude/settings.json`（ユーザー設定）
    public var userSettingsFile: URL {
        claudeDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    /// `~/.claude/CLAUDE.md`（ユーザーメモリ）
    public var userMemoryFile: URL {
        claudeDirectory.appendingPathComponent("CLAUDE.md", isDirectory: false)
    }

    /// プロジェクト側の共有設定 `<project>/.claude/settings.json`
    public func projectSettingsFile(projectDirectory: URL) -> URL {
        projectDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    /// プロジェクト側のローカル設定 `<project>/.claude/settings.local.json`
    public func projectLocalSettingsFile(projectDirectory: URL) -> URL {
        projectDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.local.json", isDirectory: false)
    }

    /// プロジェクト直下のメモリ `<project>/CLAUDE.md`
    public func projectMemoryFile(projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("CLAUDE.md", isDirectory: false)
    }
}

/// 設定の適用範囲。Claude Code の設定は「ユーザー共通」「プロジェクト共有」「プロジェクト個人」の3層。
public enum ClaudeSettingsScope: String, Sendable, CaseIterable, Identifiable {
    case user
    case project
    case projectLocal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: return "ユーザー"
        case .project: return "プロジェクト（共有）"
        case .projectLocal: return "プロジェクト（自分だけ）"
        }
    }

    public var explanation: String {
        switch self {
        case .user: return "~/.claude/settings.json — すべてのプロジェクトに効きます。"
        case .project: return ".claude/settings.json — リポジトリに入るのでチームで共有されます。"
        case .projectLocal: return ".claude/settings.local.json — 自分の環境だけに効きます（コミットされません）。"
        }
    }
}
