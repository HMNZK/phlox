// JSON-RPC レスポンス型。
import Foundation

public struct InitializeResponse: Codable, Equatable, Sendable {
    public var codexHome: String
    public var platformFamily: String
    public var platformOs: String
    public var userAgent: String
}

public struct ThreadResponse: Codable, Equatable, Sendable {
    public var thread: ThreadSummary
    public var cwd: String?
    public var model: String?
    public var modelProvider: String?
    public var reasoningEffort: String?
    public var activePermissionProfile: ActivePermissionProfile?
    public var approvalPolicy: ApprovalPolicy?
    public var approvalsReviewer: String?
    public var sandbox: SandboxPolicy?
    public var serviceTier: String?
}

public struct ThreadReadResponse: Codable, Equatable, Sendable {
    public var thread: ThreadSummary
}

public struct ThreadListResponse: Codable, Equatable, Sendable {
    public var data: [ThreadSummary]
    public var nextCursor: String?
    public var backwardsCursor: String?

    private var raw: JSONValue?

    public init(data: [ThreadSummary], nextCursor: String? = nil, backwardsCursor: String? = nil) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
        self.raw = nil
    }

    private enum CodingKeys: String, CodingKey {
        case data, nextCursor, backwardsCursor
    }

    public init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ThreadSummary].self, forKey: .data)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        backwardsCursor = try container.decodeIfPresent(String.self, forKey: .backwardsCursor)
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        if case .object(let original)? = raw { object = original } else { object = [:] }
        object["data"] = try encodeValue(data)
        try encodeOptional(nextCursor, key: "nextCursor", into: &object)
        try encodeOptional(backwardsCursor, key: "backwardsCursor", into: &object)
        try JSONValue.object(object).encode(to: encoder)
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder.appServer.decode(JSONValue.self, from: JSONEncoder.appServer.encode(value))
    }

    private func encodeOptional<T: Encodable>(_ value: T?, key: String, into object: inout [String: JSONValue]) throws {
        guard let value else {
            if case .object(let original)? = raw, original[key] == .null {
                object[key] = .null
            } else {
                object.removeValue(forKey: key)
            }
            return
        }
        object[key] = try encodeValue(value)
    }
}

public struct TurnStartResponse: Codable, Equatable, Sendable {}

public struct TurnInterruptResponse: Codable, Equatable, Sendable {}

public struct ModelListResponse: Codable, Equatable, Sendable {
    public var data: [AppServerModel]
    public var nextCursor: String?
}

public enum SkillScope: Codable, Equatable, Sendable {
    case user
    case repo
    case system
    case admin
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "user": self = .user
        case "repo": self = .repo
        case "system": self = .system
        case "admin": self = .admin
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .user: value = "user"
        case .repo: value = "repo"
        case .system: value = "system"
        case .admin: value = "admin"
        case .unknown(let unknown): value = unknown
        }
        try value.encode(to: encoder)
    }
}

public struct SkillErrorInfo: Codable, Equatable, Sendable {
    public var message: String
    public var path: String

    public init(message: String, path: String) {
        self.message = message
        self.path = path
    }
}

public struct SkillMetadata: Codable, Equatable, Sendable {
    public var description: String
    public var enabled: Bool
    public var name: String
    public var path: String
    public var scope: SkillScope
    public var shortDescription: String?
    public var dependencies: JSONValue?
    public var interface: JSONValue?

    public init(
        description: String,
        enabled: Bool,
        name: String,
        path: String,
        scope: SkillScope,
        shortDescription: String? = nil,
        dependencies: JSONValue? = nil,
        interface: JSONValue? = nil
    ) {
        self.description = description
        self.enabled = enabled
        self.name = name
        self.path = path
        self.scope = scope
        self.shortDescription = shortDescription
        self.dependencies = dependencies
        self.interface = interface
    }
}

public struct SkillsListEntry: Codable, Equatable, Sendable {
    public var cwd: String
    public var errors: [SkillErrorInfo]
    public var skills: [SkillMetadata]

    public init(cwd: String, errors: [SkillErrorInfo], skills: [SkillMetadata]) {
        self.cwd = cwd
        self.errors = errors
        self.skills = skills
    }
}

public struct SkillsListResponse: Codable, Equatable, Sendable {
    public var data: [SkillsListEntry]

    public init(data: [SkillsListEntry]) {
        self.data = data
    }
}

public struct PermissionProfileListResponse: Codable, Equatable, Sendable {
    public var data: [PermissionProfileSummary]
    public var nextCursor: String?
}

public struct CollaborationModeListResponse: Codable, Equatable, Sendable {
    public var data: [CollaborationModeMask]
}

public struct ThreadSettingsUpdateResponse: Codable, Equatable, Sendable {
    public init() {}
}
