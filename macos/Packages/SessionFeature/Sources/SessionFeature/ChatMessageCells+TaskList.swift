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
    @Environment(\.locale) private var locale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let completed = tasks.filter { $0.status == .completed }.count
        let presentation = TranscriptItemPresentation.taskList(count: tasks.count, completed: completed)
        TranscriptCard(
            isExpanded: Binding(
                get: {
                    TranscriptItemPresentation.isExpanded(
                        userOverride: userOverride,
                        defaultExpanded: presentation.defaultExpanded
                    )
                },
                set: { userOverride = $0 }
            ),
            label: Text("タスク \(completed)/\(tasks.count)"),
            summary: summary(completed: completed)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if tasks.isEmpty {
                    Text(presentation.expandedBody ?? "")
                        .font(.system(size: 12.5 * scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .frame(minHeight: 24 * scale)
                }
                ForEach(tasks) { task in
                    HStack(spacing: 10) {
                        TaskStatusMark(status: task.status, scale: scale)
                        Text(task.title)
                            .font(.system(size: 12.5 * scale, weight: task.status == .inProgress ? .semibold : .regular))
                            .foregroundStyle(task.status == .completed ? DSColor.textTertiary : DSColor.chatTextPrimary)
                            .strikethrough(task.status == .completed, color: DSColor.textTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 24 * scale)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Self.accessibilityStatus(for: task.status))：\(task.title)"))
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("ChatMessage.taskList")
    }

    /// 見出しの要約: 進行中のタスク名。全部終わっていれば「すべて完了」。
    private func summary(completed: Int) -> String? {
        if let doing = tasks.first(where: { $0.status == .inProgress }) { return doing.title }
        if !tasks.isEmpty, completed == tasks.count { return AppLocalizedString.string("すべて完了", locale: locale) }
        return nil
    }

    static func accessibilityStatus(for status: AgentTaskStatus) -> Text {
        switch status {
        case .pending: Text("未着手")
        case .inProgress: Text("進行中")
        case .completed: Text("完了")
        }
    }
}

/// 状態のしるし（✓ 完了・● 進行中 8pt・○ 未着手 11pt）。色は付けない（色は注意の 4 状態だけ）。
private struct TaskStatusMark: View {
    let status: AgentTaskStatus
    let scale: CGFloat

    var body: some View {
        Group {
            switch status {
            case .completed:
                Text(verbatim: "✓").font(.system(size: 12 * scale)).foregroundStyle(DSColor.textTertiary)
            case .inProgress:
                Circle().fill(DSColor.chatTextPrimary).frame(width: 8 * scale, height: 8 * scale)
            case .pending:
                Circle().strokeBorder(DSColor.textTertiary, lineWidth: 1).frame(width: 11 * scale, height: 11 * scale)
            }
        }
        .frame(width: 12 * scale)
        .accessibilityHidden(true)
    }
}
