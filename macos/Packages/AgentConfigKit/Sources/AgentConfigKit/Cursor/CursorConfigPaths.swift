import Foundation

/// Cursor Agent の設定資産の置き場所。テストから差し替えられるよう、ホームディレクトリを注入で受ける。
public struct CursorConfigPaths: Sendable, Equatable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: CursorConfigPaths {
        CursorConfigPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `~/.cursor`
    public var cursorDirectory: URL {
        homeDirectory.appendingPathComponent(".cursor", isDirectory: true)
    }

    /// `~/.cursor/cli-config.json`
    public var configFile: URL {
        cursorDirectory.appendingPathComponent("cli-config.json", isDirectory: false)
    }

    /// `~/.cursor/mcp.json`
    public var mcpFile: URL {
        cursorDirectory.appendingPathComponent("mcp.json", isDirectory: false)
    }

    /// プロジェクト側の MCP 設定 `<project>/.cursor/mcp.json`
    public func projectMCPFile(projectDirectory: URL) -> URL {
        projectDirectory
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("mcp.json", isDirectory: false)
    }
}
