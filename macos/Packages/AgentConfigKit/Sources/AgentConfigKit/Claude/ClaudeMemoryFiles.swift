import Foundation

/// Claude Code のメモリファイルの探索と読み書き。
/// 表現と読み書きの実体は `AgentMemoryFile` / `AgentMemoryFileStore` に置く。
public struct ClaudeMemoryFiles: Sendable {
    private let paths: ClaudeConfigPaths
    private let store = AgentMemoryFileStore()

    public init(paths: ClaudeConfigPaths) {
        self.paths = paths
    }

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    /// ユーザー用と（あれば）プロジェクト用のメモリを列挙する。
    /// 実在しないものも「まだ無い」枠として返す（新規作成の入口にするため）。
    public func discover(projectDirectory: URL?) -> [AgentMemoryFile] {
        var files: [AgentMemoryFile] = []

        for name in ["CLAUDE.md", "AGENTS.md"] {
            let url = paths.claudeDirectory.appendingPathComponent(name, isDirectory: false)
            files.append(
                AgentMemoryFile(
                    scope: .user,
                    url: url,
                    displayPath: "~/.claude/\(name)",
                    exists: fileManager.fileExists(atPath: url.path)
                )
            )
        }

        if let projectDirectory {
            for name in ["CLAUDE.md", "AGENTS.md"] {
                let url = projectDirectory.appendingPathComponent(name, isDirectory: false)
                files.append(
                    AgentMemoryFile(
                        scope: .project,
                        url: url,
                        displayPath: "\(projectDirectory.lastPathComponent)/\(name)",
                        exists: fileManager.fileExists(atPath: url.path)
                    )
                )
            }
        }

        return files
    }

    public func read(_ file: AgentMemoryFile) throws -> String {
        try store.read(file)
    }

    public func write(_ text: String, to file: AgentMemoryFile) throws {
        try store.write(text, to: file)
    }
}
