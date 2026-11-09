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

    var hasMoreRows: Bool { cache.rowOffset + 8 < cache.rows.rows.count || cache.rows.nextCursor != nil }
    var contentVersion: String { "\(cache.rows.card.revision)-\(cache.rows.card.contentRevision)" }

    var card: AgentStatusCard {
        AgentStatusCard(id: cache.rows.card.id, header: cache.rows.card.header,
            rows: cache.rows.rows.dropFirst(cache.rowOffset).prefix(8).map { row in
                let entries = cache.entries[row.id]?.entries.compactMap { entry -> AgentStatusEntry? in
                    switch entry {
                    case .action(let summary): .action(summary.action)
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
            }, totalRowCount: cache.rows.card.totalRowCount, hasTask: cache.rows.card.hasTasks)
    }

    @MainActor
    func loadEntries(_ rowID: String, next: Bool = false, endingAtID: String? = nil, startingAtID: String? = nil) {
        guard next || endingAtID != nil || cache.entries[rowID] == nil else { return }
        Task { await perform {
            try await viewModel.loadRuntimeCardEntries(inputID, rowID: rowID, next: next,
                aroundEntryID: endingAtID, startingAtID: startingAtID)
        } }
    }

    @MainActor
    func loadAction(_ actionID: String, next: Bool = false) {
        guard next || cache.actions[actionID] == nil else { return }
        Task { await perform { try await viewModel.loadRuntimeActionItems(inputID, actionID: actionID, next: next) } }
    }

    @MainActor
    func loadRows(_ navigation: RuntimeCardRowNavigation) {
        Task { await perform { try await viewModel.loadRuntimeCardRows(inputID, navigation: navigation) } }
    }

    @MainActor
    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            viewModel.runtimeChatRead.cards[inputID]?.error = nil
        } catch {
            viewModel.runtimeChatRead.cards[inputID]?.error = error.localizedDescription
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

/// A closed action has no local cursor or detail task. Keep its header independent of unrelated card updates.
private struct RuntimeCardActionEntry: View, Equatable {
    let summary: SessionRuntimeActionSummary
    let rowID: String
    let scale: CGFloat
    let isTimelineVisible: Bool
    private let runtime: RuntimeStatusCardPresentation
    private let openBinding: Binding<Bool>?
    private let openSnapshot: Bool?

    init(summary: SessionRuntimeActionSummary, rowID: String, scale: CGFloat, isTimelineVisible: Bool,
         presentation: RuntimeStatusCardPresentation, openBinding: Binding<Bool>?) {
        self.summary = summary
        self.rowID = rowID
        self.scale = scale
        self.isTimelineVisible = isTimelineVisible
        self.openBinding = openBinding
        let openSnapshot = openBinding?.wrappedValue
        self.openSnapshot = openSnapshot
        let source = presentation.cache
        let rows = SessionRuntimeCardRowsPage(sessionID: source.rows.sessionID, executionID: source.rows.executionID,
            card: source.rows.card, rows: [], nextCursor: nil)
        var ownCache = RuntimeCardReadCache(rows: rows, version: source.version, error: source.error)
        if openSnapshot != false {
            ownCache.actions[summary.id] = source.actions[summary.id]
            ownCache.actionPageOffsets[summary.id] = source.actionPageOffsets[summary.id]
        }
        runtime = RuntimeStatusCardPresentation(inputID: presentation.inputID, cache: ownCache,
            viewModel: presentation.viewModel, revealActionID: presentation.revealActionID,
            revealSerial: presentation.revealSerial, itemActions: presentation.itemActions)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.summary == rhs.summary, lhs.rowID == rhs.rowID, lhs.scale == rhs.scale,
              lhs.isTimelineVisible == rhs.isTimelineVisible, lhs.openSnapshot == rhs.openSnapshot,
              lhs.runtime.viewModel === rhs.runtime.viewModel, lhs.runtime.inputID == rhs.runtime.inputID,
              lhs.runtime.cache.rows.sessionID == rhs.runtime.cache.rows.sessionID,
              lhs.runtime.cache.rows.executionID == rhs.runtime.cache.rows.executionID,
              lhs.runtime.cache.rows.card.id == rhs.runtime.cache.rows.card.id,
              lhs.runtime.revealActionID == rhs.runtime.revealActionID, lhs.runtime.revealSerial == rhs.runtime.revealSerial else { return false }
        switch (lhs.runtime.itemActions, rhs.runtime.itemActions) {
        case (nil, nil): break
        case (.some(let left), .some(let right)):
            guard left.hasSameRenderState(as: right) else { return false }
        default: return false
        }
        if lhs.openSnapshot == false { return true }
        // Open and locally owned actions retain structure/content versions, errors, own details and their cursors.
        return runtimeCardPresentationsMatch(lhs.runtime, rhs.runtime)
    }

    var body: some View {
        AgentStatusActionRow(action: summary.action, scale: scale, isTimelineVisible: isTimelineVisible,
            runtime: runtime, openBinding: openBinding)
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
        let cardID = presentation.cache.rows.card.id
        return Binding(get: { actionDisclosure.wrappedValue.isActionOpen(actionID, cardID: cardID) },
            set: { actionDisclosure.wrappedValue.setActionOpen($0, actionID: actionID, cardID: cardID) })
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

    var body: some View {
        let visible = visibleEntries
        return VStack(alignment: .leading, spacing: 0) {
            if let page {
                ForEach(visible, id: \.id) { entry in
                    switch entry {
                    case .item(let reference):
                        RuntimeChatItemReferenceView(reference: reference, viewModel: presentation.viewModel, actions: presentation.itemActions)
                    case .action(let summary):
                        RuntimeCardActionEntry(summary: summary, rowID: rowID, scale: scale,
                            isTimelineVisible: isTimelineVisible, presentation: presentation, openBinding: actionBinding(summary.id))
                            .equatable()
                    }
                }
                let start = visible.first.flatMap { first in page.entries.firstIndex { $0.id == first.id } } ?? 0
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
                        Task { try? await presentation.viewModel.loadRuntimeCardEntries(presentation.inputID, rowID: rowID) }
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
                Button("再試行") {
                    Task { try? await presentation.viewModel.loadRuntimeCardEntries(presentation.inputID, rowID: rowID) }
                }
            }
        }
        .task(id: presentation.contentVersion) { presentation.loadEntries(rowID) }

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

    var body: some View {
        switch reference {
        case .inline(let item): itemView(item)
        case .deferred(let marker):
            if let opened = viewModel.runtimeChatRead.openedItems[marker.id], opened.digest == marker.digest {
                itemView(opened.item)
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    Text(marker.preview.displayText)
                        .font(DSFont.row)
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .textSelection(.enabled)
                    Button("全文を表示") {
                        loading = true
                        Task {
                            defer { loading = false }
                            do { _ = try await viewModel.openRuntimeItem(reference); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(loading)
                    .accessibilityIdentifier("ChatTranscript.showFullItem")
                    if loading { ProgressView().controlSize(.small) }
                    if let error { Text(error).font(DSFont.meta) }
                }
            }
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
