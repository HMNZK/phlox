import Foundation

/// Codex CLI の設定資産の置き場所。テストから差し替えられるよう、ホームディレクトリを注入で受ける。
public struct CodexConfigPaths: Sendable, Equatable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: CodexConfigPaths {
        CodexConfigPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `~/.codex`
    public var codexDirectory: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    /// `~/.codex/config.toml`
    public var configFile: URL {
        codexDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    /// Phlox が書き込む直前に残す控え。上書き事故から戻すための1世代だけ持つ。
    public var configBackupFile: URL {
        codexDirectory.appendingPathComponent("config.toml.phlox-backup", isDirectory: false)
    }

    /// `~/.codex/AGENTS.md`
    public var userMemoryFile: URL {
        codexDirectory.appendingPathComponent("AGENTS.md", isDirectory: false)
    }

    /// プロジェクト直下のメモリ `<project>/AGENTS.md`
    public func projectMemoryFile(projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("AGENTS.md", isDirectory: false)
    }
}
