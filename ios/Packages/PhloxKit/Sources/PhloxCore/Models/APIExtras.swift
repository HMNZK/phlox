import Foundation

// API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md）のドメイン型。
// 公開面は契約で凍結済み。実装（PhloxAPIClient のメソッド本体）は task-7 が担う。

/// サブエージェントの実行状態（契約 §2: running / completed / unknown の3値）。
public enum SubAgentStatus: String, Sendable, Equatable {
    case running
    case completed
    case unknown
}

/// セッション配下のサブエージェント要約（契約 §2 / GET /sessions/{id}/subagents）。
public struct SubAgentSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let status: SubAgentStatus
    public let messageCount: Int
    /// `/messages` 本文中の type=subAgent メッセージ id との対応（行タップ→詳細の解決に使う）。
    public let markerMessageID: String?

    public init(
        id: String,
        name: String,
        status: SubAgentStatus,
        messageCount: Int,
        markerMessageID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.messageCount = messageCount
        self.markerMessageID = markerMessageID
    }
}

/// 直近ターンのコスト・コンテキスト使用量（契約 §4 / GET /sessions/{id}/usage）。
/// 各フィールドは欠落可（nullable）。欠落は「不明」として扱い 0 と区別する。
public struct TurnUsage: Sendable, Equatable {
    public let costUSD: Double?
    public let contextUsedTokens: Int?
    public let contextWindowTokens: Int?

    public init(costUSD: Double?, contextUsedTokens: Int?, contextWindowTokens: Int?) {
        self.costUSD = costUSD
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
    }
}

/// 差分取得の結果（契約 §6 / GET /sessions/{id}/messages?since=…&wait=…）。
/// isSnapshot=true は全量スナップショット（クライアントは手元を全置換する）。
public struct MessagesDelta: Sendable, Equatable {
    public let messages: [ChatMessage]
    public let cursor: String?
    public let isSnapshot: Bool

    public init(messages: [ChatMessage], cursor: String?, isSnapshot: Bool) {
        self.messages = messages
        self.cursor = cursor
        self.isSnapshot = isSnapshot
    }
}
