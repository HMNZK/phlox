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

public struct CLIUsage: Sendable {
    public enum State: Sendable {
        case ok([UsageBucket])
        case unavailable(reason: String)
    }

    public let kind: AgentKind
    public let state: State
    public let updatedAt: Date
    /// データ自体の時刻（取得試行時刻 updatedAt とは別。task-16 契約・既定 nil で互換）。
    public let dataAsOf: Date?

    public init(
        kind: AgentKind,
        state: State,
        updatedAt: Date,
        dataAsOf: Date? = nil
    ) {
        self.kind = kind
        self.state = state
        self.updatedAt = updatedAt
        self.dataAsOf = dataAsOf
    }
}
