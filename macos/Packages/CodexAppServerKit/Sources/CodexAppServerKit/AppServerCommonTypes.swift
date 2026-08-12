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

public enum ThreadSessionSource: Codable, Equatable, Sendable {
    case cli
    case vscode
    case exec
    case appServer
    case unknown
    case custom(String)
    case subAgent(JSONValue)
    case unknownRaw(JSONValue)

    public var displayName: String {
        switch self {
        case .cli: "CLI"
        case .vscode: "VS Code"
        case .exec: "Exec"
        case .appServer: "App Server"
        case .unknown: "Unknown"
        case .custom(let value): value
        case .subAgent: "Sub-agent"
        case .unknownRaw: "Unknown"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        if let value = raw.stringValue {
            switch value {
            case "cli": self = .cli
            case "vscode": self = .vscode
            case "exec": self = .exec
            case "appServer": self = .appServer
            case "unknown": self = .unknown
            default: self = .unknownRaw(raw)
            }
            return
        }
        if let custom = raw["custom"]?.stringValue, case .object = raw {
            self = .custom(custom)
        } else if let subAgent = raw["subAgent"], case .object = raw {
            self = .subAgent(subAgent)
        } else {
            self = .unknownRaw(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .cli: try JSONValue.string("cli").encode(to: encoder)
        case .vscode: try JSONValue.string("vscode").encode(to: encoder)
        case .exec: try JSONValue.string("exec").encode(to: encoder)
        case .appServer: try JSONValue.string("appServer").encode(to: encoder)
        case .unknown: try JSONValue.string("unknown").encode(to: encoder)
        case .custom(let value): try JSONValue.object(["custom": .string(value)]).encode(to: encoder)
        case .subAgent(let value): try JSONValue.object(["subAgent": value]).encode(to: encoder)
        case .unknownRaw(let value): try value.encode(to: encoder)
        }
    }
}

public typealias SessionSource = ThreadSessionSource

public struct ThreadSummary: Codable, Equatable, Sendable {
    public var id: String
    public var cliVersion: String
    public var createdAt: Int64
    public var cwd: String
    public var ephemeral: Bool
    public var modelProvider: String
    public var preview: String
    public var sessionId: String
    public var source: ThreadSessionSource
    public var name: String?
    public var status: ThreadStatus?
    public var turns: [TurnSummary]?
    public var updatedAt: Int64
    public var parentThreadId: String?
    public var canAcceptDirectInput: Bool?
    public var path: String?
    public var recencyAt: Int64?
    public var threadSource: String?

    private var raw: JSONValue?

    public init(
        id: String,
        cliVersion: String,
        createdAt: Int64,
        cwd: String,
        ephemeral: Bool,
        modelProvider: String,
        preview: String,
        sessionId: String,
        source: ThreadSessionSource,
        status: ThreadStatus?,
        turns: [TurnSummary]?,
        updatedAt: Int64,
        name: String? = nil,
        parentThreadId: String? = nil,
        canAcceptDirectInput: Bool? = nil,
        path: String? = nil,
        recencyAt: Int64? = nil,
        threadSource: String? = nil
    ) {
        self.id = id
        self.cliVersion = cliVersion
        self.createdAt = createdAt
        self.cwd = cwd
        self.ephemeral = ephemeral
        self.modelProvider = modelProvider
        self.preview = preview
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.turns = turns
        self.updatedAt = updatedAt
        self.name = name
        self.parentThreadId = parentThreadId
        self.canAcceptDirectInput = canAcceptDirectInput
        self.path = path
        self.recencyAt = recencyAt
        self.threadSource = threadSource
        self.raw = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, cliVersion, createdAt, cwd, ephemeral, modelProvider, preview, sessionId
        case source, status, turns, updatedAt, name, parentThreadId, canAcceptDirectInput
        case path, recencyAt, threadSource
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        cliVersion = try container.decodeIfPresent(String.self, forKey: .cliVersion) ?? ""
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider) ?? ""
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        source = try container.decodeIfPresent(ThreadSessionSource.self, forKey: .source) ?? .unknownRaw(.null)
        status = try container.decodeIfPresent(ThreadStatus.self, forKey: .status)
        turns = try container.decodeIfPresent([TurnSummary].self, forKey: .turns)
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        parentThreadId = try container.decodeIfPresent(String.self, forKey: .parentThreadId)
        canAcceptDirectInput = try container.decodeIfPresent(Bool.self, forKey: .canAcceptDirectInput)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        recencyAt = try container.decodeIfPresent(Int64.self, forKey: .recencyAt)
        threadSource = try container.decodeIfPresent(String.self, forKey: .threadSource)
        raw = value
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        if case .object(let original)? = raw {
            object = original
        } else {
            object = [:]
        }
        setRequired(.string(id), key: "id", into: &object)
        setRequired(.string(cliVersion), key: "cliVersion", into: &object)
        setRequired(.number(Double(createdAt)), key: "createdAt", into: &object)
        setRequired(.string(cwd), key: "cwd", into: &object)
        setRequired(.bool(ephemeral), key: "ephemeral", into: &object)
        setRequired(.string(modelProvider), key: "modelProvider", into: &object)
        setRequired(.string(preview), key: "preview", into: &object)
        setRequired(.string(sessionId), key: "sessionId", into: &object)
        setRequired(try encodeValue(source), key: "source", into: &object)
        encodeOptional(status, key: "status", into: &object)
        encodeOptional(turns, key: "turns", into: &object)
        setRequired(.number(Double(updatedAt)), key: "updatedAt", into: &object)
        encodeOptional(name, key: "name", into: &object)
        encodeOptional(parentThreadId, key: "parentThreadId", into: &object)
        encodeOptional(canAcceptDirectInput, key: "canAcceptDirectInput", into: &object)
        encodeOptional(path, key: "path", into: &object)
        encodeOptional(recencyAt, key: "recencyAt", into: &object)
        encodeOptional(threadSource, key: "threadSource", into: &object)
        try JSONValue.object(object).encode(to: encoder)
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder.appServer.encode(value)
        return try JSONDecoder.appServer.decode(JSONValue.self, from: data)
    }

    private func setRequired(_ value: JSONValue, key: String, into object: inout [String: JSONValue]) {
        if raw == nil || object[key] != nil { object[key] = value }
    }

    private func encodeOptional<T>(_ value: T?, key: String, into object: inout [String: JSONValue]) where T: Encodable {
        guard let value else {
            if object[key] == nil { object.removeValue(forKey: key) }
            return
        }
        if let encoded = try? encodeValue(value) { object[key] = encoded }
    }
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
    case image(url: String, detail: String?)
    case localImage(path: String, detail: String?)
    case skill(name: String, path: String)
    case unknown(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case url
        case path
        case detail
        case name
    }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        let type = raw["type"]?.stringValue
        switch type {
        case "text", "input_text":
            let knownKeys = Set(["type", "text"])
            self = Self.rawObjectHasOnly(raw, keys: knownKeys)
                ? .text(raw["text"]?.stringValue ?? "")
                : .unknown(raw)
        case "image_url":
            self = .unknown(raw)
        case "localImage":
            let knownKeys = Set(["type", "path", "detail"])
            self = Self.rawObjectHasOnly(raw, keys: knownKeys)
                ? .localImage(
                    path: raw["path"]?.stringValue ?? "",
                    detail: raw["detail"]?.stringValue
                )
                : .unknown(raw)
        case "skill":
            let knownKeys = Set(["type", "name", "path"])
            self = Self.rawObjectHasOnly(raw, keys: knownKeys)
                ? .skill(
                    name: raw["name"]?.stringValue ?? "",
                    path: raw["path"]?.stringValue ?? ""
                )
                : .unknown(raw)
        case "image":
            let knownKeys = Set(["type", "url", "detail"])
            if !Self.rawObjectHasOnly(raw, keys: knownKeys) {
                self = .unknown(raw)
            } else if raw["detail"] == .null {
                self = .unknown(raw)
            } else if raw["detail"] != nil {
                self = .image(url: raw["url"]?.stringValue ?? "", detail: raw["detail"]?.stringValue)
            } else {
                self = .imageURL(raw["url"]?.stringValue ?? "")
            }
        default:
            self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .unknown(let raw) = self {
            try raw.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image", forKey: .type)
            try container.encode(url, forKey: .url)
        case .image(let url, let detail):
            try container.encode("image", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(detail, forKey: .detail)
        case .localImage(let path, let detail):
            try container.encode("localImage", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(detail, forKey: .detail)
        case .skill(let name, let path):
            try container.encode("skill", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case .unknown:
            break
        }
    }

    private static func rawObjectHasOnly(_ value: JSONValue, keys: Set<String>) -> Bool {
        guard case .object(let object) = value else { return false }
        return Set(object.keys).isSubset(of: keys)
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
    case unknown(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = raw["type"]?.stringValue else {
            self = .unknown(raw)
            return
        }
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
            self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .unknown(let raw) = self {
            try raw.encode(to: encoder)
            return
        }
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
        case .unknown:
            break
        }
    }
}

public enum TurnPlanStepStatus: Codable, Equatable, Sendable {
    case pending
    case inProgress
    case completed
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "pending": self = .pending
        case "inProgress": self = .inProgress
        case "completed": self = .completed
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .pending: value = "pending"
        case .inProgress: value = "inProgress"
        case .completed: value = "completed"
        case .unknown(let unknown): value = unknown
        }
        try value.encode(to: encoder)
    }
}

public struct TurnPlanStep: Codable, Equatable, Sendable {
    public var step: String
    public var status: TurnPlanStepStatus

    public init(step: String, status: TurnPlanStepStatus) {
        self.step = step
        self.status = status
    }
}

public struct TurnPlanUpdatedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var plan: [TurnPlanStep]
    public var explanation: String?

    private var raw: JSONValue?

    public init(threadId: String, turnId: String, plan: [TurnPlanStep], explanation: String? = nil) {
        self.threadId = threadId
        self.turnId = turnId
        self.plan = plan
        self.explanation = explanation
        self.raw = nil
    }

    private enum CodingKeys: String, CodingKey {
        case threadId, turnId, plan, explanation
    }

    public init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        turnId = try container.decode(String.self, forKey: .turnId)
        plan = try container.decode([TurnPlanStep].self, forKey: .plan)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        if case .object(let original)? = raw { object = original } else { object = [:] }
        object["threadId"] = .string(threadId)
        object["turnId"] = .string(turnId)
        object["plan"] = try encodeValue(plan)
        try encodeOptional(explanation, key: "explanation", into: &object)
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
