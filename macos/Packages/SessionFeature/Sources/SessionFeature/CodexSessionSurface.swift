import Foundation
import SwiftUI
import AgentDomain
import CodexAppServerKit
import DesignSystem

/// Codex surface の AX 識別子。View と headless 検査で同じ値を使う。
enum CodexSessionSurfaceAccessibilityID {
    static let root = "CodexSessionSurface"
    static let plan = "CodexPlanTaskList"
    static let subAgentError = "CodexSubAgent.error"
    static let historyError = "CodexHistory.error"
    static let backgroundError = "CodexBackgroundTerminal.error"

    static func subAgent(_ id: String) -> String { "CodexSubAgent.\(id)" }
    static func subAgentDetail(_ id: String) -> String { "CodexSubAgentDetail.\(id)" }
    static func historyRow(_ id: String) -> String { "CodexHistory.row.\(id)" }
    static func historyResume(_ id: String) -> String { "CodexHistory.resume.\(id)" }
    static func historyDetail(_ id: String) -> String { "CodexHistory.detail.\(id)" }
    static func backgroundTerminal(_ id: String) -> String { "CodexBackgroundTerminal.\(id)" }
    static func backgroundDetail(_ id: String) -> String { "CodexBackgroundTerminal.detail.\(id)" }
}

/// Codex専用の既存セッション面。新画面を増やさず、チャット上部の既存surfaceへ状態を載せる。
struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    let onJump: (String) -> Void
    let onSelectChild: (String) -> Void
    let onStopChild: (String) -> Void
    @State private var selectedChildID: String?

    init(
        viewModel: ChatSessionViewModel,
        onJump: @escaping (String) -> Void,
        onSelectChild: @escaping (String) -> Void = { _ in },
        onStopChild: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onJump = onJump
        self.onSelectChild = onSelectChild
        self.onStopChild = onStopChild
    }

    var body: some View {
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let plan = viewModel.codexPlanTaskState, !plan.tasks.isEmpty {
                    TaskListCell(tasks: plan.tasks, timestamp: Date())
                    .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.plan)
                }
                if let subAgents = viewModel.codexSubAgentState {
                    if !subAgents.children.isEmpty {
                        ForEach(subAgents.children) { child in
                            HStack {
                                Button {
                                    selectedChildID = child.id
                                    onSelectChild(child.id)
                                } label: {
                                    Text(child.summary ?? child.id).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Text(child.status)
                                Button("停止") {
                                    onStopChild(child.id)
                                }
                                .disabled(subAgents.stopState(for: child.id) != .available)
                            }
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgent(child.id))
                        }
                        if let selectedChildID,
                           let detail = subAgents.detail(for: selectedChildID) {
                            ScrollView {
                                Text(detail.transcript.joined(separator: "\n"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentDetail(selectedChildID))
                        }
                    }
                    if let error = viewModel.codexSubAgentError {
                        ErrorMessageCell(message: "サブエージェント: \(error)", timestamp: Date())
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentError)
                    }
                }
                if let history = viewModel.codexSessionHistory {
                    if !history.entries.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DSSpacing.xs) {
                                ForEach(history.entries, id: \.id) { thread in
                                    Button {
                                        guard history.select(threadID: thread.id) else { return }
                                        Task {
                                            _ = await history.readIfPossible(threadID: thread.id)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(thread.name ?? thread.preview)
                                                .lineLimit(1)
                                            Text(thread.source.displayName)
                                                .font(DSFont.monoCaption)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.historyRow(thread.id))
                                    Button("再開") {
                                        Task {
                                            guard let resumed = await history.resumeIfPossible(threadID: thread.id)
                                            else { return }
                                            viewModel.applyCodexHistory(resumed)
                                        }
                                    }
                                    .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.historyResume(thread.id))
                                }
                            }
                        }
                        if let selected = history.selectedThread {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text("ID: \(selected.id)")
                                    .font(DSFont.monoCaption)
                                Text(selected.name ?? selected.preview)
                                    .lineLimit(2)
                                Text(selected.source.displayName)
                                    .font(DSFont.monoCaption)
                                ForEach(viewModel.codexHistoryItems(for: selected), id: \.id) { item in
                                    ChatItemView(
                                        item: item,
                                        isRunningCommand: false,
                                        agentDescriptor: AgentRegistry.descriptor(for: .codex)
                                    )
                                }
                            }
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.historyDetail(selected.id))
                        }
                    }
                    if let error = history.errorMessage {
                        ErrorMessageCell(message: "履歴: \(error)", timestamp: Date())
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.historyError)
                    }
                }
                if let terminals = viewModel.codexBackgroundTerminalState {
                    if !terminals.items.isEmpty {
                        ForEach(terminals.items, id: \.itemId) { terminal in
                            HStack {
                                Button {
                                    _ = terminals.select(itemId: terminal.itemId)
                                } label: {
                                    Text(terminal.command)
                                }
                                Button("ジャンプ") {
                                    if let target = terminals.jumpTarget(for: terminal.itemId, transcriptItemIds: viewModel.transcriptItemIDs) {
                                        onJump(target)
                                    }
                                }
                                .disabled(terminals.jumpTarget(for: terminal.itemId, transcriptItemIds: viewModel.transcriptItemIDs) == nil)
                                Button("停止") { Task { _ = await terminals.stop(itemId: terminal.itemId) } }
                            }
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.backgroundTerminal(terminal.itemId))
                        }
                        if let selected = terminals.selectedTerminal {
                            let cpu = selected.cpuPercent.map { String(format: "%.2f%%", $0) } ?? "不明"
                            let memory = selected.rssKb.map { "\($0) KiB" } ?? "不明"
                            let pid = selected.osPid.map(String.init) ?? "不明"
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text("コマンド: \(selected.command)")
                                Text("作業ディレクトリ: \(selected.cwd)")
                                Text("状態: 実行中")
                                Text("PID: \(pid)")
                                Text("CPU: \(cpu)")
                                Text("メモリ: \(memory)")
                                if let output = viewModel.transcript.first(where: { $0.id == selected.itemId })?.plainText,
                                   !output.isEmpty {
                                    Text("出力: \(output)")
                                }
                            }
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.backgroundDetail(selected.itemId))
                        }
                    }
                    if let error = terminals.errorMessage {
                        ErrorMessageCell(message: "背景ターミナル: \(error)", timestamp: Date())
                        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.backgroundError)
                    }
                }
            }
            .padding(DSSpacing.xs)
            .background(DSColor.chatCard)
            .task {
                await viewModel.refreshCodexSubAgents()
                await viewModel.codexSessionHistory?.refresh()
                await viewModel.codexBackgroundTerminalState?.refresh()
            }
            .onChange(of: viewModel.threadId) { _, _ in
                Task {
                    await viewModel.refreshCodexSubAgents()
                    await viewModel.codexBackgroundTerminalState?.refresh()
                }
            }
            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.root)
        }
    }
}
