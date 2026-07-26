import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore

/// サブエージェント詳細画面（task-10）。親セッションの subAgent メッセージをチャット形式で表示する。
public struct SubAgentDetailView: View {
    @State private var viewModel: SubAgentDetailViewModel

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
        switch message {
        case let .user(_, text):
            let rendered = SubAgentDetailViewModel.renderedBody(text)
            DSChatBubble(role: .user, message: renderedDisplayText(rendered), copyText: copyText)
        case let .agent(_, text):
            let rendered = SubAgentDetailViewModel.renderedBody(text)
            DSChatBubble(
                role: .agent,
                message: renderedDisplayText(rendered),
                agentKind: viewModel.session.agent,
                copyText: copyText
            )
        case let .reasoning(_, text):
            let rendered = SubAgentDetailViewModel.renderedBody(text)
            chatRowWithCopy(copyText: copyText) {
                DSReasoningText(text: renderedDisplayText(rendered))
            }
        case let .subAgent(_, text):
            let rendered = SubAgentDetailViewModel.renderedBody(text)
            chatRowWithCopy(copyText: copyText) {
                DSSubAgentRow(text: renderedDisplayText(rendered))
            }
        case let .command(_, command, output):
            let rendered = SubAgentDetailViewModel.renderedBody(output)
            chatRowWithCopy(copyText: copyText) {
                chatMonospaceCard(title: command.map { "$ \($0)" } ?? "$", body: renderedDisplayText(rendered))
            }
        case let .fileChange(_, changes):
            let rendered = SubAgentDetailViewModel.renderedBody(
                changes.map { "\($0.path)\n\($0.diff)" }.joined(separator: "\n\n")
            )
            chatRowWithCopy(copyText: copyText) {
                chatMonospaceCard(title: "ファイル変更", body: renderedDisplayText(rendered))
            }
        case let .error(_, message):
            let rendered = SubAgentDetailViewModel.renderedBody(message)
            chatRowWithCopy(copyText: copyText) {
                DSResultBanner(message: renderedDisplayText(rendered), isError: true)
            }
        case .userQuestion:
            // AskUserQuestion はサブエージェント内では使えない（CLI 制約）ため表示なし。
            EmptyView()
        }
    }

    @ViewBuilder
    private func chatRowWithCopy<Content: View>(
        copyText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let copyText {
                ChatMessageCopyButton(text: copyText)
            }
        }
    }

    private func renderedDisplayText(_ rendered: SubAgentDetailViewModel.RenderedBody) -> String {
        guard rendered.omittedBytes > 0 else { return rendered.head }
        return """
        \(rendered.head)

        表示を省略しました（\(rendered.omittedBytes) バイト）。コピーには全文が含まれます。

        \(rendered.tail)
        """
    }

    private func chatMonospaceCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(title)
                .font(DSFont.footnote.weight(.bold))
                .foregroundStyle(DSColor.campTextQuaternary)
            if !body.isEmpty {
                Text(body)
                    .font(DSFont.campMonoCaption)
                    .tracking(-0.5)
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(DSColor.campOutputBackground, in: outputCardShape)
        .clipShape(outputCardShape)
    }

    private var outputCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
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
