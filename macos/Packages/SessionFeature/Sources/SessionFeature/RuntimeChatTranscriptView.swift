import SwiftUI
import AgentDomain
import DesignSystem

struct RuntimeChatTranscriptView: View {
    @Bindable var viewModel: ChatSessionViewModel
    @Binding var requestedScrollTarget: String?
    @Binding var currentInputPositionID: String?
    let contentMaxWidth: CGFloat?
    let bottomMargin: CGFloat
    let context: TranscriptPresentationContext
    let showsThinkingIndicator: Bool
    let itemActions: RuntimeChatItemActions
    @State private var autoFollow = ChatAutoFollowController()
    @State private var detached = false
    @State private var jumpGeneration = 0
    @State private var loadingEdge: VerticalEdge?
    @State private var offsets: [String: CGFloat] = [:]
    @State private var window: TranscriptWindow
    @State private var revealRequest: SessionRuntimeChatReadRevealTarget?
    @State private var renderOwner = UUID()
    @State private var pendingJump: RuntimeChatPendingJump?

    init(viewModel: ChatSessionViewModel, requestedScrollTarget: Binding<String?>,
         currentInputPositionID: Binding<String?>, contentMaxWidth: CGFloat?, bottomMargin: CGFloat,
         context: TranscriptPresentationContext, showsThinkingIndicator: Bool,
         itemActions: RuntimeChatItemActions) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _requestedScrollTarget = requestedScrollTarget
        _currentInputPositionID = currentInputPositionID
        self.contentMaxWidth = contentMaxWidth
        self.bottomMargin = bottomMargin
        self.context = context
        self.showsThinkingIndicator = showsThinkingIndicator
        self.itemActions = itemActions
        _window = State(initialValue: TranscriptWindow(context: context))
    }

    private var page: SessionRuntimeChatReadPage? { viewModel.runtimeChatRead.page }
    private var blocks: [SessionRuntimeChatReadBlock] { page?.blocks ?? [] }
    private var slice: RuntimeChatReadSlice {
        let renderingWindow = pendingJump?.windowForRender(window, projection: viewModel.runtimeChatRead) ?? window
        return renderingWindow.slice(of: blocks)
    }
    private var visibleBlocks: [SessionRuntimeChatReadBlock] { slice.blocks }
    /// 窓・cursor・位置の計算は受信したブロック全体で行い、描画だけから表示しない思考を除く（空の間隔を作らない）。
    private var renderedBlocks: [SessionRuntimeChatReadBlock] {
        let agent = viewModel.agentRef.builtinKind
        return visibleBlocks.filter { !$0.isHiddenReasoning(agent: agent) }
    }

    var body: some View {
        let control = viewModel.runtimeChatRead.control
        let renderedSpan = visibleBlocks.first.flatMap { first in
            visibleBlocks.last.map { last in
                RuntimeChatRenderedSpan(executionID: viewModel.executionID, epoch: viewModel.runtimeChatRead.epoch,
                    intentToken: viewModel.runtimeChatRead.appliedIntentToken, firstID: first.id, lastID: last.id,
                    count: visibleBlocks.count)
            }
        }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: TranscriptTypography.itemGap) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(renderedBlocks.enumerated()), id: \.element.id) { index, block in
                            blockView(block)
                                .padding(.top, index == 0 ? 0 : TranscriptTypography.itemGap)
                                .id(block.id)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: RuntimeChatBlockOffsets.self,
                                            value: [block.id: geometry.frame(in: .named("runtime-chat-content")).minY])
                                    }
                                }
                        }
                    }
                    if let error = viewModel.runtimeChatRead.error {
                        Text(error).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                        Button("再試行") { Task { try? await viewModel.refreshRuntimeChatRead() } }
                    }
                    if page?.newerCursor == nil, slice.hiddenNewerBlockCount == 0 {
                        CodexSessionSurface(viewModel: viewModel)
                        if viewModel.shouldShowConnectingIndicator { ConnectingIndicatorRow() }
                        if viewModel.isCompacting {
                            CompactingIndicatorCell(descriptor: AgentRegistry.descriptor(for: viewModel.agentRef.builtinKind))
                        }
                        if let activity = viewModel.activityState,
                           CompactingIndicatorPresentation.shouldShowThinkingIndicator(
                               showsThinkingIndicator: showsThinkingIndicator,
                               showsProcessingIndicator: viewModel.showsProcessingIndicator,
                               isCompacting: viewModel.isCompacting, isAwaitingUser: activity == .waiting,
                               usesStatusCard: AgentStatusCardRouting.usesStatusCard(viewModel.agentRef.builtinKind)) {
                            ThinkingIndicatorCell(descriptor: AgentRegistry.descriptor(for: viewModel.agentRef.builtinKind),
                                state: activity, hangAssessment: { viewModel.hangAssessment(now: $0) },
                                recap: { viewModel.thinkingRecap(now: $0) }, onInterrupt: { await viewModel.turnInterrupt() })
                        }
                    }
                    Color.clear.frame(height: max(1, bottomMargin)).id("chat-bottom")
                }
                .padding(.horizontal, TranscriptTypography.transcriptHorizontalInset)
                .padding(.vertical, TranscriptTypography.transcriptVerticalInset)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .coordinateSpace(.named("runtime-chat-content"))
                .background {
                    ChatAutoFollowScrollObserver(controller: autoFollow,
                        onViewportCenterChanged: updatePosition,
                        onDetachedChanged: { detached = $0 },
                        onScrollPastTop: { beginLoading(.top) },
                        onScrollPastBottom: { beginLoading(.bottom) },
                        onScrollAwayFromEdge: { loadingEdge = nil },
                        onScrollReleased: { finishLoading(proxy) },
                        hasNewerHidden: canLoad(.bottom))
                        .id(viewModel.executionID)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("チャット履歴")
                .accessibilityIdentifier("ChatTranscript.history")
                .accessibilityAction(named: Text("以前のメッセージを読み込む")) {
                    beginLoading(.top)
                    finishLoading(proxy)
                }
                .accessibilityAction(named: Text("以後のメッセージを読み込む")) {
                    beginLoading(.bottom)
                    finishLoading(proxy)
                }
            }
            .onPreferenceChange(RuntimeChatBlockOffsets.self) { offsets = $0 }
            .overlay(alignment: .top) {
                if loadingEdge == .top || (loadingEdge == nil && viewModel.runtimeChatRead.isLoading) {
                    CometLoader().padding(12).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if loadingEdge == .bottom {
                    CometLoader(label: "以後のメッセージを読み込み中")
                        .padding(.bottom, bottomMargin + 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if detached || page?.newerCursor != nil || slice.hiddenNewerBlockCount > 0 {
                    JumpToLatestButton(unseenCount: 0) { latest(proxy) }
                        .padding(.bottom, bottomMargin + DSSpacing.m)
                }
            }
            .onChange(of: requestedScrollTarget) { _, target in
                guard let target else { return }
                requestedScrollTarget = nil
                jump(target, proxy: proxy)
            }
            .onChange(of: page?.transcriptRevision) { _, _ in
                guard autoFollow.isFollowing, page?.newerCursor == nil else { return }
                window.followTail()
                Task { @MainActor in proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onKeyPress(.end) { latest(proxy); return .handled }
            .onAppear {
                if page?.newerCursor == nil { Task { @MainActor in proxy.scrollTo("chat-bottom", anchor: .bottom) } }
            }
        }
        .background(DSColor.chatBackground)
        .onChange(of: renderedSpan, initial: true) { _, span in
            control.renderedSpans[renderOwner] = span
        }
        .onDisappear {
            loadingEdge = nil
            pendingJump = nil
            revealRequest = nil
            jumpGeneration += 1
            control.renderedSpans.removeValue(forKey: renderOwner)
        }
        .onChange(of: viewModel.executionID) { _, _ in
            loadingEdge = nil
            pendingJump = nil
            revealRequest = nil
            jumpGeneration += 1
        }
        .task(id: viewModel.executionID) {
            do { try await viewModel.refreshRuntimeContent() }
            catch { viewModel.runtimeChatRead.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func blockView(_ block: SessionRuntimeChatReadBlock) -> some View {
        switch block.content {
        case .item(let reference):
            RuntimeChatItemReferenceView(reference: reference, viewModel: viewModel, actions: itemActions)
        case .card(let summary):
            RuntimeStatusCardView(viewModel: viewModel, summary: summary, cache: viewModel.runtimeChatRead.cards[summary.inputID],
                isNarrow: context == .gridTile, revealRequest: revealRequest, revealSerial: jumpGeneration,
                itemActions: itemActions)
                .equatable()
        case .commandGroup(let summary):
            RuntimeCommandGroupView(viewModel: viewModel, summary: summary, inputID: block.ownerInputID,
                itemActions: itemActions)
        }
    }

    private func updatePosition(_ center: CGFloat) {
        let match = visibleBlocks.compactMap { block -> (String, CGFloat)? in
            guard let input = block.ownerInputID, let y = offsets[block.id], y <= center + DSSpacing.m else { return nil }
            return (input, y)
        }.max { $0.1 < $1.1 }
        if let input = match?.0, currentInputPositionID != input { currentInputPositionID = input }
    }

    private func load(_ edge: VerticalEdge, proxy: ScrollViewProxy) {
        guard !viewModel.runtimeChatRead.isLoading, canLoad(edge) else {
            loadingEdge = nil
            return
        }
        revealRequest = nil
        pendingJump = nil
        autoFollow.userInitiatedJump()
        detached = true
        let anchor = edge == .top ? visibleBlocks.first?.id : visibleBlocks.last?.id
        if edge == .top, slice.hiddenBlockCount > 0 {
            let keep = window.loadEarlier(in: blocks)
            if let keep { Task { @MainActor in proxy.scrollTo(keep, anchor: .top) } }
            loadingEdge = nil
            return
        }
        if edge == .bottom, slice.hiddenNewerBlockCount > 0 {
            let keep = window.loadNewer(in: blocks)
            if let keep { Task { @MainActor in proxy.scrollTo(keep, anchor: .top) } }
            loadingEdge = nil
            return
        }
        let cursor = edge == .top ? page?.olderCursor : page?.newerCursor
        guard let cursor else { return }
        jumpGeneration += 1
        let generation = jumpGeneration
        let intent = RuntimeChatReadIntent(epoch: viewModel.runtimeChatRead.epoch, token: UUID())
        Task {
            defer { if generation == jumpGeneration { loadingEdge = nil } }
            do {
                try await viewModel.loadRuntimeChatRead(target: edge == .top ? .chatReadBefore(cursor: cursor) : .chatReadAfter(cursor: cursor),
                    intentToken: intent.token)
                guard generation == jumpGeneration, intent.isApplied(in: viewModel.runtimeChatRead) else { return }
                if edge == .bottom, let anchor { window.keepRuntimeEnd(at: anchor, in: blocks) }
                if edge == .top {
                    _ = window.loadEarlier(in: blocks)
                } else { _ = window.loadNewer(in: blocks) }
                loadingEdge = nil
                await Task.yield()
                guard generation == jumpGeneration, intent.isApplied(in: viewModel.runtimeChatRead) else { return }
                if let anchor, slice.blocks.contains(where: { $0.id == anchor }) {
                    proxy.scrollTo(anchor, anchor: .top)
                } else if let target = edge == .top ? slice.blocks.last?.id : slice.blocks.first?.id {
                    proxy.scrollTo(target, anchor: .top)
                }
            } catch { }
        }
    }

    private func jump(_ inputID: String, proxy: ScrollViewProxy) {
        loadingEdge = nil
        revealRequest = nil
        let requestedJump = RuntimeChatPendingJump(itemID: inputID, epoch: viewModel.runtimeChatRead.epoch,
            intentToken: UUID())
        pendingJump = requestedJump
        jumpGeneration += 1
        let generation = jumpGeneration
        detached = true
        autoFollow.userInitiatedJump()
        Task {
            defer { if generation == jumpGeneration { pendingJump = nil } }
            do {
                try await viewModel.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: inputID),
                    intentToken: requestedJump.intentToken)
                guard generation == jumpGeneration,
                      let appliedTarget = requestedJump.appliedTarget(in: viewModel.runtimeChatRead) else { return }
                revealRequest = appliedTarget
                let target = appliedTarget.scrollTargetID
                _ = window.reveal(itemID: target, in: blocks)
                await Task.yield()
                guard generation == jumpGeneration,
                      requestedJump.appliedTarget(in: viewModel.runtimeChatRead) != nil else { return }
                proxy.scrollTo(target, anchor: .top)
                currentInputPositionID = revealRequest?.inputID ?? inputID
            } catch { }
        }
    }

    private func latest(_ proxy: ScrollViewProxy) {
        loadingEdge = nil
        revealRequest = nil
        pendingJump = nil
        jumpGeneration += 1
        let generation = jumpGeneration
        let intent = RuntimeChatReadIntent(epoch: viewModel.runtimeChatRead.epoch, token: UUID())
        Task {
            do {
                try await viewModel.loadRuntimeChatRead(target: .chatReadTail, intentToken: intent.token)
                guard generation == jumpGeneration, intent.isApplied(in: viewModel.runtimeChatRead) else { return }
                window.followTail()
                detached = false
                autoFollow.scrollPositionChanged(isAtBottom: true)
                await Task.yield()
                guard generation == jumpGeneration, intent.isApplied(in: viewModel.runtimeChatRead) else { return }
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            } catch { }
        }
    }

    private func canLoad(_ edge: VerticalEdge) -> Bool {
        edge == .top ? page?.olderCursor != nil || slice.hiddenBlockCount > 0
            : page?.newerCursor != nil || slice.hiddenNewerBlockCount > 0
    }

    private func beginLoading(_ edge: VerticalEdge) {
        guard loadingEdge == nil, !viewModel.runtimeChatRead.isLoading, canLoad(edge) else { return }
        jumpGeneration += 1
        autoFollow.userInitiatedJump()
        detached = true
        loadingEdge = edge
    }

    private func finishLoading(_ proxy: ScrollViewProxy) {
        guard let edge = loadingEdge else { return }
        load(edge, proxy: proxy)
    }
}

struct RuntimeChatReadIntent {
    let epoch: UUID
    let token: UUID

    func isApplied(in projection: RuntimeChatReadProjection) -> Bool {
        projection.epoch == epoch && projection.appliedIntentToken == token
    }
}

/// Prepare the first successful jump frame without mutating view state during rendering.
struct RuntimeChatPendingJump {
    let itemID: String
    let epoch: UUID
    let intentToken: UUID

    func appliedTarget(in projection: RuntimeChatReadProjection) -> SessionRuntimeChatReadRevealTarget? {
        guard RuntimeChatReadIntent(epoch: epoch, token: intentToken).isApplied(in: projection),
              let target = projection.page?.revealTarget, target.itemID == itemID else { return nil }
        return target
    }

    func windowForRender(_ window: TranscriptWindow, projection: RuntimeChatReadProjection) -> TranscriptWindow {
        guard let target = appliedTarget(in: projection), let page = projection.page else { return window }
        var prepared = window
        _ = prepared.reveal(itemID: target.scrollTargetID, in: page.blocks)
        return prepared
    }
}

extension SessionRuntimeChatReadRevealTarget {
    var scrollTargetID: String { cardID ?? entryID ?? itemID }
}

private struct RuntimeChatBlockOffsets: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct RuntimeStatusCardView: View, Equatable {
    @Bindable var viewModel: ChatSessionViewModel
    let summary: SessionRuntimeCardSummary
    let cache: RuntimeCardReadCache?
    let isNarrow: Bool
    let revealRequest: SessionRuntimeChatReadRevealTarget?
    let revealSerial: Int
    let itemActions: RuntimeChatItemActions
    @State private var handledRevealSerial: Int?
    @State private var disclosure = AgentStatusCardDisclosure()

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel === rhs.viewModel && lhs.summary == rhs.summary
            && runtimeCardSnapshotsMatch(lhs.cache, rhs.cache) && lhs.isNarrow == rhs.isNarrow
            && lhs.revealRequest == rhs.revealRequest
            && (lhs.revealRequest == nil || lhs.revealSerial == rhs.revealSerial)
            && lhs.itemActions.hasSameRenderState(as: rhs.itemActions)
    }

    private var contentVersion: String {
        "\(summary.revision)-\(summary.contentRevision)-\(revealRequest?.cardID == summary.id ? revealSerial : 0)"
    }

    var body: some View {
        Group {
            if let cache {
                let presentation = RuntimeStatusCardPresentation(inputID: summary.inputID, cache: cache, viewModel: viewModel,
                    revealActionID: revealRequest?.cardID == summary.id && handledRevealSerial != revealSerial ? revealRequest?.entryID : nil,
                    revealSerial: revealSerial, itemActions: itemActions)
                AgentStatusCardView(card: presentation.card,
                    agentDescriptor: AgentRegistry.descriptor(for: viewModel.agentRef.builtinKind),
                    isStill: presentation.card.header.isLive && (viewModel.isCompacting || viewModel.shouldShowConnectingIndicator),
                    isNarrow: isNarrow, isLaunchFailureRestarting: itemActions.isRestarting,
                    revealRequest: revealRequest.flatMap { request in
                        request.cardID == summary.id && handledRevealSerial != revealSerial ? AgentStatusRevealRequest(itemID: request.entryID ?? request.itemID, serial: revealSerial) : nil
                    }, hangAssessment: { viewModel.hangAssessment(now: $0) },
                    onInterrupt: { await viewModel.turnInterrupt() }, disclosure: disclosure,
                    runtime: presentation, disclosureBinding: $disclosure)
                    .equatable()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    AgentStatusCardView(card: AgentStatusCard(id: summary.id, header: summary.header, rows: []),
                        agentDescriptor: AgentRegistry.descriptor(for: viewModel.agentRef.builtinKind), isNarrow: isNarrow)
                    Button("タスクを読み込む") { Task { try? await viewModel.loadRuntimeCardRows(summary.inputID) } }
                        .buttonStyle(.plain).font(DSFont.meta)
                        .accessibilityIdentifier("AgentStatusCard.retryRows")
                }
            }
        }
        .task(id: contentVersion) { await loadRows() }
    }

    private func loadRows() async {
        do {
            if let request = revealRequest, request.cardID == summary.id,
               handledRevealSerial != revealSerial, let rowID = request.rowID {
                try await viewModel.revealRuntimeCardEntry(summary.inputID, rowID: rowID, entryID: request.entryID)
                if let entryID = request.entryID, let cache = viewModel.runtimeChatRead.cards[summary.inputID] {
                    let card = RuntimeStatusCardPresentation(inputID: summary.inputID, cache: cache, viewModel: viewModel).card
                    disclosure.reveal(rowID: rowID, in: card)
                    disclosure.reveal(itemID: entryID, in: card)
                    if cache.entries[rowID]?.entries.contains(where: { entry in
                        if case .action(let action) = entry { action.id == entryID } else { false }
                    }) == true {
                        disclosure.setActionOpen(true, actionID: entryID, cardID: summary.id)
                    }
                }
                handledRevealSerial = revealSerial
            } else {
                if let current = viewModel.runtimeChatRead.cards[summary.inputID],
                   current.rows.card.revision == summary.revision,
                   current.rows.card.contentRevision >= summary.contentRevision { return }
                try await viewModel.loadRuntimeCardRows(summary.inputID)
            }
        } catch { }
    }
}

private struct RuntimeCommandGroupView: View {
    let viewModel: ChatSessionViewModel
    let summary: SessionRuntimeActionSummary
    let inputID: String?
    let itemActions: RuntimeChatItemActions
    @State private var page: SessionRuntimeActionItemsPage?
    @State private var fetchSequence = 0
    @State private var userOverride: Bool?
    @State private var error: String?
    @Environment(\.locale) private var locale

    private var isRunning: Bool { summary.state == .running }
    private var isOpen: Bool { userOverride ?? isRunning }
    private var firstTool: (label: String, body: String) {
        CommandToolLabel.derive(command: summary.commandGroup?.firstCommand)
    }
    private var label: Text {
        if summary.totalItemCount > 1 { Text("ツール実行 ×\(summary.totalItemCount)") }
        else if firstTool.label == "Bash" { Text("コマンド") }
        else { Text(verbatim: firstTool.label) }
    }
    private var headerSummary: String {
        if summary.totalItemCount == 1 { return firstTool.label == "Bash" ? "$ \(firstTool.body)" : firstTool.body }
        if isRunning {
            let tool = CommandToolLabel.derive(command: summary.commandGroup?.lastCommand)
            return "\(tool.label) \(tool.body)"
        }
        let first = "\(firstTool.label) \(CommandGroupCell.shortArgument(firstTool))"
        return String(format: AppLocalizedString.string("%@ ほか %lld 件", locale: locale), first, summary.totalItemCount - 1)
    }

    var body: some View {
        Group {
            if isRunning || summary.totalItemCount == 1 || summary.commandGroup?.hasNonBlankOutput == true {
                TranscriptCard(isExpanded: Binding(get: { isOpen }, set: { userOverride = $0 }),
                    label: label, summary: headerSummary, isRunning: isRunning, badges: badges) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let page {
                            ForEach(page.items, id: \.id) { reference in
                                if case .inline(.commandExecution(let id, let command, let output, let timestamp, _, _)) = reference {
                                    if summary.totalItemCount == 1 { CommandCardOutput(output: output) }
                                    else {
                                        CommandGroupToolRow(row: CommandGroupRow(id: id, command: command,
                                            output: output, timestamp: timestamp,
                                            isRunning: isRunning && page.nextCursor == nil && id == page.items.last?.id))
                                    }
                                } else { RuntimeChatItemReferenceView(reference: reference, viewModel: viewModel, actions: itemActions) }
                            }
                            if let cursor = page.nextCursor {
                                Button("さらに表示") { fetch(cursor) }
                                    .font(DSFont.meta)
                                    .accessibilityIdentifier("CommandGroupCell.loadEarlierRows")
                            }
                        } else if error == nil { ProgressView().controlSize(.small) }
                        if let error {
                            Text(error).font(DSFont.meta)
                            Button("再試行") { reload() }
                                .font(DSFont.meta)
                                .accessibilityIdentifier("CommandGroupCell.retry")
                        }
                    }
                }
                .accessibilityIdentifier("CommandGroupCell")
            }
        }
        .task(id: "\(summary.contentRevision)-\(isOpen)") { if isOpen { reload() } }
    }

    private var badges: [TranscriptCardBadge] {
        if isRunning { return [TranscriptCardBadge(id: "running", text: Text("実行中"), color: DSColor.chatTextPrimary, weight: .medium)] }
        guard summary.totalItemCount == 1, let code = summary.commandGroup?.exitCode else { return [] }
        return [TranscriptCardBadge(id: "exit", text: Text(verbatim: "exit \(code)"),
            color: code == 0 ? DSColor.textTertiary : DSColor.attentionInk(.error), weight: code == 0 ? .regular : .semibold)]
    }

    private func reload() {
        let firstID = page?.items.first?.id
        let target: SessionRuntimeContentRequest.Target = firstID.map {
            .chatActionItemsFrom(inputID: inputID, actionID: summary.id, itemID: $0)
        } ?? .chatActionItems(inputID: inputID, actionID: summary.id, cursor: nil)
        fetch(target)
    }

    private func fetch(_ cursor: SessionRuntimeChatReadCursor?) {
        fetch(.chatActionItems(inputID: inputID, actionID: summary.id, cursor: cursor))
    }

    private func fetch(_ target: SessionRuntimeContentRequest.Target) {
        fetchSequence += 1
        let sequence = fetchSequence
        let execution = viewModel.executionID
        let epoch = viewModel.runtimeChatRead.epoch
        Task {
            var confirmedMissingAction = false
            do {
                let response: SessionRuntimeContentResponse
                do { response = try await viewModel.readRuntimeChat(target) }
                catch SessionRuntimeContentError.notFound {
                    let parent = try await viewModel.readRuntimeChat(.chatReadTail)
                    guard sequence == fetchSequence, viewModel.executionID == execution,
                          viewModel.runtimeChatRead.epoch == epoch else { return }
                    guard case .chatReadPage(let timeline) = parent, timeline.sessionID == viewModel.id,
                          timeline.executionID == execution else { throw SessionRuntimeContentError.staleContent }
                    do {
                        response = try await viewModel.readRuntimeChat(.chatActionItems(inputID: inputID, actionID: summary.id, cursor: nil))
                    } catch SessionRuntimeContentError.notFound {
                        confirmedMissingAction = true
                        throw SessionRuntimeContentError.notFound
                    }
                } catch SessionRuntimeContentError.staleContent {
                    guard sequence == fetchSequence, viewModel.executionID == execution,
                          viewModel.runtimeChatRead.epoch == epoch else { return }
                    response = try await viewModel.readRuntimeChat(.chatActionItems(inputID: inputID, actionID: summary.id, cursor: nil))
                }
                guard sequence == fetchSequence, viewModel.executionID == execution,
                      viewModel.runtimeChatRead.epoch == epoch else { return }
                guard case .actionItemsPage(let value) = response, value.executionID == execution,
                      value.sessionID == viewModel.id, value.inputID == inputID,
                      value.actionID == summary.id else { throw SessionRuntimeContentError.staleContent }
                page = value
                error = nil
            } catch {
                guard sequence == fetchSequence, viewModel.executionID == execution,
                      viewModel.runtimeChatRead.epoch == epoch else { return }
                if error is CancellationError { return }
                if confirmedMissingAction {
                    page = nil
                    self.error = nil
                    viewModel.requestRuntimeContentCatchUp()
                } else if let contentError = error as? SessionRuntimeContentError, contentError == .staleContent {
                    viewModel.requestRuntimeContentCatchUp()
                } else { self.error = error.localizedDescription }
            }
        }
    }
}
