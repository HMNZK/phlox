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
    @State private var userOverride: Bool?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let presentation = TranscriptItemPresentation.taskList(count: tasks.count)
        DisclosureCard(
            isExpanded: Binding(
                get: {
                    TranscriptItemPresentation.isExpanded(
                        userOverride: userOverride,
                        defaultExpanded: presentation.defaultExpanded
                    )
                },
                set: { userOverride = $0 }
            ),
            title: presentation.heading ?? "",
            subtitle: nil,
            isToolCall: presentation.semanticInk == .process
        ) {
            VStack(alignment: .leading, spacing: TranscriptTypography.withinAnswer) {
                if tasks.isEmpty {
                    Text(presentation.expandedBody ?? "")
                        .font(ChatScaledFont.body(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                }
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                        Image(systemName: glyph(for: task.status))
                            .font(.system(size: DSIconSize.m, weight: .semibold))
                            .foregroundStyle(color(for: task.status))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(task.title)
                            .font(task.status == .inProgress ? TranscriptTypography.font(for: .bodyStrong, scale: scale) : titleFont(for: task.status, scale: scale))
                            .foregroundStyle(task.status == .completed ? DSColor.chatTextSecondary : DSColor.chatTextPrimary)
                            .strikethrough(task.status == .completed, color: DSColor.chatTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(accessibilityStatus(for: task.status)): \(task.title)")
                }
            }
            .padding(.top, TranscriptTypography.withinAnswer)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .accessibilityIdentifier("ChatMessage.taskList")
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
