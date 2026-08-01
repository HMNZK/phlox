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

/// `item/tool/requestUserInput` の選択肢 1 件（codex app-server の
/// `ToolRequestUserInputOption` と 1:1。task-0 契約）。
public struct ToolRequestUserInputOption: Codable, Equatable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

/// `item/tool/requestUserInput` の質問 1 件（`ToolRequestUserInputQuestion` と 1:1。task-0 契約）。
/// `options` が nil のときは自由入力。`isOther` / `isSecret` は省略時 false。
public struct ToolRequestUserInputQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var header: String
    public var question: String
    public var options: [ToolRequestUserInputOption]?
    public var isOther: Bool?
    public var isSecret: Bool?

    public init(
        id: String,
        header: String,
        question: String,
        options: [ToolRequestUserInputOption]? = nil,
        isOther: Bool? = nil,
        isSecret: Bool? = nil
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.isOther = isOther
        self.isSecret = isSecret
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case header
        case question
        case options
        case isOther
        case isSecret
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decode(String.self, forKey: .header)
        question = try container.decode(String.self, forKey: .question)
        options = try container.decodeIfPresent([ToolRequestUserInputOption].self, forKey: .options)
        isOther = try container.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }
}

/// `item/tool/requestUserInput` のパラメータ（`ToolRequestUserInputParams` と 1:1。task-0 契約）。
/// これは承認要求ではなく「モデルからユーザーへの質問」であり、承認ポリシーの管轄外である。
public struct ToolRequestUserInputRequest: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var questions: [ToolRequestUserInputQuestion]
    public var autoResolutionMs: Int?

    public init(
        threadId: String,
        turnId: String,
        itemId: String,
        questions: [ToolRequestUserInputQuestion],
        autoResolutionMs: Int? = nil
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.itemId = itemId
        self.questions = questions
        self.autoResolutionMs = autoResolutionMs
    }
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
