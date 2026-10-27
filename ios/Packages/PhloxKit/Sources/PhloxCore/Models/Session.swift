import AgentDomain
import Foundation

/// 一覧・詳細画面が必要とする 1 セッションの集約モデル（architecture.md §4）。
///
/// `status` は共有 AgentDomain のリッチ enum（associated value を保持）。一覧の「あなたの番」
/// 表示に使う `needsAttention` は `SessionStatus.needsAttention` から一貫導出する。
/// wire/JSON からの組み立て（Mac の flat な status 文字列の復元）は E3-1（PhloxNetworking DTO）の責務。
public struct Session: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let agent: AgentKind
    public let status: SessionStatus
    /// 承認待ち = 「あなたの番」。原則 `status.needsAttention` から導出する（便宜 init 参照）。
    public let needsAttention: Bool
    /// 「ファイル削除の承認待ち · 2分前」等の補助テキスト。
    public let subtitle: String
    public let projectId: String?
    public let projectName: String?
    /// `"pty"` for terminal sessions, `"appServer"` for structured conversations.
    public let backend: String
    public let isStalled: Bool
    public let hasUnseenCompletion: Bool
    public let completionToken: String?
    public let parentSessionId: String?
    public let statusEnteredAt: Date?
    public let updatedAt: Date

    /// Whether this session runs in the terminal backend.
    public var isPTY: Bool { backend == "pty" }

    /// 全フィールドを明示するイニシャライザ。
    /// `needsAttention` をテスト等で意図的に上書きしたい場合に使う。
    public init(
        id: String,
        name: String,
        agent: AgentKind,
        status: SessionStatus,
        needsAttention: Bool,
        subtitle: String,
        projectId: String? = nil,
        projectName: String? = nil,
        backend: String = "appServer",
        isStalled: Bool = false,
        hasUnseenCompletion: Bool = false,
        completionToken: String? = nil,
        parentSessionId: String? = nil,
        statusEnteredAt: Date? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.agent = agent
        self.status = status
        self.needsAttention = needsAttention
        self.subtitle = subtitle
        self.projectId = projectId
        self.projectName = projectName
        self.backend = backend
        self.isStalled = isStalled
        self.hasUnseenCompletion = hasUnseenCompletion
        self.completionToken = completionToken
        self.parentSessionId = parentSessionId
        self.statusEnteredAt = statusEnteredAt
        self.updatedAt = updatedAt
    }

    /// 便宜イニシャライザ: `needsAttention` を `status` から一貫導出する。
    /// 通常の構築経路はこちらを使い、判定の二重化を避ける。
    public init(
        id: String,
        name: String,
        agent: AgentKind,
        status: SessionStatus,
        subtitle: String = "",
        projectId: String? = nil,
        projectName: String? = nil,
        backend: String = "appServer",
        isStalled: Bool = false,
        hasUnseenCompletion: Bool = false,
        completionToken: String? = nil,
        parentSessionId: String? = nil,
        statusEnteredAt: Date? = nil,
        updatedAt: Date
    ) {
        self.init(
            id: id,
            name: name,
            agent: agent,
            status: status,
            needsAttention: status.needsAttention,
            subtitle: subtitle,
            projectId: projectId,
            projectName: projectName,
            backend: backend,
            isStalled: isStalled,
            hasUnseenCompletion: hasUnseenCompletion,
            completionToken: completionToken,
            parentSessionId: parentSessionId,
            statusEnteredAt: statusEnteredAt,
            updatedAt: updatedAt
        )
    }
}
