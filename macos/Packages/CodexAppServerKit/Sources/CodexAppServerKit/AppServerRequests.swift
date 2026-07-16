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

    public init(threadId: String) {
        self.threadId = threadId
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
