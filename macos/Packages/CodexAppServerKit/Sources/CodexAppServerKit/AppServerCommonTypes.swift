// JSON-RPC リクエスト/レスポンスの両方から参照される共通値型。
import Foundation

public struct ClientInfo: Codable, Equatable, Sendable {
    public var name: String
    public var title: String?
    public var version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct InitializeCapabilities: Codable, Equatable, Sendable {
    public var experimentalApi: Bool?
    public var optOutNotificationMethods: [String]?
    public var requestAttestation: Bool?

    public init(
        experimentalApi: Bool? = nil,
        optOutNotificationMethods: [String]? = nil,
        requestAttestation: Bool? = nil
    ) {
        self.experimentalApi = experimentalApi
        self.optOutNotificationMethods = optOutNotificationMethods
        self.requestAttestation = requestAttestation
    }
}

public enum ThreadSource: String, Sendable {
    case user
    case subagent
    case memoryConsolidation = "memory_consolidation"
}

public enum SessionStartSource: String, Sendable {
    case startup
    case clear
}

public struct ThreadSummary: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var status: ThreadStatus?
    public var turns: [TurnSummary]?
}

public struct AppServerModel: Codable, Equatable, Sendable {
    public var id: String
    public var model: String?
    public var displayName: String
    public var description: String?
    public var hidden: Bool?
    public var supportedReasoningEfforts: [ReasoningEffortOption]
    public var defaultReasoningEffort: String
    public var isDefault: Bool
    public var inputModalities: [String]?
    public var supportsPersonality: Bool?
    public var serviceTiers: [ModelServiceTier]?
    public var defaultServiceTier: String?
}

public struct ReasoningEffortOption: Codable, Equatable, Sendable {
    public var reasoningEffort: String
    public var description: String

    public init(reasoningEffort: String, description: String = "") {
        self.reasoningEffort = reasoningEffort
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.reasoningEffort = value
            self.description = ""
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.reasoningEffort = try keyed.decode(String.self, forKey: .reasoningEffort)
        self.description = try keyed.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct ModelServiceTier: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
}

public struct PermissionProfileSummary: Codable, Equatable, Sendable {
    public var id: String
    public var description: String?
}

public struct CollaborationModeMask: Codable, Equatable, Sendable {
    public var name: String
    public var mode: CollaborationModeKind?
    public var model: String?
    public var reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case mode
        case model
        case reasoningEffort = "reasoning_effort"
    }
}

public enum CollaborationModeKind: String, Codable, Equatable, Sendable {
    case plan
    case `default`
}

public struct CollaborationMode: Codable, Equatable, Sendable {
    public var mode: CollaborationModeKind
    public var settings: CollaborationModeSettings

    public init(mode: CollaborationModeKind, settings: CollaborationModeSettings) {
        self.mode = mode
        self.settings = settings
    }
}

public struct CollaborationModeSettings: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String?
    public var developerInstructions: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case reasoningEffort = "reasoning_effort"
        case developerInstructions = "developer_instructions"
    }

    public init(model: String, reasoningEffort: String? = nil, developerInstructions: String? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.developerInstructions = developerInstructions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(developerInstructions, forKey: .developerInstructions)
    }
}

public struct ThreadSettings: Codable, Equatable, Sendable {
    public var cwd: String
    public var model: String
    public var modelProvider: String
    public var effort: String?
    public var approvalPolicy: ApprovalPolicy
    public var approvalsReviewer: String
    public var sandboxPolicy: SandboxPolicy
    public var activePermissionProfile: ActivePermissionProfile?
    public var serviceTier: String?
    public var collaborationMode: CollaborationMode
}

public struct ActivePermissionProfile: Codable, Equatable, Sendable {
    public var id: String
    public var extends: String?
}

public enum UserInput: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text", "input_text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            self = .imageURL(try container.decode(String.self, forKey: .imageURL))
        default:
            self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(url, forKey: .imageURL)
        }
    }
}

public enum ApprovalPolicy: Codable, Equatable, Sendable {
    case named(String)
    case granular(JSONValue)

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        if let string = value.stringValue {
            self = .named(string)
        } else {
            self = .granular(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .named(let value):
            try value.encode(to: encoder)
        case .granular(let value):
            try value.encode(to: encoder)
        }
    }
}

public enum SandboxPolicy: Codable, Equatable, Sendable {
    case named(String)
    case object(JSONValue)

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        if let string = value.stringValue {
            self = .named(string)
        } else {
            self = .object(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .named(let value):
            try value.encode(to: encoder)
        case .object(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct TurnSummary: Codable, Equatable, Sendable {
    public var id: String?
    public var status: String?
    public var items: [ThreadItem]?
}

public struct ThreadItem: Codable, Equatable, Sendable {
    public var id: String?
    public var itemId: String?
    public var type: String?
    public var text: String?
    public var raw: JSONValue?

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        self.raw = raw
        self.id = raw["id"]?.stringValue
        self.itemId = raw["itemId"]?.stringValue
        self.type = raw["type"]?.stringValue
        self.text = raw["text"]?.stringValue
    }

    public func encode(to encoder: Encoder) throws {
        try raw?.encode(to: encoder)
    }
}

public enum ThreadStatus: Codable, Equatable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(flags: [String])
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "systemError":
            self = .systemError
        case "active":
            self = .active(flags: (try? container.decode([String].self, forKey: .activeFlags)) ?? [])
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded:
            try container.encode("notLoaded", forKey: .type)
        case .idle:
            try container.encode("idle", forKey: .type)
        case .systemError:
            try container.encode("systemError", forKey: .type)
        case .active(let flags):
            try container.encode("active", forKey: .type)
            try container.encode(flags, forKey: .activeFlags)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

public struct TokenUsageBreakdown: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var cachedInputTokens: Int?
    public var outputTokens: Int?
    public var reasoningOutputTokens: Int?
    public var totalTokens: Int?
}

public struct ThreadTokenUsage: Codable, Equatable, Sendable {
    public var last: TokenUsageBreakdown?
    public var total: TokenUsageBreakdown?
    public var modelContextWindow: Int?
}

public struct FilePatchChange: Codable, Equatable, Sendable {
    public var path: String
    public var diff: String
    public var kind: JSONValue?

    public init(path: String, diff: String, kind: JSONValue? = nil) {
        self.path = path
        self.diff = diff
        self.kind = kind
    }
}
