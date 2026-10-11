import AgentDomain
import Foundation

/// セッションの永続化ストアの抽象。
/// 実装は actor で thread-safe に行う。
public protocol SessionStoreProtocol: Sendable {
    func load() async -> [PersistedSessionDescriptor]
    func save(_ sessions: [PersistedSessionDescriptor]) async throws
    func takeDiscardedSessionCount() async -> Int
}

public extension SessionStoreProtocol {
    func takeDiscardedSessionCount() async -> Int { 0 }
}
