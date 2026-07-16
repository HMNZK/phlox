import AgentDomain
import Foundation

public protocol MessageStoreProtocol: Sendable {
    func record(_ message: AgentMessage) async
    func recent(limit: Int) async -> [AgentMessage]
    func message(id: UUID) async -> AgentMessage?
    func thread(rootID: UUID) async -> [AgentMessage]
}
