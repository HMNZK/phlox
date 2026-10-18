import Foundation

public struct SharedSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let statusLabel: String
    public let title: String
    public let detail: String
    public let updatedAt: Date
    /// nil は旧保存形式。文字列にして未知の将来値もデコード可能にする。
    public let displayState: String?

    public init(
        id: String,
        statusLabel: String,
        title: String,
        detail: String,
        updatedAt: Date,
        displayState: String? = nil
    ) {
        self.id = id
        self.statusLabel = statusLabel
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
        self.displayState = displayState
    }

    public var glanceState: SessionGlanceState {
        if let displayState { return SessionGlanceState(rawValue: displayState) ?? .unknown }
        // v1 のラベルと補足から、保存済みの表示だけを復元する。
        switch statusLabel {
        case "Starting": return .starting
        case "Running": return .running
        case "Finished": return .done
        case "Error": return .error
        case "Waiting":
            if detail == "Approval required" { return .approval }
            if detail == "Input required" { return .question }
            return .idle
        default: return .unknown
        }
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
