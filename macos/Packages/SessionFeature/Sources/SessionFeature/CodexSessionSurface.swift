import SwiftUI
import CodexAppServerKit
import DesignSystem

/// Codex専用の既存セッション面。新画面を増やさず、チャット上部の既存surfaceへ状態を載せる。
struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    let onJump: (String) -> Void

    var body: some View {
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let plan = viewModel.codexPlanTaskState, !plan.tasks.isEmpty {
                    TaskListCell(tasks: plan.tasks, timestamp: Date())
                    .accessibilityIdentifier("CodexPlanTaskList")
                }
                if let subAgents = viewModel.codexSubAgentState, !subAgents.children.isEmpty {
                    ForEach(subAgents.children) { child in
                        HStack {
                            Text(child.summary ?? child.id).lineLimit(1)
                            Spacer()
                            Text(child.status)
                        }
                        .accessibilityIdentifier("CodexSubAgent.\(child.id)")
                    }
                }
                if let history = viewModel.codexSessionHistory, !history.entries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DSSpacing.xs) {
                            ForEach(history.entries, id: \.id) { thread in
                                Button {
                                    Task {
                                        _ = try? await history.resume(threadID: thread.id)
                                        await viewModel.reloadCodexHistory(threadID: thread.id)
                                    }
                                } label: {
                                    Text(thread.name ?? thread.preview)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("CodexHistory.row.\(thread.id)")
                            }
                        }
                    }
                }
                if let terminals = viewModel.codexBackgroundTerminalState,
                   !terminals.items.isEmpty {
                    ForEach(terminals.items, id: \.itemId) { terminal in
                        HStack {
                            Button(terminal.command) {
                                if let target = terminals.jumpTarget(for: terminal.itemId, transcriptItemIds: viewModel.transcriptItemIDs) {
                                    onJump(target)
                                }
                            }
                            .disabled(terminals.jumpTarget(for: terminal.itemId, transcriptItemIds: viewModel.transcriptItemIDs) == nil)
                            Button("停止") { Task { _ = await terminals.stop(itemId: terminal.itemId) } }
                        }
                    }
                }
            }
            .padding(DSSpacing.xs)
            .background(DSColor.chatCard)
            .task {
                await viewModel.codexSessionHistory?.refresh()
                await viewModel.codexBackgroundTerminalState?.refresh()
            }
            .accessibilityIdentifier("CodexSessionSurface")
        }
    }
}
