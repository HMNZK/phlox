import SwiftUI
import DesignSystemIOS
import PhloxCore

/// 質問への回答画面（カンプ⑦）。チャットバブル + 入力バーで `POST /send` する。
public struct ChatAnswerView: View {
    @State private var viewModel: ChatAnswerViewModel
    @Environment(\.locale) private var locale

    public init(viewModel: ChatAnswerViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    /// カンプ⑦ スクリーンショット比較用のバブル最大幅（参照画像計測値）。
    private enum ScreenshotBubbleWidth {
        static let agent: CGFloat = 278
        static let user: CGFloat = 210
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: isScreenshotChat ? DSSpacing.xl : DSSpacing.m) {
                    DSChatBubble(
                        role: .agent,
                        message: viewModel.agentQuestion,
                        agentKind: viewModel.session.agent,
                        maxBubbleWidth: isScreenshotChat ? ScreenshotBubbleWidth.agent : nil,
                        copyText: ChatMessageCopyText.normalizedCopyText(viewModel.agentQuestion)
                    )

                    ForEach(viewModel.userMessages) { message in
                        DSChatBubble(
                            role: .user,
                            message: message.text,
                            maxBubbleWidth: isScreenshotChat ? ScreenshotBubbleWidth.user : nil,
                            copyText: ChatMessageCopyText.normalizedCopyText(message.text)
                        )
                        .opacity(message.isPending ? 0.72 : 1)
                    }

                    if case .failed(let message) = viewModel.sendState {
                        DSResultBanner(message: message, isError: true)
                    }
                }
                .padding(DSSpacing.l)
            }

            DSChatInputBar(
                text: $viewModel.inputText,
                placeholder: "回答を入力…",
                isLoading: viewModel.isSending
            ) {
                Task { await viewModel.sendAnswer() }
            }
            .padding(DSSpacing.m)
        }
        .background(DSColor.background)
        .navigationTitle(isScreenshotChat ? "" : viewModel.session.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isScreenshotChat)
        #endif
        .toolbar {
            #if os(iOS)
            if isScreenshotChat {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DSColor.campAccentBright)
                        .accessibilityLabel(Text("戻る"))
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: DSSpacing.xs) {
                        Text(viewModel.session.name)
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        questionWaitingChip
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DSColor.campAccentBright)
                        .accessibilityLabel(Text("その他"))
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    questionWaitingChip
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                questionWaitingChip
            }
            #endif
        }
        .accessibilityIdentifier(AccessibilityID.chatAnswer)
    }

    private var isScreenshotChat: Bool {
        ProcessInfo.processInfo.arguments.contains("-UIScreen=chatAnswer")
    }

    private var questionWaitingChip: some View {
        let label: String
        if isScreenshotChat {
            label = "質問待ち"
        } else {
            label = DSAttentionRow.chipLabel(for: viewModel.session, locale: locale)
        }
        let tint = DSColor.statusAwaitingApproval
        return HStack(spacing: DSSpacing.xs) {
            Image(systemName: StatusBadge.iconName(for: viewModel.session.status))
                .imageScale(.small)
            Text(label)
                .font(DSFont.captionStrong)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(tint.opacity(0.34), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityLabel(Text(label))
    }
}

#if DEBUG
#Preview("ChatAnswer") {
    NavigationStack {
        ChatAnswerView(
            viewModel: ChatAnswerViewModel(
                session: Session(
                    id: "sess-tulip",
                    name: "Tulip",
                    agent: .codex,
                    status: .awaitingApproval(prompt: "v2 契約で進めますか？"),
                    subtitle: "回答待ち: 「v2 契約で進めますか？」",
                    updatedAt: Date()
                ),
                api: StubPhloxAPI()
            )
        )
    }
}
#endif
