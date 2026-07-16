import AgentDomain
import Foundation

public struct ControlImageAttachment: Equatable, Sendable {
    public let mediaType: String
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}

public struct ControlRequest: Sendable {
    public let requester: SessionID?
    public let action: Action

    public init(requester: SessionID?, action: Action) {
        self.requester = requester
        self.action = action
    }

    public enum Action: Sendable {
        case listSessions
        case sendText(to: Recipient, text: String, submit: Bool, inReplyTo: UUID?, images: [ControlImageAttachment])
        case spawn(ref: AgentRef, backend: SessionBackend, workingDirectory: String?)
        case remove(id: SessionID)
        case rename(id: SessionID, name: String)
        case output(id: SessionID, mode: OutputMode)
        case messages(id: SessionID, since: String?, wait: Int?)
        case waitReady(id: SessionID, timeoutSeconds: Int)
        case wait(id: SessionID, timeoutSeconds: Int, sentinel: String?)
        case listApprovals
        case respondApproval(id: String, decision: ApprovalDecision)
        case registerDeviceToken(registration: DeviceTokenRegistration)
        case interrupt(id: SessionID)
        case subAgents(id: SessionID)
        case subAgentMessages(id: SessionID, subAgentID: String)
        case usage(id: SessionID)
        case sessionSettings(id: SessionID)
        case setModel(id: SessionID, model: String)
        case agentModels(kind: AgentKind)
        case cliUsage
    }
}

// MARK: - Wave 2 wire DTOs

public struct ControlSessionListItem: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let status: String
    public let workspace: String
    public let projectId: String?
    public let projectName: String?

    public init(
        id: String,
        name: String,
        kind: String,
        status: String,
        workspace: String,
        projectId: String? = nil,
        projectName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.workspace = workspace
        self.projectId = projectId
        self.projectName = projectName
    }
}

public struct ControlSessionListResponse: Encodable, Equatable, Sendable {
    public let sessions: [ControlSessionListItem]

    public init(sessions: [ControlSessionListItem]) {
        self.sessions = sessions
    }
}

public struct ControlAgentModelsResponse: Encodable, Equatable, Sendable {
    public let models: [ControlModelOption]
    public let defaultModel: String?

    public init(models: [ControlModelOption], defaultModel: String?) {
        self.models = models
        self.defaultModel = defaultModel
    }

    enum CodingKeys: String, CodingKey {
        case models, defaultModel
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(models, forKey: .models)
        if let defaultModel {
            try container.encode(defaultModel, forKey: .defaultModel)
        } else {
            try container.encodeNil(forKey: .defaultModel)
        }
    }
}

public struct ControlCLIUsageBucket: Encodable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: String?

    public init(id: String, label: String, usedPercent: Double, resetsAt: String?) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case id, label, usedPercent, resetsAt
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(usedPercent, forKey: .usedPercent)
        if let resetsAt {
            try container.encode(resetsAt, forKey: .resetsAt)
        } else {
            try container.encodeNil(forKey: .resetsAt)
        }
    }
}

public struct ControlCLIUsageAgent: Encodable, Equatable, Sendable {
    public let kind: String
    public let state: String
    public let updatedAt: String?
    public let dataAsOf: String?
    public let buckets: [ControlCLIUsageBucket]

    public init(
        kind: String,
        state: String,
        updatedAt: String?,
        dataAsOf: String?,
        buckets: [ControlCLIUsageBucket]
    ) {
        self.kind = kind
        self.state = state
        self.updatedAt = updatedAt
        self.dataAsOf = dataAsOf
        self.buckets = buckets
    }

    enum CodingKeys: String, CodingKey {
        case kind, state, updatedAt, dataAsOf, buckets
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        if let updatedAt {
            try container.encode(updatedAt, forKey: .updatedAt)
        } else {
            try container.encodeNil(forKey: .updatedAt)
        }
        if let dataAsOf {
            try container.encode(dataAsOf, forKey: .dataAsOf)
        } else {
            try container.encodeNil(forKey: .dataAsOf)
        }
        try container.encode(buckets, forKey: .buckets)
    }
}

public struct ControlCLIUsageResponse: Encodable, Equatable, Sendable {
    public let agents: [ControlCLIUsageAgent]

    public init(agents: [ControlCLIUsageAgent]) {
        self.agents = agents
    }
}

public enum ControlSpawnModelApplier {
    /// spawn 完了後にのみ呼び出し、nil は従来どおり何もしない。
    /// 戻り値 nil は適用要求なし、Bool は dashboard の適用結果を表す。
    @MainActor public static func apply(
        _ model: String?,
        to sessionID: SessionID,
        using applyModel: (String, SessionID) async -> Bool
    ) async -> Bool? {
        guard let model else { return nil }
        return await applyModel(model, sessionID)
    }
}

public enum OutputMode: String, Sendable {
    case screen
    case scrollback
}

/// 承認に対するモバイル側の応答値。モバイル DTO の "decision" フィールドと 1:1 対応。
public typealias ApprovalDecision = AgentDomain.ApprovalDecision

// MARK: - Approval DTO

/// GET /approvals で返す 1 承認分の DTO。モバイル `ApprovalDTO` と完全一致。
public struct ApprovalDTO: Sendable, Codable, Equatable {
    public let id: String
    public let sessionID: String
    public let kind: String
    public let prompt: String

    public init(id: String, sessionID: String, kind: String, prompt: String) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.prompt = prompt
    }
}

// MARK: - Response

public struct ControlResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
    }

    public static func json(_ statusCode: Int, _ object: some Encodable) -> ControlResponse {
        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(object) else {
            return ControlResponse(statusCode: 500)
        }
        return ControlResponse(statusCode: statusCode, body: body)
    }

    public static func status(_ statusCode: Int) -> ControlResponse {
        ControlResponse(statusCode: statusCode)
    }
}

/// task-5 契約（凍結・PM 著）: モバイル向けモデル選択 API のワイヤ契約。
/// 定数はワイヤ形状の単一の正（iOS 側 `PhloxModelWireContract` と一字一句一致させる）。
/// `implemented` は実装完了と同時に true へ反転する（flag だけの反転は虚偽報告として扱う）。
public enum ControlModelWireContract {
    /// GET /sessions/{id}/settings → 200 {"selectedModel": String?, "availableModels": [{"id","displayName"}]}
    public static let settingsPathSuffix = "/settings"
    /// POST /sessions/{id}/model  body {"model": String} → 200 / 404 / 400
    public static let modelPathSuffix = "/model"
    public static let selectedModelKey = "selectedModel"
    public static let availableModelsKey = "availableModels"
    public static let modelIDKey = "id"
    public static let modelDisplayNameKey = "displayName"
    public static let modelKey = "model"
    public static let implemented = true
}

/// モバイルのモデル選択肢。JSON キーは凍結済みワイヤ定数から生成する。
public struct ControlModelOption: Encodable, Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ControlModelCodingKey.self)
        try container.encode(id, forKey: .init(ControlModelWireContract.modelIDKey))
        try container.encode(displayName, forKey: .init(ControlModelWireContract.modelDisplayNameKey))
    }
}

/// GET /sessions/{id}/settings の応答 DTO。
public struct ControlSessionModelSettings: Encodable, Equatable, Sendable {
    public let selectedModel: String?
    public let availableModels: [ControlModelOption]

    public init(selectedModel: String?, availableModels: [ControlModelOption]) {
        self.selectedModel = selectedModel
        self.availableModels = availableModels
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ControlModelCodingKey.self)
        let selectedKey = ControlModelCodingKey(ControlModelWireContract.selectedModelKey)
        if let selectedModel {
            try container.encode(selectedModel, forKey: selectedKey)
        } else {
            try container.encodeNil(forKey: selectedKey)
        }
        try container.encode(
            availableModels,
            forKey: .init(ControlModelWireContract.availableModelsKey)
        )
    }
}

private struct ControlModelCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}
