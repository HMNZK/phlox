// JSON-RPC リクエスト Params 型。
import Foundation

public struct InitializeParams: Codable, Equatable, Sendable {
    public var clientInfo: ClientInfo
    public var capabilities: InitializeCapabilities?

    public init(clientInfo: ClientInfo, capabilities: InitializeCapabilities? = nil) {
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }
}

public struct ThreadStartParams: Codable, Equatable, Sendable {
    public var cwd: String?
    public var model: String?
    public var modelProvider: String?
    public var approvalPolicy: ApprovalPolicy?
    public var approvalsReviewer: String?
    public var sandbox: SandboxPolicy?
    public var baseInstructions: String?
    public var developerInstructions: String?
    public var serviceName: String?
    public var threadSource: String?
    public var ephemeral: Bool?
    public var serviceTier: String?
    public var sessionStartSource: String?
    public var personality: String?

    public init(
        cwd: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        approvalsReviewer: String? = nil,
        sandbox: SandboxPolicy? = nil,
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        serviceName: String? = nil,
        threadSource: String? = nil,
        ephemeral: Bool? = nil,
        serviceTier: String? = nil,
        sessionStartSource: String? = nil,
        personality: String? = nil
    ) {
        self.cwd = cwd
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.serviceName = serviceName
        self.threadSource = threadSource
        self.ephemeral = ephemeral
        self.serviceTier = serviceTier
        self.sessionStartSource = sessionStartSource
        self.personality = personality
    }
}

public struct ThreadResumeParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var cwd: String?
    public var model: String?
    public var modelProvider: String?
    public var approvalPolicy: ApprovalPolicy?
    public var approvalsReviewer: String?
    public var sandbox: SandboxPolicy?
    public var baseInstructions: String?
    public var developerInstructions: String?
    public var serviceTier: String?
    public var personality: String?

    public init(
        threadId: String,
        cwd: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        approvalsReviewer: String? = nil,
        sandbox: SandboxPolicy? = nil,
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        serviceTier: String? = nil,
        personality: String? = nil
    ) {
        self.threadId = threadId
        self.cwd = cwd
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.serviceTier = serviceTier
        self.personality = personality
    }
}

public struct ThreadReadParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var includeTurns: Bool

    public init(threadId: String, includeTurns: Bool = true) {
        self.threadId = threadId
        self.includeTurns = includeTurns
    }
}

public enum ThreadListCwdFilter: Codable, Equatable, Sendable {
    case single(String)
    case multiple([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
        } else {
            self = .multiple(try container.decode([String].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .single(let value): try value.encode(to: encoder)
        case .multiple(let value): try value.encode(to: encoder)
        }
    }
}

public enum ThreadSourceKind: Codable, Equatable, Sendable {
    case cli
    case vscode
    case exec
    case appServer
    case subAgent
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "cli": self = .cli
        case "vscode": self = .vscode
        case "exec": self = .exec
        case "appServer": self = .appServer
        case "subAgent": self = .subAgent
        case "subAgentReview": self = .subAgentReview
        case "subAgentCompact": self = .subAgentCompact
        case "subAgentThreadSpawn": self = .subAgentThreadSpawn
        case "subAgentOther": self = .subAgentOther
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .cli: value = "cli"
        case .vscode: value = "vscode"
        case .exec: value = "exec"
        case .appServer: value = "appServer"
        case .subAgent: value = "subAgent"
        case .subAgentReview: value = "subAgentReview"
        case .subAgentCompact: value = "subAgentCompact"
        case .subAgentThreadSpawn: value = "subAgentThreadSpawn"
        case .subAgentOther: value = "subAgentOther"
        case .unknown(let unknown): value = unknown
        }
        try value.encode(to: encoder)
    }
}

public struct ThreadListParams: Codable, Equatable, Sendable {
    public var cwd: ThreadListCwdFilter?
    public var sourceKinds: [ThreadSourceKind]?
    public var limit: UInt32?
    public var parentThreadId: String?
    public var ancestorThreadId: String?
    public var archived: Bool?
    public var cursor: String?
    public var modelProviders: [String]?
    public var searchTerm: String?
    public var sectionId: String?
    public var sortDirection: String?
    public var sortKey: String?
    public var useStateDbOnly: Bool?

    private var raw: JSONValue?

    public init(
        cwd: ThreadListCwdFilter? = nil,
        sourceKinds: [ThreadSourceKind]? = nil,
        limit: UInt32? = nil,
        parentThreadId: String? = nil,
        ancestorThreadId: String? = nil,
        archived: Bool? = nil,
        cursor: String? = nil,
        modelProviders: [String]? = nil,
        searchTerm: String? = nil,
        sectionId: String? = nil,
        sortDirection: String? = nil,
        sortKey: String? = nil,
        useStateDbOnly: Bool? = nil
    ) {
        self.cwd = cwd
        self.sourceKinds = sourceKinds
        self.limit = limit
        self.parentThreadId = parentThreadId
        self.ancestorThreadId = ancestorThreadId
        self.archived = archived
        self.cursor = cursor
        self.modelProviders = modelProviders
        self.searchTerm = searchTerm
        self.sectionId = sectionId
        self.sortDirection = sortDirection
        self.sortKey = sortKey
        self.useStateDbOnly = useStateDbOnly
        self.raw = nil
    }

    private enum CodingKeys: String, CodingKey {
        case cwd, sourceKinds, limit, parentThreadId, ancestorThreadId, archived
        case cursor, modelProviders, searchTerm, sectionId, sortDirection, sortKey
        case useStateDbOnly
    }

    public init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decodeIfPresent(ThreadListCwdFilter.self, forKey: .cwd)
        sourceKinds = try container.decodeIfPresent([ThreadSourceKind].self, forKey: .sourceKinds)
        limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
        parentThreadId = try container.decodeIfPresent(String.self, forKey: .parentThreadId)
        ancestorThreadId = try container.decodeIfPresent(String.self, forKey: .ancestorThreadId)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        modelProviders = try container.decodeIfPresent([String].self, forKey: .modelProviders)
        searchTerm = try container.decodeIfPresent(String.self, forKey: .searchTerm)
        sectionId = try container.decodeIfPresent(String.self, forKey: .sectionId)
        sortDirection = try container.decodeIfPresent(String.self, forKey: .sortDirection)
        sortKey = try container.decodeIfPresent(String.self, forKey: .sortKey)
        useStateDbOnly = try container.decodeIfPresent(Bool.self, forKey: .useStateDbOnly)
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        if case .object(let original)? = raw {
            object = original
        } else {
            object = [:]
        }
        try encodeOptional(cwd, key: "cwd", into: &object)
        try encodeOptional(sourceKinds, key: "sourceKinds", into: &object)
        try encodeOptional(limit, key: "limit", into: &object)
        try encodeOptional(parentThreadId, key: "parentThreadId", into: &object)
        try encodeOptional(ancestorThreadId, key: "ancestorThreadId", into: &object)
        try encodeOptional(archived, key: "archived", into: &object)
        try encodeOptional(cursor, key: "cursor", into: &object)
        try encodeOptional(modelProviders, key: "modelProviders", into: &object)
        try encodeOptional(searchTerm, key: "searchTerm", into: &object)
        try encodeOptional(sectionId, key: "sectionId", into: &object)
        try encodeOptional(sortDirection, key: "sortDirection", into: &object)
        try encodeOptional(sortKey, key: "sortKey", into: &object)
        try encodeOptional(useStateDbOnly, key: "useStateDbOnly", into: &object)
        try JSONValue.object(object).encode(to: encoder)
    }

    private func encodeOptional<T: Encodable>(
        _ value: T?,
        key: String,
        into object: inout [String: JSONValue]
    ) throws {
        guard let value else {
            if case .object(let original)? = raw, original[key] == .null {
                object[key] = .null
            } else {
                object.removeValue(forKey: key)
            }
            return
        }
        let data = try JSONEncoder.appServer.encode(value)
        object[key] = try JSONDecoder.appServer.decode(JSONValue.self, from: data)
    }
}

public struct SkillsListParams: Codable, Equatable, Sendable {
    public var cwds: [String]?
    public var forceReload: Bool?

    public init(cwds: [String]? = nil, forceReload: Bool? = nil) {
        self.cwds = cwds
        self.forceReload = forceReload
    }
}

public struct TurnStartParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var input: [UserInput]
    public var cwd: String?
    public var approvalPolicy: ApprovalPolicy?
    public var sandboxPolicy: SandboxPolicy?
    public var approvalsReviewer: String?
    public var clientUserMessageId: String?
    public var model: String?
    public var serviceTier: String?
    public var personality: String?

    public init(
        threadId: String,
        input: [UserInput],
        cwd: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        approvalsReviewer: String? = nil,
        clientUserMessageId: String? = nil,
        model: String? = nil,
        serviceTier: String? = nil,
        personality: String? = nil
    ) {
        self.threadId = threadId
        self.input = input
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.approvalsReviewer = approvalsReviewer
        self.clientUserMessageId = clientUserMessageId
        self.model = model
        self.serviceTier = serviceTier
        self.personality = personality
    }
}

public struct TurnInterruptParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String

    public init(threadId: String, turnId: String) {
        self.threadId = threadId
        self.turnId = turnId
    }
}

public struct ModelListParams: Codable, Equatable, Sendable {
    public var cursor: String?
    public var limit: UInt32?
    public var includeHidden: Bool?

    public init(cursor: String? = nil, limit: UInt32? = nil, includeHidden: Bool? = nil) {
        self.cursor = cursor
        self.limit = limit
        self.includeHidden = includeHidden
    }
}

public struct PermissionProfileListParams: Codable, Equatable, Sendable {
    public var cursor: String?
    public var limit: UInt32?
    public var cwd: String?

    public init(cursor: String? = nil, limit: UInt32? = nil, cwd: String? = nil) {
        self.cursor = cursor
        self.limit = limit
        self.cwd = cwd
    }
}

public struct CollaborationModeListParams: Codable, Equatable, Sendable {
    public init() {}
}

public struct ThreadSettingsUpdateParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var model: String?
    public var effort: String?
    public var approvalPolicy: ApprovalPolicy?
    public var sandboxPolicy: SandboxPolicy?
    public var permissions: String?
    public var collaborationMode: CollaborationMode?

    public init(
        threadId: String,
        model: String? = nil,
        effort: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        permissions: String? = nil,
        collaborationMode: CollaborationMode? = nil
    ) {
        self.threadId = threadId
        self.model = model
        self.effort = effort
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.permissions = permissions
        self.collaborationMode = collaborationMode
    }
}
