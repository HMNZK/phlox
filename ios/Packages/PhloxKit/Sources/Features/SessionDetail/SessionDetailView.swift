import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore
import TerminalScreenIOS

/// セッション詳細画面（カンプ③）。承認リクエスト + ターミナル出力 + 入力バー。
public struct SessionDetailView: View {
    /// task-6 契約（凍結・PM 著）: 入力バー付近にモデル選択チップ（現在モデルの表示名を表示し、
    /// タップでモデル選択シートを開く）を提供するとき true。実装と同時に反転する
    /// （flag だけの反転は虚偽報告として扱う）。
    public static let providesModelSelectorChip = true
    public static let providesScrollToDismissKeyboard = true
    /// task-1 契約（凍結・PM 著）: 左端からのスワイプで前の画面へ戻れるとき true。
    /// システムのナビゲーションバーを使うことで iOS 標準の端スワイプをそのまま成立させる（ADR 0033）。
    /// 実装と同時に反転する（flag だけの反転は虚偽報告として扱う）。
    public static let providesBackSwipeGesture = true
    /// task-1 契約（凍結・PM 著）: ターミナル出力を桁揃えのまま横スクロールで読ませるとき true。
    /// 実装と同時に反転する（flag だけの反転は虚偽報告として扱う）。
    public static let providesTerminalOutputHorizontalScroll = true

    @Environment(\.sessionComposeDraft) private var sessionComposeDraft
    @State private var viewModel: SessionDetailViewModel
    @State private var distanceFromBottom: CGFloat = 0
    @State private var scrollFollowState = SessionDetailScrollFollowState()
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
                // 本文が初めて届いたときは必ず最下部へ寄せ、以降だけ距離で追従を判定する。
                .onChange(of: viewModel.chatMessages) { scrollToBottomForContentChange(proxy) }
                .onChange(of: viewModel.outputText) { scrollToBottomForContentChange(proxy) }
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
                    scrollFollowState.reset()
                }
                .onAppear { scrollToBottomForContentChange(proxy) }
            }

            if viewModel.isInputBarEnabled || (viewModel.currentStatus == .running && viewModel.canInterrupt) {
                inputBarSection
            }
        }
        .sheet(isPresented: $viewModel.isModelSheetPresented) {
            modelSelectorSheet
        }
        .background(DSColor.background)
        .accessibilityIdentifier(AccessibilityID.sessionDetail)
        .modifier(SessionDetailNavigationChromeModifier(title: viewModel.displayName) { sessionMenu })
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

    private var sessionMenu: some View {
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
                cursorUTF16: $viewModel.inputCursorUTF16,
                placeholder: SessionDetailCopy.inputPlaceholder,
                isLoading: viewModel.isSending,
                attachmentStrip: viewModel.attachmentItems.map {
                    DSAttachmentStripItem(id: $0.id, number: $0.number, previewData: $0.previewData)
                },
                attachmentError: viewModel.attachmentError,
                contextLabel: viewModel.inputContextDisplayName,
                onAddAttachments: { viewModel.addAttachments($0) },
                onRemoveAttachment: { viewModel.removeAttachment(at: $0) },
                isRunning: viewModel.showsStopButton,
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
            .onChange(of: viewModel.inputText) { oldValue, newValue in
                viewModel.syncAttachmentsWithTextEdit(oldText: oldValue, newText: newValue)
            }
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
        let lastTranscriptID = viewModel.visibleMessages.last?.id
        return VStack(alignment: .leading, spacing: DSSpacing.m) {
            if slice.hiddenCount > 0 {
                loadEarlierMessagesButton(hiddenCount: slice.hiddenCount)
            }
            ForEach(slice.visibleBlocks) { visibleBlock in
                chatBlock(
                    visibleBlock.content,
                    lastTranscriptID: lastTranscriptID
                )
                .id(visibleBlock.id)
            }
            if viewModel.isAgentWorking {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    DSThinkingIndicator(reasoningPreview: viewModel.recap(now: context.date))
                }
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

    @ViewBuilder
    private func chatBlock(
        _ block: SessionDetailChatBlock,
        lastTranscriptID: String?
    ) -> some View {
        switch block {
        case .single(let message):
            chatRow(for: message)
        case .commandGroup(let id, let items):
            chatRowWithCopy(
                hasCopyableText: ChatMessageCopyText.commandGroupHasCopyableText(items),
                copyTextProvider: { ChatMessageCopyText.commandGroupCopyText(items) }
            ) {
                SessionDetailToolCallGroupRow(
                    items: items,
                    lastTranscriptID: lastTranscriptID,
                    isTurnRunning: viewModel.isAgentWorking,
                    isExpanded: viewModel.isMessageExpanded(id),
                    isMessageExpanded: viewModel.isMessageExpanded,
                    onToggleGroup: { viewModel.toggleMessageExpansion(id) },
                    onToggleMessage: { viewModel.toggleMessageExpansion($0) }
                )
            }
        }
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
        case let .userQuestion(_, requestId, questions, answers, state):
            chatRowWithCopy(copyText: copyText) {
                UserQuestionCard(
                    requestId: requestId,
                    questions: questions,
                    answers: answers,
                    state: state,
                    onSubmit: { requestId, answers in
                        await viewModel.answerQuestion(requestId: requestId, answers: answers)
                    }
                )
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

    @ViewBuilder
    private func chatRowWithCopy<Content: View>(
        hasCopyableText: Bool,
        copyTextProvider: @escaping () -> String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            if hasCopyableText {
                ChatMessageCopyButton(textProvider: copyTextProvider)
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
        if viewModel.terminalScreen.isANSI, !viewModel.outputText.isEmpty {
            // Mac が色つきの画面を配信できたときは端末として描き直す。
            // 端末は「今の画面」そのものなので、見出しにもトグルにも入れず全文をそのまま出す。
            // 幅は TerminalScreenView が画面に合わせて詰めるので、横スクロールは要らない。
            // 桁を1桁でも多く見せたいので、本文の左右余白ぶんだけ外へ広げて画面端まで使う。
            TerminalScreenView(screen: viewModel.terminalScreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, -DSSpacing.l)
        } else if !viewModel.outputText.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                outputSectionHeader

                if let displayed = SessionDetailMetrics.displayedOutput(
                    text: viewModel.outputText,
                    isExpanded: viewModel.isOutputExpanded
                ) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        SessionDetailOutputBody(text: displayed)
                    }
                    // 横スクロールしてもカード内の余白を保つ。縦余白は末尾を角丸と
                    // スクロールバーから離し、左右余白は本文・ヘッダの桁を揃える。
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.m)
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

    /// 本文が最初に届いたときだけ距離を無視して最下部へ寄せる。
    private func scrollToBottomForContentChange(_ proxy: ScrollViewProxy) {
        let shouldAnimate = Self.shouldAnimateScroll(
            hasPerformedInitialScroll: scrollFollowState.hasPerformedInitialScroll
        )
        let hasContent = Self.hasRenderableContent(
            visibleMessages: viewModel.visibleMessages,
            outputText: viewModel.outputText
        )
        guard scrollFollowState.onContentChanged(
            hasContent: hasContent,
            distanceFromBottom: distanceFromBottom
        ) else { return }
        scrollToBottom(proxy, animated: shouldAnimate)
    }

    /// 初回スクロールのトリガーとなる、実際に画面へ描画できる本文があるか。
    static func hasRenderableContent(visibleMessages: [ChatMessage], outputText: String) -> Bool {
        !visibleMessages.isEmpty || !outputText.isEmpty
    }

    /// 初回だけ位置を即時に確定し、以後の追従だけをアニメーションするか。
    static func shouldAnimateScroll(hasPerformedInitialScroll: Bool) -> Bool {
        hasPerformedInitialScroll
    }

    /// 最下部付近にいる時だけ追従スクロールする（上へ読み戻り中は引き戻さない）。
    private func scrollToBottomIfFollowing(_ proxy: ScrollViewProxy) {
        guard ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: distanceFromBottom) else { return }
        scrollToBottom(proxy)
    }
}

/// ターミナル出力の等幅テキスト本体。横 ScrollView 内で、外側の縦 ScrollView からは
/// 幅固定・高さ未指定で測られる。
struct SessionDetailOutputBody: View {
    let text: String

    var body: some View {
        Text(text)
            // 出力は情報密度優先: 小さめ(caption=12pt)・字間を詰める(CJK のワイド描画対策)。
            .font(DSFont.campMonoCaption)
            .tracking(-0.5)
            .foregroundStyle(DSColor.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
    }
}

/// SessionDetailView が描画するメッセージ範囲。ViewModel の visibleMessages の意味は変えない。
struct SessionDetailTranscriptSlice {
    let visibleMessages: ArraySlice<ChatMessage>
    let visibleBlocks: [SessionDetailVisibleBlock]
    let hiddenCount: Int

    var expansionAnchorID: String? {
        hiddenCount > 0 ? visibleBlocks.first?.id : nil
    }

    init(messages: [ChatMessage], window: TranscriptWindow) {
        let blockSlice = SessionDetailToolCallGrouping.visibleSlice(
            from: messages,
            blockLimit: window.limit
        )
        visibleBlocks = blockSlice.blocks
        hiddenCount = blockSlice.hiddenBlockCount

        let visibleMessageCount = visibleBlocks.reduce(0) { total, visible in
            switch visible.content {
            case .single:
                total + 1
            case .commandGroup(_, let items):
                total + items.count
            }
        }
        visibleMessages = messages.suffix(visibleMessageCount)
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

/// セッション詳細の chrome。システムのナビゲーションバーへタイトル・戻る・メニューを載せる。
///
/// バーを隠して自前のヘッダを描く構成は使わない。隠すと UIKit が端スワイプ pop を拒否し、
/// ジェスチャの delegate を差し替えて無理に通すと、pop 後に一覧の大タイトルが失われる（ADR 0033）。
private struct SessionDetailNavigationChromeModifier<Menu: View>: ViewModifier {
    let title: String
    @ViewBuilder var menu: () -> Menu

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // 戻るボタンはシステムのものを使う（自前の leading 項目に差し替えると端スワイプ pop が拒否される）。
            // editor ロールは戻るラベルを落として従来と同じ「‹」だけの見た目にする。
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu() }
            }
        #else
        content.navigationTitle(title)
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
