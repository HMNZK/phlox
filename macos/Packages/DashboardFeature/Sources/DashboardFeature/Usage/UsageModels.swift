import AgentDomain
import Foundation

public struct UsageBucket: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// `.unavailable` のとき UI に提示する任意の導線。
/// （enum case の associated value はデフォルト値を持てないため、State ではなく CLIUsage 側に持たせる）
public enum UnavailableAction: Sendable, Equatable {
    /// Cursor アプリが未インストールのとき、インストール導線を出す。
    case installCursor
}

public struct CLIUsage: Sendable {
    public enum State: Sendable {
        case ok([UsageBucket])
        case unavailable(reason: String)
    }

    public let kind: AgentKind
    public let state: State
    public let updatedAt: Date
    /// `.unavailable` のときに UI へ出す導線。既定 nil なので既存生成箇所は無改修で互換。
    public let action: UnavailableAction?
    /// データ自体の時刻（取得試行時刻 updatedAt とは別。task-16 契約・既定 nil で互換）。
    public let dataAsOf: Date?

    public init(
        kind: AgentKind,
        state: State,
        updatedAt: Date,
        action: UnavailableAction? = nil,
        dataAsOf: Date? = nil
    ) {
        self.kind = kind
        self.state = state
        self.updatedAt = updatedAt
        self.action = action
        self.dataAsOf = dataAsOf
    }
}
