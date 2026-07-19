import SwiftUI
import AgentDomain
import StructuredChatKit

public struct ChatItemView: View {
    let item: ChatItem
    let isRunningCommand: Bool
    let agentDescriptor: AgentDescriptor
    var onSelectSubAgent: ((String) -> Void)? = nil

    public init(
        item: ChatItem,
        isRunningCommand: Bool,
        agentDescriptor: AgentDescriptor,
        onSelectSubAgent: ((String) -> Void)? = nil
    ) {
        self.item = item
        self.isRunningCommand = isRunningCommand
        self.agentDescriptor = agentDescriptor
        self.onSelectSubAgent = onSelectSubAgent
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
        case .userQuestion(let id, _, let questions, let answers, let state, let timestamp):
            // task-2 が UserQuestionCell（選択肢ボタン・multiSelect・自由入力）へ差し替える骨組み。
            UserQuestionCell(
                itemId: id,
                questions: questions,
                answers: answers,
                state: state,
                timestamp: timestamp
            )
        }
    }
}
