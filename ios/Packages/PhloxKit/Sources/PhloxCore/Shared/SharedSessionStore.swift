import Foundation

public struct SharedSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let statusLabel: String
    public let title: String
    public let detail: String
    public let updatedAt: Date

    public init(
        id: String,
        statusLabel: String,
        title: String,
        detail: String,
        updatedAt: Date
    ) {
        self.id = id
        self.statusLabel = statusLabel
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct SharedSessionStore {
    public static let appGroupIdentifier = "group.com.phlox.mobile"
    public static let widgetKind = "SessionStatusWidget"

    private static let storageKey = "phlox.shared-session-summaries.v1"
    private let userDefaults: UserDefaults

    public init?(suiteName: String = Self.appGroupIdentifier) {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.userDefaults = userDefaults
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func write(_ summaries: [SharedSessionSummary]) throws {
        userDefaults.set(try Self.encode(summaries), forKey: Self.storageKey)
    }

    public func read() throws -> [SharedSessionSummary] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return [] }
        return try Self.decode(data)
    }

    public static func encode(_ summaries: [SharedSessionSummary]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(summaries)
    }

    public static func decode(_ data: Data) throws -> [SharedSessionSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode([SharedSessionSummary].self, from: data)
    }
}
