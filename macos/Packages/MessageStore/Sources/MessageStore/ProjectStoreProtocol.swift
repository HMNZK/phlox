import AgentDomain
import Foundation

public protocol ProjectStoreProtocol: Sendable {
    func load() async -> [Project]
    func save(_ projects: [Project]) async throws
}
