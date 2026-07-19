import SwiftUI
import AgentDomain
import StructuredChatKit

public struct ChatItemView: View {
    let item: ChatItem
    let isRunningCommand: Bool
    let agentDescriptor: AgentDescriptor
    var onSelectSubAgent: ((String) -> Void)? = nil
    var onRespondToUserQuestion: ((String, [String: [String]]) async -> Bool)? = nil

    public init(
        item: ChatItem,
        isRunningCommand: Bool,
        agentDescriptor: AgentDescriptor,
        onSelectSubAgent: ((String) -> Void)? = nil,
        onRespondToUserQuestion: ((String, [String: [String]]) async -> Bool)? = nil
    ) {
        self.item = item
        self.isRunningCommand = isRunningCommand
        self.agentDescriptor = agentDescriptor
        self.onSelectSubAgent = onSelectSubAgent
        self.onRespondToUserQuestion = onRespondToUserQuestion
    }

    public var body: some View {
        switch item {
        case .userMessage(_, let text, let timestamp, let attachments):
            UserMessageCell(text: text, timestamp: timestamp, attachments: attachments)
        case .agentMessage(_, let text, let timestamp):
            AgentMessageCell(text: text, timestamp: timestamp, descriptor: agentDescriptor)
        case .reasoning(_, let text, let timestamp):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else {
                ReasoningSummaryView(text: text, timestamp: timestamp)
            }
        case .commandExecution(_, let command, let output, let timestamp):
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunningCommand {
                EmptyView()
            } else {
                CommandExecutionCell(command: command, output: output, timestamp: timestamp, isRunning: isRunningCommand)
            }
        case .fileChange(_, let changes, let timestamp):
            FileChangeCell(changes: changes, timestamp: timestamp)
        case .error(_, let message, let timestamp):
            ErrorMessageCell(message: message, timestamp: timestamp)
        case .subAgentMarker(let id, let subagentType, let description, let status):
            SubAgentMarkerCell(
                id: id,
                subagentType: subagentType,
                description: description,
                status: status,
                onSelect: onSelectSubAgent
            )
        case .turnCost(_, let costUSD, let timestamp):
            TurnCostCell(costUSD: costUSD, timestamp: timestamp)
        case .userQuestion(let id, let requestId, let questions, let answers, let state, let timestamp):
            UserQuestionCell(
                itemId: id,
                requestId: requestId,
                questions: questions,
                answers: answers,
                state: state,
                timestamp: timestamp,
                onRespond: onRespondToUserQuestion
            )
        }
    }
}
