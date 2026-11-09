import Foundation
import StructuredChatKit

/// 送信済みユーザーメッセージに紐づく添付画像のメタ情報（task-7 契約。
/// 受け入れテスト ChatAttachmentBadgeTests が凍結）。
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

/// 入力（userMessage）1 件の終わり方。エージェント状態カードの見出しが読む
/// （agent-status-card-design.md §2.2）。`superseded` は実行中に次の入力が送られたこと。
public struct ChatTurnEnd: Equatable, Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case completed
        case interrupted
        case error
        case superseded
    }

    public let outcome: Outcome
    public let at: Date

    public init(outcome: Outcome, at: Date) {
        self.outcome = outcome
        self.at = at
    }
}

// Hidden secret: chat item schema and its Codable/Equatable representation.
public enum ChatItem: Identifiable, Equatable, Codable, Sendable {
    /// `turnEnd` はその入力の終わり方。`nil` は実行中か、この機能より前の記録。
    case userMessage(id: String, text: String, timestamp: Date, attachments: [ChatUserAttachment], turnEnd: ChatTurnEnd? = nil)
    case agentMessage(id: String, text: String, timestamp: Date)
    case reasoning(id: String, text: String, timestamp: Date)
    /// `completedAt` は結果が届いた時刻（`nil` は実行中か旧記録）。`intent` はエージェントが付けた短い説明。
    case commandExecution(
        id: String, command: String?, output: String, timestamp: Date,
        completedAt: Date? = nil, intent: String? = nil
    )
    case fileChange(id: String, changes: [StructuredChatKit.FilePatchChange], timestamp: Date, completedAt: Date? = nil)
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
    /// エージェントのタスクリストのスナップショット。taskListUpdated のたびに
    /// 一意の id（`task-list-<UUID>`）で追記する（旧版は固定 id `task-list` の 1 枚を置換していた）。
    case taskList(id: String, tasks: [StructuredChatKit.AgentTaskItem], timestamp: Date)

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
        case taskList
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
        case tasks
        case completedAt
        case intent
        case turnEnd
    }

    public var id: String {
        switch self {
        case .userMessage(let id, _, _, _, _),
             .agentMessage(let id, _, _),
             .reasoning(let id, _, _),
             .commandExecution(let id, _, _, _, _, _),
             .fileChange(let id, _, _, _),
             .error(let id, _, _),
             .subAgentMarker(let id, _, _, _),
             .turnCost(let id, _, _),
             .userQuestion(let id, _, _, _, _, _),
             .taskList(let id, _, _):
            id
        }
    }

    public var timestamp: Date {
        switch self {
        case .userMessage(_, _, let timestamp, _, _),
             .agentMessage(_, _, let timestamp),
             .reasoning(_, _, let timestamp),
             .commandExecution(_, _, _, let timestamp, _, _),
             .fileChange(_, _, let timestamp, _),
             .error(_, _, let timestamp),
             .turnCost(_, _, let timestamp),
             .userQuestion(_, _, _, _, _, let timestamp),
             .taskList(_, _, let timestamp):
            timestamp
        case .subAgentMarker:
            .distantPast
        }
    }

    var plainText: String {
        switch self {
        case .userMessage(_, let text, _, _, _):
            "User: \(text)"
        case .agentMessage(_, let text, _):
            "Agent: \(text)"
        case .reasoning(_, let text, _):
            "Reasoning: \(text)"
        case .commandExecution(_, let command, let output, _, _, _):
            // command==nil のとき "Command: " の空行を出さない（N1）。output も空なら全体が空。
            [command.map { "Command: \($0)" }, output.isEmpty ? nil : output]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .fileChange(_, let changes, _, _):
            changes.map { "File change: \($0.path)\n\($0.diff)" }.joined(separator: "\n")
        case .error(_, let message, _):
            "Error: \(message)"
        case .subAgentMarker(_, let subagentType, let description, let status):
            "Sub-agent \(subagentType) \(status.rawValue): \(description)"
        case .turnCost(_, let costUSD, _):
            "Turn cost: $\(costUSD)"
        case .userQuestion(_, _, let questions, _, let state, _):
            "Question (\(state.rawValue)): " + questions.map(\.question).joined(separator: " / ")
        case .taskList(_, let tasks, _):
            "Tasks: " + tasks.map { "[\($0.status.rawValue)] \($0.title)" }.joined(separator: " / ")
        }
    }

    public static func == (lhs: ChatItem, rhs: ChatItem) -> Bool {
        switch (lhs, rhs) {
        case let (
            .userMessage(lhsId, lhsText, _, lhsAttachments, lhsTurnEnd),
            .userMessage(rhsId, rhsText, _, rhsAttachments, rhsTurnEnd)
        ):
            lhsId == rhsId && lhsText == rhsText && lhsAttachments == rhsAttachments && lhsTurnEnd == rhsTurnEnd
        case let (.agentMessage(lhsId, lhsText, _), .agentMessage(rhsId, rhsText, _)):
            lhsId == rhsId && lhsText == rhsText
        case let (.reasoning(lhsId, lhsText, _), .reasoning(rhsId, rhsText, _)):
            lhsId == rhsId && lhsText == rhsText
        case let (
            .commandExecution(lhsId, lhsCommand, lhsOutput, _, lhsCompletedAt, lhsIntent),
            .commandExecution(rhsId, rhsCommand, rhsOutput, _, rhsCompletedAt, rhsIntent)
        ):
            lhsId == rhsId && lhsCommand == rhsCommand && lhsOutput == rhsOutput
                && lhsCompletedAt == rhsCompletedAt && lhsIntent == rhsIntent
        case let (.fileChange(lhsId, lhsChanges, _, lhsCompletedAt), .fileChange(rhsId, rhsChanges, _, rhsCompletedAt)):
            lhsId == rhsId && lhsChanges == rhsChanges && lhsCompletedAt == rhsCompletedAt
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
        case let (.taskList(lhsId, lhsTasks, _), .taskList(rhsId, rhsTasks, _)):
            lhsId == rhsId && lhsTasks == rhsTasks
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
                attachments: try nested.decodeIfPresent([ChatUserAttachment].self, forKey: .attachments) ?? [],
                turnEnd: try nested.decodeIfPresent(ChatTurnEnd.self, forKey: .turnEnd)
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
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast,
                completedAt: try nested.decodeIfPresent(Date.self, forKey: .completedAt),
                intent: try nested.decodeIfPresent(String.self, forKey: .intent)
            )
        } else if container.contains(.fileChange) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .fileChange)
            self = .fileChange(
                id: try nested.decode(String.self, forKey: .id),
                changes: try nested.decode([StructuredChatKit.FilePatchChange].self, forKey: .changes),
                timestamp: try nested.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast,
                completedAt: try nested.decodeIfPresent(Date.self, forKey: .completedAt)
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
        } else if container.contains(.taskList) {
            let nested = try container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .taskList)
            self = .taskList(
                id: try nested.decode(String.self, forKey: .id),
                tasks: try nested.decode([StructuredChatKit.AgentTaskItem].self, forKey: .tasks),
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
        case .userMessage(let id, let text, let timestamp, let attachments, let turnEnd):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .userMessage)
            try nested.encode(id, forKey: .id)
            try nested.encode(text, forKey: .text)
            try nested.encode(timestamp, forKey: .timestamp)
            if !attachments.isEmpty {
                try nested.encode(attachments, forKey: .attachments)
            }
            try nested.encodeIfPresent(turnEnd, forKey: .turnEnd)
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
        case .commandExecution(let id, let command, let output, let timestamp, let completedAt, let intent):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .commandExecution)
            try nested.encode(id, forKey: .id)
            try nested.encodeIfPresent(command, forKey: .command)
            try nested.encode(output, forKey: .output)
            try nested.encode(timestamp, forKey: .timestamp)
            try nested.encodeIfPresent(completedAt, forKey: .completedAt)
            try nested.encodeIfPresent(intent, forKey: .intent)
        case .fileChange(let id, let changes, let timestamp, let completedAt):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .fileChange)
            try nested.encode(id, forKey: .id)
            try nested.encode(changes, forKey: .changes)
            try nested.encode(timestamp, forKey: .timestamp)
            try nested.encodeIfPresent(completedAt, forKey: .completedAt)
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
        case .taskList(let id, let tasks, let timestamp):
            var nested = container.nestedContainer(keyedBy: AssociatedValueKeys.self, forKey: .taskList)
            try nested.encode(id, forKey: .id)
            try nested.encode(tasks, forKey: .tasks)
            try nested.encode(timestamp, forKey: .timestamp)
        }
    }
}

extension ChatItem {
    func withTimestamp(_ timestamp: Date) -> ChatItem {
        switch self {
        case .userMessage(let id, let text, _, let attachments, let turnEnd):
            .userMessage(id: id, text: text, timestamp: timestamp, attachments: attachments, turnEnd: turnEnd)
        case .agentMessage(let id, let text, _):
            .agentMessage(id: id, text: text, timestamp: timestamp)
        case .reasoning(let id, let text, _):
            .reasoning(id: id, text: text, timestamp: timestamp)
        case .commandExecution(let id, let command, let output, _, let completedAt, let intent):
            .commandExecution(
                id: id, command: command, output: output, timestamp: timestamp,
                completedAt: completedAt, intent: intent
            )
        case .fileChange(let id, let changes, _, let completedAt):
            .fileChange(id: id, changes: changes, timestamp: timestamp, completedAt: completedAt)
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
        case .taskList(let id, let tasks, _):
            .taskList(id: id, tasks: tasks, timestamp: timestamp)
        }
    }
}

