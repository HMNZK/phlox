import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore

/// セッション詳細画面（カンプ③）。承認リクエスト + ターミナル出力 + 入力バー。
public struct SessionDetailView: View {
    /// task-6 契約（凍結・PM 著）: 入力バー付近にモデル選択チップ（現在モデルの表示名を表示し、
    /// タップでモデル選択シートを開く）を提供するとき true。実装と同時に反転する
    /// （flag だけの反転は虚偽報告として扱う）。
    public static let providesModelSelectorChip = true
    public static let providesScrollToDismissKeyboard = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sessionComposeDraft) private var sessionComposeDraft
    @State private var viewModel: SessionDetailViewModel
    @State private var distanceFromBottom: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var selectedSubAgentID: String?
    @State private var transcriptWindow = TranscriptWindow()
    @State private var pendingTranscriptScrollTarget: SessionDetailTranscriptScrollTarget?
    @State private var transcriptScrollGeneration = 0
    let approvalViewModel: ApprovalViewModel?
    let onDelete: () -> Void

    public init(
        viewModel: SessionDetailViewModel,
        approvalViewModel: ApprovalViewModel? = nil,
        onDelete: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.approvalViewModel = approvalViewModel
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.m) {
                            approvalSection
                            transcriptSection
                            if case .failed(let message) = viewModel.sendState {
                                DSResultBanner(message: message, isError: true)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            // 末尾アンカー: 新着メッセージ/出力で最下部へスクロールするため。
                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchorID)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: BottomAnchorMaxYKey.self,
                                            value: proxy.frame(in: .named(Self.scrollCoordinateSpace)).maxY
                                        )
                                    }
                                )
                        }
                        .padding(DSSpacing.l)
                        .padding(.top, DSTouch.minSize)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.sendState)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .coordinateSpace(name: Self.scrollCoordinateSpace)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollViewportHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .onPreferenceChange(BottomAnchorMaxYKey.self) { bottomMaxY in
                        distanceFromBottom = max(0, bottomMaxY - scrollViewportHeight)
                    }
                    .onPreferenceChange(ScrollViewportHeightKey.self) { height in
                        scrollViewportHeight = height
                    }
                    // メッセージ/出力が更新されたら、最下部付近にいる時だけ追従スクロール。
                    .onChange(of: viewModel.chatMessages) { scrollToBottomIfFollowing(proxy) }
                    .onChange(of: viewModel.outputText) { scrollToBottomIfFollowing(proxy) }
                    .onChange(of: viewModel.expandedMessageIDs) { _, _ in scrollToBottomIfFollowing(proxy) }
                    .onChange(of: pendingTranscriptScrollTarget) { _, target in
                        guard let target else { return }
                        pendingTranscriptScrollTarget = nil
                        let generation = transcriptScrollGeneration
                        Task { @MainActor in
                            guard generation == transcriptScrollGeneration else { return }
                            switch target {
                            case .anchor(let anchorID):
                                proxy.scrollTo(anchorID, anchor: .top)
                            case .bottom:
                                scrollToBottom(proxy)
                            }
                        }
                    }
                    .onChange(of: viewModel.session.id) { _, _ in
                        transcriptWindow.reset()
                        pendingTranscriptScrollTarget = nil
                        transcriptScrollGeneration += 1
                    }
                    .onAppear { scrollToBottom(proxy, animated: false) }
                }

                if viewModel.isInputBarEnabled || (viewModel.currentStatus == .running && viewModel.canInterrupt) {
                    inputBarSection
                }
            }
            .sheet(isPresented: $viewModel.isModelSheetPresented) {
                modelSelectorSheet
            }

            topBar
        }
        .background(DSColor.background)
        .accessibilityIdentifier(AccessibilityID.sessionDetail)
        .modifier(SessionDetailNavigationBarHiddenModifier())
        .alert("名前変更", isPresented: $viewModel.isRenamePresented) {
            TextField("セッション名", text: $viewModel.renameDraft)
            Button("キャンセル", role: .cancel) {
                viewModel.isRenamePresented = false
            }
            Button("変更") {
                Task { await viewModel.commitRename() }
            }
        }
        .task(id: viewModel.session.id) {
            await viewModel.startPolling(composeDraft: sessionComposeDraft)
        }
        .task(id: approvalViewModel?.sessionID) {
            await approvalViewModel?.load()
        }
        .navigationDestination(item: $selectedSubAgentID) { subAgentID in
            SubAgentDetailView(
                viewModel: viewModel.makeSubAgentDetailViewModel(subAgentID: subAgentID)
            )
        }
    }

    private var topBar: some View {
        ZStack {
            Text(viewModel.displayName)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DSTouch.minSize * 2)

            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DSFont.headline.weight(.semibold))
                        .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                }
                .accessibilityLabel("戻る")

                Spacer(minLength: 0)

                Menu {
                    Button("モデル変更") {
                        viewModel.isModelSheetPresented = true
                    }
                    Button("名前変更") {
                        viewModel.beginRename()
                    }
                    Button("削除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DSFont.headline.weight(.semibold))
                        .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                }
                .accessibilityLabel("セッションメニュー")
            }
            .foregroundStyle(DSColor.accent)
        }
        .frame(height: DSTouch.minSize)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var inputBarSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let usageLine = SessionDetailUsageFormat.line(for: viewModel.turnUsage) {
                Text(usageLine)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, DSSpacing.m)
            }

            DSInputBar(
                text: $viewModel.inputText,
                placeholder: SessionDetailCopy.inputPlaceholder,
                isLoading: viewModel.isSending,
                attachmentStrip: viewModel.attachmentItems.map {
                    DSAttachmentStripItem(id: $0.id, previewData: $0.previewData)
                },
                attachmentError: viewModel.attachmentError,
                contextLabel: viewModel.inputContextDisplayName,
                onAddAttachments: { viewModel.addAttachments($0) },
                onRemoveAttachment: { viewModel.removeAttachment(at: $0) },
                isRunning: viewModel.currentStatus == .running && viewModel.canInterrupt,
                onStop: {
                    Task { await viewModel.stop() }
                },
                modelSelector: {
                    if viewModel.showsModelSelectorChip,
                       let name = viewModel.selectedModelDisplayName {
                        modelSelectorChip(name: name)
                    }
                }
            ) {
                Task { await viewModel.sendMessage(composeDraft: sessionComposeDraft) }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.bottom, DSSpacing.m)
        }
    }

    private var modelSelectorSheet: some View {
        ModelPickerSheet(
            entries: viewModel.modelPickerEntries,
            selectedEntryID: viewModel.selectedModelPickerEntryID,
            onSelect: { entryID in
                viewModel.isModelSheetPresented = false
                Task { await viewModel.selectModelPickerEntry(entryID: entryID) }
            },
            onDismiss: { viewModel.isModelSheetPresented = false }
        )
        .presentationDetents([.medium, .large])
    }

    private func modelSelectorChip(name: String) -> some View {
        Button {
            viewModel.beginModelSelection()
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(name)
                    .font(DSFont.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(DSFont.footnote.weight(.semibold))
            }
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColor.fillSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("モデルを変更: \(name)")
    }

    @ViewBuilder
    private var approvalSection: some View {
        if case .awaitingApproval = viewModel.currentStatus, let approvalViewModel {
            ApprovalBarView(viewModel: approvalViewModel)
        }
    }

    /// エラー → バナー、構造化チャットあり → チャット、初回データ待ち → 接続表示、
    /// それ以外 → 従来のターミナル出力、の順で表示する。
    @ViewBuilder
    private var transcriptSection: some View {
        if let error = viewModel.loadError {
            DSResultBanner(message: error, isError: true)
        } else if viewModel.showsChat {
            chatSection
        } else if viewModel.showsInitialLoadingIndicator {
            DSConnectingIndicator(size: 96)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(320, scrollViewportHeight - DSTouch.minSize - DSSpacing.l * 2))
        } else {
            outputSection
        }
    }

    private var chatSection: some View {
        let slice = SessionDetailTranscriptSlice(
            messages: viewModel.visibleMessages,
            window: transcriptWindow
        )
        return VStack(alignment: .leading, spacing: DSSpacing.m) {
            if slice.hiddenCount > 0 {
                loadEarlierMessagesButton(hiddenCount: slice.hiddenCount)
            }
            ForEach(slice.visibleMessages) { message in
                chatRow(for: message)
                    .id(message.id)
            }
            if viewModel.isAgentWorking {
                DSThinkingIndicator(reasoningPreview: viewModel.thinkingPreview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadEarlierMessagesButton(hiddenCount: Int) -> some View {
        Button {
            let decision = SessionDetailTranscriptExpansionPolicy.expand(
                messages: viewModel.visibleMessages,
                window: transcriptWindow,
                scrollGeneration: transcriptScrollGeneration
            )
            transcriptWindow = decision.window
            transcriptScrollGeneration = decision.scrollGeneration
            pendingTranscriptScrollTarget = decision.scrollTarget
        } label: {
            Text("以前のメッセージを表示（残り \(hiddenCount) 件）")
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(DSColor.fillSubtle)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SessionDetail.loadEarlierMessages")
    }

    /// 1 メッセージの描画。user/agent はバブル、reasoning は v1 では agent 風バブル、
    /// command/fileChange はモノスペースカード、error はエラーバナー。
    @ViewBuilder
    private func chatRow(for message: ChatMessage) -> some View {
        let copyText = ChatMessageCopyText.copyText(for: message)
        switch message {
        case let .user(id, text):
            DSChatBubble(
                role: .user,
                message: text,
                attachmentImageCount: viewModel.attachmentImageCount(forMessageID: id),
                copyText: copyText
            )
        case let .agent(_, text):
            DSChatBubble(
                role: .agent,
                message: text,
                agentKind: viewModel.session.agent,
                copyText: copyText
            )
        case let .reasoning(id, text):
            chatRowWithCopy(copyText: copyText) {
                DSReasoningText(
                    text: text,
                    isExpanded: viewModel.isMessageExpanded(id),
                    onToggle: { viewModel.toggleMessageExpansion(id) }
                )
            }
        case let .subAgent(id, text):
            let linkedSubAgentID = viewModel.subAgentID(forMessageID: id)
            chatRowWithCopy(copyText: copyText) {
                DSSubAgentRow(
                    text: text,
                    isTappable: linkedSubAgentID != nil,
                    onTap: linkedSubAgentID.map { subAgentID in
                        { selectedSubAgentID = subAgentID }
                    }
                )
            }
        case let .command(id, command, output):
            chatRowWithCopy(copyText: copyText) {
                collapsibleMonospaceCard(
                    messageID: id,
                    title: command.map { "$ \($0)" } ?? "$",
                    preview: SessionDetailViewModel.collapsedMessagePreview(for: message),
                    body: output
                )
            }
        case let .fileChange(id, changes):
            chatRowWithCopy(copyText: copyText) {
                collapsibleMonospaceCard(
                    messageID: id,
                    title: "ファイル変更",
                    preview: SessionDetailViewModel.collapsedMessagePreview(for: message),
                    body: changes.map { "\($0.path)\n\($0.diff)" }.joined(separator: "\n\n")
                )
            }
        case let .error(_, message):
            chatRowWithCopy(copyText: copyText) {
                DSResultBanner(message: message, isError: true)
            }
        case let .userQuestion(_, _, questions, _, _):
            // task-4 が質問カード（選択肢ボタン・multiSelect・自由入力・回答送信）へ差し替える骨組み。
            chatRowWithCopy(copyText: copyText) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(questions, id: \.question) { question in
                        Text(question.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.question)
                    }
                }
            }
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

    private func collapsibleMonospaceCard(
        messageID: String,
        title: String,
        preview: String,
        body: String
    ) -> some View {
        let isExpanded = viewModel.isMessageExpanded(messageID)
        return VStack(alignment: .leading, spacing: DSSpacing.s) {
            Button {
                viewModel.toggleMessageExpansion(messageID)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSFont.footnote.weight(.bold))
                        .foregroundStyle(DSColor.campTextQuaternary)
                    if !isExpanded, !preview.isEmpty {
                        Text(preview)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.campTextQuaternary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded, !body.isEmpty {
                Text(body)
                    // 端末出力と同じく密度優先（caption=12pt・字間を詰める）。
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

    @ViewBuilder
    private var outputSection: some View {
        if !viewModel.outputText.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                outputSectionHeader

                if let displayed = SessionDetailMetrics.displayedOutput(
                    text: viewModel.outputText,
                    isExpanded: viewModel.isOutputExpanded
                ) {
                    // モバイル幅に収めるため長い行は折り返す（横スクロールしない）。
                    // ASCII テーブル等の整列は崩れるが、画面幅で読めることを優先する。
                    Text(displayed)
                        // 出力は情報密度優先: 小さめ(caption=12pt)・字間を詰める(CJK のワイド描画対策)。
                        .font(DSFont.campMonoCaption)
                        .tracking(-0.5)
                        .foregroundStyle(DSColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DSSpacing.m)
                }
            }
            .background(DSColor.campOutputBackground, in: outputCardShape)
            .clipShape(outputCardShape)
        }
    }

    private var outputSectionHeader: some View {
        Button {
            if outputNeedsToggle {
                viewModel.isOutputExpanded.toggle()
            }
        } label: {
            HStack(spacing: DSSpacing.s) {
                Text(SessionDetailCopy.outputSectionTitle)
                    .font(DSFont.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(DSColor.campTextQuaternary)

                Spacer(minLength: 0)

                if outputNeedsToggle {
                    Image(systemName: viewModel.isOutputExpanded ? "chevron.down" : "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.campTextQuaternary)
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .frame(minHeight: DSTouch.minSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!outputNeedsToggle)
        .accessibilityLabel(Text(SessionDetailCopy.outputSectionTitle))
        .accessibilityValue(Text(viewModel.isOutputExpanded ? "展開" : "折りたたみ"))
        .accessibilityHint(Text(outputNeedsToggle ? "タップで出力を表示切替" : ""))
    }

    private var outputNeedsToggle: Bool {
        SessionDetailMetrics.outputNeedsToggle(text: viewModel.outputText)
    }

    private var outputCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
    }

    private static let bottomAnchorID = "session-detail-bottom"
    private static let scrollCoordinateSpace = "session-detail-scroll"

    /// 末尾アンカーまでスクロールして最下部へ寄せる。初回は即時、更新時はアニメーション。
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// 最下部付近にいる時だけ追従スクロールする（上へ読み戻り中は引き戻さない）。
    private func scrollToBottomIfFollowing(_ proxy: ScrollViewProxy) {
        guard ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: distanceFromBottom) else { return }
        scrollToBottom(proxy)
    }
}

/// SessionDetailView が描画するメッセージ範囲。ViewModel の visibleMessages の意味は変えない。
struct SessionDetailTranscriptSlice {
    let visibleMessages: ArraySlice<ChatMessage>
    let hiddenCount: Int

    var expansionAnchorID: String? {
        hiddenCount > 0 ? visibleMessages.first?.id : nil
    }

    init(messages: [ChatMessage], window: TranscriptWindow) {
        let range = window.visibleRange(totalCount: messages.count)
        visibleMessages = messages[range.startIndex...]
        hiddenCount = range.hiddenCount
    }
}

enum SessionDetailTranscriptScrollTarget: Equatable {
    case anchor(String)
    case bottom
}

struct SessionDetailTranscriptExpansionDecision {
    let window: TranscriptWindow
    let scrollGeneration: Int
    let scrollTarget: SessionDetailTranscriptScrollTarget?
}

enum SessionDetailTranscriptExpansionPolicy {
    static func expand(
        messages: [ChatMessage],
        window: TranscriptWindow,
        scrollGeneration: Int
    ) -> SessionDetailTranscriptExpansionDecision {
        let anchorID = SessionDetailTranscriptSlice(
            messages: messages,
            window: window
        ).expansionAnchorID
        var expandedWindow = window
        expandedWindow.expand()

        return SessionDetailTranscriptExpansionDecision(
            window: expandedWindow,
            scrollGeneration: scrollGeneration + 1,
            scrollTarget: anchorID.map(SessionDetailTranscriptScrollTarget.anchor)
        )
    }
}

/// ターン usage の表示文言（テスト可能な契約）。
enum SessionDetailUsageFormat {
    static func line(for usage: TurnUsage?) -> String? {
        guard let usage else { return nil }
        var parts: [String] = []
        if let cost = usage.costUSD {
            parts.append(String(format: "$%.4f", cost))
        }
        if let used = usage.contextUsedTokens, let window = usage.contextWindowTokens, window > 0 {
            let percent = Int((Double(used) / Double(window) * 100).rounded())
            parts.append("コンテキスト \(percent)%")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct BottomAnchorMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SessionDetailNavigationBarHiddenModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(.hidden, for: .navigationBar)
        #else
        content
        #endif
    }
}

#if DEBUG
#Preview("Awaiting Approval") {
    NavigationStack {
        SessionDetailView(
            viewModel: SessionDetailViewModel(
                session: Session(
                    id: "s1",
                    name: "Rose",
                    agent: .claudeCode,
                    status: .awaitingApproval(prompt: "ControlServer.swift を削除して続行しますか？"),
                    subtitle: "承認待ち",
                    updatedAt: Date()
                ),
                api: StubPhloxAPI(
                    approvals: [
                        Approval(
                            id: "a1",
                            sessionID: "s1",
                            kind: .claudeCode,
                            prompt: "ControlServer.swift を削除して続行しますか？"
                        ),
                    ],
                    outputText: "› rm ControlServer.swift\n⏵ cascade: 3 descendants"
                )
            ),
            approvalViewModel: ApprovalViewModel(
                sessionID: "s1",
                agentKind: .claudeCode,
                api: StubPhloxAPI(
                    approvals: [
                        Approval(
                            id: "a1",
                            sessionID: "s1",
                            kind: .claudeCode,
                            prompt: "ControlServer.swift を削除して続行しますか？"
                        ),
                    ]
                )
            ),
            onDelete: {}
        )
    }
}
#endif
