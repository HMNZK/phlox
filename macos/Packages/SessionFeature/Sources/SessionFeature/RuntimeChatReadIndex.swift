import AgentDomain
import CryptoKit
import Foundation
import StructuredChatKit

@MainActor
final class RuntimeChatReadIndexStore {
    private var dirtyFrom: Int?
    private var dirtyItemIDs: Set<String> = []
    private var hasUnspecifiedEdits = false
    private var indexedCount = 0
    private let worker = RuntimeChatReadIndexWorker()

    func invalidate(from position: Int, itemIDs: Set<String>? = nil) {
        dirtyFrom = min(dirtyFrom ?? max(0, position), max(0, position))
        if let itemIDs { dirtyItemIDs.formUnion(itemIDs) }
        else if position < indexedCount { hasUnspecifiedEdits = true }
    }

    func response(items: [ChatItem], executionID: UUID, revision: Int, liveState: AgentStatusLiveState,
                  usesCards: Bool, request: SessionRuntimeContentRequest, usage: [String: TurnUsage]) async throws -> SessionRuntimeContentResponse {
        let dirty = dirtyFrom
        let edits: Set<String>? = hasUnspecifiedEdits ? nil : dirtyItemIDs
        dirtyFrom = nil; dirtyItemIDs.removeAll(); hasUnspecifiedEdits = false
        indexedCount = items.count
        return try await worker.response(items: items, executionID: executionID, revision: revision,
            liveState: liveState, usesCards: usesCards, dirtyFrom: dirty, changedItemIDs: edits, request: request, usage: usage)
    }
}

private actor RuntimeChatReadIndexWorker {
    private var index: RuntimeChatReadIndex?

    func response(items: [ChatItem], executionID: UUID, revision: Int, liveState: AgentStatusLiveState,
                  usesCards: Bool, dirtyFrom: Int?, changedItemIDs: Set<String>?,
                  request: SessionRuntimeContentRequest, usage: [String: TurnUsage]) throws -> SessionRuntimeContentResponse {
        if let index, index.executionID == executionID {
            if revision < index.transcriptRevision { return try index.response(for: request, usage: usage) }
            let start = min(dirtyFrom ?? items.count, index.itemCount)
            if !index.update(items: items, from: start, changedItemIDs: changedItemIDs, revision: revision, liveState: liveState) {
                index.rebuild(items: items, from: dirtyFrom ?? index.tailStart, revision: revision, liveState: liveState)
            }
            return try index.response(for: request, usage: usage)
        }
        let built = RuntimeChatReadIndex(items: items, executionID: executionID, transcriptRevision: revision,
            liveState: liveState, usesCards: usesCards)
        index = built
        return try built.response(for: request, usage: usage)
    }
}

private final class RuntimeChatReadIndex {
    final class Item {
        var value: ChatItem
        private var cachedReference: SessionRuntimeChatItemReference?
        init(_ value: ChatItem) { self.value = value }
        func replace(_ value: ChatItem) { self.value = value; cachedReference = nil }

        func reference() throws -> SessionRuntimeChatItemReference {
            if let cachedReference { return cachedReference }
            let data = try Self.encoder.encode(value)
            let reference: SessionRuntimeChatItemReference
            if data.count <= SessionRuntimeChatReadLimits.maximumInlineItemBytes {
                reference = .inline(value)
            } else {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                reference = .deferred(.init(kind: .chatItem, id: value.id, digest: digest,
                    totalBytes: data.count, preview: bounded(value.plainText), itemKind: value.readKind))
            }
            cachedReference = reference
            return reference
        }

        private static var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return encoder
        }
    }

    final class Action {
        let id: String
        let accumulator: AgentStatusCardBuilder.ActionAccumulator
        let inputID: String?
        var detailItems: [Item]
        var cachedGroupSummary: SessionRuntimeCommandGroupSummary?
        var contentRevision = 0
        var structureRevision: UInt64 = 1
        init(_ action: AgentStatusAction, inputID: String?, items: inout [String: Item]) {
            id = action.id
            accumulator = .init(items: action.items)
            self.inputID = inputID
            detailItems = action.items.map { value in
                if let item = items[value.id] { return item }
                let item = Item(value); items[value.id] = item; return item
            }
        }
        init(_ item: Item, inputID: String?) {
            id = item.value.id
            accumulator = .init(items: [item.value])
            self.inputID = inputID
            detailItems = [item]
        }
        func commandGroupSummary() -> SessionRuntimeCommandGroupSummary {
            if let cachedGroupSummary { return cachedGroupSummary }
            let summary = SessionRuntimeCommandGroupSummary(
                firstCommand: detailItems.first?.value.readCommand.map(bounded),
                lastCommand: detailItems.last?.value.readCommand.map(bounded),
                timestamp: detailItems.last?.value.timestamp ?? .distantPast,
                hasNonBlankOutput: accumulator.nonBlankOutputCount > 0,
                exitCode: detailItems.count == 1 ? detailItems.first.flatMap { CommandExitCode.parse($0.value.readOutput) } : nil)
            cachedGroupSummary = summary
            return summary
        }

        func summary(running: Bool, turnEnd: ChatTurnEnd?) -> SessionRuntimeActionSummary {
            var summary = SessionRuntimeActionSummary(id: id, label: accumulator.resolvedLabel(running: running, turnEnd: turnEnd).bounded,
                state: accumulator.state(running: running, turnEnd: turnEnd),
                startedAt: detailItems.first.flatMap { $0.value.timestamp == .distantPast ? nil : $0.value.timestamp },
                duration: accumulator.duration, totalItemCount: detailItems.count)
            summary.contentRevision = contentRevision
            return summary
        }
    }

    enum Entry {
        case item(Item)
        case action(Action)
        var id: String {
            switch self { case .item(let item): item.value.id; case .action(let action): action.id }
        }
    }

    final class Row {
        let id: String
        let kind: SessionRuntimeCardRow.Kind
        var entries: [Entry]
        var entryPositions: [String: Int] = [:]
        var actionStates: [AgentStatusWorkState: Int] = [:]
        var actionCount = 0
        init(_ row: AgentStatusRow, inputID: String, items: inout [String: Item], actions: inout [String: Action],
             actionByItem: inout [String: Action], rowByItem: inout [String: Row], running: Bool, end: ChatTurnEnd?) {
            id = row.id
            let source: [AgentStatusEntry]
            switch row {
            case .task(let task):
                kind = .task(id: task.id, title: bounded(task.title), state: task.state,
                    startedAt: task.startedAt, endedAt: task.endedAt)
                source = task.entries
            case .outside(let outside): kind = .outside(state: outside.state); source = outside.entries
            }
            entries = source.map { entry in
                switch entry {
                case .item(let value):
                    if let item = items[value.id] { return .item(item) }
                    let item = Item(value); items[value.id] = item; return .item(item)
                case .action(let value):
                    let action = Action(value, inputID: inputID, items: &items)
                    actions[action.id] = action
                    for item in value.items { actionByItem[item.id] = action }
                    return .action(action)
                }
            }
            for (position, entry) in entries.enumerated() {
                entryPositions[entry.id] = position
                rowByItem[entry.id] = self
                if case .action(let action) = entry {
                    actionCount += 1
                    actionStates[action.accumulator.state(running: running, turnEnd: end), default: 0] += 1
                    for item in action.detailItems { rowByItem[item.value.id] = self }
                }
            }
        }
        init(item: Item, inputID: String?) {
            id = "outside-\(item.value.id)"
            kind = .outside(state: .unknown)
            entries = []
        }
        func summary() -> SessionRuntimeCardRow {
            let displayedKind: SessionRuntimeCardRow.Kind
            if case .outside = kind {
                displayedKind = .outside(state: .aggregate(actionStates.compactMap { $1 > 0 ? $0 : nil }))
            } else { displayedKind = kind }
            return .init(id: id, kind: displayedKind, totalEntryCount: entries.count, totalActionCount: actionCount)
        }
    }

    final class Card {
        let id: String
        let input: Item
        var revision: UInt64
        var contentRevision: Int
        var header: AgentStatusHeader
        var changeCounts = AgentStatusChangeCounts(items: [ChatItem]())
        var rows: [Row]
        var rowsByID: [String: Row]
        var rowPositions: [String: Int]
        let shownIndex: [String: Int]
        var outsideByAnchor: [Int: Row] = [:]
        var appendRow: Row?
        let outsideAnchor: Int
        var lastAction: Action?
        var lastWorkRowID: String?
        let firstInProgressRowID: String?
        var hasActivityBoundary: Bool
        init(_ card: AgentStatusCard, input: Item, effective: AgentStatusCardBuilder.Snapshot?,
             seenOwnSnapshot: Bool, hasWork: Bool, revision: UInt64, contentRevision: Int, items: inout [String: Item], actions: inout [String: Action],
             actionByItem: inout [String: Action], rowByItem: inout [String: Row], liveState: AgentStatusLiveState) {
            id = card.id; self.input = input; self.revision = revision; self.contentRevision = contentRevision; header = card.header
            hasActivityBoundary = seenOwnSnapshot || hasWork
            shownIndex = Dictionary(card.rows.compactMap { row -> String? in
                if case .task(let task) = row { return task.id }; return nil
            }.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            outsideAnchor = AgentStatusCardBuilder.outsideAnchor(effective, seenOwnSnapshot, shownIndex)
            let end = input.value.readTurnEnd
            rows = card.rows.map { Row($0, inputID: input.value.id, items: &items, actions: &actions,
                actionByItem: &actionByItem, rowByItem: &rowByItem, running: liveState.isProcessing, end: end) }
            rowPositions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            firstInProgressRowID = rows.first { row in
                if case .task(_, _, .inProgress, _, _) = row.kind { return true }; return false
            }?.id
            for row in card.rows {
                for case .action(let action) in row.entries {
                    for item in action.items { changeCounts.update(item) }
                }
            }
            var position = 0
            for row in rows {
                switch row.kind {
                case .task: position += 1
                case .outside: outsideByAnchor[position] = row
                }
            }
            if let owner = effective?.owner, shownIndex[owner] != nil { appendRow = rowsByID["task-\(owner)"] }
            else { appendRow = outsideByAnchor[outsideAnchor] }
        }
        func summary() -> SessionRuntimeCardSummary {
            var summary = SessionRuntimeCardSummary(id: id, inputID: input.value.id, revision: revision,
                contentRevision: contentRevision, header: header.bounded, totalRowCount: rows.count, hasTasks: !shownIndex.isEmpty)
            summary.changeCounts = changeCounts.counts
            if header.isLive {
                summary.activeRowID = lastAction?.accumulator.state(running: true, turnEnd: input.value.readTurnEnd) == .running
                    ? lastWorkRowID : firstInProgressRowID
            }
            return summary
        }
    }

    struct Block {
        enum Content { case item(Item), group(Action), card(Card) }
        let id: String
        let inputID: String?
        let content: Content
    }
    private struct BlockStructureKey: Equatable {
        enum Kind: Equatable { case item(String), commandGroup, card }
        let id: String
        let ownerInputID: String?
        let kind: Kind

        init(_ block: Block) {
            id = block.id
            ownerInputID = block.inputID
            kind = switch block.content {
            case .item(let item): .item(item.value.readKind)
            case .group: .commandGroup
            case .card: .card
            }
        }
    }

    struct Interval {
        let start: Int
        var end: Int
        let inputID: String?
        let baseline: ChatItem?
        var blockStart: Int
        var card: Card?
        var lastSnapshot: ChatItem?
    }

    let executionID: UUID
    private(set) var transcriptRevision: Int
    private(set) var itemCount: Int
    private var liveState: AgentStatusLiveState
    private let usesCards: Bool
    private var blocks: [Block] = []
    private var blockPositionByID: [String: Int] = [:]
    private var itemBlockID: [String: String] = [:]
    private var intervals: [Interval] = []
    private var intervalsByInput: [String: Int] = [:]
    private var items: [String: Item] = [:]
    private var inputItems: [Item] = []
    private var inputPositions: [String: Int] = [:]
    private var inputBlockPositions: [String: Int] = [:]
    private var actions: [String: Action] = [:]
    private var priorActionsForRebuild: [String: Action] = [:]
    private var actionByItem: [String: Action] = [:]
    private var rowByItem: [String: Row] = [:]
    private var sourceIDs: [String] = []
    private var itemPositionByID: [String: Int] = [:]
    var tailStart: Int { intervals.last?.start ?? 0 }
    private var nextRevision: UInt64 = 1
    private var timelineStructureRevision: UInt64 = 1
    private var historyStructureRevision: UInt64 = 1

    init(items source: [ChatItem], executionID: UUID, transcriptRevision: Int, liveState: AgentStatusLiveState,
         usesCards: Bool) {
        self.executionID = executionID; self.transcriptRevision = transcriptRevision
        self.liveState = liveState; self.usesCards = usesCards; itemCount = 0
        rebuild(items: source, from: 0, revision: transcriptRevision, liveState: liveState)
    }

    func rebuild(items source: [ChatItem], from dirty: Int, revision: Int, liveState nextLive: AgentStatusLiveState) {
        let affected = itemCount > 0 ? intervalIndex(containing: min(max(0, dirty), itemCount - 1)) ?? 0 : 0
        let begin = affected < intervals.count ? intervals[affected].start : 0
        let blockStart = affected < intervals.count ? intervals[affected].blockStart : 0
        var baseline = affected < intervals.count ? intervals[affected].baseline : nil
        let inputStart = affected < intervals.count
            ? intervals[affected].inputID.flatMap { inputPositions[$0] } ?? 0 : 0
        let oldBlockKeys = blocks.dropFirst(blockStart).map(BlockStructureKey.init)
        let oldInputIDs = inputItems.dropFirst(inputStart).map { $0.value.id }
        for id in sourceIDs.dropFirst(begin) {
            items.removeValue(forKey: id)
            if let action = actionByItem.removeValue(forKey: id) {
                priorActionsForRebuild[action.id] = action
                actions.removeValue(forKey: action.id)
            }
            rowByItem.removeValue(forKey: id)
            itemPositionByID.removeValue(forKey: id)
            itemBlockID.removeValue(forKey: id)
        }
        for item in inputItems.dropFirst(inputStart) {
            inputPositions.removeValue(forKey: item.value.id)
            inputBlockPositions.removeValue(forKey: item.value.id)
            intervalsByInput.removeValue(forKey: item.value.id)
        }
        sourceIDs.removeLast(sourceIDs.count - begin)
        inputItems.removeLast(inputItems.count - inputStart)
        for block in blocks.dropFirst(blockStart) { blockPositionByID.removeValue(forKey: block.id) }
        blocks.removeLast(blocks.count - blockStart)
        intervals.removeLast(intervals.count - affected)
        liveState = nextLive
        transcriptRevision = revision
        var start = begin
        var hasInput = false
        if begin < source.count {
            for position in begin..<source.count {
                itemPositionByID[source[position].id] = sourceIDs.count
                sourceIDs.append(source[position].id)
                if case .userMessage = source[position] {
                    if position > start {
                        appendInterval(source, range: start..<position, baseline: baseline, running: false, isInput: hasInput)
                        if let last = intervals.last?.lastSnapshot { baseline = last }
                    }
                    start = position; hasInput = true
                }
            }
            appendInterval(source, range: start..<source.count, baseline: baseline,
                running: nextLive.isProcessing, isInput: hasInput)
        }
        let preservesTimelinePrefix = oldBlockKeys.count <= blocks.count - blockStart
            && oldBlockKeys.enumerated().allSatisfy { offset, key in
                key == BlockStructureKey(self.blocks[blockStart + offset])
            }
        let preservesHistoryPrefix = oldInputIDs.count <= inputItems.count - inputStart
            && oldInputIDs.enumerated().allSatisfy { offset, id in
                id == self.inputItems[inputStart + offset].value.id
            }
        if !preservesTimelinePrefix { timelineStructureRevision &+= 1 }
        if !preservesHistoryPrefix { historyStructureRevision &+= 1 }
        itemCount = source.count
        priorActionsForRebuild.removeAll()
    }

    private func stampActionRevisions(_ action: Action) {
        guard let previous = priorActionsForRebuild[action.id] else {
            action.contentRevision = transcriptRevision
            return
        }
        action.contentRevision = previous.accumulator.items == action.accumulator.items
            ? previous.contentRevision : transcriptRevision
        let preservesPrefix = action.detailItems.map(\.value.id).starts(with: previous.detailItems.map(\.value.id))
        action.structureRevision = preservesPrefix ? previous.structureRevision : previous.structureRevision &+ 1
    }

    private func appendBlock(_ block: Block) {
        blockPositionByID[block.id] = blocks.count
        blocks.append(block)
        switch block.content {
        case .item(let item): itemBlockID[item.value.id] = block.id
        case .group(let action):
            stampActionRevisions(action)
            for item in action.detailItems { itemBlockID[item.value.id] = block.id }
        case .card(let card):
            for row in card.rows {
                for entry in row.entries {
                    switch entry {
                    case .item(let item): itemBlockID[item.value.id] = block.id
                    case .action(let action):
                        stampActionRevisions(action)
                        for item in action.detailItems { itemBlockID[item.value.id] = block.id }
                    }
                }
            }
        }
    }

    private func register(_ action: Action) {
        actions[action.id] = action
        for item in action.detailItems { items[item.value.id] = item; actionByItem[item.value.id] = action }
    }

    private func appendInterval(_ source: [ChatItem], range: Range<Int>, baseline: ChatItem?, running: Bool, isInput: Bool) {
        let inputID = isInput ? source[range.lowerBound].id : nil
        let values = Array(source[range])
        let input = Item(source[range.lowerBound])
        let lastSnapshot = values.last { if case .taskList = $0 { true } else { false } }
        let effective = (lastSnapshot ?? baseline).flatMap(AgentStatusCardBuilder.Snapshot.init)
        let state = AgentStatusLiveState(isProcessing: running, activityState: liveState.activityState,
            hangAssessment: nil, isAwaitingReply: running && liveState.isAwaitingReply)
        let sourceBlocks = usesCards && isInput
            ? AgentStatusCardBuilder.buildInputInterval(items: values, baseline: baseline, liveState: state)
            : ChatTranscriptGrouping.blocks(from: values)
        var card: Card?
        let blockStart = blocks.count
        for block in sourceBlocks {
            switch block {
            case .single(let value):
                let item = Item(value); items[value.id] = item
                appendBlock(.init(id: value.id, inputID: inputID, content: .item(item)))
            case .commandGroup(let id, let values):
                let accumulator = AgentStatusCardBuilder.ActionAccumulator(items: values)
                let action = Action(accumulator.materialize(running: running, turnEnd: input.value.readTurnEnd),
                    inputID: inputID, items: &items)
                register(action)
                appendBlock(.init(id: id, inputID: inputID, content: .group(action)))
            case .statusCard(let value):
                let record = Card(value, input: input, effective: effective, seenOwnSnapshot: lastSnapshot != nil,
                    hasWork: values.contains { AgentStatusCardBuilder.isWork($0) && !AgentStatusCardBuilder.isEmptyFileChange($0) },
                    revision: nextRevision, contentRevision: transcriptRevision, items: &items, actions: &actions, actionByItem: &actionByItem,
                    rowByItem: &rowByItem, liveState: state)
                nextRevision &+= 1
                card = record
                let lastWorkID = values.last { AgentStatusCardBuilder.isWork($0) && !AgentStatusCardBuilder.isEmptyFileChange($0) }?.id
                record.lastAction = lastWorkID.flatMap { actionByItem[$0] }
                record.lastWorkRowID = lastWorkID.flatMap { rowByItem[$0]?.id }
                appendBlock(.init(id: value.id, inputID: inputID, content: .card(record)))
            }
        }
        if let card {
            for value in values where itemBlockID[value.id] == nil { itemBlockID[value.id] = card.id }
        }
        if let inputID {
            intervalsByInput[inputID] = intervals.count
            inputBlockPositions[inputID] = blockStart
            inputPositions[inputID] = inputItems.count
            inputItems.append(items[inputID] ?? input)
        }
        intervals.append(.init(start: range.lowerBound, end: range.upperBound, inputID: inputID,
            baseline: baseline, blockStart: blockStart, card: card, lastSnapshot: lastSnapshot))
    }

    func update(items source: [ChatItem], from dirty: Int, changedItemIDs: Set<String>?, revision: Int, liveState nextLive: AgentStatusLiveState) -> Bool {
        guard source.count >= itemCount, liveState.isProcessing == nextLive.isProcessing,
              let last = intervals.last, last.end == itemCount else {
            return source.isEmpty && itemCount == 0 && revision == transcriptRevision
        }
        let start = min(dirty, itemCount)
        var changedSemantics = false
        var latestContentChanged = false
        if start < itemCount {
            let positions = changedItemIDs.map { ids in ids.compactMap { itemPositionByID[$0] }.filter { $0 < itemCount } }
                ?? Array(start..<itemCount)
            for position in positions {
                guard position < source.count, source[position].id == sourceIDs[position],
                      let previous = items[sourceIDs[position]], previous.value.readKind == source[position].readKind else { return false }
                guard previous.value != source[position], let ownerIndex = intervalIndex(containing: position) else { continue }
                let ownerCard = intervals[ownerIndex].card
                let running = ownerIndex == intervals.count - 1 && nextLive.isProcessing
                let end = ownerCard?.input.value.readTurnEnd
                if ownerIndex == intervals.count - 1 { latestContentChanged = true }
                ownerCard?.contentRevision = revision
                switch source[position] {
                case .userMessage, .taskList: return false
                case .commandExecution, .fileChange, .subAgentMarker:
                    if ownerCard != nil, AgentStatusCardBuilder.isEmptyFileChange(source[position]) { return false }
                    guard let action = actionByItem[source[position].id] else {
                        guard ownerCard == nil else { return false }
                        previous.replace(source[position]); continue
                    }
                    guard ownerCard == nil || AgentStatusCardBuilder.mergeKind(previous.value) == AgentStatusCardBuilder.mergeKind(source[position]) else { return false }
                    let oldSummary = action.summary(running: running, turnEnd: end)
                    let oldState = action.accumulator.state(running: running, turnEnd: end)
                    ownerCard?.changeCounts.update(source[position])
                    action.accumulator.replace(source[position]); previous.replace(source[position]); action.cachedGroupSummary = nil
                    if oldSummary != action.summary(running: running, turnEnd: end), let ownerCard {
                        ownerCard.revision = nextRevision; nextRevision &+= 1
                    }
                    action.contentRevision = revision
                    if let row = rowByItem[source[position].id] {
                        row.actionStates[oldState, default: 0] -= 1
                        row.actionStates[action.accumulator.state(running: running, turnEnd: end), default: 0] += 1
                    }
                default: previous.replace(source[position])
                }
            }
        }
        if source.count > itemCount {
            if last.card == nil, !usesCards || last.inputID == nil {
                return appendUngroupedInterval(source, revision: revision, liveState: nextLive)
            }
            guard nextLive.isProcessing, let card = last.card else { return false }
            changedSemantics = true
            latestContentChanged = true
            for value in source[itemCount...] {
                switch value { case .userMessage, .taskList, .turnCost: return false; default: break }
                if AgentStatusCardBuilder.isEmptyFileChange(value) { return false }
                let item = Item(value)
                card.changeCounts.update(value)
                if !card.hasActivityBoundary {
                    if case .agentMessage = value { return false }
                    if case .reasoning = value {
                        items[value.id] = item
                        let position = blocks.count - 1
                        blocks.insert(.init(id: value.id, inputID: last.inputID, content: .item(item)), at: position)
                        timelineStructureRevision &+= 1
                        blockPositionByID[value.id] = position; blockPositionByID[card.id] = position + 1
                        itemBlockID[value.id] = value.id
                        itemPositionByID[value.id] = sourceIDs.count; sourceIDs.append(value.id)
                        continue
                    }
                }
                items[value.id] = item
                let row: Row
                if let existing = card.appendRow { row = existing }
                else {
                    row = Row(item: item, inputID: last.inputID)
                    let beforeTask = card.shownIndex.first { $0.value == card.outsideAnchor }?.key
                    let position = beforeTask.flatMap { task in card.rows.firstIndex { $0.id == "task-\(task)" } } ?? card.rows.count
                    card.rows.insert(row, at: position)
                    for index in position..<card.rows.count { card.rowPositions[card.rows[index].id] = index }
                    card.rowsByID[row.id] = row; card.outsideByAnchor[card.outsideAnchor] = row; card.appendRow = row
                    card.revision = nextRevision; nextRevision &+= 1
                }
                if AgentStatusCardBuilder.isWork(value) {
                    card.hasActivityBoundary = true
                    let action: Action
                    if let kind = AgentStatusCardBuilder.mergeKind(value), case .action(let previous)? = row.entries.last,
                       AgentStatusCardBuilder.mergeKind(previous.accumulator.items[0]) == kind {
                        action = previous
                        row.actionStates[action.accumulator.state(running: true, turnEnd: card.input.value.readTurnEnd), default: 0] -= 1
                        action.accumulator.append(value); action.detailItems.append(item)
                    } else {
                        action = Action(item, inputID: last.inputID)
                        actions[action.id] = action; row.entryPositions[action.id] = row.entries.count
                        row.entries.append(.action(action)); row.actionCount += 1
                    }
                    action.contentRevision = revision
                    actionByItem[value.id] = action; rowByItem[value.id] = row
                    row.actionStates[action.accumulator.state(running: true, turnEnd: card.input.value.readTurnEnd), default: 0] += 1
                    card.lastAction = action; card.lastWorkRowID = row.id
                } else { row.entryPositions[value.id] = row.entries.count; row.entries.append(.item(item)); rowByItem[value.id] = row }
                itemBlockID[value.id] = card.id
                itemPositionByID[value.id] = sourceIDs.count
                sourceIDs.append(value.id)
            }
            intervals[intervals.count - 1].end = source.count
            itemCount = source.count
        }
        liveState = nextLive
        if let card = intervals.last?.card {
            let current = card.lastAction.flatMap { action -> AgentStatusAction.Label? in
                action.accumulator.state(running: nextLive.isProcessing, turnEnd: card.input.value.readTurnEnd) == .running
                    ? action.accumulator.label : nil
            }
            let previousHeader = card.header
            card.header = AgentStatusCardBuilder.makeHeader(current: current, startedAt: card.input.value.timestamp,
                turnEnd: card.input.value.readTurnEnd, running: nextLive.isProcessing, liveState: nextLive)
            changedSemantics = changedSemantics || previousHeader != card.header
            if changedSemantics { card.revision = nextRevision; nextRevision &+= 1 }
            if latestContentChanged || changedSemantics { card.contentRevision = revision }
        }
        transcriptRevision = revision
        return true
    }
    private func appendUngroupedInterval(_ source: [ChatItem], revision: Int, liveState nextLive: AgentStatusLiveState) -> Bool {
        let inputID = intervals.last?.inputID
        for value in source[itemCount...] {
            switch value { case .userMessage, .taskList: return false; default: break }
            let item = Item(value)
            items[value.id] = item
            if case .commandExecution = value {
                let action: Action
                if case .group(let previous)? = blocks.last?.content {
                    action = previous
                    action.accumulator.append(value); action.detailItems.append(item); action.cachedGroupSummary = nil
                } else {
                    action = Action(item, inputID: inputID)
                    actions[action.id] = action
                    appendBlock(.init(id: action.id, inputID: inputID, content: .group(action)))
                }
                action.contentRevision = revision
                actionByItem[value.id] = action
                itemBlockID[value.id] = action.id
            } else {
                appendBlock(.init(id: value.id, inputID: inputID, content: .item(item)))
            }
            itemPositionByID[value.id] = sourceIDs.count; sourceIDs.append(value.id)
        }
        intervals[intervals.count - 1].end = source.count
        itemCount = source.count; transcriptRevision = revision; liveState = nextLive
        return true
    }

}

extension RuntimeChatReadIndex {
    func response(for request: SessionRuntimeContentRequest, usage: [String: TurnUsage]) throws -> SessionRuntimeContentResponse {
        let response: SessionRuntimeContentResponse
        switch request.target {
        case .chatReadTail:
            response = .chatReadPage(try timelineBefore(request, end: blocks.count, usage: usage))
        case .chatReadBefore(let cursor):
            try validate(cursor, scope: "timeline", revision: timelineStructureRevision, ids: blocks.mapAt(cursor.index, \.id))
            response = .chatReadPage(try timelineBefore(request, end: cursor.index, usage: usage))
        case .chatReadAfter(let cursor):
            try validate(cursor, scope: "timeline", revision: timelineStructureRevision, ids: blocks.mapAt(cursor.index, \.id))
            response = .chatReadPage(try timeline(request, start: cursor.index + 1, usage: usage))
        case .chatReadAround(let inputID):
            guard let position = inputBlockPositions[inputID] else { throw SessionRuntimeContentError.notFound }
            response = .chatReadPage(try timeline(request, start: position, usage: usage))
        case .chatReadAroundItem(let itemID):
            guard let position = itemPositionByID[itemID],
                  let intervalIndex = intervalIndex(containing: position) else { throw SessionRuntimeContentError.notFound }
            let interval = intervals[intervalIndex]
            guard let blockID = itemBlockID[itemID], let blockPosition = blockPositionByID[blockID] else {
                throw SessionRuntimeContentError.notFound
            }
            let cardID: String?
            if case .card(let card) = blocks[blockPosition].content { cardID = card.id } else { cardID = nil }
            var page = try timeline(request, start: blockPosition, usage: usage)
            page.revealTarget = .init(inputID: interval.inputID, cardID: cardID,
                rowID: cardID == nil ? nil : rowByItem[itemID]?.id,
                entryID: actionByItem[itemID]?.id ?? itemID, itemID: itemID)
            response = .chatReadPage(page)
        case .chatCardRows(let inputID, let cursor):
            let card = try card(inputID)
            let start = try nextStart(cursor, scope: "rows:\(inputID)", revision: card.revision, count: card.rows.count) {
                card.rows[$0].id
            }
            response = try cardRows(request, inputID: inputID, card: card, start: start)
        case .chatCardRowsAround(let inputID, let rowID):
            let card = try card(inputID)
            guard let start = card.rowPositions[rowID] else { throw SessionRuntimeContentError.notFound }
            response = try cardRows(request, inputID: inputID, card: card, start: start)
        case .chatRowEntries(let inputID, let rowID, let cursor):
            let card = try card(inputID)
            guard let row = card.rowsByID[rowID] else { throw SessionRuntimeContentError.notFound }
            if let cursor {
                try validate(cursor, scope: "entries:\(inputID):\(rowID)", revision: card.revision,
                    ids: row.entries.mapAt(cursor.index, \.id))
            }
            response = try cardEntries(request, inputID: inputID, card: card, row: row, end: cursor?.index ?? row.entries.count)
        case .chatRowEntriesAround(let inputID, let rowID, let entryID):
            let card = try card(inputID)
            guard let row = card.rowsByID[rowID], let position = row.entryPositions[entryID] else { throw SessionRuntimeContentError.notFound }
            response = try cardEntries(request, inputID: inputID, card: card, row: row, end: position + 1)
        case .chatActionItems(let inputID, let actionID, let cursor):
            guard let action = actions[actionID], action.inputID == inputID else { throw SessionRuntimeContentError.notFound }
            let revision = inputID.flatMap { intervalsByInput[$0] }.flatMap { intervals[$0].card?.revision } ?? action.structureRevision
            let scope = "action:\(inputID ?? ""): \(actionID)"
            let start = try nextStart(cursor, scope: scope, revision: revision, count: action.detailItems.count) {
                action.detailItems[$0].value.id
            }
            response = try actionItems(request, inputID: inputID, action: action, start: start)
        case .chatActionItemsFrom(let inputID, let actionID, let itemID):
            guard let action = actions[actionID], action.inputID == inputID,
                  let start = action.accumulator.index(ofItemID: itemID) else { throw SessionRuntimeContentError.notFound }
            response = try actionItems(request, inputID: inputID, action: action, start: start)
        case .inputHistory(let cursor):
            if let cursor { try validate(cursor, scope: "history", revision: historyStructureRevision, ids: inputItems.mapAt(cursor.index, \.value.id)) }
            let end = cursor?.index ?? inputItems.count
            response = .inputHistoryPage(try history(request, start: max(0, end - SessionRuntimeChatReadLimits.maximumItemsPerPage), end: end, backwards: true))
        case .inputHistoryAfter(let cursor):
            try validate(cursor, scope: "history", revision: historyStructureRevision, ids: inputItems.mapAt(cursor.index, \.value.id))
            response = .inputHistoryPage(try history(request, start: cursor.index + 1, end: inputItems.count))
        default: throw SessionRuntimeContentError.invalidRequest
        }
        guard try Self.encoder.encode(response).count <= SessionRuntimeChatReadLimits.maximumResponseBytes else {
            throw SessionRuntimeContentError.invalidRequest
        }
        return response
    }

    private func actionItems(_ request: SessionRuntimeContentRequest, inputID: String?, action: Action, start: Int) throws -> SessionRuntimeContentResponse {
        let revision = inputID.flatMap { intervalsByInput[$0] }.flatMap { intervals[$0].card?.revision } ?? action.structureRevision
        let scope = "action:\(inputID ?? ""): \(action.id)"
        let values = try page(from: start, count: action.detailItems.count) { try action.detailItems[$0].reference() }
        return .actionItemsPage(.init(sessionID: request.sessionID, executionID: executionID,
            inputID: inputID, actionID: action.id, revision: revision, items: values,
            nextCursor: nextCursor(scope: scope, revision: revision, start: start, count: values.count,
                total: action.detailItems.count, id: { action.detailItems[$0].value.id })))
    }

    private func cardRows(_ request: SessionRuntimeContentRequest, inputID: String, card: Card, start: Int) throws -> SessionRuntimeContentResponse {
        let rows = try page(from: start, count: card.rows.count, maximumItems: 8) { card.rows[$0].summary() }
        return .cardRowsPage(.init(sessionID: request.sessionID, executionID: executionID,
            card: card.summary(), rows: rows, nextCursor: nextCursor(scope: "rows:\(inputID)", revision: card.revision,
                start: start, count: rows.count, total: card.rows.count, id: { card.rows[$0].id })))
    }

    private func cardEntries(_ request: SessionRuntimeContentRequest, inputID: String, card: Card, row: Row, end: Int) throws -> SessionRuntimeContentResponse {
        let entries: [SessionRuntimeCardEntry] = try pageBefore(end: end) { position in
            switch row.entries[position] {
            case .item(let item): .item(try item.reference())
            case .action(let action): .action(action.summary(running: card.header.isLive, turnEnd: card.input.value.readTurnEnd))
            }
        }
        return .cardEntriesPage(.init(sessionID: request.sessionID, executionID: executionID,
            inputID: inputID, rowID: row.id, revision: card.revision, entries: entries,
            nextCursor: end > entries.count ? cursor("entries:\(inputID):\(row.id)", revision: card.revision,
                index: end - entries.count, id: row.entries[end - entries.count].id) : nil))
    }

    private func intervalIndex(containing position: Int) -> Int? {
        var low = 0
        var high = intervals.count
        while low < high {
            let middle = (low + high) / 2
            if intervals[middle].end <= position { low = middle + 1 } else { high = middle }
        }
        return low < intervals.count && intervals[low].start <= position ? low : nil
    }

    private func card(_ inputID: String) throws -> Card {
        guard let position = intervalsByInput[inputID], let card = intervals[position].card else {
            throw SessionRuntimeContentError.notFound
        }
        return card
    }

    private func readBlock(at position: Int) throws -> SessionRuntimeChatReadBlock {
        let block = blocks[position]
        let content: SessionRuntimeChatReadBlock.Content
        switch block.content {
        case .item(let item): content = .item(try item.reference())
        case .group(let action):
            let running = liveState.isProcessing && block.id == blocks.last?.id
            var summary = action.summary(running: running, turnEnd: nil)
            summary.commandGroup = action.commandGroupSummary()
            content = .commandGroup(summary)
        case .card(let card): content = .card(card.summary())
        }
        return .init(id: block.id, ownerInputID: block.inputID, content: content)
    }

    private func timelineBefore(_ request: SessionRuntimeContentRequest, end: Int, usage: [String: TurnUsage]) throws -> SessionRuntimeChatReadPage {
        let values = try pageBefore(end: end) { try readBlock(at: $0) }
        return makeTimeline(request, start: end - values.count, values: values, usage: usage)
    }

    private func timeline(_ request: SessionRuntimeContentRequest, start: Int, end: Int? = nil,
                          usage: [String: TurnUsage]) throws -> SessionRuntimeChatReadPage {
        let limit = end ?? blocks.count
        let values: [SessionRuntimeChatReadBlock] = try page(from: start, count: limit) { position in
            try readBlock(at: position)
        }
        return makeTimeline(request, start: start, values: values, usage: usage)
    }

    private func makeTimeline(_ request: SessionRuntimeContentRequest, start: Int,
                              values: [SessionRuntimeChatReadBlock], usage: [String: TurnUsage]) -> SessionRuntimeChatReadPage {
        let finish = start + values.count
        let older = start > 0 && start < blocks.count ? cursor("timeline", revision: timelineStructureRevision, index: start, id: blocks[start].id) : nil
        let newer = finish < blocks.count && finish > 0 ? cursor("timeline", revision: timelineStructureRevision, index: finish - 1, id: blocks[finish - 1].id) : nil
        var visibleUsage: [String: TurnUsage] = [:]
        for value in values { if let valueUsage = usage[value.id] { visibleUsage[value.id] = valueUsage } }
        return .init(sessionID: request.sessionID, executionID: executionID, transcriptRevision: transcriptRevision,
            revision: timelineStructureRevision, totalBlockCount: blocks.count, startIndex: start, blocks: values, olderCursor: older,
            newerCursor: newer, latestHeader: intervals.last?.card?.header.bounded, turnUsageByItemID: visibleUsage)
    }

    private func history(_ request: SessionRuntimeContentRequest, start: Int, end: Int, backwards: Bool = false) throws -> SessionRuntimeInputHistoryPage {
        let value: (Int) throws -> SessionRuntimeInputHistorySummary = { position in
            let item = self.inputItems[position]
            guard case .userMessage(_, let text, let timestamp, let attachments, _) = item.value else {
                throw SessionRuntimeContentError.invalidRequest
            }
            return .init(id: item.value.id, preview: .init(text, maximumBytes: 512), timestamp: timestamp,
                canRecall: attachments.isEmpty && text.range(of: #"\[Image #\d+\]"#, options: .regularExpression) == nil,
                content: try item.reference())
        }
        let values = backwards ? try pageBefore(end: end, value: value) : try page(from: start, count: end, value: value)
        let start = backwards ? end - values.count : start
        let finish = start + values.count
        return .init(sessionID: request.sessionID, executionID: executionID, revision: historyStructureRevision, totalCount: inputItems.count,
            entries: values,
            olderCursor: start > 0 ? cursor("history", revision: historyStructureRevision, index: start, id: inputItems[start].value.id) : nil,
            newerCursor: finish < inputItems.count && finish > 0
                ? cursor("history", revision: historyStructureRevision, index: finish - 1, id: inputItems[finish - 1].value.id) : nil)
    }

    private func pageBefore<Value: Encodable>(end: Int, value: (Int) throws -> Value) throws -> [Value] {
        guard end >= 0 else { throw SessionRuntimeContentError.invalidRequest }
        var result: [Value] = []
        var bytes = 8192
        for position in (max(0, end - SessionRuntimeChatReadLimits.maximumItemsPerPage)..<end).reversed() {
            let candidate = try value(position)
            let size = try Self.encoder.encode(candidate).count + 1
            guard bytes + size <= SessionRuntimeChatReadLimits.maximumResponseBytes else { break }
            result.append(candidate); bytes += size
        }
        guard end == 0 || !result.isEmpty else { throw SessionRuntimeContentError.invalidRequest }
        return result.reversed()
    }

    private func page<Value: Encodable>(from start: Int, count: Int, maximumItems: Int = SessionRuntimeChatReadLimits.maximumItemsPerPage, value: (Int) throws -> Value) throws -> [Value] {
        guard start >= 0, start <= count else { throw SessionRuntimeContentError.invalidRequest }
        var result: [Value] = []
        var bytes = 8192
        for position in start..<min(count, start + maximumItems) {
            let candidate = try value(position)
            let size = try Self.encoder.encode(candidate).count + 1
            guard bytes + size <= SessionRuntimeChatReadLimits.maximumResponseBytes else { break }
            result.append(candidate); bytes += size
        }
        guard start == count || !result.isEmpty else { throw SessionRuntimeContentError.invalidRequest }
        return result
    }

    private func nextStart(_ cursor: SessionRuntimeChatReadCursor?, scope: String, revision: UInt64,
                           count: Int, id: (Int) -> String) throws -> Int {
        guard let cursor else { return 0 }
        guard cursor.scopeID == scope, cursor.index >= 0 else { throw SessionRuntimeContentError.invalidRequest }
        guard cursor.revision == revision else { throw SessionRuntimeContentError.staleContent }
        guard cursor.index < count else { throw SessionRuntimeContentError.invalidRequest }
        guard id(cursor.index) == cursor.anchorID else { throw SessionRuntimeContentError.staleContent }
        return cursor.index + 1
    }

    private func nextCursor(scope: String, revision: UInt64, start: Int, count: Int, total: Int,
                            id: (Int) -> String) -> SessionRuntimeChatReadCursor? {
        let finish = start + count
        return finish > 0 && finish < total ? cursor(scope, revision: revision, index: finish - 1, id: id(finish - 1)) : nil
    }

    private func validate(_ cursor: SessionRuntimeChatReadCursor, scope: String, revision: UInt64, ids: String?) throws {
        guard cursor.index >= 0, cursor.scopeID == scope else { throw SessionRuntimeContentError.invalidRequest }
        guard cursor.revision == revision, ids == cursor.anchorID else { throw SessionRuntimeContentError.staleContent }
    }

    private func cursor(_ scope: String, revision: UInt64, index: Int, id: String) -> SessionRuntimeChatReadCursor {
        .init(scopeID: scope, revision: revision, index: index, anchorID: id)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return encoder
    }
}

extension ChatSessionViewModel {
    public func runtimeChatReadContent(for request: SessionRuntimeContentRequest) async throws -> SessionRuntimeContentResponse {
        guard request.sessionID == id, request.executionID == executionID else { throw SessionRuntimeContentError.staleContent }
        guard request.target.requiresChatReadModel else { return try runtimeContent(for: request) }
        let response = try await runtimeChatReadIndex.response(items: transcript, executionID: executionID,
            revision: transcriptRevision, liveState: statusCardLiveState,
            usesCards: AgentStatusCardRouting.usesStatusCard(agentRef.builtinKind), request: request, usage: turnUsageByItemID)
        guard request.executionID == executionID else { throw SessionRuntimeContentError.staleContent }
        return response
    }
}

private func bounded(_ text: String) -> String { SessionRuntimeTextPreview(text, maximumBytes: 512).displayText }

private extension Array {
    func mapAt<Value>(_ index: Int, _ keyPath: KeyPath<Element, Value>) -> Value? {
        indices.contains(index) ? self[index][keyPath: keyPath] : nil
    }
}

private extension ChatItem {
    var readOutput: String {
        if case .commandExecution(_, _, let output, _, _, _) = self { output } else { "" }
    }
    var readCommand: String? {
        if case .commandExecution(_, let command, _, _, _, _) = self { command } else { nil }
    }
    var readTurnEnd: ChatTurnEnd? {
        if case .userMessage(_, _, _, _, let end) = self { end } else { nil }
    }
    var readKind: String {
        switch self {
        case .userMessage: "userMessage"
        case .agentMessage: "agentMessage"
        case .reasoning: "reasoning"
        case .commandExecution: "commandExecution"
        case .fileChange: "fileChange"
        case .error: "error"
        case .subAgentMarker: "subAgentMarker"
        case .turnCost: "turnCost"
        case .userQuestion: "userQuestion"
        case .taskList: "taskList"
        }
    }
}

private extension AgentStatusAction.Label {
    var bounded: Self {
        switch self {
        case .read(let file, let more): .read(file: SessionRuntimeTextPreview(file, maximumBytes: 512).displayText, more: more)
        case .search(let query, let hits): .search(query: SessionRuntimeTextPreview(query, maximumBytes: 512).displayText, hits: hits)
        case .edit(let file): .edit(file: SessionRuntimeTextPreview(file, maximumBytes: 512).displayText)
        case .write(let file): .write(file: SessionRuntimeTextPreview(file, maximumBytes: 512).displayText)
        case .run(let intent): .run(intent: SessionRuntimeTextPreview(intent, maximumBytes: 512).displayText)
        case .command(let command): .command(SessionRuntimeTextPreview(command, maximumBytes: 512).displayText)
        case .tool(let tool): .tool(SessionRuntimeTextPreview(tool, maximumBytes: 512).displayText)
        case .subAgent(let description, let type, let status):
            .subAgent(description: SessionRuntimeTextPreview(description, maximumBytes: 512).displayText,
                type: SessionRuntimeTextPreview(type, maximumBytes: 512).displayText, status: status)
        case .searches, .editFiles: self
        }
    }
}

private extension AgentStatusHeader {
    var bounded: Self {
        .init(state: state, current: current?.bounded, activityState: activityState,
            startedAt: startedAt, endedAt: endedAt, silence: silence)
    }
}
