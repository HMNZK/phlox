import SwiftUI
import AgentDomain
import DesignSystem

@MainActor
final class RuntimeChatItemActions {
    let restart: (() -> Void)?
    let close: (() -> Void)?
    let isRestarting: Bool

    init(restart: (() -> Void)?, close: (() -> Void)?, isRestarting: Bool) {
        self.restart = restart
        self.close = close
        self.isRestarting = isRestarting
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
    func loadEntries(_ rowID: String, next: Bool = false) {
        guard next || cache.entries[rowID] == nil else { return }
        Task { await perform { try await viewModel.loadRuntimeCardEntries(inputID, rowID: rowID, next: next) } }
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
    @State private var entryEnd: Int?

    private func actionBinding(_ actionID: String) -> Binding<Bool>? {
        guard let actionDisclosure else { return nil }
        return Binding(get: { actionDisclosure.wrappedValue.isActionOpen(actionID, cardID: presentation.cache.rows.card.id) },
            set: { actionDisclosure.wrappedValue.setActionOpen($0, actionID: actionID, cardID: presentation.cache.rows.card.id) })
    }

    private var page: SessionRuntimeCardEntriesPage? { presentation.cache.entries[rowID] }
    private var visibleEntries: [SessionRuntimeCardEntry] {
        guard let page else { return [] }
        let end = min(entryEnd ?? page.entries.count, page.entries.count)
        let candidates = Array(page.entries.prefix(end).suffix(AgentStatusCardDisclosure.initialEntryLimit))
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
        VStack(alignment: .leading, spacing: 0) {
            if let page {
                ForEach(visibleEntries, id: \.id) { entry in
                    switch entry {
                    case .item(let reference):
                        RuntimeChatItemReferenceView(reference: reference, viewModel: presentation.viewModel, actions: presentation.itemActions)
                    case .action(let summary):
                        AgentStatusActionRow(action: summary.action, scale: scale,
                            isTimelineVisible: isTimelineVisible, runtime: presentation, openBinding: actionBinding(summary.id))
                    }
                }
                if (entryEnd ?? page.entries.count) - visibleEntries.count > 0 || page.nextCursor != nil {
                    Button("さらに表示") {
                        let start = (entryEnd ?? page.entries.count) - visibleEntries.count
                        if start > 0 { entryEnd = start }
                        else { entryEnd = nil; presentation.loadEntries(rowID, next: true) }
                    }
                        .buttonStyle(.plain).font(DSFont.meta)
                        .accessibilityIdentifier("AgentStatusCard.showMore")
                }
                if entryEnd != nil || presentation.cache.entryIsLatest[rowID] == false {
                    Button("最新の作業に戻る") {
                        entryEnd = nil
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
        .onChange(of: page?.entries.first?.id) { _, _ in entryEnd = nil }
        .onChange(of: presentation.revealSerial, initial: true) { _, _ in
            if let actionID = presentation.revealActionID,
               let index = page?.entries.firstIndex(where: { $0.id == actionID }) { entryEnd = index + 1 }
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
