import Foundation
import SwiftUI
import AgentDomain
import DesignSystem

/// Codex surface の AX 識別子。View と headless 検査で同じ値を使う。
enum CodexSessionSurfaceAccessibilityID {
    static let root = "CodexSessionSurface"
    static let plan = "CodexPlanTaskList"
    static let subAgentError = "CodexSubAgent.error"

    static func subAgent(_ id: String) -> String { "CodexSubAgent.\(id)" }
    static func subAgentDetail(_ id: String) -> String { "CodexSubAgentDetail.\(id)" }
}

/// Codex専用の既存セッション面。新画面を増やさず、チャット上部の既存surfaceへ状態を載せる。
struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    let onSelectChild: (String) -> Void
    let onStopChild: (String) -> Void
    @State private var selectedChildID: String?

    init(
        viewModel: ChatSessionViewModel,
        onSelectChild: @escaping (String) -> Void = { _ in },
        onStopChild: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onSelectChild = onSelectChild
        self.onStopChild = onStopChild
    }

    var body: some View {
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let plan = viewModel.codexPlanTaskState, !plan.tasks.isEmpty {
                    TaskListCell(tasks: plan.tasks, timestamp: Date())
                    .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.plan)
                    .accessibilityElement(children: .contain)
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
                                .accessibilityLabel(child.summary ?? child.id)
                                Spacer()
                                Text(child.status)
                                Button("停止") {
                                    onStopChild(child.id)
                                }
                                .disabled(subAgents.stopState(for: child.id) != .available)
                            }
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgent(child.id))
                            .accessibilityElement(children: .contain)
                        }
                        if let selectedChildID,
                           let detail = subAgents.detail(for: selectedChildID) {
                            ScrollView {
                                Text(detail.transcript.joined(separator: "\n"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentDetail(selectedChildID))
                            }
                            .frame(maxHeight: 120)
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentDetail(selectedChildID))
                            .accessibilityElement(children: .contain)
                        }
                    }
                    if let error = viewModel.codexSubAgentError {
                        ErrorMessageCell(message: "サブエージェント: \(error)", timestamp: Date())
                            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentError)
                    }
                }
            }
            .padding(DSSpacing.xs)
            .background(DSColor.chatCard)
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
}
