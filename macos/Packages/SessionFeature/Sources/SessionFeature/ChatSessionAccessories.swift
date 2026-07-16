import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

struct SessionActivityOverlayStrip: View {
    let backgroundTasks: [RunningBackgroundTask]
    let transcriptItemIDs: () -> Set<String>
    let subAgents: [SubAgentRef]
    let selectedSubAgentId: String?
    let onJump: (String) -> Void
    let onSelectSubAgent: (String) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(spacing: 0) {
            BackgroundTaskStrip(
                tasks: backgroundTasks,
                transcriptItemIDs: transcriptItemIDs,
                onJump: onJump
            )
            SubAgentStrip(
                subAgents: subAgents,
                selectedSubAgentId: selectedSubAgentId,
                includesMainButton: false,
                onSelectMain: {},
                onSelectSubAgent: onSelectSubAgent
            )
        }
    }
}

private struct BackgroundTaskStrip: View {
    let tasks: [RunningBackgroundTask]
    let transcriptItemIDs: () -> Set<String>
    let onJump: (String) -> Void
    @State private var isCollapsed = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(DSColor.chatAccent)
                    .frame(height: 2)
                HStack(spacing: DSSpacing.s) {
                    Label("実行中 \(tasks.count)", systemImage: "bolt.fill")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.chatTextPrimary)
                    Spacer(minLength: DSSpacing.s)
                    Button {
                        isCollapsed.toggle()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: DSIconSize.s, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .help(isCollapsed ? "展開" : "折りたたみ")
                }
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.s)
                .padding(.bottom, isCollapsed ? DSSpacing.s : DSSpacing.xs)

                if !isCollapsed {
                    let resolvedTranscriptItemIDs = transcriptItemIDs()
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        ForEach(tasks) { task in
                            BackgroundTaskRow(
                                task: task,
                                jumpTarget: jumpTarget(for: task, transcriptItemIDs: resolvedTranscriptItemIDs),
                                onJump: onJump
                            )
                        }
                    }
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.bottom, DSSpacing.s)
                }
            }
            // overlay で本文の上に浮くため、下地（chatBackground）を敷いて透けを防ぐ。
            .background(DSColor.chatAccent.opacity(0.10).background(DSColor.chatBackground))
            .overlay(alignment: .bottom) {
                Divider().overlay(DSColor.chatAccent.opacity(0.35))
            }
            .accessibilityIdentifier("BackgroundTaskStrip")
        }
    }

    private func jumpTarget(for task: RunningBackgroundTask, transcriptItemIDs: Set<String>) -> String? {
        guard let toolUseId = task.toolUseId, transcriptItemIDs.contains(toolUseId) else { return nil }
        return toolUseId
    }
}

private struct BackgroundTaskRow: View {
    let task: RunningBackgroundTask
    let jumpTarget: String?
    let onJump: (String) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        Button {
            if let jumpTarget {
                onJump(jumpTarget)
            }
        } label: {
            HStack(spacing: DSSpacing.s) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                Text(Self.label(for: task.taskType))
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.chatAccent)
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
                Text(task.description.isEmpty ? task.taskId : task.description)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ElapsedTaskTimeText(startedAt: task.startedAt)
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .fill(DSColor.chatCard.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .strokeBorder(DSColor.chatAccent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(jumpTarget == nil)
        .accessibilityIdentifier("BackgroundTaskStrip.row")
        .help(jumpTarget == nil ? "該当セルが見つかりません" : "該当セルへ移動")
    }

    private static func label(for taskType: String) -> String {
        switch taskType {
        case "local_bash":
            "シェル"
        case "local_agent":
            "サブエージェント"
        default:
            taskType
        }
    }
}

struct SubAgentStrip: View {
    let subAgents: [SubAgentRef]
    let selectedSubAgentId: String?
    let includesMainButton: Bool
    let onSelectMain: () -> Void
    let onSelectSubAgent: (String) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        if !subAgents.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(DSColor.chatAccent.opacity(0.68))
                    .frame(height: 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        if includesMainButton {
                            SubAgentMainSwitchButton(
                                isSelected: selectedSubAgentId == nil,
                                onSelect: onSelectMain
                            )
                        }
                        ForEach(subAgents) { subAgent in
                            SubAgentStripRow(
                                subAgent: subAgent,
                                isSelected: selectedSubAgentId == subAgent.id,
                                onSelect: { onSelectSubAgent(subAgent.id) }
                            )
                        }
                    }
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.vertical, DSSpacing.s)
                }
            }
            .background(DSColor.chatAccent.opacity(0.08).background(DSColor.chatBackground))
            .overlay(alignment: .bottom) {
                Divider().overlay(DSColor.chatAccent.opacity(0.24))
            }
            .accessibilityIdentifier("SubAgentStrip")
        }
    }
}

private struct SubAgentMainSwitchButton: View {
    let isSelected: Bool
    let onSelect: () -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        Button(action: onSelect) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "text.bubble")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                Text("メイン")
                    .font(DSFont.captionStrong)
            }
            .foregroundStyle(isSelected ? DSColor.chatBackground : DSColor.chatTextPrimary)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .fill(isSelected ? DSColor.chatAccent : DSColor.chatCard.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .strokeBorder(DSColor.chatAccent.opacity(isSelected ? 0 : 0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SubAgentStrip.main")
        .help("メインチャットを表示")
    }
}

private struct SubAgentStripRow: View {
    let subAgent: SubAgentRef
    let isSelected: Bool
    let onSelect: () -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        Button(action: onSelect) {
            HStack(spacing: DSSpacing.xs) {
                statusIcon
                    .frame(width: 16, height: 16)
                Text(subAgent.subagentType)
                    .font(DSFont.captionStrong)
                    .foregroundStyle(isSelected ? DSColor.chatBackground : DSColor.chatAccent)
                    .lineLimit(1)
                Text(subAgent.description)
                    .font(DSFont.caption)
                    .foregroundStyle(isSelected ? DSColor.chatBackground.opacity(0.86) : DSColor.chatTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .fill(isSelected ? DSColor.chatAccent : DSColor.chatCard.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .strokeBorder(DSColor.chatAccent.opacity(isSelected ? 0 : 0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SubAgentStrip.row")
        .help(isSelected ? "メインへ戻る" : "サブエージェントを表示")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch subAgent.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isSelected ? DSColor.chatBackground : DSColor.chatSuccess)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(isSelected ? DSColor.chatBackground : DSColor.statusError)
        }
    }
}

private struct ElapsedTaskTimeText: View {
    let startedAt: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            Text(Self.formatElapsed(from: startedAt, to: context.date))
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.chatTextSecondary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
                .accessibilityLabel("経過時間 \(Self.formatElapsed(from: startedAt, to: context.date))")
        }
    }

    private static func formatElapsed(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, min(Int(end.timeIntervalSince(start)), 359_999))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct ApprovalBanner: View {
    @Bindable var viewModel: ChatSessionViewModel
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        if !viewModel.pendingApprovals.isEmpty {
            VStack(spacing: DSSpacing.s) {
                ForEach(viewModel.pendingApprovals) { approval in
                    HStack(spacing: DSSpacing.m) {
                        Image(systemName: icon(for: approval.kind))
                            .foregroundStyle(DSColor.statusAwaitingApproval)
                        Text(approval.prompt)
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.chatTextPrimary)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        Button("Accept") {
                            respond(approval, .accept)
                        }
                        Button("Decline") {
                            respond(approval, .decline)
                        }
                        Button("Cancel") {
                            respond(approval, .cancel)
                        }
                    }
                    .padding(DSSpacing.m)
                    .background(DSColor.statusAwaitingApproval.opacity(0.14), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .strokeBorder(DSColor.statusAwaitingApproval.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(DSColor.chatCard)
        }
    }

    private func icon(for kind: ChatApprovalKind) -> String {
        switch kind {
        case .command:
            "terminal"
        case .fileChange:
            "doc.badge.gearshape"
        case .permissions:
            "lock.shield"
        }
    }

    private func respond(_ approval: ChatApprovalRequest, _ decision: ApprovalDecision) {
        Task {
            await viewModel.respondToApproval(approval.id, decision: decision)
        }
    }
}

private struct RawEventLogView: View {
    let events: [String]
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.s) {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Text(event)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DSSpacing.l)
        }
        .background(DSColor.background)
    }
}
