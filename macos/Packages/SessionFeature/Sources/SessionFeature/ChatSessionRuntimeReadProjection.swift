import Foundation

struct RuntimeChatReadProjection {
    let epoch = UUID()
    var page: SessionRuntimeChatReadPage?
    var history: SessionRuntimeInputHistoryPage?
    var latestHistory: [SessionRuntimeInputHistorySummary] = []
    var cards: [String: RuntimeCardReadCache] = [:]
    var openedItems: [String: RuntimeOpenedItem] = [:]
    var followsTail = true
    var anchorInputID: String?
    var anchorItemID: String?
    var generation: UInt64 = 0
    var appliedIntentToken: UUID?
    var isLoading = false
    var isLoadingHistory = false
    var error: String?
    var historyError: String?
    var recall = RuntimeInputRecall()
    let control = RuntimeChatReadControl()

    var historyEntries: [InputHistoryEntry] { history?.entries.map(\.displayEntry) ?? [] }
    var latestEntries: [InputHistoryEntry] { latestHistory.map(\.displayEntry) }
    var hasEarlierHistory: Bool { history?.olderCursor != nil }
}

@MainActor
final class RuntimeChatReadControl {
    var timelineLoadTask: Task<Void, Error>?
    var queueTail: Task<Void, Never>?
    var inFlight: [Data: RuntimeChatReadFlight] = [:]
    var renderedSpans: [UUID: RuntimeChatRenderedSpan] = [:]
    var cardOperationGeneration: UInt64 = 0
    var activeCardOperations = 0
    var needsContentCatchUp = false
    var catchUpScheduled = false

    nonisolated init() {}
}

struct RuntimeChatRenderedSpan: Equatable {
    let executionID: UUID
    let epoch: UUID
    let intentToken: UUID?
    let firstID: String
    let lastID: String
    let count: Int
}

private struct RuntimeReadTransactionContext {
    let executionID: UUID
    let epoch: UUID
    let generation: UInt64
    let cardOperationGeneration: UInt64
}

struct RuntimeOpenedItem {
    let digest: String
    let item: ChatItem
}

struct RuntimeChatReadFlight {
    let token: UUID
    let task: Task<SessionRuntimeContentResponse, Error>
}

struct RuntimeInputRecall {
    var history: SessionRuntimeInputHistoryPage?
    var selectedID: String?
    var savedDraft = ""
    var recalledText: String?
    var isLoading = false
}

private struct RuntimeInputRecallRequest {
    let direction: InputHistoryCursor.Direction
    let originalDraft: String
    let executionID: UUID
    let epoch: UUID
}

enum RuntimeCardRowNavigation {
    case refresh, next, first, active, around(String)
}

struct RuntimeCardReadCache: Sendable, Equatable {
    var isRowWindowManual = false
    var startsAtBeginning = true
    var rows: SessionRuntimeCardRowsPage
    var rowOffset = 0
    var entryIsLatest: [String: Bool] = [:]
    var entryStartIDs: [String: String] = [:]
    var actionPageOffsets: [String: Int] = [:]
    var entries: [String: SessionRuntimeCardEntriesPage] = [:]
    var actions: [String: SessionRuntimeActionItemsPage] = [:]
    var version: UInt64 = 0
    var byteCounts: [String: Int] = [:]
    var error: String?
}

extension SessionRuntimeInputHistorySummary {
    var displayEntry: InputHistoryEntry {
        InputHistoryEntry(id: id, text: preview.displayText, timestamp: timestamp)
    }
}

extension ChatSessionViewModel {
    var usesRuntimeChatReadModel: Bool { isRuntimeProjection && runtimeSupportsChatReadModel }

    func refreshRuntimeChatRead() async throws {
        guard usesRuntimeChatReadModel else { return }
        // A refresh must not supersede an explicit jump before its page has been applied.
        // Wait for that navigation, then refresh its committed position once.
        while let navigation = runtimeChatRead.control.timelineLoadTask {
            // The explicit operation reports its own failure; refresh the last committed page.
            do { try await navigation.value } catch { }
        }
        let target: SessionRuntimeContentRequest.Target
        if let itemID = runtimeChatRead.anchorItemID {
            target = .chatReadAroundItem(itemID: itemID)
        } else if !runtimeChatRead.followsTail, let inputID = runtimeChatRead.anchorInputID {
            target = .chatReadAround(inputID: inputID)
        } else { target = .chatReadTail }
        try await startRuntimeChatRead(target: target, preservingWindow: true, intentToken: nil)
        try await loadRuntimeInputHistory(refreshLatest: true)
    }

    func loadRuntimeChatRead(target: SessionRuntimeContentRequest.Target, intentToken: UUID? = nil) async throws {
        try await startRuntimeChatRead(target: target, preservingWindow: false, intentToken: intentToken)
    }

    private func startRuntimeChatRead(target: SessionRuntimeContentRequest.Target, preservingWindow: Bool,
                                      intentToken: UUID?) async throws {
        guard usesRuntimeChatReadModel else { throw SessionRuntimeContentError.invalidRequest }
        let old = runtimeChatRead
        let committedIntent = intentToken ?? (preservingWindow ? nil : UUID())
        let epoch = old.epoch
        let cardOperationGeneration = old.control.cardOperationGeneration
        let span = old.control.renderedSpans.count == 1 ? old.control.renderedSpans.values.first : nil
        let rendered = span.flatMap { hint -> RuntimeChatRenderedSpan? in
            hint.executionID == executionID && hint.epoch == epoch && hint.intentToken == old.appliedIntentToken ? hint : nil
        }
        runtimeChatRead.generation &+= 1
        let generation = runtimeChatRead.generation
        let execution = executionID
        runtimeChatRead.isLoading = true
        let task = Task {
            defer {
                if runtimeChatRead.generation == generation {
                    runtimeChatRead.isLoading = false
                    runtimeChatRead.control.timelineLoadTask = nil
                    scheduleRuntimeContentCatchUpIfReady(control: old.control, execution: execution, epoch: epoch)
                }
            }
            try await applyRuntimeChatRead(target: target, generation: generation, execution: execution,
                epoch: epoch, old: old, cardOperationGeneration: cardOperationGeneration,
                preservingWindow: preservingWindow, rendered: rendered, intentToken: committedIntent)
        }
        runtimeChatRead.control.timelineLoadTask = task
        try await task.value
    }

    private func applyRuntimeChatRead(target: SessionRuntimeContentRequest.Target,
                                      generation: UInt64, execution: UUID, epoch: UUID,
                                      old: RuntimeChatReadProjection, cardOperationGeneration: UInt64,
                                      preservingWindow: Bool,
                                      rendered: RuntimeChatRenderedSpan?, intentToken: UUID?) async throws {
        do {
            let context = RuntimeReadTransactionContext(executionID: execution, epoch: epoch,
                generation: generation, cardOperationGeneration: cardOperationGeneration)
            let page: SessionRuntimeChatReadPage
            if preservingWindow, let previous = old.page {
                page = try await refreshedRuntimeWindow(previous, followsTail: old.followsTail,
                    rendered: rendered, context: context)
            } else {
                let incoming = try await readRuntimeTimeline(target)
                page = try mergedRuntimeReadPage(incoming, target: target)
            }
            var prepared: [String: RuntimeCardReadCache] = [:]
            for block in page.blocks {
                try validateRuntimeReadContext(context)
                if case .card(let summary) = block.content {
                    prepared[summary.inputID] = try await preparedRuntimeCard(summary,
                        old: old.cards[summary.inputID], context: context)
                }
            }
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  generation == runtimeChatRead.generation else { return }
            // A row/detail operation performed while this transaction waited wins.
            let affected = Set(old.cards.keys).union(prepared.keys)
            guard runtimeChatRead.control.cardOperationGeneration == cardOperationGeneration,
                  affected.allSatisfy({ runtimeChatRead.cards[$0]?.version == old.cards[$0]?.version }) else {
                if preservingWindow { runtimeChatRead.control.needsContentCatchUp = true }
                return
            }
            guard prepared.count <= TranscriptWindow.defaultLimit * TranscriptWindow.maxStages,
                  prepared.values.reduce(0, { $0 + $1.byteCounts.values.reduce(0, +) }) <= 4 * 1024 * 1024 else {
                throw SessionRuntimeContentError.invalidRequest
            }
            var next = runtimeChatRead
            next.page = page
            next.appliedIntentToken = preservingWindow ? old.appliedIntentToken : intentToken
            next.cards = prepared
            switch target {
            case .chatReadTail:
                next.followsTail = true; next.anchorInputID = nil; next.anchorItemID = nil
            case .chatReadAround(let inputID):
                next.followsTail = false; next.anchorInputID = inputID; next.anchorItemID = nil
            case .chatReadAroundItem(let itemID):
                next.followsTail = false; next.anchorInputID = nil; next.anchorItemID = itemID
            case .chatReadBefore, .chatReadAfter:
                next.followsTail = false; next.anchorInputID = nil; next.anchorItemID = nil
            default: break
            }
            if !next.followsTail, next.anchorInputID == nil {
                next.anchorInputID = page.blocks.compactMap(\.ownerInputID).first
            }
            next.error = nil
            runtimeChatRead = next
        } catch {
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  generation == runtimeChatRead.generation else { return }
            guard runtimeChatRead.control.cardOperationGeneration == cardOperationGeneration else {
                if preservingWindow { runtimeChatRead.control.needsContentCatchUp = true }
                return
            }
            runtimeChatRead.error = error.localizedDescription
            throw error
        }
    }

    private func beginRuntimeCardOperation() -> RuntimeChatReadControl {
        let control = runtimeChatRead.control
        control.cardOperationGeneration &+= 1
        control.activeCardOperations += 1
        return control
    }

    private func endRuntimeCardOperation(control: RuntimeChatReadControl, execution: UUID, epoch: UUID) {
        control.activeCardOperations -= 1
        scheduleRuntimeContentCatchUpIfReady(control: control, execution: execution, epoch: epoch)
    }

    private func scheduleRuntimeContentCatchUpIfReady(control: RuntimeChatReadControl, execution: UUID, epoch: UUID) {
        guard executionID == execution, runtimeChatRead.epoch == epoch, runtimeChatRead.control === control,
              control.needsContentCatchUp, control.activeCardOperations == 0,
              control.timelineLoadTask == nil, !control.catchUpScheduled else { return }
        control.needsContentCatchUp = false
        control.catchUpScheduled = true
        Task {
            defer {
                control.catchUpScheduled = false
                scheduleRuntimeContentCatchUpIfReady(control: control, execution: execution, epoch: epoch)
            }
            guard executionID == execution, runtimeChatRead.epoch == epoch, runtimeChatRead.control === control else { return }
            // refreshRuntimeContent coalesces with its existing task; a genuine read failure is not retried.
            try? await refreshRuntimeContent()
        }
    }

    private func validateRuntimeReadContext(_ context: RuntimeReadTransactionContext?) throws {
        guard let context else { return }
        guard executionID == context.executionID, runtimeChatRead.epoch == context.epoch,
              runtimeChatRead.generation == context.generation,
              runtimeChatRead.control.cardOperationGeneration == context.cardOperationGeneration else {
            throw CancellationError()
        }
    }

    private func readRuntimeTimeline(_ target: SessionRuntimeContentRequest.Target) async throws -> SessionRuntimeChatReadPage {
        let execution = executionID
        let response = try await readRuntimeChat(target)
        guard case .chatReadPage(let page) = response, page.sessionID == id, page.executionID == execution,
              page.blocks.count <= SessionRuntimeChatReadLimits.maximumItemsPerPage else {
            throw SessionRuntimeContentError.staleContent
        }
        return page
    }

    private func refreshedRuntimeWindow(_ previous: SessionRuntimeChatReadPage, followsTail: Bool,
                                         rendered: RuntimeChatRenderedSpan?, context: RuntimeReadTransactionContext) async throws -> SessionRuntimeChatReadPage {
        try validateRuntimeReadContext(context)
        let wantedFirst = rendered?.firstID ?? previous.blocks.first?.id
        let wantedLast = rendered?.lastID ?? previous.blocks.last?.id
        guard let wantedFirst, let wantedLast,
              let firstBlock = previous.blocks.first(where: { $0.id == wantedFirst }) else {
            return try await readRuntimeTimeline(.chatReadTail)
        }
        let target: SessionRuntimeContentRequest.Target
        if followsTail { target = .chatReadTail }
        else {
            switch firstBlock.content {
            case .item(let item): target = .chatReadAroundItem(itemID: item.id)
            case .commandGroup(let action): target = .chatReadAroundItem(itemID: action.id)
            case .card(let card): target = .chatReadAround(inputID: card.inputID)
            }
        }
        var result = try await readRuntimeTimeline(target)
        let freshTail = result
        let maximum = TranscriptWindow.defaultLimit * TranscriptWindow.maxStages
        if followsTail, result.revision == previous.revision,
           result.totalBlockCount - previous.startIndex > maximum { return freshTail }
        var blocks = result.blocks
        var start = result.startIndex
        var usage = result.turnUsageByItemID
        let structure = result.revision
        for _ in 0..<maximum {
            try validateRuntimeReadContext(context)
            let foundFirst = blocks.contains { $0.id == wantedFirst }
            let foundLast = blocks.contains { $0.id == wantedLast }
            if foundFirst && (followsTail || foundLast) { break }
            let cursor = followsTail ? result.olderCursor : result.newerCursor
            guard let cursor else {
                if followsTail { return freshTail }
                throw SessionRuntimeContentError.staleContent
            }
            let page = try await readRuntimeTimeline(followsTail ? .chatReadBefore(cursor: cursor) : .chatReadAfter(cursor: cursor))
            guard page.executionID == result.executionID, page.revision == structure, !page.blocks.isEmpty else {
                throw SessionRuntimeContentError.staleContent
            }
            if followsTail {
                guard page.startIndex + page.blocks.count == start else { throw SessionRuntimeContentError.staleContent }
                blocks = page.blocks + blocks
                start = page.startIndex
            } else {
                guard page.startIndex == start + blocks.count else { throw SessionRuntimeContentError.staleContent }
                blocks += page.blocks
            }
            usage.merge(page.turnUsageByItemID) { _, new in new }
            result = page
            // Context before the required first block is expendable, never the requested span.
            if let first = blocks.firstIndex(where: { $0.id == wantedFirst }), first > 0 {
                blocks.removeFirst(first); start += first
            }
            guard blocks.count <= maximum,
                  try blocks.reduce(0, { try $0 + JSONEncoder().encode($1).count }) <= 4 * 1024 * 1024 else {
                if followsTail { return freshTail }
                throw SessionRuntimeContentError.invalidRequest
            }
        }
        if followsTail, !blocks.contains(where: { $0.id == wantedFirst }) { return freshTail }
        guard let first = blocks.firstIndex(where: { $0.id == wantedFirst }),
              let last = followsTail ? blocks.indices.last : blocks.firstIndex(where: { $0.id == wantedLast }), first <= last else {
            throw SessionRuntimeContentError.staleContent
        }
        let kept = Array(blocks[first...last])
        start += first
        let finish = start + kept.count
        let ids = Set(kept.map(\.id))
        var refreshed = SessionRuntimeChatReadPage(sessionID: id, executionID: result.executionID,
            transcriptRevision: result.transcriptRevision, revision: structure,
            totalBlockCount: result.totalBlockCount, startIndex: start, blocks: kept,
            olderCursor: start > 0 ? .init(scopeID: "timeline", revision: structure, index: start, anchorID: kept[0].id) : nil,
            newerCursor: finish < result.totalBlockCount ? .init(scopeID: "timeline", revision: structure,
                index: finish - 1, anchorID: kept[kept.count - 1].id) : nil,
            latestHeader: result.latestHeader, turnUsageByItemID: usage.filter { ids.contains($0.key) })
        if let reveal = previous.revealTarget, ids.contains(reveal.scrollTargetID) { refreshed.revealTarget = reveal }
        return refreshed
    }

    private func preparedRuntimeCard(_ summary: SessionRuntimeCardSummary, old: RuntimeCardReadCache?,
                                     navigation: RuntimeCardRowNavigation = .refresh,
                                     force: Bool = false,
                                     context: RuntimeReadTransactionContext? = nil) async throws -> RuntimeCardReadCache {
        try validateRuntimeReadContext(context)
        if !force, case .refresh = navigation, let old, old.rows.card.revision == summary.revision,
           old.rows.card.contentRevision >= summary.contentRevision { return old }
        var prepared = try await fetchedRuntimeCardRows(summary, old: old, navigation: navigation)
        try validateRuntimeReadContext(context)
        guard let old else { return prepared }
        if old.rows.card.revision == prepared.rows.card.revision,
           old.rows.card.contentRevision == prepared.rows.card.contentRevision {
            prepared.entries = old.entries
            prepared.actions = old.actions
            prepared.entryIsLatest = old.entryIsLatest
            prepared.entryStartIDs = old.entryStartIDs
            prepared.actionPageOffsets = old.actionPageOffsets
            prepared.byteCounts.merge(old.byteCounts.filter { $0.key != "rows" }) { _, old in old }
            return prepared
        }
        // Rebuild the already fetched detail windows before publishing the new card metadata.
        prepared.entryIsLatest = old.entryIsLatest
        prepared.entryStartIDs = old.entryStartIDs
        prepared.actionPageOffsets = old.actionPageOffsets
        var removedRows = Set<String>()
        for (rowID, previous) in old.entries {
            try validateRuntimeReadContext(context)
            let lastID = old.entryIsLatest[rowID] == false ? previous.entries.last?.id : nil
            guard let page = try await refreshedRuntimeEntries(inputID: summary.inputID, rowID: rowID,
                lastID: lastID, card: prepared.rows.card, execution: prepared.rows.executionID) else {
                removedRows.insert(rowID)
                prepared.entryIsLatest.removeValue(forKey: rowID)
                prepared.entryStartIDs.removeValue(forKey: rowID)
                continue
            }
            if let lastID, page.entries.last?.id != lastID {
                prepared.entryIsLatest[rowID] = true
                prepared.entryStartIDs.removeValue(forKey: rowID)
            }
            prepared.entries[rowID] = page
            prepared.byteCounts["entries-\(rowID)"] = try JSONEncoder().encode(page).count
        }
        for actionID in old.actions.keys {
            try validateRuntimeReadContext(context)
            let belongedToRemovedRow = old.entries.contains { rowID, page in
                removedRows.contains(rowID) && page.entries.contains { $0.id == actionID }
            }
            if belongedToRemovedRow {
                prepared.actionPageOffsets.removeValue(forKey: actionID)
                continue
            }
            let firstID = old.actions[actionID]?.items.first?.id
            guard let page = try await refreshedRuntimeActionItems(inputID: summary.inputID, actionID: actionID,
                firstID: firstID, card: prepared.rows.card, execution: prepared.rows.executionID) else {
                prepared.actionPageOffsets.removeValue(forKey: actionID)
                continue
            }
            prepared.actions[actionID] = page
            if let firstID, page.items.first?.id != firstID { prepared.actionPageOffsets[actionID] = 0 }
            prepared.byteCounts["actions-\(actionID)"] = try JSONEncoder().encode(page).count
        }
        return prepared
    }

    private func refreshedRuntimeEntries(inputID: String, rowID: String, lastID: String?,
                                         card: SessionRuntimeCardSummary, execution: UUID) async throws -> SessionRuntimeCardEntriesPage? {
        let target: SessionRuntimeContentRequest.Target = lastID.map {
            .chatRowEntriesAround(inputID: inputID, rowID: rowID, entryID: $0)
        } ?? .chatRowEntries(inputID: inputID, rowID: rowID, cursor: nil)
        let response: SessionRuntimeContentResponse
        do { response = try await readRuntimeChat(target) }
        catch SessionRuntimeContentError.notFound {
            // A removed manual boundary is different from a removed row: verify the row once.
            guard lastID != nil else { return nil }
            do { response = try await readRuntimeChat(.chatRowEntries(inputID: inputID, rowID: rowID, cursor: nil)) }
            catch SessionRuntimeContentError.notFound { return nil }
        }
        guard case .cardEntriesPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.inputID == inputID, page.rowID == rowID,
              page.revision == card.revision else { throw SessionRuntimeContentError.staleContent }
        return page
    }

    private func refreshedRuntimeActionItems(inputID: String, actionID: String, firstID: String?,
                                             card: SessionRuntimeCardSummary, execution: UUID) async throws -> SessionRuntimeActionItemsPage? {
        let target: SessionRuntimeContentRequest.Target = firstID.map {
            .chatActionItemsFrom(inputID: inputID, actionID: actionID, itemID: $0)
        } ?? .chatActionItems(inputID: inputID, actionID: actionID, cursor: nil)
        let response: SessionRuntimeContentResponse
        do { response = try await readRuntimeChat(target) }
        catch SessionRuntimeContentError.notFound {
            // Verify the action once if only the old first-item boundary was removed.
            guard firstID != nil else { return nil }
            do { response = try await readRuntimeChat(.chatActionItems(inputID: inputID, actionID: actionID, cursor: nil)) }
            catch SessionRuntimeContentError.notFound { return nil }
        }
        guard case .actionItemsPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.inputID == inputID, page.actionID == actionID,
              page.revision == card.revision else { throw SessionRuntimeContentError.staleContent }
        return page
    }

    private func mergedRuntimeReadPage(_ incoming: SessionRuntimeChatReadPage,
                                       target: SessionRuntimeContentRequest.Target) throws -> SessionRuntimeChatReadPage {
        guard let current = runtimeChatRead.page, current.executionID == incoming.executionID,
              current.revision == incoming.revision else { return incoming }
        var combined: [SessionRuntimeChatReadBlock]
        var start: Int
        let older: Bool
        switch target {
        case .chatReadBefore where incoming.startIndex + incoming.blocks.count == current.startIndex:
            combined = incoming.blocks + current.blocks
            start = incoming.startIndex
            older = true
        case .chatReadAfter where current.startIndex + current.blocks.count == incoming.startIndex:
            combined = current.blocks + incoming.blocks
            start = current.startIndex
            older = false
        default: return incoming
        }
        var costs = try combined.map { try JSONEncoder().encode($0).count }
        var bytes = costs.reduce(0, +)
        while combined.count > TranscriptWindow.defaultLimit * TranscriptWindow.maxStages || bytes > 4 * 1024 * 1024 {
            if older { combined.removeLast(); bytes -= costs.removeLast() }
            else { combined.removeFirst(); bytes -= costs.removeFirst(); start += 1 }
        }
        let finish = start + combined.count
        let olderCursor = start > 0 ? combined.first.map {
            SessionRuntimeChatReadCursor(scopeID: "timeline", revision: incoming.revision, index: start, anchorID: $0.id)
        } : nil
        let newerCursor = finish < incoming.totalBlockCount ? combined.last.map {
            SessionRuntimeChatReadCursor(scopeID: "timeline", revision: incoming.revision, index: finish - 1, anchorID: $0.id)
        } : nil
        let ids = Set(combined.map(\.id))
        let usage = current.turnUsageByItemID.merging(incoming.turnUsageByItemID) { _, new in new }.filter { ids.contains($0.key) }
        return SessionRuntimeChatReadPage(sessionID: id, executionID: incoming.executionID,
            transcriptRevision: incoming.transcriptRevision, revision: incoming.revision,
            totalBlockCount: incoming.totalBlockCount, startIndex: start, blocks: combined,
            olderCursor: olderCursor, newerCursor: newerCursor,
            latestHeader: incoming.latestHeader, turnUsageByItemID: usage)
    }

    func loadRuntimeInputHistory(earlier: Bool = false, newer: Bool = false, refreshLatest: Bool = false) async throws {
        guard usesRuntimeChatReadModel, !runtimeChatRead.isLoadingHistory else { return }
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let target: SessionRuntimeContentRequest.Target
        if earlier {
            guard let cursor = runtimeChatRead.history?.olderCursor else { return }
            target = .inputHistory(before: cursor)
        } else if newer {
            guard let cursor = runtimeChatRead.history?.newerCursor else { return }
            target = .inputHistoryAfter(cursor: cursor)
        } else { target = .inputHistory(before: nil) }
        runtimeChatRead.isLoadingHistory = true
        defer { if executionID == execution, runtimeChatRead.epoch == epoch { runtimeChatRead.isLoadingHistory = false } }
        do {
            let response = try await readRuntimeChat(target)
            guard executionID == execution, runtimeChatRead.epoch == epoch else {
                throw SessionRuntimeContentError.staleContent
            }
            guard case .inputHistoryPage(let page) = response, page.sessionID == id,
                  page.executionID == execution else { throw SessionRuntimeContentError.staleContent }
            if !refreshLatest || runtimeChatRead.history == nil || runtimeChatRead.history?.newerCursor == nil
                || runtimeChatRead.history?.revision != page.revision {
                runtimeChatRead.history = page
            }
            if !earlier && !newer { runtimeChatRead.latestHistory = Array(page.entries.suffix(12)) }
            runtimeChatRead.historyError = nil
        } catch {
            if executionID == execution, runtimeChatRead.epoch == epoch { runtimeChatRead.historyError = error.localizedDescription }
            throw error
        }
    }

    func loadRuntimeCardRows(_ inputID: String, navigation: RuntimeCardRowNavigation = .refresh) async throws {
        let old = runtimeChatRead.cards[inputID]
        if case .next = navigation, let old, old.rowOffset + 8 < old.rows.rows.count {
            runtimeChatRead.cards[inputID]?.rowOffset += 8
            runtimeChatRead.cards[inputID]?.isRowWindowManual = true
            runtimeChatRead.cards[inputID]?.version &+= 1
            return
        }
        if case .next = navigation, old?.rows.nextCursor == nil { return }
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let summary = runtimeChatRead.page?.blocks.compactMap { block -> SessionRuntimeCardSummary? in
            if case .card(let value) = block.content, value.inputID == inputID { value } else { nil }
        }.first ?? old?.rows.card
        guard let summary else { throw SessionRuntimeContentError.notFound }
        // Record the operation before awaiting, so a pending transaction cannot beat it to publication.
        let control = beginRuntimeCardOperation()
        defer { endRuntimeCardOperation(control: control, execution: execution, epoch: epoch) }
        // Explicit row operations still fetch; the view avoids redundant automatic refreshes.
        let prepared = try await preparedRuntimeCard(summary, old: old, navigation: navigation, force: true)
        guard execution == executionID, runtimeChatRead.epoch == epoch,
              runtimeChatRead.cards[inputID]?.version == old?.version else { return }
        runtimeChatRead.cards[inputID] = prepared
        trimRuntimeCardCache(keeping: inputID)
    }

    private func fetchedRuntimeCardRows(_ summary: SessionRuntimeCardSummary, old: RuntimeCardReadCache?,
                                       navigation: RuntimeCardRowNavigation) async throws -> RuntimeCardReadCache {
        let inputID = summary.inputID
        let execution = executionID
        let target: SessionRuntimeContentRequest.Target
        let manual: Bool
        let first: Bool
        switch navigation {
        case .next:
            guard let cursor = old?.rows.nextCursor else { throw SessionRuntimeContentError.invalidRequest }
            target = .chatCardRows(inputID: inputID, cursor: cursor)
            manual = true; first = false
        case .first:
            target = .chatCardRows(inputID: inputID, cursor: nil)
            manual = true; first = true
        case .around(let rowID):
            target = .chatCardRowsAround(inputID: inputID, rowID: rowID)
            manual = true; first = false
        case .refresh, .active:
            let rowID: String?
            if case .refresh = navigation, old?.isRowWindowManual == true {
                rowID = old.flatMap { $0.rows.rows.dropFirst($0.rowOffset).first?.id }
                manual = true
            } else { rowID = summary.activeRowID; manual = false }
            if let rowID {
                target = .chatCardRowsAround(inputID: inputID, rowID: rowID); first = false
            } else {
                target = .chatCardRows(inputID: inputID, cursor: nil); first = true
            }
        }
        let response: SessionRuntimeContentResponse
        var recoveredManualBoundary = false
        do { response = try await readRuntimeChat(target) }
        catch SessionRuntimeContentError.notFound {
            guard case .refresh = navigation, old?.isRowWindowManual == true else { throw SessionRuntimeContentError.notFound }
            let fallback: SessionRuntimeContentRequest.Target = summary.activeRowID.map {
                .chatCardRowsAround(inputID: inputID, rowID: $0)
            } ?? .chatCardRows(inputID: inputID, cursor: nil)
            response = try await readRuntimeChat(fallback)
            recoveredManualBoundary = true
        }
        guard case .cardRowsPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.card.inputID == inputID,
              page.card.revision == summary.revision, page.card.contentRevision >= summary.contentRevision else {
            throw SessionRuntimeContentError.staleContent
        }
        return RuntimeCardReadCache(isRowWindowManual: recoveredManualBoundary ? false : manual,
            startsAtBeginning: recoveredManualBoundary ? summary.activeRowID == nil : first, rows: page,
            version: (old?.version ?? 0) &+ 1, byteCounts: ["rows": try JSONEncoder().encode(page).count])
    }

    func loadRuntimeCardEntries(_ inputID: String, rowID: String, next: Bool = false,
                                aroundEntryID: String? = nil, startingAtID: String? = nil) async throws {
        guard let cache = runtimeChatRead.cards[inputID] else { return }
        let cursor = next ? cache.entries[rowID]?.nextCursor : nil
        guard !next || cursor != nil else { return }
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let control = beginRuntimeCardOperation()
        defer { endRuntimeCardOperation(control: control, execution: execution, epoch: epoch) }
        let revision = cache.rows.card.revision
        let target: SessionRuntimeContentRequest.Target
        if let aroundEntryID { target = .chatRowEntriesAround(inputID: inputID, rowID: rowID, entryID: aroundEntryID) }
        else { target = .chatRowEntries(inputID: inputID, rowID: rowID, cursor: cursor) }
        let response = try await readRuntimeChat(target)
        guard execution == executionID else { return }
        guard case .cardEntriesPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.inputID == inputID, page.rowID == rowID,
              page.revision == revision, runtimeChatRead.cards[inputID]?.rows.card.revision == revision else {
            throw SessionRuntimeContentError.staleContent
        }
        guard var updated = runtimeChatRead.cards[inputID] else { return }
        if updated.entries.count >= 8, updated.entries[rowID] == nil {
            updated.entries.removeAll()
            updated.entryIsLatest.removeAll()
            updated.entryStartIDs.removeAll()
            updated.byteCounts = updated.byteCounts.filter { !$0.key.hasPrefix("entries-") }
        }
        updated.entryIsLatest[rowID] = !next && aroundEntryID == nil
        updated.entryStartIDs[rowID] = startingAtID
        updated.entries[rowID] = page
        updated.byteCounts["entries-\(rowID)"] = try JSONEncoder().encode(page).count
        updated.version &+= 1
        runtimeChatRead.cards[inputID] = updated
        trimRuntimeCardCache(keeping: inputID)
    }

    func loadRuntimeActionItems(_ inputID: String, actionID: String, next: Bool = false) async throws {
        guard let cache = runtimeChatRead.cards[inputID] else { return }
        let cursor = next ? cache.actions[actionID]?.nextCursor : nil
        guard !next || cursor != nil else { return }
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let control = beginRuntimeCardOperation()
        defer { endRuntimeCardOperation(control: control, execution: execution, epoch: epoch) }
        let revision = cache.rows.card.revision
        let response = try await readRuntimeChat(.chatActionItems(inputID: inputID, actionID: actionID, cursor: cursor))
        guard execution == executionID else { return }
        guard case .actionItemsPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.actionID == actionID, page.inputID == inputID,
              page.revision == revision, runtimeChatRead.cards[inputID]?.rows.card.revision == revision else {
            throw SessionRuntimeContentError.staleContent
        }
        guard var updated = runtimeChatRead.cards[inputID] else { return }
        if updated.actions.count >= 2, updated.actions[actionID] == nil {
            updated.actions.removeAll()
            updated.actionPageOffsets.removeAll()
            updated.byteCounts = updated.byteCounts.filter { !$0.key.hasPrefix("actions-") }
        }
        updated.actionPageOffsets[actionID] = next ? (cache.actionPageOffsets[actionID] ?? 0) + 1 : 0
        updated.actions[actionID] = page
        updated.byteCounts["actions-\(actionID)"] = try JSONEncoder().encode(page).count
        updated.version &+= 1
        runtimeChatRead.cards[inputID] = updated
        trimRuntimeCardCache(keeping: inputID)
    }

    func revealRuntimeCardEntry(_ inputID: String, rowID: String, entryID: String?) async throws {
        try await loadRuntimeCardRows(inputID, navigation: .around(rowID))
        try await loadRuntimeCardEntries(inputID, rowID: rowID, aroundEntryID: entryID)
    }

    private func trimRuntimeCardCache(keeping inputID: String) {
        var bytes = runtimeChatRead.cards.values.reduce(0) { $0 + $1.byteCounts.values.reduce(0, +) }
        let removable = runtimeChatRead.cards.keys.filter { $0 != inputID }.sorted()
        for key in removable {
            guard bytes > 4 * 1024 * 1024 else { break }
            guard var card = runtimeChatRead.cards[key] else { continue }
            let oldCost = card.byteCounts.values.reduce(0, +)
            card.entries.removeAll()
            card.actions.removeAll()
            card.byteCounts = card.byteCounts.filter { $0.key == "rows" }
            card.version &+= 1
            runtimeChatRead.cards[key] = card
            bytes -= oldCost - card.byteCounts.values.reduce(0, +)
        }
        for key in removable {
            guard bytes > 4 * 1024 * 1024 || runtimeChatRead.cards.count > TranscriptWindow.defaultLimit * TranscriptWindow.maxStages else { break }
            if let removed = runtimeChatRead.cards.removeValue(forKey: key) {
                bytes -= removed.byteCounts.values.reduce(0, +)
            }
        }
    }

    func openRuntimeItem(_ reference: SessionRuntimeChatItemReference) async throws -> ChatItem {
        switch reference {
        case .inline(let item): return item
        case .deferred(let marker):
            guard runtimeContentLoader != nil else { throw SessionRuntimeContentError.invalidRequest }
            let execution = executionID
            let epoch = runtimeChatRead.epoch
            let queuedLoader: @MainActor (SessionRuntimeContentRequest) async throws -> SessionRuntimeContentResponse = { request in
                guard request.executionID == self.executionID, self.runtimeChatRead.epoch == epoch else { throw SessionRuntimeContentError.staleContent }
                return try await self.readRuntimeChat(request.target)
            }
            let data = try await loadRuntimeChunk(marker, execution: execution, using: queuedLoader)
            guard execution == executionID, runtimeChatRead.epoch == epoch else { throw SessionRuntimeContentError.staleContent }
            let item = try JSONDecoder().decode(ChatItem.self, from: data)
            guard item.id == marker.id else { throw SessionRuntimeContentError.staleContent }
            runtimeChatRead.openedItems = [item.id: RuntimeOpenedItem(digest: marker.digest, item: item)]
            return item
        }
    }

    func recallRuntimeInputHistory(_ direction: InputHistoryCursor.Direction) -> Bool {
        let wasLoading = runtimeChatRead.recall.isLoading
        guard let request = beginRuntimeInputRecall(direction) else { return wasLoading }
        Task { await applyRuntimeInputRecall(request) }
        return true
    }

    func recallRuntimeInputHistory(_ direction: InputHistoryCursor.Direction) async -> Bool {
        let wasLoading = runtimeChatRead.recall.isLoading
        guard let request = beginRuntimeInputRecall(direction) else { return wasLoading }
        await applyRuntimeInputRecall(request)
        return true
    }

    private func beginRuntimeInputRecall(_ direction: InputHistoryCursor.Direction) -> RuntimeInputRecallRequest? {
        guard attachmentStore.attachments.isEmpty, !runtimeChatRead.recall.isLoading else { return nil }
        if let recalled = runtimeChatRead.recall.recalledText, recalled != draft {
            runtimeChatRead.recall = RuntimeInputRecall()
        }
        if runtimeChatRead.recall.selectedID == nil, case .newer = direction { return nil }
        let request = RuntimeInputRecallRequest(direction: direction, originalDraft: draft,
            executionID: executionID, epoch: runtimeChatRead.epoch)
        runtimeChatRead.recall.isLoading = true
        return request
    }

    private func applyRuntimeInputRecall(_ request: RuntimeInputRecallRequest) async {
        let direction = request.direction
        let originalDraft = request.originalDraft
        let execution = request.executionID
        let epoch = request.epoch
        defer { if execution == executionID, runtimeChatRead.epoch == epoch { runtimeChatRead.recall.isLoading = false } }
        do {
            if runtimeChatRead.recall.history == nil {
                let page = try await readRuntimeInputHistoryPage(.inputHistory(before: nil))
                guard runtimeChatRead.epoch == epoch else { return }
                runtimeChatRead.recall.history = page
            }
            var entries = runtimeChatRead.recall.history?.entries ?? []
            let selected = runtimeChatRead.recall.selectedID
            var candidate: SessionRuntimeInputHistorySummary?
            if case .older = direction {
                let end = selected.flatMap { id in entries.firstIndex { $0.id == id } } ?? entries.count
                candidate = entries[..<end].last(where: \.canRecall)
                while candidate == nil, let cursor = runtimeChatRead.recall.history?.olderCursor {
                    try Task.checkCancellation()
                    let page = try await readRuntimeInputHistoryPage(.inputHistory(before: cursor))
                    guard execution == executionID, runtimeChatRead.epoch == epoch, draft == originalDraft,
                          page.olderCursor != cursor else { return }
                    runtimeChatRead.recall.history = page
                    entries = page.entries
                    candidate = entries.last(where: \.canRecall)
                }
            } else {
                let start = selected.flatMap { id in entries.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
                candidate = entries.dropFirst(start).first(where: \.canRecall)
                while candidate == nil, let cursor = runtimeChatRead.recall.history?.newerCursor {
                    try Task.checkCancellation()
                    let page = try await readRuntimeInputHistoryPage(.inputHistoryAfter(cursor: cursor))
                    guard execution == executionID, runtimeChatRead.epoch == epoch, draft == originalDraft,
                          page.newerCursor != cursor else { return }
                    runtimeChatRead.recall.history = page
                    entries = page.entries
                    candidate = entries.first(where: \.canRecall)
                }
                if candidate == nil, execution == executionID, runtimeChatRead.epoch == epoch, draft == originalDraft {
                    draft = runtimeChatRead.recall.savedDraft
                    runtimeChatRead.recall = RuntimeInputRecall()
                    return
                }
            }
            guard let candidate else { return }
            let item = try await openRuntimeItem(candidate.content)
            guard execution == executionID, runtimeChatRead.epoch == epoch, draft == originalDraft,
                  case .userMessage(_, let text, _, let attachments, _) = item,
                  attachments.isEmpty,
                  text.range(of: #"\[Image #\d+\]"#, options: .regularExpression) == nil else { return }
            if selected == nil { runtimeChatRead.recall.savedDraft = originalDraft }
            runtimeChatRead.recall.selectedID = candidate.id
            runtimeChatRead.recall.recalledText = text
            draft = text
        } catch {
            if execution == executionID, runtimeChatRead.epoch == epoch { runtimeChatRead.historyError = error.localizedDescription }
        }
    }

    private func readRuntimeInputHistoryPage(_ target: SessionRuntimeContentRequest.Target) async throws -> SessionRuntimeInputHistoryPage {
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let response = try await readRuntimeChat(target)
        guard execution == executionID, runtimeChatRead.epoch == epoch, case .inputHistoryPage(let page) = response,
              page.sessionID == id, page.executionID == execution,
              page.entries.count <= SessionRuntimeChatReadLimits.maximumItemsPerPage else {
            throw SessionRuntimeContentError.staleContent
        }
        return page
    }

    func readRuntimeChat(_ target: SessionRuntimeContentRequest.Target) async throws -> SessionRuntimeContentResponse {
        guard usesRuntimeChatReadModel, let loader = runtimeContentLoader else {
            throw SessionRuntimeContentError.invalidRequest
        }
        let prior = runtimeChatRead.control.queueTail
        let request = SessionRuntimeContentRequest(sessionID: id, executionID: executionID, target: target)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = try encoder.encode(request)
        if let flight = runtimeChatRead.control.inFlight[key] { return try await flight.task.value }
        let token = UUID()
        let epoch = runtimeChatRead.epoch
        let task = Task {
            await prior?.value
            try Task.checkCancellation()
            guard self.executionID == request.executionID, self.runtimeChatRead.epoch == epoch else {
                throw SessionRuntimeContentError.staleContent
            }
            let response = try await loader(request)
            guard self.executionID == request.executionID, self.runtimeChatRead.epoch == epoch else {
                throw SessionRuntimeContentError.staleContent
            }
            return response
        }
        runtimeChatRead.control.queueTail = Task { _ = try? await task.value }
        runtimeChatRead.control.inFlight[key] = RuntimeChatReadFlight(token: token, task: task)
        defer {
            if runtimeChatRead.control.inFlight[key]?.token == token { runtimeChatRead.control.inFlight.removeValue(forKey: key) }
        }
        return try await task.value
    }
}
