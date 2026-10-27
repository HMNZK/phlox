import Foundation

/// 新規セッション起動リクエスト（カンプ④ / POST /sessions）。
public struct SpawnRequest: Sendable, Equatable {
    public let agent: AgentKind
    public let workspace: String
    public let projectID: String?
    public let prompt: String?
    public let model: String?
    public let effort: String?
    public let permission: String?
    public let planMode: Bool?
    public let usesWorktree: Bool?
    public let startPoint: NewChatStartPoint?
    public let resumeHistoryID: String?

    public init(
        agent: AgentKind,
        workspace: String,
        projectID: String? = nil,
        prompt: String? = nil,
        model: String? = nil,
        effort: String? = nil,
        permission: String? = nil,
        planMode: Bool? = nil,
        usesWorktree: Bool? = nil,
        startPoint: NewChatStartPoint? = nil,
        resumeHistoryID: String? = nil
    ) {
        self.agent = agent
        self.workspace = workspace
        self.projectID = projectID
        self.prompt = prompt
        self.model = model
        self.effort = effort
        self.permission = permission
        self.planMode = planMode
        self.usesWorktree = usesWorktree
        self.startPoint = startPoint
        self.resumeHistoryID = resumeHistoryID
    }
}

public struct NewChatStartPoint: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case head, localBranch, remoteBranch, tag, commit }
    public let kind: Kind
    public let value: String?
    public let title: String
    public let summary: String?
    public var id: String { "\(kind.rawValue):\(value ?? "")" }

    public init(kind: Kind, value: String? = nil, title: String, summary: String? = nil) {
        self.kind = kind
        self.value = value
        self.title = title
        self.summary = summary
    }
}

public struct NewChatHistoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let updatedAt: Date
    public let branch: String?
    public let workingDirectory: String?

    public init(id: String, title: String, updatedAt: Date, branch: String? = nil, workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.branch = branch
        self.workingDirectory = workingDirectory
    }
}

/// PATCH /sessions/{id}/settings. The outer optional on `permission` distinguishes omission
/// from an explicit `null` value that selects the agent default.
public struct SessionSettingsUpdate: Sendable, Equatable {
    public let effort: String?
    public let permission: String??
    public let planMode: Bool?

    public init(effort: String? = nil, permission: String?? = nil, planMode: Bool? = nil) {
        self.effort = effort
        self.permission = permission
        self.planMode = planMode
    }
}

/// セッションへの送信リクエスト（カンプ⑦ / POST /send（to,text,images）。
/// images は API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md §5）。既定 [] で後方互換。
public struct SendRequest: Sendable, Equatable {
    public let sessionID: String
    public let text: String
    public let images: [SendAttachment]
    public let skill: AgentSkillSelection?

    public init(sessionID: String, text: String, images: [SendAttachment] = [], skill: AgentSkillSelection? = nil) {
        self.sessionID = sessionID
        self.text = text
        self.images = images
        self.skill = skill
    }
}

/// 送信に添付する画像（契約 §5: mediaType は image/png / image/jpeg を必須サポート）。
public struct SendAttachment: Sendable, Equatable {
    public let mediaType: String
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}

/// 送信結果。
public struct SendResult: Sendable, Equatable {
    public let accepted: Bool
    public let message: String?

    public init(accepted: Bool, message: String? = nil) {
        self.accepted = accepted
        self.message = message
    }
}
