import Foundation
import PhloxCore

// wire（Mac プロキシ）JSON の DTO 群。Domain モデル（PhloxCore）へはここでのみ変換し、
// wire format を Domain に漏らさない（E1-3 / E3-1）。

struct SessionListDTO: Decodable {
    let sessions: [SessionDTO]
}

struct SessionDTO: Decodable {
    let id: String
    let name: String
    let kind: String
    let status: String
    let workspace: String?
    let projectId: String?
    let projectName: String?
    let backend: String
    let isStalled: Bool
    let hasUnseenCompletion: Bool
    let parentSessionId: String?
    let statusEnteredAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, status, workspace, projectId, projectName
        case backend, isStalled, hasUnseenCompletion, parentSessionId, statusEnteredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(String.self, forKey: .kind)
        status = try container.decode(String.self, forKey: .status)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        backend = try container.decodeIfPresent(String.self, forKey: .backend) ?? "appServer"
        isStalled = try container.decodeIfPresent(Bool.self, forKey: .isStalled) ?? false
        hasUnseenCompletion = try container.decodeIfPresent(Bool.self, forKey: .hasUnseenCompletion) ?? false
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        statusEnteredAt = try container.decodeIfPresent(String.self, forKey: .statusEnteredAt)
    }

    /// Domain へ変換。未知 kind（カスタム CLI 等）は MVP では nil（呼び出し側で除外）。
    func toDomain(now: Date = Date()) -> Session? {
        guard let agent = AgentKind(rawValue: kind) else { return nil }
        return Session(
            id: id,
            name: name,
            agent: agent,
            status: SessionStatus(wire: status),
            subtitle: workspace ?? "",
            projectId: projectId,
            projectName: projectName,
            backend: backend,
            isStalled: isStalled,
            hasUnseenCompletion: hasUnseenCompletion,
            parentSessionId: parentSessionId,
            statusEnteredAt: parsedStatusEnteredAt(),
            updatedAt: now
        )
    }

    private func parsedStatusEnteredAt() -> Date? {
        guard let statusEnteredAt else { return nil }
        return ISO8601DateFormatter().date(from: statusEnteredAt)
    }
}

struct ApprovalListDTO: Decodable {
    let approvals: [ApprovalDTO]
}

struct ApprovalDTO: Decodable {
    let id: String
    let sessionID: String
    let kind: String
    let prompt: String
    let actionKind: String?

    func toDomain() -> Approval? {
        guard let agent = AgentKind(rawValue: kind) else { return nil }
        return Approval(id: id, sessionID: sessionID, kind: agent, prompt: prompt, actionKind: actionKind)
    }
}

struct ServerErrorDTO: Decodable {
    let error: String?
    let message: String?
    let reason: String?

    /// Mac の `ErrorDTO` は理由を **`error`** キーで返す（ControlServer 全エンドポイント共通の wire 形）。
    /// 旧経路互換で message/reason も見て、いずれか非 nil を人間向け理由として採る。
    var displayReason: String? { error ?? message ?? reason }
}

// MARK: - 構造化チャット（GET /sessions/{id}/messages）

/// Mac の `GET /sessions/{id}/messages` は `{ "sessionId": …, "messages": [...] }` を返す
/// （実機 wire で確認: Codex セッションが 200、非構造化/不在は 404）。
struct ChatMessagesDTO: Decodable {
    let sessionId: String
    let messages: [ChatMessageDTO]
}

/// 1 メッセージ分。`type` で種別を判別し、種別に使うキーのみ present（不要キーは省略される）。
struct ChatMessageDTO: Decodable {
    let id: String
    let type: String
    let createdAt: String?
    let text: String?
    let command: String?
    let output: String?
    let changes: [ChatFileChangeDTO]?
    let message: String?
    /// AskUserQuestion（type == userQuestion）向け。他 type では省略される。
    let requestId: String?
    let state: String?
    let questions: [UserQuestionItemDTO]?
    let answers: [String: [String]]?

    init(
        id: String,
        type: String,
        createdAt: String? = nil,
        text: String? = nil,
        command: String? = nil,
        output: String? = nil,
        changes: [ChatFileChangeDTO]? = nil,
        message: String? = nil,
        requestId: String? = nil,
        state: String? = nil,
        questions: [UserQuestionItemDTO]? = nil,
        answers: [String: [String]]? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.text = text
        self.command = command
        self.output = output
        self.changes = changes
        self.message = message
        self.requestId = requestId
        self.state = state
        self.questions = questions
        self.answers = answers
    }

    /// wire の `type` で Domain `ChatMessage` に変換。未知 type は nil（前方互換 = 呼び出し側で除外）。
    func toDomain() -> ChatMessage? {
        switch type {
        case "user":
            return .user(id: id, text: text ?? "", createdAt: parsedCreatedAt())
        case "agent":
            return .agent(id: id, text: text ?? "", createdAt: parsedCreatedAt())
        case "reasoning":
            return .reasoning(id: id, text: text ?? "")
        case "command":
            return .command(id: id, command: command, output: output ?? "")
        case "fileChange":
            return .fileChange(id: id, changes: (changes ?? []).map { $0.toDomain() })
        case "error":
            return .error(id: id, message: message ?? "")
        case "subAgent":
            return .subAgent(id: id, text: text ?? "")
        case "turnCost":
            guard let costUSD = Self.parseTurnCost(text) else { return nil }
            return .turnCost(id: id, costUSD: costUSD)
        case PhloxQuestionWireContract.messageType:
            return decodeUserQuestion()
        default:
            return nil
        }
    }

    private func parsedCreatedAt() -> Date? {
        guard let createdAt else { return nil }
        return ISO8601DateFormatter().date(from: createdAt)
    }

    private static func parseTurnCost(_ text: String?) -> Double? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericValue = value.hasPrefix("$") ? String(value.dropFirst()) : value
        return Double(numericValue)
    }

    private func decodeUserQuestion() -> ChatMessage? {
        guard let requestId,
              let stateString = state,
              let state = UserQuestionState(rawValue: stateString),
              let questions
        else { return nil }
        return .userQuestion(
            id: id,
            requestId: requestId,
            questions: questions.map { $0.toDomain() },
            answers: answers,
            state: state
        )
    }
}

/// AskUserQuestion の質問 1 件（wire）。
struct UserQuestionItemDTO: Decodable {
    let id: String?
    let question: String
    let header: String
    let multiSelect: Bool
    let options: [UserQuestionOptionDTO]
    let toolName: String?
    let toolDetail: String?
    let allowsSessionScope: Bool?

    func toDomain() -> UserQuestionItem {
        UserQuestionItem(
            question: question,
            header: header,
            options: options.map { $0.toDomain() },
            multiSelect: multiSelect,
            id: id,
            toolName: toolName,
            toolDetail: toolDetail,
            allowsSessionScope: allowsSessionScope ?? false
        )
    }
}

/// AskUserQuestion の選択肢 1 件（wire）。
struct UserQuestionOptionDTO: Decodable {
    let label: String
    let description: String?

    func toDomain() -> UserQuestionOption {
        UserQuestionOption(label: label, description: description)
    }
}

struct ChatFileChangeDTO: Decodable {
    let path: String
    let diff: String
    let kind: String?

    func toDomain() -> ChatFileChange { ChatFileChange(path: path, diff: diff, kind: kind) }
}

/// Mac の `POST /sessions` は body の **`kind`** と **`backend`** を使う（workspace/prompt は無視。実機 wire で確認）。
/// モバイルは構造化チャット(.appServer)で起動し、チャットバブル表示にする（既定 PTY は CLI/loopflow 用）。
/// 最初の指示は spawn 後に `POST /send` で配送する（`SpawnViewModel.create`）。
struct SpawnRequestDTO: Encodable {
    let kind: String
    let backend: String
    let model: String?
    let projectId: String?
    let effort: String?
    let permission: String?
    let planMode: Bool?
}

/// `POST /sessions`（spawn）のレスポンス。Mac は新規セッション **id のみ**返す（`{"id": …}`）。
struct IDDTO: Decodable {
    let id: String
}

/// `GET /sessions/{id}/ready` のレスポンス。Mac は既定10秒ロングポーリングし `{"ready": bool}` を返す。
struct ReadyDTO: Decodable {
    let ready: Bool
}

struct SendRequestDTO: Encodable {
    let to: String
    let text: String
    private let images: [SendAttachmentDTO]?

    init(to: String, text: String, images: [SendAttachment] = []) {
        self.to = to
        self.text = text
        self.images = images.isEmpty ? nil : images.map { SendAttachmentDTO(mediaType: $0.mediaType, data: $0.data) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(to, forKey: .to)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(images, forKey: .images)
    }

    private enum CodingKeys: String, CodingKey {
        case to, text, images
    }
}

struct SendAttachmentDTO: Encodable {
    let mediaType: String
    let dataBase64: String

    init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.dataBase64 = data.base64EncodedString()
    }
}

// MARK: - API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md）

struct UsageDTO: Decodable {
    let turn: TurnUsageDTO?
}

struct TurnUsageDTO: Decodable {
    let costUSD: Double?
    let contextUsedTokens: Int?
    let contextWindowTokens: Int?

    func toDomain() -> TurnUsage {
        TurnUsage(
            costUSD: costUSD,
            contextUsedTokens: contextUsedTokens,
            contextWindowTokens: contextWindowTokens
        )
    }
}

public struct CLIUsageResponse: Sendable, Equatable, Decodable {
    public let agents: [CLIUsage]

    public init(agents: [CLIUsage]) {
        self.agents = agents
    }
}

struct MessagesDeltaDTO: Decodable {
    let messages: [ChatMessageDTO]
    let cursor: String?
    let snapshot: Bool?

    func toDomain(since: String?) -> MessagesDelta {
        let isSnapshot = since == nil || snapshot == true
        return MessagesDelta(
            messages: messages.compactMap { $0.toDomain() },
            cursor: cursor,
            isSnapshot: isSnapshot
        )
    }
}

struct RespondRequestDTO: Encodable {
    let decision: String
}

/// POST sessions/{id}/question（AskUserQuestion 回答）。
struct RespondToQuestionRequestDTO: Encodable {
    let requestId: String
    let answers: [String: [String]]
}

// MARK: - Model selection (task-6 / PhloxModelWireContract)

struct AgentSettingsResponseDTO: Decodable {
    let availableEfforts: [String: [AgentSettingOption]]
    let availablePermissions: [AgentSettingOption]
    let planModeAvailable: Bool
    let defaultEfforts: [String: String]?
    let defaultPermission: String?

    func toDomain() -> AgentSettings {
        AgentSettings(
            availableEfforts: availableEfforts,
            availablePermissions: availablePermissions,
            planModeAvailable: planModeAvailable,
            defaultEfforts: defaultEfforts,
            defaultPermission: defaultPermission
        )
    }
}

struct ProjectsResponseDTO: Decodable {
    let projects: [ProjectSummary]
}

public struct SessionModelSettings: Sendable, Equatable {
    public let selectedModel: String?
    public let availableModels: [SessionModelOption]
    public let selectedEffort: String?
    public let availableEfforts: [AgentSettingOption]
    public let selectedPermission: String?
    public let availablePermissions: [AgentSettingOption]
    public let planMode: Bool
    public let planModeAvailable: Bool

    public init(
        selectedModel: String?,
        availableModels: [SessionModelOption],
        selectedEffort: String? = nil,
        availableEfforts: [AgentSettingOption] = [],
        selectedPermission: String? = nil,
        availablePermissions: [AgentSettingOption] = [],
        planMode: Bool = false,
        planModeAvailable: Bool = false
    ) {
        self.selectedModel = selectedModel
        self.availableModels = availableModels
        self.selectedEffort = selectedEffort
        self.availableEfforts = availableEfforts
        self.selectedPermission = selectedPermission
        self.availablePermissions = availablePermissions
        self.planMode = planMode
        self.planModeAvailable = planModeAvailable
    }
}

struct SessionModelSettingsDTO: Decodable {
    let selectedModel: String?
    let availableModels: [SessionModelOptionDTO]
    let selectedEffort: String?
    let availableEfforts: [AgentSettingOption]?
    let selectedPermission: String?
    let availablePermissions: [AgentSettingOption]?
    let planMode: Bool?
    let planModeAvailable: Bool?

    func toDomain() -> SessionModelSettings {
        SessionModelSettings(
            selectedModel: selectedModel,
            availableModels: availableModels.map { $0.toDomain() },
            selectedEffort: selectedEffort,
            availableEfforts: availableEfforts ?? [],
            selectedPermission: selectedPermission,
            availablePermissions: availablePermissions ?? [],
            planMode: planMode ?? false,
            planModeAvailable: planModeAvailable ?? false
        )
    }
}

struct SessionModelOptionDTO: Decodable {
    let id: String
    let displayName: String

    func toDomain() -> SessionModelOption {
        SessionModelOption(id: id, displayName: displayName)
    }
}

struct SetModelRequestDTO: Encodable {
    let model: String
}

struct SetSessionSettingsRequestDTO: Encodable {
    let update: SessionSettingsUpdate

    private enum CodingKeys: String, CodingKey {
        case effort, permission, planMode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(update.effort, forKey: .effort)
        if let permission = update.permission {
            try container.encode(permission, forKey: .permission)
        }
        try container.encodeIfPresent(update.planMode, forKey: .planMode)
    }
}

extension SessionStatus {
    /// Mac wire の flat status 文字列から復元（associated value は欠落するためプレースホルダ）。
    /// prompt は GET /approvals、exitCode/message は詳細/出力で補完する設計（E1-3 §4 申し送り）。
    init(wire: String) {
        switch wire {
        case "starting": self = .starting
        case "idle": self = .idle
        case "running": self = .running
        case "awaitingApproval": self = .awaitingApproval(prompt: "")
        case "awaitingUserQuestion": self = .awaitingUserQuestion
        case "completed": self = .completed(exitCode: 0)
        case "error": self = .error(message: "")
        default: self = .idle
        }
    }
}
