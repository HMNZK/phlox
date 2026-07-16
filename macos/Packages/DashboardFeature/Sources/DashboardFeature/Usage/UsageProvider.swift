import AgentDomain

public protocol UsageProvider: Sendable {
    var kind: AgentKind { get }
    func fetch() async -> CLIUsage
}
