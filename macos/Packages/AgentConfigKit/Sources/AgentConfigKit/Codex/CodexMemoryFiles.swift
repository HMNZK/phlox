import Foundation

/// Codex のメモリファイル（AGENTS.md）の探索と読み書き。
public struct CodexMemoryFiles: Sendable {
    private let paths: CodexConfigPaths
    private let store = AgentMemoryFileStore()

    public init(paths: CodexConfigPaths) {
        self.paths = paths
    }

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    public func discover(projectDirectory: URL?) -> [AgentMemoryFile] {
        var files: [AgentMemoryFile] = [
            AgentMemoryFile(
                scope: .user,
                url: paths.userMemoryFile,
                displayPath: "~/.codex/AGENTS.md",
                exists: fileManager.fileExists(atPath: paths.userMemoryFile.path)
            )
        ]

        if let projectDirectory {
            let url = paths.projectMemoryFile(projectDirectory: projectDirectory)
            files.append(
                AgentMemoryFile(
                    scope: .project,
                    url: url,
                    displayPath: "\(projectDirectory.lastPathComponent)/AGENTS.md",
                    exists: fileManager.fileExists(atPath: url.path)
                )
            )
        }

        return files
    }

    public func read(_ file: AgentMemoryFile) throws -> String {
        try store.read(file)
    }

    public func write(_ text: String, to file: AgentMemoryFile) throws {
        try store.write(text, to: file)
    }

    /// シンボリックリンクなら、その実体のパスを返す（画面で「どこに書くか」を示すため）。
    public func symlinkTarget(of file: AgentMemoryFile) -> String? {
        try? fileManager.destinationOfSymbolicLink(atPath: file.url.path)
    }
}
