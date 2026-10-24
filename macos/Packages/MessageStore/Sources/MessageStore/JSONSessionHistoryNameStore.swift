import AgentDomain
import Foundation

public struct SessionHistoryKey: Codable, Hashable, Sendable {
    public let agentRef: AgentRef
    public let nativeSessionID: String

    public init(agentRef: AgentRef, nativeSessionID: String) {
        self.agentRef = agentRef
        self.nativeSessionID = UUID(uuidString: nativeSessionID)?.uuidString.lowercased() ?? nativeSessionID
    }
}

public actor JSONSessionHistoryNameStore {
    private struct Record: Codable, Sendable {
        let key: SessionHistoryKey
        let name: String
    }

    private let store: JSONFileStore<[Record]>?
    private var memory: [Record] = []

    public init(fileURL: URL? = nil) {
        store = fileURL.map { JSONFileStore(fileURL: $0, category: "SessionHistoryNames") }
    }

    public func names() -> [SessionHistoryKey: String] {
        Dictionary((store?.load() ?? memory).map { ($0.key, $0.name) }, uniquingKeysWith: { _, latest in latest })
    }

    public func record(key: SessionHistoryKey, name: String) throws {
        var records = store?.load() ?? memory
        records.removeAll { $0.key == key }
        records.append(Record(key: key, name: name))
        try store?.save(records)
        memory = records
    }
}
