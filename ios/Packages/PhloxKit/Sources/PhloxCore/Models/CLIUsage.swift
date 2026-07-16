import Foundation

public enum CLIUsageState: String, Sendable, Equatable, Decodable {
    case ok
    case unavailable
}

public struct UsageBucket: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct CLIUsage: Sendable, Equatable, Decodable {
    public let kind: AgentKind
    public let state: CLIUsageState
    public let buckets: [UsageBucket]
    public let updatedAt: Date?
    public let dataAsOf: Date?

    public init(
        kind: AgentKind,
        state: CLIUsageState,
        buckets: [UsageBucket],
        updatedAt: Date?,
        dataAsOf: Date?
    ) {
        self.kind = kind
        self.state = state
        self.buckets = buckets
        self.updatedAt = updatedAt
        self.dataAsOf = dataAsOf
    }
}
