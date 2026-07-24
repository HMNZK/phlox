import SwiftUI
import StructuredChatKit
import DesignSystem

/// エージェントのタスクリストカード（tasks/task-2.md 契約。受け入れテスト
/// AcceptanceTaskListCardTests が凍結）。transcript 内に 1 枚だけ置かれ、
/// taskListUpdated のたびに最新スナップショットへ差し替わる。
///
/// スケルトン（フェーズ1 凍結公開面）: 表示実装は task-2 が行う。
struct TaskListCell: View {
    let tasks: [AgentTaskItem]
    let timestamp: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        DisclosureCard(
            isExpanded: .constant(true),
            title: "Tasks",
            subtitle: tasks.isEmpty ? "No tasks" : "\(tasks.count) tasks",
            timestamp: timestamp,
            systemImage: "checklist",
            accent: hasInProgressTask ? DSColor.chatAccent : DSColor.chatSuccess,
            status: hasInProgressTask ? .running : .complete
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                        Image(systemName: glyph(for: task.status))
                            .font(.system(size: DSIconSize.m, weight: .semibold))
                            .foregroundStyle(color(for: task.status))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(task.title)
                            .font(titleFont(for: task.status, scale: scale))
                            .foregroundStyle(task.status == .completed ? DSColor.chatTextSecondary : DSColor.chatTextPrimary)
                            .strikethrough(task.status == .completed, color: DSColor.chatTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(accessibilityStatus(for: task.status)): \(task.title)")
                }
            }
            .padding(.top, DSSpacing.s)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .accessibilityIdentifier("ChatMessage.taskList")
    }

    private var hasInProgressTask: Bool {
        tasks.contains { $0.status == .inProgress }
    }

    private func glyph(for status: AgentTaskStatus) -> String {
        switch status {
        case .pending: "circle"
        case .inProgress: "arrow.triangle.2.circlepath.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    private func color(for status: AgentTaskStatus) -> Color {
        switch status {
        case .pending: DSColor.chatTextSecondary
        case .inProgress: DSColor.chatAccent
        case .completed: DSColor.chatSuccess
        }
    }

    private func titleFont(for status: AgentTaskStatus, scale: CGFloat) -> Font {
        status == .inProgress ? ChatScaledFont.body(scale: scale).weight(.semibold) : ChatScaledFont.body(scale: scale)
    }

    private func accessibilityStatus(for status: AgentTaskStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .inProgress: "In progress"
        case .completed: "Completed"
        }
    }
}
