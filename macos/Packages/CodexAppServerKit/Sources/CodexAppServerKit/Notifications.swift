import AgentDomain
import Foundation

public struct AgentMessageDeltaNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String
}

public struct ReasoningSummaryTextDeltaNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String
}

public struct CommandExecutionOutputDeltaNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String
}

public struct FileChangePatchUpdatedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var changes: [FilePatchChange]
}

public struct ItemStartedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var startedAtMs: Int?
    public var item: ThreadItem
}

public struct ItemCompletedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var completedAtMs: Int?
    public var item: ThreadItem
}

public struct TurnLifecycleNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turn: TurnSummary
}

public struct TurnInterruptedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String?

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        self.threadId = raw["threadId"]?.stringValue ?? ""
        self.turnId = raw["turnId"]?.stringValue
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue] = ["threadId": .string(threadId)]
        if let turnId {
            object["turnId"] = .string(turnId)
        }
        try JSONValue.object(object).encode(to: encoder)
    }
}

public struct ThreadTokenUsageUpdatedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var tokenUsage: ThreadTokenUsage
}

public struct ThreadStatusChangedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var status: ThreadStatus
}

public struct ThreadSettingsUpdatedNotification: Codable, Equatable, Sendable {
    public var threadId: String
    public var threadSettings: ThreadSettings
}

public struct ErrorNotification: Codable, Equatable, Sendable {
    public var threadId: String?
    public var turnId: String?
    public var willRetry: Bool?
    public var error: TurnError?
}

public struct TurnError: Codable, Equatable, Sendable {
    public var message: String
    public var additionalDetails: String?
}

public struct WarningNotification: Codable, Equatable, Sendable {
    public var message: String
    public var threadId: String?
}

public struct CommandExecutionApprovalRequest: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var startedAtMs: Int
    public var approvalId: String?
    public var command: String?
    public var cwd: String?
    public var reason: String?
}

public struct FileChangeApprovalRequest: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var startedAtMs: Int
    public var grantRoot: String?
    public var reason: String?
}

public struct PermissionsApprovalRequest: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var startedAtMs: Int
    public var cwd: String
    public var reason: String?
    public var permissions: JSONValue
}

public typealias ApprovalDecision = AgentDomain.ApprovalDecision

public struct ApprovalDecisionResponse: Codable, Equatable, Sendable {
    public var decision: ApprovalDecision

    public init(decision: ApprovalDecision) {
        self.decision = decision
    }
}

public struct PermissionsApprovalResponse: Codable, Equatable, Sendable {
    public var permissions: JSONValue
    public var scope: String?
    public var strictAutoReview: Bool?

    public init(permissions: JSONValue, scope: String? = nil, strictAutoReview: Bool? = nil) {
        self.permissions = permissions
        self.scope = scope
        self.strictAutoReview = strictAutoReview
    }
}
