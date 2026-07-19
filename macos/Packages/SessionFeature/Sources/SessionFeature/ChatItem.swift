import Foundation
import StructuredChatKit

/// 送信済みユーザーメッセージに紐づく添付画像のメタ情報（task-7 契約。
/// 受け入れテスト ChatFixTask7AttachmentBadgeAcceptanceTests が凍結）。
/// 画像バイトは保持しない（バッジ表示用のメタのみ。ストレージ肥大の防止）。
public struct ChatUserAttachment: Equatable, Codable, Sendable {
    public let filename: String?
    public let mediaType: String

    public init(filename: String? = nil, mediaType: String) {
        self.filename = filename
        self.mediaType = mediaType
    }
}

/// 質問カードの表示状態（task-0 契約）。pending=回答待ち / answered=回答済み /
/// expired=失効（turn 中断・プロセス終了・respawn で回答不能になった）。
public enum ChatUserQuestionState: String, Codable, Sendable {
    case pending
    case answered
    case expired
}

// Hidden secret: chat item schema and its Codable/Equatable representation.
public enum ChatItem: Identifiable, Equatable, Codable, Sendable {
    case userMessage(id: String, text: String, timestamp: Date, attachments: [ChatUserAttachment])
    case agentMessage(id: String, text: String, timestamp: Date)
    case reasoning(id: String, text: String, timestamp: Date)
    case commandExecution(id: String, command: String?, output: String, timestamp: Date)
    case fileChange(id: String, changes: [StructuredChatKit.FilePatchChange], timestamp: Date)
    case error(id: String, message: String, timestamp: Date)
    case subAgentMarker(id: String, subagentType: String, description: String, status: SubAgentStatus)
    /// ターン完了時の API コスト行（task-6 契約。受け入れテスト TurnCostItem が凍結）。
    case turnCost(id: String, costUSD: Double, timestamp: Date)
    /// AskUserQuestion の質問カード（task-0 契約。受け入れテスト
    /// AcceptanceUserQuestionChatItemCodableTests が凍結）。answers は「質問文 → 選択 label 配列」。
    case userQuestion(
        id: String,
        requestId: String,
        questions: [StructuredChatKit.ChatUserQuestion],
        answers: [String: [String]]?,
        state: ChatUserQuestionState,
        timestamp: Date
    )

    /// 既存呼び出し互換の3引数ファクトリ（attachments なし）。
    public static func userMessage(id: String, text: String, timestamp: Date) -> ChatItem {
        .userMessage(id: id, text: text, timestamp: timestamp, attachments: [])
    }

    private enum CodingKeys: String, CodingKey {
        case userMessage
        case agentMessage
        case reasoning
        case commandExecution
        case fileChange
        case error
        case subAgentMarker
        case turnCost
        case userQuestion
    }

    private enum AssociatedValueKeys: String, CodingKey {
        case id
        case text
        case command
        case output
        case changes
        case message
        case timestamp
        case subagentType
        case description
        case status
        case costUSD
        case attachments
        case requestId
        case questions
        case answers
        case state
    }

    public var id: String {
        switch self {
        case .userMessage(let id, _, _, _),
             .agentMessage(let id, _, _),
             .reasoning(let id, _, _),
             .commandExecution(let id, _, _, _),
             .fileChange(let id, _, _),
             .error(let id, _, _),
             .subAgentMarker(let id, _, _, _),
             .turnCost(let id, _, _),
             .userQuestion(let id, _, _, _, _, _):
            id
        }
    }

    public var timestamp: Date {
        switch self {
        case .userMessage(_, _, let timestamp, _),
             .agentMessage(_, _, let timestamp),
             .reasoning(_, _, let timestamp),
             .commandExecution(_, _, _, let timestamp),
             .fileChange(_, _, let timestamp),
             .error(_, _, let timestamp),
             .turnCost(_, _, let timestamp),
             .userQuestion(_, _, _, _, _, let timestamp):
            timestamp
        case .subAgentMarker:
            .distantPast
        }
    }

    var plainText: String {
        switch self {
        case .userMessage(_, let text, _, _):
            "User: \(text)"
        case .agentMessage(_, let text, _):
            "Agent: \(text)"
        case .reasoning(_, let text, _):
            "Reasoning: \(text)"
        case .commandExecution(_, let command, let output, _):
            // command==nil のとき "Command: " の空行を出さない（N1）。output も空なら全体が空。
            [command.map { "Command: \($0)" }, output.isEmpty ? nil : output]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .fileChange(_, let changes, _):
            changes.map { "File change: \($0.path)\n\($0.diff)" }.joined(separator: "\n")
        case .error(_, let message, _):
            "Error: \(message)"
        case .subAgentMarker(_, let subagentType, let description, let status):
            "Sub-agent \(subagentType) \(status.rawValue): \(description)"
        case .turnCost(_, let costUSD, _):
            "Turn cost: $\(costUSD)"
        case .userQuestion(_, _, let questions, _, let state, _):
            "Question (\(state.rawValue)): " + questions.map(\.question).joined(separator: " / ")
        }
    }

    public static func == (lhs: ChatItem, rhs: ChatItem) -> Bool {
        switch (lhs, rhs) {
        case let (.userMessage(lhsId, lhsText, _, lhsAttachments), .userMessage(rhsId, rhsText, _, rhsAttachments)):
            lhsId == rhsId && lhsText == rhsText && lhsAttachments == rhsAttachments
        case let (.agentMessage(lhsId, lhsText, _), .agentMessage(rhsId, rhsText, _)):
            lhsId == rhsId && lhsText == rhsText
        case let (.reasoning(lhsId, lhsText, _), .reasoning(rhsId, rhsText, _)):
            lhsId == rhsId && lhsText == rhsText
        case let (.commandExecution(lhsId, lhsCommand, lhsOutput, _), .commandExecution(rhsId, rhsCommand, rhsOutput, _)):
            lhsId == rhsId && lhsCommand == rhsCommand && lhsOutput == rhsOutput
        case let (.fileChange(lhsId, lhsChanges, _), .fileChange(rhsId, rhsChanges, _)):
            lhsId == rhsId && lhsChanges == rhsChanges
        case let (.error(lhsId, lhsMessage, _), .error(rhsId, rhsMessage, _)):
            lhsId == rhsId && lhsMessage == rhsMessage
        case let (
            .subAgentMarker(lhsId, lhsType, lhsDescription, lhsStatus),
            .subAgentMarker(rhsId, rhsType, rhsDescription, rhsStatus)
        ):
            lhsId == rhsId
                && lhsType == rhsType
                && lhsDescription == rhsDescription
                && lhsStatus == rhsStatus
        case let (.turnCost(lhsId, lhsCost, _), .turnCost(rhsId, rhsCost, _)):
            lhsId == rhsId && lhsCost == rhsCost
        case let (
            .userQuestion(lhsId, lhsRequestId, lhsQuestions, lhsAnswers, lhsState, _),
            .userQuestion(rhsId, rhsRequestId, rhsQuestions, rhsAnswers, rhsState, _)
        ):
            lhsId == rhsId
                && lhsRequestId == rhsRequestId
                && lhsQuestions == rhsQuestions
                && lhsAnswers == rhsAnswers
                && lhsState == rhsState
        default:
            false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.userMessage) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .userMessage)
            self = .userMessage(
                id: try nested.decode(String.self, forKey: .id),
                text: try nested.decode(String.self, forKey: .text),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast,
                attachments: try nested.decodeIfPresent([ChatUserAttachment].self, forKey: .attachments) ?? []
            )
        } else if container.contains(.agentMessage) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .agentMessage)
            self = .agentMessage(
                id: try nested.decode(String.self, forKey: .id),
                text: try nested.decode(String.self, forKey: .text),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.reasoning) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .reasoning)
            self = .reasoning(
                id: try nested.decode(String.self, forKey: .id),
                text: try nested.decode(String.self, forKey: .text),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.commandExecution) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .commandExecution)
            self = .commandExecution(
                id: try nested.decode(String.self, forKey: .id),
                command: try nested.decodeIfPresent(String.self, forKey: .command),
                output: try nested.decode(String.self, forKey: .output),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.fileChange) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .fileChange)
            self = .fileChange(
                id: try nested.decode(String.self, forKey: .id),
                changes: try nested.decode([StructuredChatKit.FilePatchChange].self, forKey: .changes),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.error) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .error)
            self = .error(
                id: try nested.decode(String.self, forKey: .id),
                message: try nested.decode(String.self, forKey: .message),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.subAgentMarker) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .subAgentMarker)
            self = .subAgentMarker(
                id: try nested.decode(String.self, forKey: .id),
                subagentType: try nested.decode(String.self, forKey: .subagentType),
                description: try nested.decode(String.self, forKey: .description),
                status: try nested.decode(SubAgentStatus.self, forKey: .status)
            )
        } else if container.contains(.turnCost) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .turnCost)
            self = .turnCost(
                id: try nested.decode(String.self, forKey: .id),
                costUSD: try nested.decode(Double.self, forKey: .costUSD),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else if container.contains(.userQuestion) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .userQuestion)
            self = .userQuestion(
                id: try nested.decode(String.self, forKey: .id),
                requestId: try nested.decode(String.self, forKey: .requestId),
                questions: try nested.decode([StructuredChatKit.ChatUserQuestion].self, forKey: .questions),
                answers: try nested.decodeIfPresent([String: [String]].self, forKey: .answers),
                state: try nested.decode(ChatUserQuestionState.self, forKey: .state),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
            )
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected one ChatItem case key"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userMessage(let id, let text, let timestamp, let attachments):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .userMessage)
            try nested.encode(id, forKey: .id)
            try nested.encode(text, forKey: .text)
            try nested.encode(timestamp, forKey: .timestamp)
            if !attachments.isEmpty {
                try nested.encode(attachments, forKey: .attachments)
            }
        case .agentMessage(let id, let text, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .agentMessage)
            try nested.encode(id, forKey: .id)
            try nested.encode(text, forKey: .text)
            try nested.encode(timestamp, forKey: .timestamp)
        case .reasoning(let id, let text, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .reasoning)
            try nested.encode(id, forKey: .id)
            try nested.encode(text, forKey: .text)
            try nested.encode(timestamp, forKey: .timestamp)
        case .commandExecution(let id, let command, let output, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .commandExecution)
            try nested.encode(id, forKey: .id)
            try nested.encodeIfPresent(command, forKey: .command)
            try nested.encode(output, forKey: .output)
            try nested.encode(timestamp, forKey: .timestamp)
        case .fileChange(let id, let changes, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .fileChange)
            try nested.encode(id, forKey: .id)
            try nested.encode(changes, forKey: .changes)
            try nested.encode(timestamp, forKey: .timestamp)
        case .error(let id, let message, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .error)
            try nested.encode(id, forKey: .id)
            try nested.encode(message, forKey: .message)
            try nested.encode(timestamp, forKey: .timestamp)
        case .subAgentMarker(let id, let subagentType, let description, let status):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .subAgentMarker)
            try nested.encode(id, forKey: .id)
            try nested.encode(subagentType, forKey: .subagentType)
            try nested.encode(description, forKey: .description)
            try nested.encode(status, forKey: .status)
        case .turnCost(let id, let costUSD, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .turnCost)
            try nested.encode(id, forKey: .id)
            try nested.encode(costUSD, forKey: .costUSD)
            try nested.encode(timestamp, forKey: .timestamp)
        case .userQuestion(let id, let requestId, let questions, let answers, let state, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .userQuestion)
            try nested.encode(id, forKey: .id)
            try nested.encode(requestId, forKey: .requestId)
            try nested.encode(questions, forKey: .questions)
            try nested.encodeIfPresent(answers, forKey: .answers)
            try nested.encode(state, forKey: .state)
            try nested.encode(timestamp, forKey: .timestamp)
        }
    }
}

extension ChatItem {
    func withTimestamp(_ timestamp: Date) -> ChatItem {
        switch self {
        case .userMessage(let id, let text, _, let attachments):
            .userMessage(id: id, text: text, timestamp: timestamp, attachments: attachments)
        case .agentMessage(let id, let text, _):
            .agentMessage(id: id, text: text, timestamp: timestamp)
        case .reasoning(let id, let text, _):
            .reasoning(id: id, text: text, timestamp: timestamp)
        case .commandExecution(let id, let command, let output, _):
            .commandExecution(id: id, command: command, output: output, timestamp: timestamp)
        case .fileChange(let id, let changes, _):
            .fileChange(id: id, changes: changes, timestamp: timestamp)
        case .error(let id, let message, _):
            .error(id: id, message: message, timestamp: timestamp)
        case .subAgentMarker(let id, let subagentType, let description, let status):
            .subAgentMarker(id: id, subagentType: subagentType, description: description, status: status)
        case .turnCost(let id, let costUSD, _):
            .turnCost(id: id, costUSD: costUSD, timestamp: timestamp)
        case .userQuestion(let id, let requestId, let questions, let answers, let state, _):
            .userQuestion(
                id: id,
                requestId: requestId,
                questions: questions,
                answers: answers,
                state: state,
                timestamp: timestamp
            )
        }
    }
}

