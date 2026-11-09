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
    var generation: UInt64 = 0
    var isLoading = false
    var isLoadingHistory = false
    var error: String?
    var historyError: String?
    var recall = RuntimeInputRecall()
    var queueTail: Task<Void, Never>?
    var inFlight: [Data: RuntimeChatReadFlight] = [:]

    var historyEntries: [InputHistoryEntry] { history?.entries.map(\.displayEntry) ?? [] }
    var latestEntries: [InputHistoryEntry] { latestHistory.map(\.displayEntry) }
    var hasEarlierHistory: Bool { history?.olderCursor != nil }
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

struct RuntimeCardReadCache: Sendable {
    var isRowWindowManual = false
    var startsAtBeginning = true
    var rows: SessionRuntimeCardRowsPage
    var rowOffset = 0
    var entryIsLatest: [String: Bool] = [:]
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
        let target: SessionRuntimeContentRequest.Target
        if !runtimeChatRead.followsTail, let inputID = runtimeChatRead.anchorInputID {
            target = .chatReadAround(inputID: inputID)
        } else { target = .chatReadTail }
        try await loadRuntimeChatRead(target: target)
        try await loadRuntimeInputHistory(refreshLatest: true)
    }

    func loadRuntimeChatRead(target: SessionRuntimeContentRequest.Target) async throws {
        guard usesRuntimeChatReadModel else { throw SessionRuntimeContentError.invalidRequest }
        switch target {
        case .chatReadTail: runtimeChatRead.followsTail = true; runtimeChatRead.anchorInputID = nil
        case .chatReadAround(let inputID): runtimeChatRead.followsTail = false; runtimeChatRead.anchorInputID = inputID
        case .chatReadBefore, .chatReadAfter, .chatReadAroundItem: runtimeChatRead.followsTail = false; runtimeChatRead.anchorInputID = nil
        default: break
        }
        runtimeChatRead.generation &+= 1
        let generation = runtimeChatRead.generation
        let execution = executionID
        runtimeChatRead.isLoading = true
        defer {
            if runtimeChatRead.generation == generation { runtimeChatRead.isLoading = false }
        }
        do {
            let response = try await readRuntimeChat(target)
            guard executionID == execution, generation == runtimeChatRead.generation else { return }
            guard case .chatReadPage(let page) = response,
                  page.sessionID == id, page.executionID == execution,
                  page.blocks.count <= SessionRuntimeChatReadLimits.maximumItemsPerPage else {
                throw SessionRuntimeContentError.staleContent
            }
            var next = runtimeChatRead
            next.page = try mergedRuntimeReadPage(page, target: target)
            let retainedInputs = Set(next.page?.blocks.compactMap(\.ownerInputID) ?? [])
            next.cards = next.cards.filter { retainedInputs.contains($0.key) }
            if !next.followsTail, next.anchorInputID == nil {
                next.anchorInputID = page.blocks.compactMap(\.ownerInputID).first
            }
            next.error = nil
            runtimeChatRead = next
        } catch {
            guard executionID == execution, generation == runtimeChatRead.generation else { return }
            runtimeChatRead.error = error.localizedDescription
            throw error
        }
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
            if !refreshLatest || runtimeChatRead.history == nil || runtimeChatRead.history?.newerCursor == nil {
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
        let execution = executionID
        let old = runtimeChatRead.cards[inputID]
        let summary = runtimeChatRead.page?.blocks.compactMap { block -> SessionRuntimeCardSummary? in
            if case .card(let value) = block.content, value.inputID == inputID { value } else { nil }
        }.first ?? old?.rows.card
        let target: SessionRuntimeContentRequest.Target
        let manual: Bool
        let first: Bool
        switch navigation {
        case .next:
            if let old, old.rowOffset + 8 < old.rows.rows.count {
                runtimeChatRead.cards[inputID]?.rowOffset += 8
                runtimeChatRead.cards[inputID]?.isRowWindowManual = true
                runtimeChatRead.cards[inputID]?.version &+= 1
                return
            }
            guard let cursor = old?.rows.nextCursor else { return }
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
            } else { rowID = summary?.activeRowID; manual = false }
            if let rowID {
                target = .chatCardRowsAround(inputID: inputID, rowID: rowID); first = false
            } else {
                target = .chatCardRows(inputID: inputID, cursor: nil); first = true
            }
        }
        let response = try await readRuntimeChat(target)
        guard execution == executionID else { return }
        guard case .cardRowsPage(let page) = response, page.sessionID == id,
              page.executionID == execution, page.card.inputID == inputID else {
            throw SessionRuntimeContentError.staleContent
        }
        if let current = runtimeChatRead.page?.blocks.compactMap({ block -> SessionRuntimeCardSummary? in
            if case .card(let summary) = block.content, summary.inputID == inputID { summary } else { nil }
        }).first, current.revision != page.card.revision { throw SessionRuntimeContentError.staleContent }
        runtimeChatRead.cards[inputID] = RuntimeCardReadCache(isRowWindowManual: manual, startsAtBeginning: first, rows: page,
            version: (old?.version ?? 0) &+ 1,
            byteCounts: ["rows": try JSONEncoder().encode(page).count])
        trimRuntimeCardCache(keeping: inputID)
    }

    func loadRuntimeCardEntries(_ inputID: String, rowID: String, next: Bool = false, aroundEntryID: String? = nil) async throws {
        guard let cache = runtimeChatRead.cards[inputID] else { return }
        let cursor = next ? cache.entries[rowID]?.nextCursor : nil
        guard !next || cursor != nil else { return }
        let execution = executionID
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
            updated.byteCounts = updated.byteCounts.filter { !$0.key.hasPrefix("entries-") }
        }
        updated.entryIsLatest[rowID] = !next && aroundEntryID == nil
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
        let prior = runtimeChatRead.queueTail
        let request = SessionRuntimeContentRequest(sessionID: id, executionID: executionID, target: target)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = try encoder.encode(request)
        if let flight = runtimeChatRead.inFlight[key] { return try await flight.task.value }
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
        runtimeChatRead.queueTail = Task { _ = try? await task.value }
        runtimeChatRead.inFlight[key] = RuntimeChatReadFlight(token: token, task: task)
        defer {
            if runtimeChatRead.inFlight[key]?.token == token { runtimeChatRead.inFlight.removeValue(forKey: key) }
        }
        return try await task.value
    }
}
