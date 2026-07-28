import SwiftUI
import AgentDomain
import StructuredChatKit

public struct ChatItemView: View, Equatable {
    let item: ChatItem
    let isRunningCommand: Bool
    let agentDescriptor: AgentDescriptor
    var onSelectSubAgent: ((String) -> Void)? = nil
    var onRespondToUserQuestion: ((String, [String: [String]]) async -> Bool)? = nil
    /// 未回答の質問カードを回答せずに閉じる（＝ターンを中断する）。
    /// 配線しない場所（サブエージェントのドロワー・チームのタイムライン等の閲覧専用表示）では
    /// 閉じるボタン自体が出ない。
    var onDismissUserQuestion: (() -> Void)? = nil

    public init(
        item: ChatItem,
        isRunningCommand: Bool,
        agentDescriptor: AgentDescriptor,
        onSelectSubAgent: ((String) -> Void)? = nil,
        onRespondToUserQuestion: ((String, [String: [String]]) async -> Bool)? = nil,
        onDismissUserQuestion: (() -> Void)? = nil
    ) {
        self.item = item
        self.isRunningCommand = isRunningCommand
        self.agentDescriptor = agentDescriptor
        self.onSelectSubAgent = onSelectSubAgent
        self.onRespondToUserQuestion = onRespondToUserQuestion
        self.onDismissUserQuestion = onDismissUserQuestion
    }

    /// ADR 0116: 未変更行の body 再評価をスキップするための同値性（呼び出し側で `.equatable()`）。
    /// 表示に効く値だけを比較し、**クロージャは比較対象から外す**——`onRespondToUserQuestion` 等は
    /// 呼び出しのたびに新しく生成されるため、含めると常に不一致になり差分が一切効かなくなる。
    /// これらは viewModel を捕捉する安定した参照であり、セッションが変わる場合は
    /// `SessionGridView` の `.id(session.id)` によってビュー identity ごと作り直される。
    /// `@State`/`@AppStorage` は各セル自身の invalidation で再評価されるため、ここでは扱わない
    /// （テーマ変更などは同値性に関わらず反映される）。
    nonisolated public static func == (lhs: ChatItemView, rhs: ChatItemView) -> Bool {
        lhs.item == rhs.item
            && lhs.isRunningCommand == rhs.isRunningCommand
            && lhs.agentDescriptor == rhs.agentDescriptor
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
        case .taskList(_, let tasks, let timestamp):
            TaskListCell(tasks: tasks, timestamp: timestamp)
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
                onRespond: onRespondToUserQuestion,
                onDismiss: onDismissUserQuestion
            )
        }
    }
}
