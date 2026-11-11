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
    var timelineGeneration: UInt64 = 0
    var historyGeneration: UInt64 = 0
    var latestHistoryGeneration: UInt64 = 0
    var queueTail: Task<Void, Never>?
    var inFlight: [Data: RuntimeChatReadFlight] = [:]
    var renderedSpans: [UUID: RuntimeChatRenderedSpan] = [:]
    var cardOperationGeneration: UInt64 = 0
    var cardReadGenerations: [RuntimeCardReadTarget: UInt64] = [:]
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

@MainActor
private final class RuntimeReadTransactionContext {
    let executionID: UUID
    let epoch: UUID
    let generation: UInt64
    let cardOperationGeneration: UInt64
    let parents = RuntimeReadParentVerification()
    var recoveredTimelineAnchor = false

    init(executionID: UUID, epoch: UUID, generation: UInt64, cardOperationGeneration: UInt64) {
        self.executionID = executionID
        self.epoch = epoch
        self.generation = generation
        self.cardOperationGeneration = cardOperationGeneration
    }
}

@MainActor
private final class RuntimeReadParentVerification {
    var sessionExists = false
    var cards: Set<String> = []
}

enum RuntimeCardReadTarget: Hashable, Sendable {
    case rows(String)
    case entries(String, String)
    case action(String, String)

    var inputID: String {
        switch self {
        case .rows(let inputID), .entries(let inputID, _), .action(let inputID, _): inputID
        }
    }
}

struct RuntimeCardReadFailure: Sendable, Equatable {
    let target: RuntimeCardReadTarget?
    let generation: UInt64
    let message: String
}

private struct RuntimeCardReadOperation {
    let target: RuntimeCardReadTarget
    let executionID: UUID
    let epoch: UUID
    let revision: UInt64
    let generation: UInt64
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
    var failure: RuntimeCardReadFailure?
    var error: String? {
        get { failure?.message }
        set { failure = newValue.map { RuntimeCardReadFailure(target: nil, generation: 0, message: $0) } }
    }
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
    }

    func loadRuntimeChatRead(target: SessionRuntimeContentRequest.Target, intentToken: UUID? = nil) async throws {
        try await startRuntimeChatRead(target: target, preservingWindow: false, intentToken: intentToken)
    }

    private func startRuntimeChatRead(target: SessionRuntimeContentRequest.Target, preservingWindow: Bool,
                                      intentToken: UUID?) async throws {
        guard usesRuntimeChatReadModel else { throw SessionRuntimeContentError.invalidRequest }
        let old = runtimeChatRead
        if preservingWindow { old.control.needsContentCatchUp = false }
        let committedIntent = intentToken ?? (preservingWindow ? nil : UUID())
        let epoch = old.epoch
        let cardOperationGeneration = old.control.cardOperationGeneration
        let historyGeneration = old.control.historyGeneration
        let latestHistoryGeneration = old.control.latestHistoryGeneration
        let showsProgress = !preservingWindow || old.page == nil
        let span = old.control.renderedSpans.count == 1 ? old.control.renderedSpans.values.first : nil
        let rendered = span.flatMap { hint -> RuntimeChatRenderedSpan? in
            hint.executionID == executionID && hint.epoch == epoch && hint.intentToken == old.appliedIntentToken ? hint : nil
        }
        runtimeChatRead.control.timelineGeneration &+= 1
        let generation = runtimeChatRead.control.timelineGeneration
        let execution = executionID
        if showsProgress { runtimeChatRead.isLoading = true }
        let task = Task {
            defer {
                if runtimeChatRead.control.timelineGeneration == generation {
                    if showsProgress { runtimeChatRead.isLoading = false }
                    runtimeChatRead.control.timelineLoadTask = nil
                    scheduleRuntimeContentCatchUpIfReady(control: old.control, execution: execution, epoch: epoch)
                }
            }
            let historyFailure = try await applyRuntimeChatRead(target: target, generation: generation, execution: execution,
                epoch: epoch, old: old, cardOperationGeneration: cardOperationGeneration,
                historyGeneration: historyGeneration, latestHistoryGeneration: latestHistoryGeneration,
                preservingWindow: preservingWindow, rendered: rendered, intentToken: committedIntent)
            if let historyFailure { throw historyFailure }
        }
        runtimeChatRead.control.timelineLoadTask = task
        try await task.value
    }

    private func applyRuntimeChatRead(target: SessionRuntimeContentRequest.Target,
                                      generation: UInt64, execution: UUID, epoch: UUID,
                                      old: RuntimeChatReadProjection, cardOperationGeneration: UInt64,
                                      historyGeneration: UInt64, latestHistoryGeneration: UInt64,
                                      preservingWindow: Bool,
                                      rendered: RuntimeChatRenderedSpan?, intentToken: UUID?) async throws -> Error? {
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
            let latestHistory: Result<SessionRuntimeInputHistoryPage, Error>?
            if preservingWindow {
                do { latestHistory = .success(try await readRuntimeInputHistoryPage(.inputHistory(before: nil))) }
                catch { latestHistory = .failure(error) }
            } else { latestHistory = nil }
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  generation == runtimeChatRead.control.timelineGeneration else { return nil }
            // A row/detail operation performed while this transaction waited wins.
            let affected = Set(old.cards.keys).union(prepared.keys)
            guard runtimeChatRead.control.cardOperationGeneration == cardOperationGeneration,
                  affected.allSatisfy({ runtimeChatRead.cards[$0]?.version == old.cards[$0]?.version }) else {
                if preservingWindow { runtimeChatRead.control.needsContentCatchUp = true }
                return nil
            }
            guard prepared.count <= TranscriptWindow.defaultLimit * TranscriptWindow.maxStages,
                  prepared.values.reduce(0, { $0 + $1.byteCounts.values.reduce(0, +) }) <= 4 * 1024 * 1024 else {
                throw SessionRuntimeContentError.invalidRequest
            }
            var next = runtimeChatRead
            next.page = page
            next.appliedIntentToken = preservingWindow ? old.appliedIntentToken : intentToken
            next.cards = prepared
            let appliedTarget: SessionRuntimeContentRequest.Target = context.recoveredTimelineAnchor ? .chatReadTail : target
            switch appliedTarget {
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
            let historyFailure = latestHistory.flatMap {
                applyRuntimeLatestHistory($0, to: &next, historyGeneration: historyGeneration,
                    latestHistoryGeneration: latestHistoryGeneration)
            }
            next.control.cardReadGenerations = next.control.cardReadGenerations.filter { prepared[$0.key.inputID] != nil }
            for (inputID, card) in prepared {
                guard card.version != old.cards[inputID]?.version else { continue }
                let targets = refreshedRuntimeCardTargets(inputID, old: old.cards[inputID], new: card)
                for target in targets { next.control.cardReadGenerations.removeValue(forKey: target) }
            }
            runtimeChatRead = next
            return historyFailure
        } catch {
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  generation == runtimeChatRead.control.timelineGeneration else { return nil }
            guard runtimeChatRead.control.cardOperationGeneration == cardOperationGeneration else {
                if preservingWindow { runtimeChatRead.control.needsContentCatchUp = true }
                return nil
            }
            if error is CancellationError { throw error }
            if let contentError = error as? SessionRuntimeContentError, contentError == .staleContent {
                runtimeChatRead.control.needsContentCatchUp = true
            } else { runtimeChatRead.error = error.localizedDescription }
            throw error
        }
    }

    private func refreshedRuntimeCardTargets(_ inputID: String, old: RuntimeCardReadCache?,
                                              new: RuntimeCardReadCache) -> Set<RuntimeCardReadTarget> {
        var targets: Set<RuntimeCardReadTarget> = [.rows(inputID)]
        if let old, old.rows.card.revision != new.rows.card.revision
            || old.rows.card.contentRevision != new.rows.card.contentRevision {
            targets.formUnion(old.entries.keys.map { .entries(inputID, $0) })
            targets.formUnion(old.actions.keys.map { .action(inputID, $0) })
            if let failedTarget = old.failure?.target, failedTarget.inputID == inputID { targets.insert(failedTarget) }
        }
        return targets
    }

    private func clearRuntimeCardFailure(_ cache: inout RuntimeCardReadCache,
                                         targets: Set<RuntimeCardReadTarget>, through generation: UInt64 = .max) {
        if let failure = cache.failure, let target = failure.target,
           targets.contains(target), failure.generation <= generation { cache.failure = nil }
    }

    private func isCurrentRuntimeCardOperation(_ operation: RuntimeCardReadOperation) -> Bool {
        executionID == operation.executionID && runtimeChatRead.epoch == operation.epoch
            && runtimeChatRead.control.cardReadGenerations[operation.target] == operation.generation
            && (runtimeChatRead.cards[operation.target.inputID]?.rows.card.revision ?? operation.revision) == operation.revision
    }

    private func performRuntimeCardRead(_ target: RuntimeCardReadTarget, revision: UInt64,
                                        read: (RuntimeCardReadOperation) async throws -> Void) async throws {
        let execution = executionID
        let epoch = runtimeChatRead.epoch
        let control = beginRuntimeCardOperation()
        let operation = RuntimeCardReadOperation(target: target, executionID: execution, epoch: epoch,
            revision: revision, generation: control.cardOperationGeneration)
        control.cardReadGenerations[target] = operation.generation
        defer {
            if control.cardReadGenerations[target] == operation.generation {
                control.cardReadGenerations.removeValue(forKey: target)
            }
            endRuntimeCardOperation(control: control, execution: execution, epoch: epoch)
        }
        do { try await read(operation) }
        catch {
            guard isCurrentRuntimeCardOperation(operation) else { return }
            if error is CancellationError { throw error }
            var failure = error
            if let contentError = error as? SessionRuntimeContentError, contentError == .notFound,
               let card = runtimeChatRead.cards[target.inputID]?.rows.card {
                do {
                    try await verifyRuntimeCardParent(card, execution: execution, context: nil, parents: RuntimeReadParentVerification())
                    failure = SessionRuntimeContentError.staleContent
                } catch { failure = error }
            }
            guard isCurrentRuntimeCardOperation(operation) else { return }
            if let contentError = failure as? SessionRuntimeContentError, contentError == .staleContent {
                control.needsContentCatchUp = true
            } else if (runtimeChatRead.cards[target.inputID]?.failure?.generation ?? 0) <= operation.generation {
                runtimeChatRead.cards[target.inputID]?.failure = RuntimeCardReadFailure(target: target,
                    generation: operation.generation, message: failure.localizedDescription)
                runtimeChatRead.cards[target.inputID]?.version &+= 1
            }
            throw failure
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

    func requestRuntimeContentCatchUp() {
        let control = runtimeChatRead.control
        control.needsContentCatchUp = true
        scheduleRuntimeContentCatchUpIfReady(control: control, execution: executionID, epoch: runtimeChatRead.epoch)
    }

    private func scheduleRuntimeContentCatchUpIfReady(control: RuntimeChatReadControl, execution: UUID, epoch: UUID) {
        guard executionID == execution, runtimeChatRead.epoch == epoch, runtimeChatRead.control === control,
              control.needsContentCatchUp, control.activeCardOperations == 0,
              control.timelineLoadTask == nil, !control.catchUpScheduled else { return }
        control.needsContentCatchUp = false
        control.catchUpScheduled = true
        Task {
            defer { control.catchUpScheduled = false }
            guard executionID == execution, runtimeChatRead.epoch == epoch, runtimeChatRead.control === control else { return }
            // Keep recovery inside this task so a second stale read waits for the normal refresh.
            try? await refreshRuntimeChatRead()
        }
    }

    private func validateRuntimeReadContext(_ context: RuntimeReadTransactionContext?) throws {
        guard let context else { return }
        guard executionID == context.executionID, runtimeChatRead.epoch == context.epoch,
              runtimeChatRead.control.timelineGeneration == context.generation,
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
        var result: SessionRuntimeChatReadPage
        do { result = try await readRuntimeTimeline(target) }
        catch SessionRuntimeContentError.notFound {
            guard !followsTail else { throw SessionRuntimeContentError.notFound }
            let tail = try await readRuntimeTimeline(.chatReadTail)
            try validateRuntimeReadContext(context)
            context.recoveredTimelineAnchor = true
            return tail
        }
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
            // A removed window end cannot be recovered by retrying the same span.
            guard let cursor else { return freshTail }
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
        let parents = context?.parents ?? RuntimeReadParentVerification()
        var prepared = try await fetchedRuntimeCardRows(summary, old: old, navigation: navigation,
            context: context, parents: parents)
        prepared.failure = old?.failure
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
            clearRuntimeCardFailure(&prepared, targets: [.rows(summary.inputID)])
            return prepared
        }
        // Rebuild the already fetched detail windows before publishing the new card metadata.
        prepared.entryIsLatest = old.entryIsLatest
        prepared.entryStartIDs = old.entryStartIDs
        prepared.actionPageOffsets = old.actionPageOffsets
        var removedRows = Set<String>()
        var rowIDs = Array(old.entries.keys)
        if case .entries(_, let rowID)? = old.failure?.target, old.entries[rowID] == nil { rowIDs.append(rowID) }
        for rowID in rowIDs {
            try validateRuntimeReadContext(context)
            let lastID = old.entryIsLatest[rowID] == false ? old.entries[rowID]?.entries.last?.id : nil
            guard let page = try await refreshedRuntimeEntries(inputID: summary.inputID, rowID: rowID,
                lastID: lastID, card: prepared.rows.card, execution: prepared.rows.executionID, context: context, parents: parents) else {
                removedRows.insert(rowID)
                prepared.entryIsLatest.removeValue(forKey: rowID)
                prepared.entryStartIDs.removeValue(forKey: rowID)
                continue
            }
            if let lastID, page.entries.last?.id != lastID {
                prepared.entryIsLatest[rowID] = true
                prepared.entryStartIDs.removeValue(forKey: rowID)
            }
            if prepared.entries.count >= 8, old.entries[rowID] == nil {
                prepared.entries.removeAll()
                prepared.entryIsLatest.removeAll()
                prepared.entryStartIDs.removeAll()
                prepared.byteCounts = prepared.byteCounts.filter { !$0.key.hasPrefix("entries-") }
            }
            if old.entries[rowID] == nil { prepared.entryIsLatest[rowID] = true }
            prepared.entries[rowID] = page
            prepared.byteCounts["entries-\(rowID)"] = try JSONEncoder().encode(page).count
        }
        var actionIDs = Array(old.actions.keys)
        if case .action(_, let actionID)? = old.failure?.target, old.actions[actionID] == nil { actionIDs.append(actionID) }
        for actionID in actionIDs {
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
                firstID: firstID, card: prepared.rows.card, execution: prepared.rows.executionID, context: context, parents: parents) else {
                prepared.actionPageOffsets.removeValue(forKey: actionID)
                continue
            }
            if prepared.actions.count >= 2, old.actions[actionID] == nil {
                prepared.actions.removeAll()
                prepared.actionPageOffsets.removeAll()
                prepared.byteCounts = prepared.byteCounts.filter { !$0.key.hasPrefix("actions-") }
            }
            prepared.actions[actionID] = page
            if let firstID, page.items.first?.id != firstID { prepared.actionPageOffsets[actionID] = 0 }
            prepared.byteCounts["actions-\(actionID)"] = try JSONEncoder().encode(page).count
        }
        clearRuntimeCardFailure(&prepared, targets: refreshedRuntimeCardTargets(summary.inputID, old: old, new: prepared))
        return prepared
    }

    private func verifyRuntimeCardParent(_ card: SessionRuntimeCardSummary, execution: UUID,
                                         context: RuntimeReadTransactionContext?, parents: RuntimeReadParentVerification) async throws {
        try validateRuntimeReadContext(context)
        if !parents.sessionExists {
            let tail = try await readRuntimeTimeline(.chatReadTail)
            guard tail.executionID == execution else { throw SessionRuntimeContentError.staleContent }
            try validateRuntimeReadContext(context)
            parents.sessionExists = true
        }
        guard !parents.cards.contains(card.inputID) else { return }
        let response: SessionRuntimeContentResponse
        do { response = try await readRuntimeChat(.chatCardRows(inputID: card.inputID, cursor: nil)) }
        catch SessionRuntimeContentError.notFound { throw SessionRuntimeContentError.staleContent }
        try validateRuntimeReadContext(context)
        guard case .cardRowsPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.card.inputID == card.inputID,
              page.card.revision == card.revision, page.card.contentRevision >= card.contentRevision else {
            throw SessionRuntimeContentError.staleContent
        }
        parents.cards.insert(card.inputID)
    }

    private func refreshedRuntimeEntries(inputID: String, rowID: String, lastID: String?,
                                         card: SessionRuntimeCardSummary, execution: UUID,
                                         context: RuntimeReadTransactionContext?, parents: RuntimeReadParentVerification) async throws -> SessionRuntimeCardEntriesPage? {
        let target: SessionRuntimeContentRequest.Target = lastID.map {
            .chatRowEntriesAround(inputID: inputID, rowID: rowID, entryID: $0)
        } ?? .chatRowEntries(inputID: inputID, rowID: rowID, cursor: nil)
        let response: SessionRuntimeContentResponse
        do { response = try await readRuntimeChat(target) }
        catch SessionRuntimeContentError.notFound {
            try await verifyRuntimeCardParent(card, execution: execution, context: context, parents: parents)
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
                                             card: SessionRuntimeCardSummary, execution: UUID,
                                             context: RuntimeReadTransactionContext?, parents: RuntimeReadParentVerification) async throws -> SessionRuntimeActionItemsPage? {
        let target: SessionRuntimeContentRequest.Target = firstID.map {
            .chatActionItemsFrom(inputID: inputID, actionID: actionID, itemID: $0)
        } ?? .chatActionItems(inputID: inputID, actionID: actionID, cursor: nil)
        let response: SessionRuntimeContentResponse
        do { response = try await readRuntimeChat(target) }
        catch SessionRuntimeContentError.notFound {
            try await verifyRuntimeCardParent(card, execution: execution, context: context, parents: parents)
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
        let control = runtimeChatRead.control
        let target: SessionRuntimeContentRequest.Target
        if earlier {
            guard let cursor = runtimeChatRead.history?.olderCursor else { return }
            target = .inputHistory(before: cursor)
        } else if newer {
            guard let cursor = runtimeChatRead.history?.newerCursor else { return }
            target = .inputHistoryAfter(cursor: cursor)
        } else { target = .inputHistory(before: nil) }
        control.historyGeneration &+= 1
        let generation = control.historyGeneration
        if !earlier && !newer { control.latestHistoryGeneration &+= 1 }
        let showsProgress = !refreshLatest || runtimeChatRead.history == nil
        if showsProgress { runtimeChatRead.isLoadingHistory = true }
        defer {
            if showsProgress, executionID == execution, runtimeChatRead.epoch == epoch {
                runtimeChatRead.isLoadingHistory = false
            }
        }
        do {
            let page = try await readRuntimeInputHistoryPage(target)
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  control.historyGeneration == generation else { return }
            guard page.revision >= (runtimeChatRead.history?.revision ?? 0) else { throw SessionRuntimeContentError.staleContent }
            var next = runtimeChatRead
            if !refreshLatest || next.history == nil || next.history?.newerCursor == nil || next.history?.revision != page.revision {
                if next.history != page { next.history = page }
            }
            if !earlier && !newer {
                let latest = Array(page.entries.suffix(12))
                if next.latestHistory != latest { next.latestHistory = latest }
            }
            next.historyError = nil
            if next.history != runtimeChatRead.history || next.latestHistory != runtimeChatRead.latestHistory
                || next.historyError != runtimeChatRead.historyError { runtimeChatRead = next }
        } catch {
            guard executionID == execution, runtimeChatRead.epoch == epoch,
                  control.historyGeneration == generation else { return }
            runtimeChatRead.historyError = error.localizedDescription
            throw error
        }
    }

    private func applyRuntimeLatestHistory(_ result: Result<SessionRuntimeInputHistoryPage, Error>,
                                           to next: inout RuntimeChatReadProjection, historyGeneration: UInt64,
                                           latestHistoryGeneration: UInt64) -> Error? {
        switch result {
        case .success(let page):
            guard page.revision >= (next.history?.revision ?? 0) else { return nil }
            let newScope = next.history?.revision != page.revision
            let panelUnchanged = next.control.historyGeneration == historyGeneration
            if newScope || (panelUnchanged && (next.history == nil || next.history?.newerCursor == nil)) {
                if next.history != page { next.history = page }
            }
            if next.control.latestHistoryGeneration == latestHistoryGeneration {
                let latest = Array(page.entries.suffix(12))
                if next.latestHistory != latest { next.latestHistory = latest }
            }
            if panelUnchanged || newScope { next.historyError = nil }
            return nil
        case .failure(let error):
            guard next.control.historyGeneration == historyGeneration else { return nil }
            next.historyError = error.localizedDescription
            return error
        }
    }

    func loadRuntimeCardRows(_ inputID: String, navigation: RuntimeCardRowNavigation = .refresh) async throws {
        let old = runtimeChatRead.cards[inputID]
        if case .next = navigation, old?.rows.nextCursor == nil,
           (old?.rowOffset ?? 0) + 8 >= (old?.rows.rows.count ?? 0) { return }
        let summary = runtimeChatRead.page?.blocks.compactMap { block -> SessionRuntimeCardSummary? in
            if case .card(let value) = block.content, value.inputID == inputID { value } else { nil }
        }.first ?? old?.rows.card
        guard let summary else { throw SessionRuntimeContentError.notFound }
        try await performRuntimeCardRead(.rows(inputID), revision: summary.revision) { operation in
            if case .next = navigation, let old, old.rowOffset + 8 < old.rows.rows.count {
                runtimeChatRead.cards[inputID]?.rowOffset += 8
                runtimeChatRead.cards[inputID]?.isRowWindowManual = true
                runtimeChatRead.cards[inputID]?.version &+= 1
                return
            }
            var prepared = try await preparedRuntimeCard(summary, old: old, navigation: navigation, force: true)
            guard isCurrentRuntimeCardOperation(operation) else { return }
            let targets = refreshedRuntimeCardTargets(inputID, old: old, new: prepared)
            if let current = runtimeChatRead.cards[inputID] {
                prepared.version = current.version &+ 1
                prepared.failure = current.failure
                if let old {
                    for rowID in old.entries.keys where current.entries[rowID] == nil {
                        prepared.entries.removeValue(forKey: rowID)
                        prepared.entryIsLatest.removeValue(forKey: rowID)
                        prepared.entryStartIDs.removeValue(forKey: rowID)
                        prepared.byteCounts.removeValue(forKey: "entries-\(rowID)")
                    }
                    for actionID in old.actions.keys where current.actions[actionID] == nil {
                        prepared.actions.removeValue(forKey: actionID)
                        prepared.actionPageOffsets.removeValue(forKey: actionID)
                        prepared.byteCounts.removeValue(forKey: "actions-\(actionID)")
                    }
                }
                for (rowID, page) in current.entries where current.entries[rowID] != old?.entries[rowID]
                    || current.entryIsLatest[rowID] != old?.entryIsLatest[rowID]
                    || current.entryStartIDs[rowID] != old?.entryStartIDs[rowID] {
                    prepared.entries[rowID] = page
                    prepared.entryIsLatest[rowID] = current.entryIsLatest[rowID]
                    prepared.entryStartIDs[rowID] = current.entryStartIDs[rowID]
                    prepared.byteCounts["entries-\(rowID)"] = current.byteCounts["entries-\(rowID)"]
                }
                for (actionID, page) in current.actions where current.actions[actionID] != old?.actions[actionID]
                    || current.actionPageOffsets[actionID] != old?.actionPageOffsets[actionID] {
                    prepared.actions[actionID] = page
                    prepared.actionPageOffsets[actionID] = current.actionPageOffsets[actionID]
                    prepared.byteCounts["actions-\(actionID)"] = current.byteCounts["actions-\(actionID)"]
                }
            }
            clearRuntimeCardFailure(&prepared, targets: targets, through: operation.generation)
            runtimeChatRead.cards[inputID] = prepared
            trimRuntimeCardCache(keeping: inputID)
        }
    }

    private func fetchedRuntimeCardRows(_ summary: SessionRuntimeCardSummary, old: RuntimeCardReadCache?,
                                       navigation: RuntimeCardRowNavigation,
                                       context: RuntimeReadTransactionContext?, parents: RuntimeReadParentVerification) async throws -> RuntimeCardReadCache {
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
            try await verifyRuntimeCardParent(summary, execution: execution, context: context, parents: parents)
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
        let revision = cache.rows.card.revision
        let target: SessionRuntimeContentRequest.Target
        if let aroundEntryID { target = .chatRowEntriesAround(inputID: inputID, rowID: rowID, entryID: aroundEntryID) }
        else { target = .chatRowEntries(inputID: inputID, rowID: rowID, cursor: cursor) }
        try await performRuntimeCardRead(.entries(inputID, rowID), revision: revision) { operation in
            let response = try await readRuntimeChat(target)
            guard isCurrentRuntimeCardOperation(operation) else { return }
            guard case .cardEntriesPage(let page) = response, page.sessionID == id,
                  page.executionID == operation.executionID, page.inputID == inputID, page.rowID == rowID,
                  page.revision == revision else { throw SessionRuntimeContentError.staleContent }
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
            clearRuntimeCardFailure(&updated, targets: [operation.target], through: operation.generation)
            updated.version &+= 1
            runtimeChatRead.cards[inputID] = updated
            trimRuntimeCardCache(keeping: inputID)
        }
    }

    func loadRuntimeActionItems(_ inputID: String, actionID: String, next: Bool = false) async throws {
        guard let cache = runtimeChatRead.cards[inputID] else { return }
        let cursor = next ? cache.actions[actionID]?.nextCursor : nil
        guard !next || cursor != nil else { return }
        let revision = cache.rows.card.revision
        try await performRuntimeCardRead(.action(inputID, actionID), revision: revision) { operation in
            let response = try await readRuntimeChat(.chatActionItems(inputID: inputID, actionID: actionID, cursor: cursor))
            guard isCurrentRuntimeCardOperation(operation) else { return }
            guard case .actionItemsPage(let page) = response, page.sessionID == id,
                  page.executionID == operation.executionID, page.actionID == actionID, page.inputID == inputID,
                  page.revision == revision else { throw SessionRuntimeContentError.staleContent }
            guard var updated = runtimeChatRead.cards[inputID] else { return }
            if updated.actions.count >= 2, updated.actions[actionID] == nil {
                updated.actions.removeAll()
                updated.actionPageOffsets.removeAll()
                updated.byteCounts = updated.byteCounts.filter { !$0.key.hasPrefix("actions-") }
            }
            updated.actionPageOffsets[actionID] = next ? (cache.actionPageOffsets[actionID] ?? 0) + 1 : 0
            updated.actions[actionID] = page
            updated.byteCounts["actions-\(actionID)"] = try JSONEncoder().encode(page).count
            clearRuntimeCardFailure(&updated, targets: [operation.target], through: operation.generation)
            updated.version &+= 1
            runtimeChatRead.cards[inputID] = updated
            trimRuntimeCardCache(keeping: inputID)
        }
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
