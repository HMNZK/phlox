import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

/// Codex のプラン表示。子エージェントは共通の strip / marker で表示する。
enum CodexSessionSurfaceAccessibilityID {
    static let root = "CodexSessionSurface"
    static let plan = "CodexPlanTaskList"
    static let subAgentError = "CodexSubAgent.error"
}

struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    private var scale: CGFloat { ChatFontSettings.adjusted(from: chatScale, by: 0) }
    private var hasContent: Bool {
        !(viewModel.codexPlanTaskState?.tasks.isEmpty ?? true) || viewModel.codexSubAgentError != nil
    }

    var body: some View {
        let _ = themeID
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: 0) {
                if let plan = viewModel.codexPlanTaskState, !plan.tasks.isEmpty {
                    planSection(plan.tasks)
                }
                if viewModel.codexSubAgentError != nil {
                    ErrorMessageCell(message: "サブエージェント情報を取得できませんでした", timestamp: Date())
                        .padding(8)
                        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentError)
                }
            }
            .background {
                if hasContent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSColor.cardBackground)
                }
            }
            .overlay {
                if hasContent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DSColor.separator, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.root)
        }
    }

    private func planSection(_ tasks: [AgentTaskItem]) -> some View {
        let completed = tasks.filter { $0.status == .completed }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("プラン")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(completed) / \(tasks.count) 完了")
                    .font(.system(size: 12 * scale))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Rectangle().fill(DSColor.separator).frame(height: 1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tasks) { task in
                    HStack(spacing: 9) {
                        CodexPlanMark(status: task.status)
                        Text(task.title)
                            .font(.system(size: 12.5 * scale, weight: task.status == .inProgress ? .semibold : .regular))
                            .foregroundStyle(task.status == .completed ? DSColor.textTertiary : DSColor.textPrimary)
                            .strikethrough(task.status == .completed, color: DSColor.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 24 * scale)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(TaskListCell.accessibilityStatus(for: task.status))：\(task.title)"))
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.plan)
        .accessibilityElement(children: .contain)
    }
}

/// ✓ 完了・● 進行中（8pt）・○ 未着手（11pt）。幅 12。
private struct CodexPlanMark: View {
    let status: AgentTaskStatus

    var body: some View {
        Group {
            switch status {
            case .completed:
                Text(verbatim: "✓").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
            case .inProgress:
                Circle().fill(DSColor.textPrimary).frame(width: 8, height: 8)
            case .pending:
                Circle().strokeBorder(DSColor.textPrimary, lineWidth: 1).frame(width: 10, height: 10)
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}
