import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

public struct TeamTimelineView: View {
    let viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let isCreating: Bool
    let onSelectAgentKind: (AgentKind, SessionBackend) -> Void
    @State private var store = TeamTimelineStore()
    @State private var spawnError: TeamTimelineSpawnError?

    private static let ptyScrollbackLines = 400
    private static let messageLimitPerSession = 200
    private static let refreshInterval: Duration = .milliseconds(350)

    private var selectedSessionID: SessionID? { router.selectedSession }

    public init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        isCreating: Bool,
        onSelectAgentKind: @escaping (AgentKind, SessionBackend) -> Void
    ) {
        self.viewModel = viewModel
        self.router = router
        self.isCreating = isCreating
        self.onSelectAgentKind = onSelectAgentKind
    }

    public var body: some View {
        Group {
            switch StartAreaPolicy.content(
                hasSelectedProject: router.selectedProjectID != nil,
                hasSelectedSession: selectedSessionID != nil
            ) {
            case .sessionContent:
                timeline(sources: store.sources, items: store.items)
            case .agentStartCards:
                AgentStartCardsView(
                    cards: AgentStartCardsModel.cards(available: viewModel.availableAgentKinds),
                    isCreating: isCreating,
                    onSelect: onSelectAgentKind
                )
            case .selectProjectPlaceholder:
                SelectProjectPlaceholderView()
            }
        }
        .background(DSColor.chatBackground)
        .alert(
            "セッションの起動に失敗しました",
            isPresented: spawnErrorAlertBinding,
            presenting: spawnError
        ) { _ in
            Button("OK", role: .cancel) { spawnError = nil }
        } message: { err in
            Text(err.message)
        }
        .task(id: selectedSessionID) {
            await runRefreshLoop(selectedSessionID: selectedSessionID)
        }
    }

    private func timeline(sources: [TeamTimelineSource], items: [TeamTimelineItem]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                // NOTE: LazyVStack を使わない（ADR 0030 決定1）。Lazy 配置は可変高の行と
                // リサイズの組み合わせで「不動点が成立しない自走ループ」に入り、main thread が
                // 100% 固着する（2026-07-07 チームビューで再発を実測 = LazySubviewPlacements が
                // ホットパス支配。ADR 0045 / delivery/0024 参照）。遅延機構を再導入しないこと。
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    header(sources: sources)
                    if items.isEmpty, thinkingSources(from: sources).isEmpty {
                        emptyTimeline
                    } else {
                        AgoraTimelineRows(items: items, onOpenSession: openSession)
                        AgoraThinkingIndicatorRows(
                            sources: thinkingSources(from: sources)
                        )
                    }
                    Color.clear.frame(height: 1)
                }
                .padding(.horizontal, DSSpacing.l)
                .padding(.vertical, DSSpacing.m)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            TeamComposer(
                targetDisplayName: composerTargetDisplayName,
                isReadyForInput: composerIsReadyForInput,
                onSend: sendTeamMessage
            )
        }
    }

    private func header(sources: [TeamTimelineSource]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "person.3")
                    .font(.system(size: DSIconSize.l, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                Text("アゴラ")
                    .font(DSFont.sectionHeader)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Text("\(sources.count) セッション")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }

            if let coordinator = viewModel.agoraDiscussionCoordinator,
               TeamTimelineAgoraPolicy.isDiscussionActive(phase: coordinator.phase) {
                AgoraDiscussionHeaderView(
                    utteranceCount: coordinator.utteranceCount,
                    maxUtterances: coordinator.maxUtterances,
                    participants: discussionHeaderParticipants(coordinator: coordinator),
                    onStop: { Task { await viewModel.stopAgoraDiscussion() } }
                )
                HStack {
                    Spacer(minLength: 0)
                    addAgentMenu
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(sources) { source in
                            TeamTimelineSourceChip(source: source)
                        }
                        addAgentMenu
                    }
                }
            }
        }
        .padding(.bottom, DSSpacing.xs)
    }

    @ViewBuilder
    private var addAgentMenu: some View {
        if TeamTimelineAgoraPolicy.isDiscussionActive(
            phase: viewModel.agoraDiscussionCoordinator?.phase
        ) {
            Button {
                Task { await addClaudeDiscussionParticipant() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textSecondary)
            .background(DSColor.fillSubtle, in: Circle())
            .disabled(isAddAgentDisabled)
            .help("Claude チャットを追加")
        } else {
            Menu {
                ForEach(viewModel.availableAgentKinds, id: \.self) { kind in
                    let descriptor = AgentRegistry.descriptor(for: kind)
                    ForEach(AgentStartCardsModel.modes(for: descriptor), id: \.self) { mode in
                        Button {
                            onSelectAgentKind(kind, mode.backend)
                        } label: {
                            Text("\(descriptor.displayName) — \(mode.label)")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textSecondary)
            .background(DSColor.fillSubtle, in: Circle())
            .disabled(isAddAgentDisabled)
            .help(addAgentHelp)
        }
    }

    private var composerTargetDisplayName: String? {
        if TeamTimelineAgoraPolicy.isDiscussionActive(
            phase: viewModel.agoraDiscussionCoordinator?.phase
        ) {
            return "討論"
        }
        return composerTargetNode?.displayName
    }

    private var composerIsReadyForInput: Bool {
        if TeamTimelineAgoraPolicy.isDiscussionActive(
            phase: viewModel.agoraDiscussionCoordinator?.phase
        ) {
            return true
        }
        return store.isComposerReadyForInput
    }

    private func discussionHeaderParticipants(
        coordinator: AgoraDiscussionCoordinator
    ) -> [AgoraDiscussionHeaderView.Participant] {
        let nodes = viewModel.sessionNodes
        return coordinator.participants.map { participant in
            let displayName = nodes.first { $0.id == participant.id }?.displayName
                ?? participant.id.rawValue.uuidString
            return AgoraDiscussionHeaderView.Participant(
                id: participant.id,
                displayName: displayName,
                role: participant.role,
                isFacilitator: participant.isFacilitator
            )
        }
    }

    private func addClaudeDiscussionParticipant() async {
        guard !isCreating else { return }
        guard let projectID = router.selectedProjectID
            ?? viewModel.defaultProjectID(forSelectedSession: router.selectedSession)
        else { return }

        do {
            let newID = try await viewModel.spawnNewSession(
                kind: .claudeCode,
                projectID: projectID,
                backend: .appServer,
                launchContext: .interactive
            )
            await viewModel.addAgoraDiscussionParticipant(id: newID, role: nil)
        } catch {
            let raw = error.localizedDescription
            spawnError = TeamTimelineSpawnError(
                message: raw.isEmpty ? String(describing: error) : raw
            )
        }
    }

    private var spawnErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { spawnError != nil },
            set: { if !$0 { spawnError = nil } }
        )
    }

    private var canResolveProjectForNewSession: Bool {
        router.selectedProjectID != nil
            || viewModel.defaultProjectID(forSelectedSession: router.selectedSession) != nil
    }

    private var isAddAgentDisabled: Bool {
        isCreating || !canResolveProjectForNewSession
    }

    private var addAgentHelp: String {
        if isCreating {
            return "エージェントを追加中"
        }
        return canResolveProjectForNewSession ? "エージェントを追加" : "プロジェクトを選択"
    }

    private var emptyTimeline: some View {
        Text("表示できる会話がありません")
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    @MainActor
    private func runRefreshLoop(selectedSessionID: SessionID?) async {
        refreshTimeline(selectedSessionID: selectedSessionID)

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            refreshTimeline(selectedSessionID: selectedSessionID)
        }
    }

    @MainActor
    private func refreshTimeline(selectedSessionID: SessionID?) {
        let nodes = viewModel.sessionNodes
        let discussionParticipantIDs = TeamTimelineAgoraPolicy.discussionParticipantIDs(
            coordinator: viewModel.agoraDiscussionCoordinator
        )
        let signature = TeamTimelineSignature.make(
            selectedSessionID: selectedSessionID,
            selectedProjectID: router.selectedProjectID,
            sessions: nodes.map(signatureSession(for:)),
            discussionParticipantIDs: discussionParticipantIDs
        )

        let parentByID = parentLinks(nodes: nodes)
        let rootID = TeamComposerTarget.resolveRootSessionID(
            selectedSessionID: selectedSessionID,
            parentByID: parentByID
        )
        let composerReadyForInput = rootID
            .flatMap { rootID in nodes.first { $0.id == rootID } }?
            .controllable
            .isReadyForInput ?? false
        store.refreshComposerReadiness(composerReadyForInput)

        store.refreshAgoraTimelineIfNeeded(
            signature: signature,
            messageLimitPerSession: Self.messageLimitPerSession,
            discussionParticipants: discussionParticipantIDs
        ) {
            return makeSources(
                selectedSessionID: selectedSessionID,
                nodes: nodes,
                discussionParticipantIDs: discussionParticipantIDs
            )
        }
    }

    private func makeSources(
        selectedSessionID: SessionID?,
        nodes: [SessionNode],
        discussionParticipantIDs: Set<SessionID>?
    ) -> [AgentTimelineSource] {
        guard !nodes.isEmpty else { return [] }
        guard let targetProjectID = router.selectedProjectID
            ?? selectedSessionID.flatMap({ selectedID in
                nodes.first { $0.id == selectedID }?.projectID
            })
        else {
            return []
        }

        let inputs = nodes.map { node in
            SessionTreeInput(
                id: node.id,
                parentSessionID: node.controllable.parentSessionID,
                projectID: node.projectID,
                launchContext: node.launchContext,
                status: node.status,
                name: node.name,
                agentRef: node.agentRef
            )
        }
        let forest = SessionTree.buildForest(from: inputs)
        let orderedIDs = AgoraParticipantsPolicy.orderedProjectSessionIDs(
            forest: forest,
            projectID: targetProjectID
        )
        let orderedNodes = TeamTimelineNodeOrdering.ordered(ids: orderedIDs, items: nodes, id: \.id)
        let parentByID = Dictionary(
            uniqueKeysWithValues: orderedNodes.compactMap { node -> (SessionID, SessionID)? in
                guard let parentID = node.controllable.parentSessionID else { return nil }
                return (node.id, parentID)
            }
        )
        let participantIDs = AgoraParticipantsPolicy.participants(
            orderedIDs: orderedIDs,
            parentByID: parentByID,
            discussionParticipants: discussionParticipantIDs
        )
        let participantNodes = TeamTimelineNodeOrdering.ordered(
            ids: participantIDs,
            items: orderedNodes,
            id: \.id
        )
        return participantNodes.map(agentSource(for:))
    }

    private func thinkingSources(from sources: [TeamTimelineSource]) -> [TeamTimelineSource] {
        let statusesByID = Dictionary(
            uniqueKeysWithValues: viewModel.sessionNodes.map { ($0.id, $0.status) }
        )
        let thinkingIDs = AgoraThinkingPolicy.thinkingSessionIDs(
            sources: sources,
            statusesByID: statusesByID
        )
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        return thinkingIDs.compactMap { sourceByID[$0] }
    }

    private func agentSource(for node: SessionNode) -> AgentTimelineSource {
        let messages: [TeamTimelineSourceMessage]
        if let chatItems = node.appServer?.transcript {
            messages = AgoraTimelineContentPolicy.filteredTranscript(chatItems)
                .map(TeamTimelineSourceMessage.chatItem)
        } else {
            let text = node.controllable.readText(lines: Self.ptyScrollbackLines)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            messages = text.isEmpty
                ? []
                : [
                    TeamTimelineSourceMessage(
                        id: "terminal-\(node.id.rawValue.uuidString)",
                        timestamp: node.lastOutputAt,
                        content: .terminalText(text)
                    ),
                ]
        }

        return AgentTimelineSource(
            id: node.id,
            parentSessionID: node.controllable.parentSessionID,
            displayName: node.displayName,
            agentDescriptor: node.agentDescriptor,
            messages: messages
        )
    }

    private func signatureSession(for node: SessionNode) -> TeamTimelineSignatureSession {
        let content: TeamTimelineSignatureContent
        if let chatSession = node.appServer {
            content = .appServer(transcriptRevision: chatSession.transcriptRevision)
        } else {
            content = .pty(lastOutputAt: node.lastOutputAt)
        }

        return TeamTimelineSignatureSession(
            id: node.id,
            parentSessionID: node.controllable.parentSessionID,
            projectID: node.projectID,
            launchContext: node.launchContext,
            status: node.status,
            name: node.name,
            displayName: node.displayName,
            agentDescriptor: node.agentDescriptor,
            content: content
        )
    }

    private var composerTargetNode: SessionNode? {
        let nodes = viewModel.sessionNodes
        let parentByID = parentLinks(nodes: nodes)
        guard let rootID = TeamComposerTarget.resolveRootSessionID(
            selectedSessionID: selectedSessionID,
            parentByID: parentByID
        ) else {
            return nil
        }
        return nodes.first { $0.id == rootID }
    }

    private func parentLinks(nodes: [SessionNode]) -> [SessionID: SessionID?] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.controllable.parentSessionID) })
    }

    private func openSession(_ sessionID: SessionID) {
        router.openSingle(sessionID: sessionID)
    }

    private func sendTeamMessage(_ text: String) async throws {
        let action = AgoraComposerRouting.action(
            phase: viewModel.agoraDiscussionCoordinator?.phase,
            canStartDiscussion: TeamTimelineAgoraPolicy.canStartDiscussion(
                canResolveProject: canResolveProjectForNewSession
            ),
            text: text
        )
        switch action {
        case .startDiscussion(let agenda):
            _ = await viewModel.startAgoraDiscussion(
                agenda: agenda,
                selectedSessionID: selectedSessionID
            )
        case .discussionUtterance(let utterance):
            await viewModel.submitAgoraUserUtterance(utterance)
        case .legacyRootSend(let message):
            guard let target = composerTargetNode?.controllable else { return }
            try await target.sendText(message, submit: true)
        }
    }
}

@MainActor
enum TeamTimelineAgoraPolicy {
    static func isDiscussionActive(phase: AgoraDiscussionPhase?) -> Bool {
        switch phase {
        case .discussing, .concluding:
            return true
        case .idle, .ended, nil:
            return false
        }
    }

    static func canStartDiscussion(canResolveProject: Bool) -> Bool {
        canResolveProject
    }

    static func discussionParticipantIDs(
        coordinator: AgoraDiscussionCoordinator?
    ) -> Set<SessionID>? {
        guard let coordinator, isDiscussionActive(phase: coordinator.phase) else { return nil }
        return Set(coordinator.participants.map(\.id))
    }

    static func addAgentKindDuringDiscussion(isDiscussionActive: Bool) -> AgentKind? {
        isDiscussionActive ? .claudeCode : nil
    }
}

private struct TeamTimelineSpawnError: Identifiable {
    let id = UUID()
    let message: String
}

private struct TeamTimelineSourceChip: View {
    let source: TeamTimelineSource

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            AgentBrandIcon(descriptor: source.agentDescriptor, size: 14)
            Text(source.agentDescriptor.displayName)
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textPrimary)
            Text(source.displayName)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColor.fillSubtle, in: Capsule())
    }
}

private struct AgoraTimelineRows: View {
    let items: [TeamTimelineItem]
    let onOpenSession: (SessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            ForEach(items) { item in
                AgoraTimelineRow(item: item, onOpenSession: onOpenSession)
            }
        }
    }
}

private struct AgoraThinkingIndicatorRows: View {
    let sources: [TeamTimelineSource]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            ForEach(sources) { source in
                AgoraThinkingIndicatorRow(source: source)
            }
        }
    }
}

private struct AgoraTimelineRow: View {
    let item: TeamTimelineItem
    let onOpenSession: (SessionID) -> Void

    var body: some View {
        if AgentChatRowPolicy.showsSpeakerHeader(for: item.content) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                speakerHeader
                messageContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            messageContent
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var speakerHeader: some View {
        Button {
            onOpenSession(item.sessionID)
        } label: {
            HStack(spacing: DSSpacing.xs) {
                AgentBrandIcon(descriptor: item.agentDescriptor, size: 16)
                Text(item.sessionDisplayName)
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(item.agentDescriptor.displayName)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help("シングルビューで開く")
    }

    @ViewBuilder
    private var messageContent: some View {
        switch item.content {
        case .chatItem(let chatItem):
            if AgentChatRowPolicy.usesAgentMessageBubble(for: item.content),
               case .agentMessage(_, let text, let timestamp) = chatItem {
                AgoraAgentMessageBubble(
                    text: text,
                    timestamp: timestamp
                )
            } else {
                ChatItemView(
                    item: chatItem,
                    isRunningCommand: false,
                    agentDescriptor: item.agentDescriptor
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: AgentChatRowPolicy.showsSpeakerHeader(for: item.content) ? .leading : .trailing
                )
            }
        case .terminalText(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(DSColor.chatTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .background(
                    DSColor.fillSubtle,
                    in: RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                )
        }
    }
}
