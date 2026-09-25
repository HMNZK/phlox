import Foundation
import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

/// Codex surface の AX 識別子。View と headless 検査で同じ値を使う。
enum CodexSessionSurfaceAccessibilityID {
    static let root = "CodexSessionSurface"
    static let plan = "CodexPlanTaskList"
    static let subAgentError = "CodexSubAgent.error"

    static func subAgent(_ id: String) -> String { "CodexSubAgent.\(id)" }
    static func subAgentDetail(_ id: String) -> String { "CodexSubAgentDetail.\(id)" }
}

/// Codex のプランと子スレッド（PhloxChat.dc.html の isCodex）。会話の中の 1 枚のカードとして出す。
/// 角丸 10・1pt 枠・カード地。「プラン 3 / 5 完了」→ タスク行 → 区切り →「子スレッド n」→ 子スレッド行（題名・要約・状態・停止）。
struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    let onSelectChild: (String) -> Void
    let onStopChild: (String) -> Void
    @State private var selectedChildID: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    /// 会話の文字サイズ設定に合わせる倍率。
    private var scale: CGFloat { ChatFontSettings.adjusted(from: chatScale, by: 0) }

    init(
        viewModel: ChatSessionViewModel,
        onSelectChild: @escaping (String) -> Void = { _ in },
        onStopChild: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onSelectChild = onSelectChild
        self.onStopChild = onStopChild
    }

    private var hasContent: Bool {
        !(viewModel.codexPlanTaskState?.tasks.isEmpty ?? true)
            || !(viewModel.codexSubAgentState?.children.isEmpty ?? true)
            || viewModel.codexSubAgentError != nil
    }

    var body: some View {
        let _ = themeID
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: 0) {
                if let plan = viewModel.codexPlanTaskState, !plan.tasks.isEmpty {
                    planSection(plan.tasks)
                }
                if let subAgents = viewModel.codexSubAgentState, !subAgents.children.isEmpty {
                    childrenSection(subAgents)
                }
                if let error = viewModel.codexSubAgentError {
                    ErrorMessageCell(message: "サブエージェント: \(error)", timestamp: Date())
                        .padding(8)
                        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentError)
                }
            }
            // 中身が無い間は面を描かない。子スレッドの取得（.task）は中身の有無に関係なく走らせる。
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
            .task {
                await viewModel.refreshCodexSubAgents()
            }
            .onChange(of: viewModel.threadId) { _, _ in
                Task {
                    await viewModel.refreshCodexSubAgents()
                }
            }
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

    private func childrenSection(_ subAgents: CodexSubAgentState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.codexPlanTaskState?.tasks.isEmpty == false {
                Rectangle().fill(DSColor.separator).frame(height: 1)
            }
            HStack(spacing: 8) {
                Text("子スレッド")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(subAgents.children.count)")
                    .font(.system(size: 12 * scale))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(subAgents.children) { child in
                let canStop = subAgents.stopState(for: child.id) == .available
                Rectangle().fill(DSColor.separator).frame(height: 1)
                HStack(spacing: 10) {
                    Button {
                        selectedChildID = child.id
                        onSelectChild(child.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(child.summary ?? child.id)
                                .font(.system(size: 12.5 * scale))
                                .foregroundStyle(DSColor.textPrimary)
                                .lineLimit(1)
                            if let source = child.sourceIdentity, !source.isEmpty {
                                Text(verbatim: source)
                                    .font(.system(size: 11 * scale))
                                    .foregroundStyle(DSColor.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(child.summary ?? child.id)
                    Self.statusText(child.status)
                        .font(.system(size: 11 * scale, weight: Self.isRunning(child.status) ? .semibold : .regular))
                        .foregroundStyle(Self.isRunning(child.status) ? DSColor.textPrimary : DSColor.textTertiary)
                    Button {
                        onStopChild(child.id)
                    } label: {
                        Text("停止")
                            .font(.system(size: 11.5 * scale))
                            .foregroundStyle(canStop ? DSColor.textPrimary : DSColor.textTertiary)
                            .padding(.horizontal, 9)
                            .frame(height: 22 * scale)
                            .background {
                                if canStop {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DSColor.controlBackground)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(canStop ? DSColor.controlBorder : DSColor.separator, lineWidth: canStop ? 0.5 : 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStop)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgent(child.id))
                .accessibilityElement(children: .contain)
            }
            if let selectedChildID, let detail = subAgents.detail(for: selectedChildID) {
                Rectangle().fill(DSColor.separator).frame(height: 1)
                ScrollView {
                    Text(detail.transcript.joined(separator: "\n"))
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentDetail(selectedChildID))
                }
                .frame(maxHeight: 120)
                .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentDetail(selectedChildID))
                .accessibilityElement(children: .contain)
            }
        }
    }

    static func isRunning(_ status: String) -> Bool {
        ["active", "running", "inprogress", "in_progress"].contains(status.lowercased())
    }

    static func statusText(_ status: String) -> Text {
        if isRunning(status) { return Text("実行中") }
        switch status.lowercased() {
        case "idle", "completed": return Text("完了")
        case "error", "systemerror", "failed": return Text("エラー")
        default: return Text("不明")
        }
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
