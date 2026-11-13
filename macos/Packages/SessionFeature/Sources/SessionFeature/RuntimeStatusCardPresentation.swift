import SwiftUI
import AgentDomain
import DesignSystem

@MainActor
final class RuntimeChatItemActionRouter {
    private var restart: (() -> Void)?
    private var close: (() -> Void)?

    init(restart: (() -> Void)? = nil, close: (() -> Void)? = nil) {
        self.restart = restart
        self.close = close
    }

    func install(restart: (() -> Void)?, close: (() -> Void)?) {
        self.restart = restart
        self.close = close
    }

    func performRestart() { restart?() }
    func performClose() { close?() }
}

@MainActor
final class RuntimeChatItemActions {
    private let router: RuntimeChatItemActionRouter
    private let incomingRestart: (() -> Void)?
    private let incomingClose: (() -> Void)?
    nonisolated let canRestart: Bool
    nonisolated let canClose: Bool
    nonisolated let isRestarting: Bool

    var restart: (() -> Void)? {
        guard canRestart else { return nil }
        let router = router
        return { router.performRestart() }
    }
    var close: (() -> Void)? {
        guard canClose else { return nil }
        let router = router
        return { router.performClose() }
    }

    init(restart: (() -> Void)?, close: (() -> Void)?, isRestarting: Bool,
         router: RuntimeChatItemActionRouter? = nil) {
        self.router = router ?? RuntimeChatItemActionRouter(restart: restart, close: close)
        incomingRestart = restart
        incomingClose = close
        canRestart = restart != nil
        canClose = close != nil
        self.isRestarting = isRestarting
    }

    func installHandlers() { router.install(restart: incomingRestart, close: incomingClose) }

    nonisolated func hasSameRenderState(as other: RuntimeChatItemActions) -> Bool {
        router === other.router && canRestart == other.canRestart
            && canClose == other.canClose && isRestarting == other.isRestarting
    }
}

struct RuntimeStatusCardPresentation: Sendable {
    let inputID: String
    let cache: RuntimeCardReadCache
    let viewModel: ChatSessionViewModel
    var revealActionID: String? = nil
    var revealSerial = 0
    var itemActions: RuntimeChatItemActions? = nil

    var contentVersion: String { "\(cache.rows.card.revision)-\(cache.rows.card.contentRevision)" }

    var card: AgentStatusCard {
        let agent = viewModel.agentRef.builtinKind
        return AgentStatusCard(id: cache.rows.card.id, header: cache.rows.card.header,
            rows: cache.rows.rows.map { row in
                let entries = cache.entries[row.id]?.entries.compactMap { entry -> AgentStatusEntry? in
                    switch entry {
                    case .action(let summary): .action(summary.action)
                    case .item(let reference) where reference.isHiddenReasoning(agent: agent): nil
                    case .item(.inline(let item)): .item(item)
                    case .item(.deferred): nil
                    }
                } ?? []
                switch row.kind {
                case .task(let id, let title, let state, let start, let end):
                    return .task(AgentStatusTask(id: id, title: title, state: state,
                        startedAt: start, endedAt: end, entries: entries, totalEntryCount: row.totalEntryCount))
                case .outside(let state):
                    return .outside(AgentStatusOutsideGroup(id: row.id, entries: entries,
                        totalEntryCount: row.totalEntryCount, totalActionCount: row.totalActionCount,
                        aggregateState: state))
                }
            }, changeCounts: cache.rows.card.changeCounts, totalRowCount: cache.rows.card.totalRowCount, hasTask: cache.rows.card.hasTasks)
    }

    @MainActor
    func loadEntries(_ rowID: String, next: Bool = false, endingAtID: String? = nil, startingAtID: String? = nil) {
        Task { try? await viewModel.loadRuntimeCardEntries(inputID, rowID: rowID, next: next,
            aroundEntryID: endingAtID, startingAtID: startingAtID) }
    }

    @MainActor
    func loadAction(_ actionID: String, next: Bool = false) {
        Task { try? await viewModel.loadRuntimeActionItems(inputID, actionID: actionID, next: next) }
    }

    @MainActor
    func retry(_ rowID: String) {
        guard let target = cache.failure?.target else { loadEntries(rowID); return }
        switch target {
        case .rows: Task { try? await viewModel.loadRuntimeCardRows(inputID) }
        case .entries(_, let failedRowID): loadEntries(failedRowID)
        case .action(_, let actionID): loadAction(actionID)
        }
    }

}

func runtimeCardSnapshotsMatch(_ lhs: RuntimeCardReadCache?, _ rhs: RuntimeCardReadCache?) -> Bool {
    lhs?.version == rhs?.version && lhs == rhs
}

extension RuntimeStatusCardPresentation {
    nonisolated func hasSameRenderState(as other: Self) -> Bool {
        inputID == other.inputID && viewModel === other.viewModel
            && runtimeCardSnapshotsMatch(cache, other.cache)
            && revealActionID == other.revealActionID && revealSerial == other.revealSerial
            && {
                switch (itemActions, other.itemActions) {
                case (nil, nil): true
                case (.some(let lhs), .some(let rhs)): lhs.hasSameRenderState(as: rhs)
                default: false
                }
            }()
    }
}

func runtimeCardPresentationsMatch(_ lhs: RuntimeStatusCardPresentation?, _ rhs: RuntimeStatusCardPresentation?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let lhs), .some(let rhs)): lhs.hasSameRenderState(as: rhs)
    default: false
    }
}

extension SessionRuntimeActionSummary {
    var action: AgentStatusAction {
        AgentStatusAction(items: [], label: label, state: state, duration: duration,
            totalItemCount: totalItemCount, remoteID: id, remoteStartedAt: startedAt)
    }
}

struct RuntimeCardEntriesView: View {
    let presentation: RuntimeStatusCardPresentation
    let rowID: String
    let scale: CGFloat
    let isTimelineVisible: Bool
    var actionDisclosure: Binding<AgentStatusCardDisclosure>? = nil

    private func actionBinding(_ actionID: String) -> Binding<Bool>? {
        guard let actionDisclosure else { return nil }
        return Binding(get: { actionDisclosure.wrappedValue.isActionOpen(actionID, cardID: presentation.cache.rows.card.id) },
            set: { actionDisclosure.wrappedValue.setActionOpen($0, actionID: actionID, cardID: presentation.cache.rows.card.id) })
    }

    private var page: SessionRuntimeCardEntriesPage? { presentation.cache.entries[rowID] }
    private var visibleEntries: [SessionRuntimeCardEntry] {
        guard let page else { return [] }
        let candidates: [SessionRuntimeCardEntry]
        if let firstID = presentation.cache.entryStartIDs[rowID], let start = page.entries.firstIndex(where: { $0.id == firstID }) {
            candidates = Array(page.entries.dropFirst(start).suffix(AgentStatusCardDisclosure.initialEntryLimit))
        } else { candidates = Array(page.entries.suffix(AgentStatusCardDisclosure.initialEntryLimit)) }
        let weights = candidates.map { entry -> Int in
            switch entry {
            case .action: TranscriptRenderBudget.statusCardEntryUnits
            case .item(.inline(let item)): TranscriptRenderBudget.weight(of: .single(item))
            case .item(.deferred(let marker)):
                max(TranscriptRenderBudget.otherBlockUnits, marker.preview.text.count * TranscriptRenderBudget.textCharacterUnits)
            }
        }
        let count = TranscriptRenderBudget.allowedBlockCount(weights: weights,
            requestedLimit: AgentStatusCardDisclosure.initialEntryLimit,
            defaultLimit: AgentStatusCardDisclosure.initialEntryLimit, minimumBlocks: 1)
        return Array(candidates.suffix(count))
    }
    /// 「さらに表示」や先頭位置は受信した項目全体で決め、描画だけから表示しない思考を除く。
    private var renderedEntries: [SessionRuntimeCardEntry] {
        let agent = presentation.viewModel.agentRef.builtinKind
        return visibleEntries.filter { !$0.isHiddenReasoning(agent: agent) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let page {
                ForEach(renderedEntries, id: \.id) { entry in
                    switch entry {
                    case .item(let reference):
                        RuntimeChatItemReferenceView(reference: reference, viewModel: presentation.viewModel, actions: presentation.itemActions)
                    case .action(let summary):
                        AgentStatusActionRow(action: summary.action, scale: scale,
                            isTimelineVisible: isTimelineVisible, runtime: presentation, openBinding: actionBinding(summary.id))
                    }
                }
                let start = visibleEntries.first.flatMap { first in page.entries.firstIndex { $0.id == first.id } } ?? 0
                if start > 0 || page.nextCursor != nil {
                    Button("さらに表示") {
                        if start > 0 {
                            presentation.loadEntries(rowID, endingAtID: page.entries[start - 1].id,
                                startingAtID: page.entries.first?.id)
                        } else { presentation.loadEntries(rowID, next: true) }
                    }
                        .buttonStyle(.plain).font(DSFont.meta)
                        .accessibilityIdentifier("AgentStatusCard.showMore")
                }
                if presentation.cache.entryIsLatest[rowID] == false {
                    Button("最新の作業に戻る") {
                        presentation.loadEntries(rowID)
                    }
                    .buttonStyle(.plain).font(DSFont.meta)
                }
            } else {
                Button("作業を読み込む") { presentation.loadEntries(rowID) }
                    .buttonStyle(.plain).font(DSFont.meta)
                    .accessibilityIdentifier("AgentStatusCard.reloadEntries.\(rowID)")
            }
            if let error = presentation.cache.error {
                Text(error).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                Button("再試行") { presentation.retry(rowID) }
            }
        }
        .task(id: presentation.contentVersion) {
            if presentation.cache.entries[rowID] == nil { presentation.loadEntries(rowID) }
        }

    }
}

struct RuntimeChatItemReferenceView: View {
    let reference: SessionRuntimeChatItemReference
    let viewModel: ChatSessionViewModel
    var isActionDetail = false
    var actionScale: CGFloat = 1
    var actions: RuntimeChatItemActions? = nil
    @State private var loading = false
    @State private var error: String?
    @State private var openedReasoning: RuntimeOpenedItem?

    var body: some View {
        // 一覧側で除いたうえでの最後の防御。思考の全文取得（.task）も始めない。
        if reference.isHiddenReasoning(agent: viewModel.agentRef.builtinKind) {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            switch reference {
            case .inline(let item): itemView(item)
            case .deferred(let marker):
                if let opened = openedReasoning?.digest == marker.digest
                    ? openedReasoning : viewModel.runtimeChatRead.openedItems[marker.id], opened.digest == marker.digest {
                    itemView(opened.item)
                } else {
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        Text(marker.preview.displayText)
                            .font(DSFont.row)
                            .foregroundStyle(DSColor.chatTextSecondary)
                            .textSelection(.enabled)
                        if marker.itemKind != "reasoning" || error != nil {
                            Button("全文を表示") { Task { await loadFullItem() } }
                                .disabled(loading)
                                .accessibilityIdentifier("ChatTranscript.showFullItem")
                        }
                        if loading { ProgressView().controlSize(.small) }
                        if let error { Text(error).font(DSFont.meta) }
                    }
                }
            }
        }
        .task(id: reasoningDigest) {
            if reasoningDigest != nil { await loadFullItem() }
        }
    }

    private var reasoningDigest: String? {
        if case .deferred(let marker) = reference, marker.itemKind == "reasoning" { marker.digest }
        else { nil }
    }

    private func loadFullItem() async {
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        do {
            let item = try await viewModel.openRuntimeItem(reference)
            try Task.checkCancellation()
            if case .deferred(let marker) = reference, marker.itemKind == "reasoning" {
                // 共通キャッシュは1件だけなので、表示中の思考は行の寿命まで保持する。
                openedReasoning = RuntimeOpenedItem(digest: marker.digest, item: item)
            }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func itemView(_ item: ChatItem) -> some View {
        if isActionDetail, case .commandExecution(_, let command, let output, _, _, _) = item {
            AgentStatusCommandDetail(command: command, output: output, scale: actionScale)
        } else if isActionDetail, case .fileChange(let id, let changes, let timestamp, _) = item {
            FileChangeCell(changes: changes, timestamp: timestamp, itemID: id, startsExpanded: true)
        } else {
        ChatItemView(item: item, isRunningCommand: false,
            agentDescriptor: AgentRegistry.descriptor(for: viewModel.agentRef.builtinKind),
            onRespondToUserQuestion: { requestID, answers in
                await viewModel.respondToUserQuestion(requestId: requestID, answers: answers)
            }, onDismissUserQuestion: {
                if case .userQuestion(_, let requestID, _, _, _, _) = item {
                    Task { await viewModel.dismissUserQuestion(requestId: requestID) }
                }
            }, turnUsage: viewModel.runtimeChatRead.page?.turnUsageByItemID[item.id],
            onLaunchFailureRestart: item.id == "launch-error-\(viewModel.id.rawValue)" ? actions?.restart : nil,
            isLaunchFailureRestarting: actions?.isRestarting ?? false,
            onLaunchFailureClose: item.id == "launch-error-\(viewModel.id.rawValue)" ? actions?.close : nil)
            .equatable()
        }
    }
}
