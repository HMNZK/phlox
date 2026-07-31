import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore

/// サブエージェント詳細画面（task-10）。親セッションの subAgent メッセージをチャット形式で表示する。
public struct SubAgentDetailView: View {
    @State private var viewModel: SubAgentDetailViewModel
    @State private var expansionOverrides: [String: Bool] = [:]

    public init(viewModel: SubAgentDetailViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                if let error = viewModel.loadError {
                    DSResultBanner(message: error, isError: true)
                } else if viewModel.isInitialLoading {
                    DSConnectingIndicator(size: 96)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 320)
                } else {
                    if viewModel.hiddenMessageCount > 0 {
                        Button("以前のメッセージを読む（\(viewModel.hiddenMessageCount)件）") {
                            viewModel.expandVisibleWindow()
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(viewModel.visibleMessages) { message in
                        chatRow(for: message)
                    }
                }
            }
            .padding(DSSpacing.l)
        }
        .background(DSColor.background)
        .navigationTitle("サブエージェント")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.startPolling() }
    }

    @ViewBuilder
    private func chatRow(for message: ChatMessage) -> some View {
        let copyText = ChatMessageCopyText.copyText(for: message)
        switch ChatRowKind.forMessage(message) {
        case .userBubble:
            if case let .user(_, text) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(text)
                DSChatBubble(role: .user, message: renderedDisplayText(rendered), copyText: copyText)
            }
        case .agentBubble:
            if case let .agent(_, text) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(text)
                DSChatBubble(
                    role: .agent,
                    message: renderedDisplayText(rendered),
                    agentKind: viewModel.session.agent,
                    copyText: copyText
                )
            }
        case .reasoning:
            if case let .reasoning(_, text) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(text)
                chatRowWithCopy(copyText: copyText) {
                    DSReasoningText(text: renderedDisplayText(rendered))
                }
            }
        case .subAgent:
            if case let .subAgent(_, text) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(text)
                chatRowWithCopy(copyText: copyText) {
                    DSSubAgentRow(text: renderedDisplayText(rendered))
                }
            }
        case .commandCard:
            if case let .command(id, command, output) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(output)
                chatRowWithCopy(copyText: copyText) {
                    SessionDetailCommandCard(
                        command: command,
                        output: renderedDisplayText(rendered),
                        isExpanded: isMessageExpanded(id),
                        onToggle: { toggleMessageExpansion(id) }
                    )
                }
            }
        case .fileChangeCard:
            if case let .fileChange(id, changes) = message {
                let data = SessionDetailDiffCodeViewData(changes: changes)
                chatRowWithCopy(copyText: copyText) {
                    SessionDetailFileChangeCard(
                        data: data,
                        isExpanded: isMessageExpanded(id),
                        onToggle: { toggleMessageExpansion(id) }
                    )
                }
            }
        case .error:
            if case let .error(_, message) = message {
                let rendered = SubAgentDetailViewModel.renderedBody(message)
                chatRowWithCopy(copyText: copyText) {
                    DSResultBanner(message: renderedDisplayText(rendered), isError: true)
                }
            }
        case .userQuestion:
            if case .userQuestion = message {
                // AskUserQuestion はサブエージェント内では使えない（CLI 制約）ため表示なし。
                EmptyView()
            }
        }
    }

    /// コピーは行ごとのボタンではなく長押しメニューで出す（SessionDetailView と同じ作法）。
    private func chatRowWithCopy<Content: View>(
        copyText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .chatMessageCopyContextMenu(copyText: copyText)
    }

    private func renderedDisplayText(_ rendered: SubAgentDetailViewModel.RenderedBody) -> String {
        guard rendered.omittedBytes > 0 else { return rendered.head }
        return """
        \(rendered.head)

        表示を省略しました（\(rendered.omittedBytes) バイト）。コピーには全文が含まれます。

        \(rendered.tail)
        """
    }

    private func isMessageExpanded(_ messageID: String) -> Bool {
        expansionOverrides[messageID] ?? false
    }

    private func toggleMessageExpansion(_ messageID: String) {
        let current = expansionOverrides[messageID] ?? false
        expansionOverrides[messageID] = !current
    }
}

#if DEBUG
#Preview("SubAgentDetailView") {
    NavigationStack {
        SubAgentDetailView(
            viewModel: SubAgentDetailViewModel(
                session: Session(
                    id: "s1", name: "Rose", agent: .claudeCode, status: .running,
                    subtitle: "proj", updatedAt: Date()
                ),
                subAgentID: "sa1",
                api: StubPhloxAPI()
            )
        )
    }
}
#endif
