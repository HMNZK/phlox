import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore
#if canImport(UIKit)
import UIKit
#endif

enum ChatRowKind: Equatable {
    case userBubble
    case agentBubble
    case reasoning
    case subAgent
    case commandCard
    case fileChangeCard
    case error
    case userQuestion
    case turnCost

    static func forMessage(_ message: ChatMessage) -> Self {
        switch message {
        case .user:
            .userBubble
        case .agent:
            .agentBubble
        case .reasoning:
            .reasoning
        case .subAgent:
            .subAgent
        case .command:
            .commandCard
        case .fileChange:
            .fileChangeCard
        case .error:
            .error
        case .userQuestion:
            .userQuestion
        case .turnCost:
            .turnCost
        }
    }
}

/// セッション詳細画面（カンプ③）。承認リクエスト + 会話 + 入力バー。
public struct SessionDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageViewModel) private var usageViewModel
    @State private var viewModel: SessionDetailViewModel
    @State private var distanceFromBottom: CGFloat = 0
    @State private var scrollFollowState = SessionDetailScrollFollowState()
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var transcriptWindow = TranscriptWindow()
    @State private var pendingTranscriptScrollTarget: SessionDetailTranscriptScrollTarget?
    @State private var transcriptScrollGeneration = 0
    @State private var partialSelectionMessageID: String?
    @State private var isKeyboardVisible = false
    #if os(iOS)
    @State private var renameSelection: TextSelection?
    #endif
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let scrollToBottomOnAppear: Bool
    let onDelete: () -> Void

    public init(
        viewModel: SessionDetailViewModel,
        scrollToBottomOnAppear: Bool = true,
        onDelete: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.scrollToBottomOnAppear = scrollToBottomOnAppear
        self.onDelete = onDelete
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if viewModel.session.isPTY {
                    EmptyView()
                } else if viewModel.isSessionMissing {
                    Color.clear
                } else {
                    renameFailureBanner
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: DSSpacing.m) {
                                    transcriptSection
                                    if !scrollsReplyWithTranscript {
                                        transcriptBottomAnchor
                                    }
                                }
                                .padding(DSSpacing.l)
                                if scrollsReplyWithTranscript {
                                    replyAreaContent(availableHeight: geometry.size.height)
                                        .fixedSize(horizontal: false, vertical: true)
                                    transcriptBottomAnchor
                                }
                            }
                            .frame(minHeight: scrollViewportHeight, alignment: .bottom)
                            .animation(reduceMotion ? nil : DSMotion.disclosure, value: viewModel.sendState)
                        }
                        .frame(maxHeight: .infinity)
                        .scrollDismissesKeyboard(.interactively)
                        .coordinateSpace(name: Self.scrollCoordinateSpace)
                        .background(IOSColor.bg.base)
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
                        .onChange(of: viewModel.chatMessages) {
                            if scrollToBottomOnAppear {
                                scrollToBottomForContentChange(proxy)
                            }
                        }
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
                        .onAppear {
                            if scrollToBottomOnAppear {
                                scrollToBottomForContentChange(proxy)
                            }
                        }
                    }
                    if !scrollsReplyWithTranscript {
                        replyAreaContent(availableHeight: geometry.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                transcriptStateOverlay(in: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isModelSheetPresented) {
            modelSelectorSheet
        }
        .background(IOSColor.bg.base.ignoresSafeArea())
        .accessibilityIdentifier(AccessibilityID.sessionDetail)
        .modifier(DSSessionNavigationChrome(
            title: viewModel.displayName,
            subtitle: navigationSubtitle
        ) { sessionMenu })
        .navigationStackHomeBackButton()
        .alert("名前を変更", isPresented: $viewModel.isRenamePresented) {
            #if os(iOS)
            TextField(text: $viewModel.renameDraft, selection: $renameSelection) {
                Text("セッション名")
            }
            #else
            TextField("セッション名", text: $viewModel.renameDraft)
            #endif
            Button("キャンセル", role: .cancel) {
                viewModel.isRenamePresented = false
            }
            Button("変更") {
                Task { await viewModel.commitRename() }
            }
        } message: {
            Text("一覧と詳細に出る名前です。")
        }
#if canImport(UIKit)
        .onChange(of: viewModel.renameError) { _, error in
            guard let error else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "名前を変更できませんでした。名前は “\(viewModel.displayName)” のままです。\(error)"
            )
        }
        .onChange(of: viewModel.loadError) { _, error in
            guard let error else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: viewModel.isSessionMissing
                    ? "このセッションは見つかりません。Mac 側で削除されたか、終了して片付けられました。一覧に戻って、ほかのセッションを開いてください。"
                    : "会話を読み込めませんでした。Mac から会話の内容を受け取れませんでした。\(error)"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
#endif
        .task(id: viewModel.session.id) {
            await viewModel.startPolling()
        }
        .task(id: shouldShowInputBar) {
            guard shouldShowInputBar else { return }
            await usageViewModel?.load()
        }
        .task(id: viewModel.session.id) {
            guard !viewModel.session.isPTY else { return }
            await viewModel.loadApprovals()
        }
    }

    private var presentation: SessionDetailPresentationState { viewModel.presentationState }

    @ViewBuilder
    private func transcriptStateOverlay(in geometry: GeometryProxy) -> some View {
        if viewModel.session.isPTY {
            Text("このセッションは iPhone では表示できません。Mac で開いてください")
                .font(DSFont.subheadline)
                .foregroundStyle(IOSColor.text.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .offset(y: stateTopOffset(in: geometry))
                .accessibilityElement(children: .combine)
        } else if viewModel.isSessionMissing {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("このセッションは見つかりません")
                    .font(DSFont.headline)
                Text("Mac 側で削除されたか、終了して片付けられました。")
                    .font(DSFont.subheadline)
                Text("一覧に戻って、ほかのセッションを開いてください。")
                    .font(DSFont.subheadline)
                Button("一覧に戻る") { dismiss() }
                    .font(DSFont.body)
                    .frame(minHeight: DSTouch.minSize)
                Text(viewModel.loadError ?? "HTTP 404")
                    .font(DSFont.sessionDetailTechnical)
                    .foregroundStyle(IOSColor.text.secondary)
            }
            .foregroundStyle(IOSColor.text.primary)
            .padding(DSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: stateTopOffset(in: geometry))
        } else {
            transcriptStateContent
                .frame(maxWidth: .infinity)
                .offset(y: stateTopOffset(in: geometry))
        }
    }

    @ViewBuilder
    private var transcriptStateContent: some View {
        switch presentation.transcript {
        case .loading:
            VStack(spacing: DSSpacing.m) {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(width: 30, height: 30)
                Text("会話を読み込んでいます…")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
            }
            .frame(maxWidth: .infinity)
        case .empty:
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(DSFont.sessionEmptyIcon)
                    .foregroundStyle(IOSColor.text.secondary)
                    .frame(width: 60, height: 60)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("まだ会話はありません")
                    .font(DSFont.title.weight(.bold))
                    .foregroundStyle(IOSColor.text.primary)
                    .padding(.top, 4)
                Text("このセッションにはまだメッセージがありません。下の入力欄から指示を送ると、ここに会話が表示されます。")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        case .fetchError:
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("会話を読み込めませんでした")
                    .font(DSFont.title.weight(.bold))
                    .foregroundStyle(IOSColor.status.error)
                Text("Mac から会話の内容を受け取れませんでした。3 秒ごとに読み込み直しています。続くときは一覧に戻って開き直してください。")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.loadError ?? "メッセージの取得に失敗しました")
                    .font(DSFont.sessionDetailTechnical)
                    .foregroundStyle(IOSColor.text.secondary)
                    .textSelection(.enabled)
            }
            .padding(DSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IOSColor.status.errorBackground, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("会話を読み込めませんでした。Mac から会話の内容を受け取れませんでした。3 秒ごとに読み込み直しています。続くときは一覧に戻って開き直してください。\(viewModel.loadError ?? "メッセージの取得に失敗しました")")
        case .unsupported, .messages:
            EmptyView()
        }
    }

    private func stateTopOffset(in geometry: GeometryProxy) -> CGFloat {
        let frame = geometry.frame(in: .global)
        let screenHeight = frame.maxY + geometry.safeAreaInsets.bottom
        return max(0, screenHeight * 0.34 - frame.minY)
    }

    private var navigationSubtitle: Text? {
        guard let state = presentation.displayState else { return nil }
        let stateLabel = Text(state.localizedLabel(locale: locale))
            .foregroundColor(navigationStatusColor)
        let agentLabel = Text(" · \(viewModel.session.agent.displayName)")
            .foregroundColor(IOSColor.text.secondary)
        return stateLabel + agentLabel
    }

    private var navigationStatusColor: Color {
        guard let state = presentation.displayState,
              let color = IOSStatusVocabulary.presentation(for: state).color else {
            return IOSColor.text.tertiary
        }
        return color
    }

    @ViewBuilder
    private var renameFailureBanner: some View {
        if let message = viewModel.renameError {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("名前を変更できませんでした")
                    .font(DSFont.subheadline.weight(.semibold))
                Text("名前は “\(viewModel.displayName)” のままです。")
                    .font(DSFont.subheadline)
                Text(message)
                    .font(DSFont.sessionDetailTechnical)
                    .textSelection(.enabled)
            }
            .foregroundStyle(IOSColor.status.error)
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IOSColor.status.errorBackground, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, DSSpacing.l)
            .padding(.top, DSSpacing.s)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("名前を変更できませんでした。名前は “\(viewModel.displayName)” のままです。\(message)")
        }
    }

    private var sessionMenu: some View {
        Menu {
            if presentation.allowsModelSelection {
                Button {
                    viewModel.isModelSheetPresented = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("モデル変更")
                        Text("現在: \(viewModel.selectedModelDisplayName ?? viewModel.modelSettings?.selectedModel ?? "未取得")")
                            .font(.caption)
                    }
                }
                Divider()
            }
            Button("名前変更") {
                viewModel.beginRename()
                #if os(iOS)
                let name = viewModel.renameDraft
                renameSelection = name.isEmpty ? nil : TextSelection(range: name.startIndex..<name.endIndex)
                #endif
            }
            Divider()
            Button("削除", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(DSFont.headline.weight(.semibold))
        }
        .accessibilityLabel("セッションメニュー")
    }

    private var inputBarSection: some View {
        VStack(spacing: 0) {
            DSInputBar(
                text: $viewModel.inputText,
                cursorUTF16: $viewModel.inputCursorUTF16,
                placeholder: SessionDetailCopy.inputPlaceholder(isAnsweringSelectionlessQuestion: pendingPlainQuestion != nil),
                isLoading: viewModel.isSending,
                attachmentStrip: viewModel.attachmentItems.map {
                    DSAttachmentStripItem(id: $0.id, number: $0.number, previewData: $0.previewData)
                },
                contextLabel: viewModel.inputContextDisplayName,
                onAddAttachments: { results in
                    Task { await viewModel.addAttachmentLoadResults(results) }
                },
                onRemoveAttachment: { viewModel.removeAttachment(at: $0) },
                onAttachmentLimitReached: { viewModel.attachmentLimitReached() },
                isRunning: viewModel.showsStopButton,
                onStop: {
                    Task { await viewModel.stop() }
                },
                model: inputModel,
                onSelectModel: { viewModel.beginModelSelection() },
                settings: inputBarSettings
            ) {
                submitInput()
            }
            .onChange(of: viewModel.inputText) { oldValue, newValue in
                viewModel.syncAttachmentsWithTextEdit(oldText: oldValue, newText: newValue)
            }
        }
    }

    private var transcriptBottomAnchor: some View {
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

    private var scrollsReplyWithTranscript: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    /// 送信失敗 → 承認 → 質問 → 入力欄の順で積む。
    private func replyAreaContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            if case .failed(let message) = viewModel.sendState,
               message != viewModel.attachmentError {
                if let presentation = viewModel.sendErrorPresentation {
                    catalogError(presentation)
                } else {
                    errorLine(message)
                }
            }
            if let settingsError = viewModel.settingsChangeError { errorLine(settingsError, maximumLines: nil) }
            if let attachmentError = viewModel.attachmentError {
                errorLine(attachmentError, maximumLines: dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            if let presentation = viewModel.replyApprovalPresentation ?? viewModel.approvalLoadPresentation {
                catalogError(presentation)
            } else if let approvalError = viewModel.replyApprovalError ?? viewModel.approvalLoadError {
                errorLine(approvalError)
            }
            if let result = viewModel.replyApprovalResult {
                ReplyApprovalCard(
                    approval: nil,
                    result: result,
                    index: 0,
                    count: 0,
                    isResponding: viewModel.isReplyApprovalResponding,
                    isKeyboardVisible: false,
                    onDecision: { _ in },
                    onPrevious: {},
                    onNext: {},
                    onShowNext: { Task { await viewModel.showNextAttention() } }
                )
                .padding(.horizontal, DSSpacing.m)
            } else if let approval = viewModel.currentReplyApproval {
                ReplyApprovalCard(
                    approval: approval,
                    result: nil,
                    index: viewModel.currentReplyApprovalPage,
                    count: viewModel.replyApprovals.count,
                    isResponding: viewModel.isReplyApprovalResponding,
                    isKeyboardVisible: isKeyboardVisible,
                    onDecision: { decision in Task { await viewModel.respond(to: approval, decision: decision) } },
                    onPrevious: { viewModel.moveReplyApproval(to: viewModel.replyApprovalIndex - 1) },
                    onNext: { viewModel.moveReplyApproval(to: viewModel.replyApprovalIndex + 1) },
                    onShowNext: { Task { await viewModel.showNextAttention() } },
                    initiallyShowsDiff: viewModel.replyApprovalDiffInitiallyExpanded,
                    maxContentHeight: min(360, max(60, availableHeight * 0.25))
                )
                .padding(.horizontal, DSSpacing.m)
            }

            ForEach(viewModel.replyApprovalResult == nil ? pendingQuestions : []) { question in
                if viewModel.questionAnswerFailureRequestID == question.requestId {
                    errorLine("回答を送信できませんでした。選んだ内容は残っています")
                }
                UserQuestionCard(
                    requestId: question.requestId,
                    questions: question.questions,
                    answers: question.answers,
                    state: question.state,
                    usesInputBarForFreeText: question.usesInputBarForFreeText,
                    maxContentHeight: min(360, max(60, availableHeight * 0.25)),
                    onSubmit: { requestId, answers in
                        await viewModel.answerQuestion(requestId: requestId, answers: answers)
                    }
                )
                .padding(.horizontal, DSSpacing.m)
                .id(question.id)
            }

            if presentation.showsStartingBanner {
                HStack(spacing: DSSpacing.s) {
                    ProgressView()
                    Text("セッションを起動しています。準備ができると入力できます")
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.m)
                    .background(DSColor.fillSubtle, in: Capsule())
                    .padding(.horizontal, 12)
            } else if shouldShowInputBar {
                inputBarSection
                if presentation.showsUsage, let usageViewModel, usageViewModel.shouldShowRow {
                    UsageRingRow(viewModel: usageViewModel)
                        .padding(.horizontal, DSSpacing.xl)
                }
            }
        }
        .padding(.top, DSSpacing.s)
        .padding(.bottom, DSSpacing.m)
    }

    private func errorLine(_ message: String, maximumLines: Int? = 1) -> some View {
        Text(message)
            .font(DSFont.inputBar(.error, for: dynamicTypeSize).weight(.semibold))
            .foregroundStyle(IOSColor.status.error)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : maximumLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .accessibilityAddTraits(.isStaticText)
    }

    private func catalogError(_ presentation: ErrorPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(presentation.title)
                .font(DSFont.iosCaption2.weight(.medium))
                .foregroundStyle(presentation.isNeutral ? IOSColor.text.primary : IOSColor.status.error)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.cause)
                .font(DSFont.iosCaption2)
                .foregroundStyle(IOSColor.text.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.nextStep.isEmpty {
                Text(presentation.nextStep)
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let technicalDetail = presentation.technicalDetail {
                Text(technicalDetail)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var shouldShowInputBar: Bool {
        presentation.showsInputBar
    }

    private struct PendingQuestion: Identifiable {
        let id: String
        let requestId: String
        let questions: [UserQuestionItem]
        let answers: [String: [String]]?
        let state: UserQuestionState

        var usesInputBarForFreeText: Bool {
            state == .pending && questions.count == 1 && questions.first?.options.isEmpty == true
        }
    }

    private var pendingQuestions: [PendingQuestion] {
        viewModel.visibleMessages.compactMap { message in
            guard case let .userQuestion(id, requestId, questions, answers, state) = message,
                  state == .pending else { return nil }
            let visibleQuestions = viewModel.session.agent == .claudeCode
                && ReplyApproval.isClaudeToolPermissionQuestion(questions)
                ? []
                : questions
            guard !visibleQuestions.isEmpty else { return nil }
            return PendingQuestion(id: id, requestId: requestId, questions: visibleQuestions, answers: answers, state: state)
        }
    }

    private var pendingPlainQuestion: PendingQuestion? {
        guard viewModel.replyApprovalResult == nil else { return nil }
        return pendingQuestions.first(where: \.usesInputBarForFreeText)
    }

    private var transcriptMessages: [ChatMessage] {
        SessionDetailTranscriptPresentation.messagesForTranscript(viewModel.visibleMessages)
    }

    private var visibleTranscriptMessages: [ChatMessage] {
        SessionDetailTranscriptPresentation.visibleTranscriptRows(transcriptMessages)
    }

    private var inputModel: (kind: AgentKind, displayName: String)? {
        guard viewModel.showsModelSelectorChip,
              let displayName = viewModel.selectedModelDisplayName else { return nil }
        return (viewModel.session.agent, displayName)
    }

    private var inputBarSettings: DSInputBarSettings? {
        guard let settings = viewModel.modelSettings else { return nil }
        return DSInputBarSettings(
            agentName: viewModel.session.agent.displayName,
            effortOptions: settings.availableEfforts.map {
                DSInputBarSettingOption(value: $0.value, displayName: $0.displayName)
            },
            selectedEffort: settings.selectedEffort,
            permissionOptions: settings.availablePermissions.map {
                DSInputBarSettingOption(value: $0.value, displayName: $0.displayName)
            },
            selectedPermission: settings.selectedPermission,
            planMode: settings.planMode,
            planModeAvailable: settings.planModeAvailable,
            isUpdatingEffort: viewModel.settingsChangeInFlight == .effort,
            isUpdatingPermission: viewModel.settingsChangeInFlight == .permission,
            isUpdatingPlanMode: viewModel.settingsChangeInFlight == .planMode,
            onSelectEffort: { value in Task { await viewModel.selectEffort(value) } },
            onSelectPermission: { value in Task { await viewModel.selectPermission(value) } },
            onSelectPlanMode: { value in Task { await viewModel.selectPlanMode(value) } }
        )
    }

    private func submitInput() {
        if let question = pendingPlainQuestion {
            let answer = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return }
            Task {
                if await viewModel.answerQuestion(
                    requestId: question.requestId,
                    answers: [question.questions[0].question: [answer]]
                ) {
                    viewModel.inputText = ""
                }
            }
        } else {
            Task { await viewModel.sendMessage() }
        }
    }

    private var modelSelectorSheet: some View {
        ModelPickerSheet(
            entries: viewModel.modelPickerEntries,
            selectedEntryID: viewModel.selectedModelPickerEntryID,
            agentName: viewModel.session.agent.displayName,
            defaultEntryID: viewModel.defaultModelPickerEntryID,
            isChangingModelID: viewModel.modelSelectionInFlightID,
            failureMessage: viewModel.modelSelectionError,
            onSelect: { entryID in
                Task { await viewModel.selectModelPickerEntry(entryID: entryID) }
            },
            onDismiss: { viewModel.isModelSheetPresented = false }
        )
        .presentationDetents([.height(680)])
        .presentationDragIndicator(.visible)
    }

    /// 表示用の状態値に従って本文を描画する。
    @ViewBuilder
    private var transcriptSection: some View {
        switch presentation.transcript {
        case .unsupported, .loading, .empty, .fetchError:
            EmptyView()
        case .messages:
            chatSection
        }
    }

    private var chatSection: some View {
        let slice = SessionDetailTranscriptSlice(
            messages: visibleTranscriptMessages,
            window: transcriptWindow
        )
        let lastTranscriptID = visibleTranscriptMessages.last?.id
        let latestTurnCostID = SessionDetailTranscriptPresentation.latestTurnCostID(in: transcriptMessages)
        return VStack(alignment: .leading, spacing: 14) {
            if slice.hiddenCount > 0 {
                loadEarlierMessagesButton(hiddenCount: slice.hiddenCount)
            }
            ForEach(slice.visibleBlocks) { visibleBlock in
                chatBlock(
                    visibleBlock.content,
                    lastTranscriptID: lastTranscriptID,
                    latestTurnCostID: latestTurnCostID
                )
                .id(visibleBlock.id)
            }
            if viewModel.session.isStalled {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let startedAt = viewModel.session.statusEnteredAt ?? context.date
                    stalledStatusRow(elapsed: context.date.timeIntervalSince(startedAt))
                }
            } else if let activityState = viewModel.activityState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    DSThinkingIndicator(
                        state: activityState,
                        reasoningPreview: viewModel.recap(now: context.date)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stalledStatusRow(elapsed: TimeInterval) -> some View {
        HStack(spacing: 10) {
            (Text("無応答 ") + Text(SessionDetailPresentationState.elapsedClock(elapsed))
                .font(DSFont.subheadline.monospaced().weight(.semibold)))
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(IOSColor.status.stalled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.stop() }
            } label: {
                Text("中断")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(IOSColor.text.primary)
                    .padding(.horizontal, 18)
                    .frame(minHeight: DSTouch.minSize)
                    .background(IOSColor.bg.fill, in: Capsule())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("中断（実行を止める）")
        }
        .padding(.vertical, 6)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .background(IOSColor.status.stalledBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .font(DSFont.subheadline.weight(.medium))
                .foregroundStyle(IOSColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.s)
                .frame(minHeight: DSTouch.minSize)
                .background(IOSColor.bg.fill, in: Capsule())
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityIdentifier("SessionDetail.loadEarlierMessages")
    }

    @ViewBuilder
    private func chatBlock(
        _ block: SessionDetailChatBlock,
        lastTranscriptID: String?,
        latestTurnCostID: String?
    ) -> some View {
        switch block {
        case .single(let message):
            chatRow(for: message, lastTranscriptID: lastTranscriptID, latestTurnCostID: latestTurnCostID)
        case .commandGroup(let id, let items):
            chatRowWithCopy(
                messageID: id,
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

    /// 1 メッセージの描画。
    @ViewBuilder
    private func chatRow(
        for message: ChatMessage,
        lastTranscriptID: String?,
        latestTurnCostID: String?
    ) -> some View {
        let copyText = ChatMessageCopyText.copyText(for: message)
        switch ChatRowKind.forMessage(message) {
        case .userBubble:
            if case let .user(id, text, createdAt) = message {
                chatRowWithCopy(
                    messageID: id,
                    copyText: copyText,
                    menuTitle: ChatMessageCopyText.contextMenuTitle(createdAt: createdAt)
                ) {
                    SessionDetailUserMessageBubble(
                        text: text,
                        attachmentPreviews: viewModel.attachmentPreviews(forMessageID: id)
                    )
                }
            }
        case .agentBubble:
            if case let .agent(id, text, createdAt) = message {
                chatRowWithCopy(
                    messageID: id,
                    copyText: copyText,
                    menuTitle: ChatMessageCopyText.contextMenuTitle(createdAt: createdAt)
                ) {
                    DSMarkdownText(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .reasoning:
            if case let .reasoning(id, text) = message {
                chatRowWithCopy(messageID: id, copyText: copyText) {
                    DSReasoningText(
                        text: text,
                        isExpanded: viewModel.isMessageExpanded(id),
                        onToggle: { viewModel.toggleMessageExpansion(id) }
                    )
                }
            }
        case .subAgent:
            if case let .subAgent(_, text) = message {
                SessionDetailSubAgentCard(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .commandCard:
            if case let .command(id, command, output) = message {
                chatRowWithCopy(messageID: id, copyText: copyText) {
                    SessionDetailCommandCard(
                        command: command,
                        output: output,
                        isExpanded: viewModel.isMessageExpanded(id),
                        isRunning: viewModel.isAgentWorking && id == lastTranscriptID,
                        onToggle: { viewModel.toggleMessageExpansion(id) }
                    )
                }
            }
        case .fileChangeCard:
            if case let .fileChange(id, changes) = message {
                chatRowWithCopy(
                    messageID: id,
                    copyText: copyText
                ) {
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                            let itemID = "\(id)-file-\(index)"
                            SessionDetailFileChangeCard(
                                change: change,
                                isExpanded: viewModel.isMessageExpanded(itemID),
                                onToggle: { viewModel.toggleMessageExpansion(itemID) }
                            )
                        }
                    }
                }
            }
        case .error:
            if case let .error(id, message) = message {
                chatRowWithCopy(messageID: id, copyText: copyText) {
                    SessionDetailErrorCard(message: message)
                }
            }
        case .userQuestion:
            if case let .userQuestion(id, _, questions, answers, state) = message {
                chatRowWithCopy(messageID: id, copyText: copyText) {
                    SessionDetailAnsweredQuestionCard(
                        questions: questions,
                        answers: answers,
                        state: state,
                        isExpanded: viewModel.isMessageExpanded(id),
                        onToggle: { viewModel.toggleMessageExpansion(id) }
                    )
                }
            }
        case .turnCost:
            if case let .turnCost(id, costUSD) = message,
               let line = SessionDetailUsageFormat.line(
                costUSD: costUSD,
                for: id == latestTurnCostID ? viewModel.turnUsage : nil,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
               ) {
                Text(line)
                    .font(DSFont.sessionDetailUsage)
                    .foregroundStyle(IOSColor.text.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier(id == latestTurnCostID ? "SessionDetailTurnUsage" : "SessionDetailTurnCost")
            }
        }
    }

    /// コピーは行ごとのボタンではなく長押しメニューで出す（バブルと同じ作法）。
    /// 全行にボタンを常設すると転写が読めなくなるため。
    private func chatRowWithCopy<Content: View>(
        messageID: String,
        copyText: String?,
        menuTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .chatMessageCopyContextMenu(
                copyText: copyText,
                menuTitle: menuTitle,
                partialSelectionEnabled: partialSelectionMessageID == messageID,
                onPartialSelection: { partialSelectionMessageID = messageID }
            )
    }

    private func chatRowWithCopy<Content: View>(
        messageID: String,
        hasCopyableText: Bool,
        copyTextProvider: @escaping () -> String?,
        menuTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .chatMessageCopyContextMenu(
                hasCopyableText: hasCopyableText,
                deferredCopyText: ChatMessageDeferredCopyText(copyTextProvider),
                menuTitle: menuTitle,
                partialSelectionEnabled: partialSelectionMessageID == messageID,
                onPartialSelection: { partialSelectionMessageID = messageID }
            )
    }

    private static let bottomAnchorID = "session-detail-bottom"
    private static let scrollCoordinateSpace = "session-detail-scroll"

    /// 末尾アンカーまでスクロールして最下部へ寄せる。初回は即時、更新時はアニメーション。
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated && !reduceMotion {
            withAnimation(DSMotion.followNewContent) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// 本文が最初に届いたときだけ距離を無視して最下部へ寄せる。
    private func scrollToBottomForContentChange(_ proxy: ScrollViewProxy) {
        let shouldAnimate = Self.shouldAnimateScroll(
            hasPerformedInitialScroll: scrollFollowState.hasPerformedInitialScroll,
            reduceMotion: reduceMotion
        )
        let hasContent = Self.hasRenderableContent(
            visibleMessages: viewModel.visibleMessages
        )
        guard scrollFollowState.onContentChanged(
            hasContent: hasContent,
            distanceFromBottom: distanceFromBottom
        ) else { return }
        scrollToBottom(proxy, animated: shouldAnimate)
    }

    /// 初回スクロールのトリガーとなる、実際に画面へ描画できる本文があるか。
    static func hasRenderableContent(visibleMessages: [ChatMessage]) -> Bool {
        !visibleMessages.isEmpty
    }

    /// 初回だけ位置を即時に確定し、以後の追従だけをアニメーションするか。
    static func shouldAnimateScroll(hasPerformedInitialScroll: Bool, reduceMotion: Bool = false) -> Bool {
        hasPerformedInitialScroll && !reduceMotion
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
        line(costUSD: nil, for: usage)
    }

    static func line(costUSD: Double?, for usage: TurnUsage?, isAccessibilitySize: Bool = false) -> String? {
        SessionDetailTranscriptPresentation.turnUsageLine(costUSD: costUSD, usage: usage, isAccessibilitySize: isAccessibilitySize)
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
