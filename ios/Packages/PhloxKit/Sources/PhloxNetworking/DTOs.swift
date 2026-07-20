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
            updatedAt: now
        )
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

    func toDomain() -> Approval? {
        guard let agent = AgentKind(rawValue: kind) else { return nil }
        return Approval(id: id, sessionID: sessionID, kind: agent, prompt: prompt)
    }
}

struct OutputDTO: Decodable {
    let output: String

    /// Mac の `GET /sessions/{id}/output` は本文を **`text`** キーで返す（実機 wire で確認）。
    /// Domain では output と呼ぶため CodingKeys で wire キー `text` を写す。
    enum CodingKeys: String, CodingKey {
        case output = "text"
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
            return .user(id: id, text: text ?? "")
        case "agent":
            return .agent(id: id, text: text ?? "")
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
        case PhloxQuestionWireContract.messageType:
            return decodeUserQuestion()
        default:
            return nil
        }
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
    let question: String
    let header: String
    let multiSelect: Bool
    let options: [UserQuestionOptionDTO]

    func toDomain() -> UserQuestionItem {
        UserQuestionItem(
            question: question,
            header: header,
            options: options.map { $0.toDomain() },
            multiSelect: multiSelect
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

struct SubAgentsListDTO: Decodable {
    let subAgents: [SubAgentDTO]
}

struct SubAgentDTO: Decodable {
    let id: String
    let name: String
    let status: String
    let messageCount: Int
    let markerMessageId: String?

    func toDomain() -> SubAgentSummary {
        SubAgentSummary(
            id: id,
            name: name,
            status: SubAgentStatus(rawValue: status) ?? .unknown,
            messageCount: messageCount,
            markerMessageID: markerMessageId
        )
    }
}

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

public struct SessionModelSettings: Sendable, Equatable {
    public let selectedModel: String?
    public let availableModels: [SessionModelOption]

    public init(selectedModel: String?, availableModels: [SessionModelOption]) {
        self.selectedModel = selectedModel
        self.availableModels = availableModels
    }
}

struct SessionModelSettingsDTO: Decodable {
    let selectedModel: String?
    let availableModels: [SessionModelOptionDTO]

    func toDomain() -> SessionModelSettings {
        SessionModelSettings(
            selectedModel: selectedModel,
            availableModels: availableModels.map { $0.toDomain() }
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

extension SessionStatus {
    /// Mac wire の flat status 文字列から復元（associated value は欠落するためプレースホルダ）。
    /// prompt は GET /approvals、exitCode/message は詳細/出力で補完する設計（E1-3 §4 申し送り）。
    init(wire: String) {
        switch wire {
        case "starting": self = .starting
        case "idle": self = .idle
        case "running": self = .running
        case "awaitingApproval": self = .awaitingApproval(prompt: "")
        case "completed": self = .completed(exitCode: 0)
        case "error": self = .error(message: "")
        default: self = .idle
        }
    }
}
