import Foundation

struct RuntimeOverviewTranscriptIndex {
    private var executionID: UUID?
    private var indexedCount = 0
    private var pendingPositions: [Int] = []
    private var agentPositions: [Int] = []
    private var invalidatedFrom: Int? = 0
    private var editedItemIDs: Set<String> = []

    mutating func invalidate(from index: Int = 0) {
        invalidatedFrom = min(invalidatedFrom ?? max(0, index), max(0, index))
    }

    mutating func noteChange(isAppendOnly: Bool, from index: Int, itemIDs: Set<String>?) {
        guard !isAppendOnly else { return }
        if let itemIDs { editedItemIDs.formUnion(itemIDs) }
        else { invalidate(from: index) }
    }

    mutating func metadata(in transcript: [ChatItem], positionsByID: [String: Int], executionID: UUID)
        -> (pendingPositions: [Int], lastAgentText: SessionRuntimeTextPreview?) {
        if self.executionID != executionID || transcript.count < indexedCount {
            self.executionID = executionID
            indexedCount = 0
            pendingPositions.removeAll()
            agentPositions.removeAll()
            invalidatedFrom = 0
        }
        let start = min(invalidatedFrom ?? indexedCount, indexedCount, transcript.count)
        if invalidatedFrom != nil {
            pendingPositions.removeSubrange(Self.lowerBound(start, in: pendingPositions)..<pendingPositions.count)
            agentPositions.removeSubrange(Self.lowerBound(start, in: agentPositions)..<agentPositions.count)
        }
        for id in editedItemIDs {
            guard let position = positionsByID[id], position < start else { continue }
            update(transcript[position], at: position)
        }
        for position in start..<transcript.count { update(transcript[position], at: position) }
        indexedCount = transcript.count
        invalidatedFrom = nil
        editedItemIDs.removeAll()
        let lastAgentText: SessionRuntimeTextPreview?
        if let index = agentPositions.last, case .agentMessage(_, let text, _) = transcript[index] {
            lastAgentText = SessionRuntimeTextPreview(text)
        } else { lastAgentText = nil }
        return (pendingPositions, lastAgentText)
    }

    private mutating func update(_ item: ChatItem, at index: Int) {
        let pending: Bool
        if case .userQuestion(_, _, _, _, .pending, _) = item { pending = true }
        else { pending = false }
        Self.set(index, present: pending, in: &pendingPositions)
        let eligible: Bool
        if case .agentMessage(_, let text, _) = item {
            eligible = !SessionRuntimeTextPreview(text).text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else { eligible = false }
        Self.set(index, present: eligible, in: &agentPositions)
    }

    private static func set(_ index: Int, present: Bool, in positions: inout [Int]) {
        let offset = lowerBound(index, in: positions)
        if offset < positions.count, positions[offset] == index {
            if !present { positions.remove(at: offset) }
        } else if present { positions.insert(index, at: offset) }
    }

    private static func lowerBound(_ index: Int, in positions: [Int]) -> Int {
        guard let last = positions.last else { return 0 }
        if last < index { return positions.count }
        if last == index { return positions.count - 1 }
        var lower = 0
        var upper = positions.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if positions[middle] < index { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }
}
