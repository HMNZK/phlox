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
    public let titleUserMessages: [String]?
    public let titleSummary: String?

    public init(
        sessionID: String,
        preview: String,
        firstUserAt: Date?,
        lastModified: Date,
        gitBranch: String?,
        fileURL: URL,
        titleUserMessages: [String]? = nil,
        titleSummary: String? = nil
    ) {
        self.sessionID = sessionID
        self.preview = preview
        self.firstUserAt = firstUserAt
        self.lastModified = lastModified
        self.gitBranch = gitBranch
        self.fileURL = fileURL
        self.titleUserMessages = titleUserMessages
        self.titleSummary = titleSummary
    }

    /// 再開時に会話へ読み込む発言の上限（新しい方から）。履歴カードの件数もこの上限で頭打ちになる。
    public static let transcriptItemLimit = 500
}

/// 履歴カードの件数と最後の発言（PhloxChat の履歴カード「18 件 · ブランチ」「最後: …」。C-21）。
public struct ChatHistorySummary: Equatable, Sendable {
    public let messageCount: Int
    /// 読み込み上限に届いた（実際はもっと多い）。
    public let reachesLimit: Bool
    public let lastMessage: String?

    init(items: [ChatItem], limit: Int = ClaudeSessionHistoryEntry.transcriptItemLimit) {
        let texts = items.compactMap { item -> String? in
            switch item {
            case .userMessage(_, let text, _, _), .agentMessage(_, let text, _): text
            default: nil
            }
        }
        messageCount = texts.count
        reachesLimit = items.count >= limit
        lastMessage = texts.last.map {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
