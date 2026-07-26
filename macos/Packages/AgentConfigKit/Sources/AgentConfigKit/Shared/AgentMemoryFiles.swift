import Foundation

/// エージェントが毎回読み込む「メモリ」ファイル1枚（CLAUDE.md / AGENTS.md など）。
///
/// Claude Code も Codex も「決まった場所に置いた Markdown を毎回読む」点は同じなので、
/// 表現と読み書きはここで共有し、どこを探すかだけを各エージェント側で決める。
public struct AgentMemoryFile: Sendable, Equatable, Identifiable {
    public enum Scope: String, Sendable, Equatable {
        case user
        case project

        public var displayName: String {
            switch self {
            case .user: return "ユーザー"
            case .project: return "プロジェクト"
            }
        }
    }

    public let scope: Scope
    public let url: URL
    /// 画面に出す名前（`~/.claude/CLAUDE.md` のように短縮したパス）。
    public let displayPath: String
    public let exists: Bool

    public var id: String { url.path }

    public var fileName: String { url.lastPathComponent }

    public init(scope: Scope, url: URL, displayPath: String, exists: Bool) {
        self.scope = scope
        self.url = url
        self.displayPath = displayPath
        self.exists = exists
    }
}

/// メモリファイルの読み書き。
public struct AgentMemoryFileStore: Sendable {
    public init() {}

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    public func read(_ file: AgentMemoryFile) throws -> String {
        guard fileManager.fileExists(atPath: file.url.path) else { return "" }
        return try String(contentsOf: file.url, encoding: .utf8)
    }

    public func write(_ text: String, to file: AgentMemoryFile) throws {
        let directory = file.url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // シンボリックリンク（例: ~/.codex/AGENTS.md → ~/.claude/AGENTS.md）は
        // リンクごと置き換えず、リンク先の実体へ書く。
        let target = (try? fileManager.destinationOfSymbolicLink(atPath: file.url.path))
            .map { path -> URL in
                path.hasPrefix("/")
                    ? URL(fileURLWithPath: path)
                    : directory.appendingPathComponent(path).standardizedFileURL
            } ?? file.url
        try Data(text.utf8).write(to: target, options: .atomic)
    }
}
