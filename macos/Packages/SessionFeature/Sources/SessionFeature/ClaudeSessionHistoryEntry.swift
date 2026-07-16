import Foundation

/// `~/.claude/projects/` 配下の過去セッション 1 件のメタ情報。
///
/// 履歴ピッカー（`ChatHistoryStartView`）と再開フロー（`ChatSessionViewModel`）が
/// 消費する Session ドメインのデータ型。生成元の走査ロジック
/// （`ClaudeSessionHistoryDiscovery` / `ClaudeSessionTranscriptLoader`・Spawn 側）は
/// この型を注入クロージャ経由で供給する（依存方向: Dashboard/Spawn → Session の一方向）。
public struct ClaudeSessionHistoryEntry: Equatable, Sendable, Identifiable {
    public var id: String { sessionID }
    public let sessionID: String
    public let preview: String
    public let firstUserAt: Date?
    public let lastModified: Date
    public let gitBranch: String?
    public let fileURL: URL

    public init(
        sessionID: String,
        preview: String,
        firstUserAt: Date?,
        lastModified: Date,
        gitBranch: String?,
        fileURL: URL
    ) {
        self.sessionID = sessionID
        self.preview = preview
        self.firstUserAt = firstUserAt
        self.lastModified = lastModified
        self.gitBranch = gitBranch
        self.fileURL = fileURL
    }
}
