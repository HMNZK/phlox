import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

struct SessionActivityOverlayStrip: View {
    let viewModel: ChatSessionViewModel
    let onJump: (String) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(spacing: 0) {
            BackgroundTaskStrip(
                tasks: viewModel.runningBackgroundTasks,
                transcriptItemIDs: { viewModel.transcriptItemIDs },
                onJump: onJump
            )
            SubAgentStrip(viewModel: viewModel)
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
                    .foregroundStyle(DSColor.accentInk)
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
    let onDismiss: (String) -> Void
    var onStop: ((String) -> Void)? = nil
    /// 表示 ID ごとの停止状態。nil は停止 API の無い子（Claude など）。
    var stopState: (String) -> CodexSubAgentStopState? = { _ in nil }
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
                        SubAgentMainLabel()
                        ForEach(subAgents) { subAgent in
                            SubAgentStripRow(
                                subAgent: subAgent,
                                onDismiss: { onDismiss(subAgent.id) },
                                stopState: stopState(subAgent.id),
                                onStop: { onStop?(subAgent.id) }
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

extension SubAgentStrip {
    /// 単一表示とグリッドタイルで共通の配線（停止・✕）。
    /// 停止の配線をここに一本化して、両表示で食い違わないようにする。
    init(viewModel: ChatSessionViewModel) {
        self.init(
            subAgents: viewModel.stripSubAgents,
            onDismiss: { viewModel.dismissSubAgent($0) },
            onStop: { viewModel.stopSubAgent(displayID: $0) },
            stopState: { viewModel.subAgentStopState(forDisplayID: $0) }
        )
    }
}

/// 「メイン」の札。サブエージェントの中身を見せなくなったので切り替えの役はなく、押せない（見た目は選択中のまま）。
private struct SubAgentMainLabel: View {
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "text.bubble")
                .font(.system(size: DSIconSize.s, weight: .semibold))
            Text("メイン")
                .font(DSFont.captionStrong)
        }
        .foregroundStyle(DSColor.chatBackground)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .fill(DSColor.chatAccent)
        )
        .accessibilityIdentifier("SubAgentStrip.main")
    }
}

/// 札の右端に、ポインタを置いた時だけ出す操作。
enum SubAgentChipControl: Equatable {
    case none
    /// 実行中で止められる子の停止ボタン。
    case stop
    /// 札を閉じる ✕。
    case dismiss
}

/// 札の名前の横に出す状態アイコン。出すのは「実行中」と「失敗」だけ。
enum SubAgentChipStatusIcon: Equatable {
    /// 実行中のローディングアニメーション。
    case loading
    /// 失敗のマーク。
    case failure
}

enum SubAgentChipPresentation {
    /// 実行中＝ローディング、失敗＝失敗マーク。完了（ユーザーが止めた札を含む）は名前だけでアイコンを出さない。
    static func statusIcon(for status: SubAgentStatus) -> SubAgentChipStatusIcon? {
        switch status {
        case .running: .loading
        case .failed: .failure
        case .completed, .stopped: nil
        }
    }

    /// 実行中の札は、止められる間だけ停止ボタン。止められない実行中（停止 API の無い Claude の子・turn 不明）と
    /// 停止中（interrupt 待ち）は何も出さない（✕ で閉じると、走り続ける子の札だけが消える）。
    /// 実行中でない札（完了・失敗・ユーザーが止めた札）は ✕。
    static func control(
        isHovering: Bool,
        status: SubAgentStatus,
        stopState: CodexSubAgentStopState?
    ) -> SubAgentChipControl {
        guard isHovering, stopState != .stopping else { return .none }
        if status == .running { return stopState == .available ? .stop : .none }
        return .dismiss
    }
}

/// サブエージェントの札（PhloxChat.dc.html の subs）: 高さ 22・角丸 11・11.5pt・ホバー色の地。
/// 中身は見せないので押しても何も開かない。ポインタを置くと右端に停止ボタンまたは ✕（閉じる）。
struct SubAgentStripRow: View {
    let subAgent: SubAgentRef
    let onDismiss: () -> Void
    var stopState: CodexSubAgentStopState? = nil
    var onStop: () -> Void = {}
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @State private var isHovering = false

    var body: some View {
        let _ = themeID
        let control = SubAgentChipPresentation.control(isHovering: isHovering, status: subAgent.status, stopState: stopState)
        HStack(spacing: 5) {
            Text(verbatim: subAgent.description.isEmpty ? subAgent.subagentType : subAgent.description)
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)
                .accessibilityLabel(Text("サブエージェント \(subAgent.description)、\(statusLabel)"))
                .accessibilityIdentifier("SubAgentStrip.row")
                // 停止・✕ はポインタを置いた時だけ出るので、VoiceOver からは行の操作として実行できるようにする。
                // 出す操作はホバー時の見た目と同じ関数で決める（実行中で止められる子に「閉じる」は出さない）。
                .accessibilityActions {
                    switch accessibilityControl {
                    case .stop: Button("サブエージェントを停止", action: onStop)
                    case .dismiss: Button("サブエージェントを閉じる", action: onDismiss)
                    case .none: EmptyView()
                    }
                }

            switch SubAgentChipPresentation.statusIcon(for: subAgent.status) {
            case .loading:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            case .failure:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.attentionInk(.error))
                    .accessibilityHidden(true)
            case nil:
                EmptyView()
            }

            switch control {
            case .stop:
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help("サブエージェントを停止")
                .accessibilityLabel("サブエージェントを停止")
                .accessibilityIdentifier("SubAgentStrip.stop")
            case .dismiss:
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help("サブエージェントを閉じる")
                .accessibilityLabel("サブエージェントを閉じる")
                .accessibilityIdentifier("SubAgentStrip.dismiss")
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(DSColor.fillSubtle)
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    /// ホバー中と同じ判定（VoiceOver ではホバーできないので、ホバーしている前提で出す操作を決める）。
    private var accessibilityControl: SubAgentChipControl {
        SubAgentChipPresentation.control(isHovering: true, status: subAgent.status, stopState: stopState)
    }

    private var statusLabel: Text {
        switch subAgent.status {
        case .running: Text("実行中")
        case .completed: Text("完了")
        case .failed: Text("失敗")
        case .stopped: Text("subagent.status.stopped")
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
                        .chatTextSelection()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DSSpacing.l)
        }
        .background(DSColor.background)
    }
}
