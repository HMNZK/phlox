import AgentDomain
import Foundation

/// `AppEnvironment.init` のデフォルト引数・テスト用。永続化は行わない。
public struct NoOpProjectStore: ProjectStoreProtocol, Sendable {
    public init() {}

    public func load() async -> [Project] {
        []
    }

    public func save(_ projects: [Project]) async throws {}
}
