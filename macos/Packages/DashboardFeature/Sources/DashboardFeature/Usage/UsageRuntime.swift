import AgentDomain
import Foundation

public struct UsageRuntimeSnapshot: Codable, Sendable {
    public var usages: [AgentKind: CLIUsage]
    public var failures: [AgentKind: UsageFailure]

    public init(usages: [AgentKind: CLIUsage], failures: [AgentKind: UsageFailure]) {
        self.usages = usages
        self.failures = failures
    }
}

public enum UsageRuntimeCommand: Codable, Sendable {
    case refresh([AgentKind])
    case settingsChanged
}

public typealias UsageRuntimeCommandHandler = @MainActor (UsageRuntimeCommand) async throws -> Void
