import AgentDomain
import DashboardFeature
import Darwin
import Foundation
import SessionFeature

struct RuntimeArrayPatch<Element: Codable & Equatable & Sendable>: Codable, Sendable {
    let prefixCount: Int
    let suffix: [Element]

    init(prefixCount: Int, suffix: [Element]) {
        self.prefixCount = prefixCount
        self.suffix = suffix
    }

    init(replacing baseline: [Element], with value: [Element]) {
        self.init(replacing: baseline, with: value, areEquivalent: { $0 == $1 })
    }

    init(replacing baseline: [Element], with value: [Element],
         areEquivalent: (Element, Element) throws -> Bool) rethrows {
        if sharesStorage(baseline, value) {
            prefixCount = value.count
            suffix = []
            return
        }
        var count = 0
        for (old, new) in zip(baseline, value) {
            guard try areEquivalent(old, new) else { break }
            count += 1
        }
        prefixCount = count
        suffix = Array(value.dropFirst(count))
    }

    func applying(to baseline: [Element]) throws -> [Element] {
        guard (0...baseline.count).contains(prefixCount) else { throw invalidSnapshotUpdate() }
        if prefixCount == baseline.count, suffix.isEmpty { return baseline }
        return Array(baseline.prefix(prefixCount)) + suffix
    }
}

struct RuntimeLogPatch: Codable, Sendable {
    let retainedSuffixCount: Int
    let appended: [String]

    init(retainedSuffixCount: Int, appended: [String]) {
        self.retainedSuffixCount = retainedSuffixCount
        self.appended = appended
    }

    init(replacing baseline: [String], with value: [String]) {
        guard !value.isEmpty else {
            retainedSuffixCount = 0
            appended = []
            return
        }
        if sharesStorage(baseline, value) {
            retainedSuffixCount = value.count
            appended = []
            return
        }
        var fallback = Array(repeating: 0, count: value.count)
        var count = 0
        for index in value.indices.dropFirst() {
            while count > 0, !sameUTF8(value[index], value[count]) { count = fallback[count - 1] }
            if sameUTF8(value[index], value[count]) { count += 1 }
            fallback[index] = count
        }
        count = 0
        for entry in baseline {
            while count > 0, count == value.count || !sameUTF8(entry, value[count]) {
                count = fallback[count - 1]
            }
            if sameUTF8(entry, value[count]) { count += 1 }
        }
        retainedSuffixCount = count
        appended = Array(value.dropFirst(count))
    }

    func applying(to baseline: [String]) throws -> [String] {
        guard (0...baseline.count).contains(retainedSuffixCount) else { throw invalidSnapshotUpdate() }
        if retainedSuffixCount == baseline.count, appended.isEmpty { return baseline }
        return Array(baseline.suffix(retainedSuffixCount)) + appended
    }
}

struct SessionRuntimeChatPatch: Codable, Sendable {
    let id: SessionID
    var executionID: UUID
    let transcript: RuntimeArrayPatch<ChatItem>
    var subAgentTranscripts: [String: RuntimeArrayPatch<ChatItem>]
    let rawEventLog: RuntimeLogPatch
    let reusedSkillSelection: Bool
    let reusedHistoryEntries: Bool
    let reusedHistorySummaries: Bool
}

struct SessionRuntimePreparedSnapshot: Sendable {
    let update: SessionRuntimeSnapshotUpdate
    let baseline: SessionRuntimeSnapshotBaseline
}

struct SessionRuntimeSnapshotUpdate: Codable, Sendable {
    let sequence: UInt64
    let baseSequence: UInt64?
    var snapshot: DashboardRuntimeSnapshot
    var chatPatches: [SessionRuntimeChatPatch]

    static func prepare(_ envelope: SessionRuntimeSnapshotEnvelope,
                        base: SessionRuntimeSnapshotBaseline?,
                        maximumBytes: Int = SessionRuntimeTransport.maximumSnapshotBytes) throws -> SessionRuntimePreparedSnapshot {
        let baseline = try SessionRuntimeSnapshotBaseline(envelope: envelope, previous: base, maximumBytes: maximumBytes)
        guard let base else {
            return .init(update: .init(sequence: envelope.sequence, baseSequence: nil,
                snapshot: envelope.snapshot, chatPatches: []), baseline: baseline)
        }
        guard envelope.sequence > base.envelope.sequence else { throw invalidSnapshotUpdate() }
        let oldSessions = try indexedSessions(base.envelope.snapshot.sessions)
        var payload = envelope.snapshot
        var patches: [SessionRuntimeChatPatch] = []
        for index in payload.sessions.indices {
            guard case .chat(var chat) = payload.sessions[index],
                  case .chat(let old)? = oldSessions[chat.id], sameExecution(chat, old) else { continue }
            let transcript = try RuntimeArrayPatch(replacing: old.transcript, with: chat.transcript, areEquivalent: sameChatItem)
            chat.transcript = []
            var childPatches: [String: RuntimeArrayPatch<ChatItem>] = [:]
            for (id, items) in chat.subAgents.transcripts {
                guard let previous = old.subAgents.transcripts[id] else { continue }
                childPatches[id] = try RuntimeArrayPatch(replacing: previous, with: items, areEquivalent: sameChatItem)
                chat.subAgents.transcripts[id] = []
            }
            let rawEventLog = RuntimeLogPatch(replacing: old.rawEventLog, with: chat.rawEventLog)
            let reuseSkills = try sameSkills(chat.skillSelection, old.skillSelection)
            let reuseHistory = try sameHistoryEntries(chat.historyEntries, old.historyEntries)
            let reuseSummaries = sameHistorySummaries(chat.historySummaries, old.historySummaries)
            chat.rawEventLog = []
            if reuseSkills { chat.skillSelection = nil }
            if reuseHistory { chat.historyEntries = [] }
            if reuseSummaries { chat.historySummaries = [:] }
            payload.sessions[index] = .chat(chat)
            patches.append(.init(id: chat.id, executionID: chat.executionID, transcript: transcript,
                subAgentTranscripts: childPatches, rawEventLog: rawEventLog,
                reusedSkillSelection: reuseSkills, reusedHistoryEntries: reuseHistory,
                reusedHistorySummaries: reuseSummaries))
        }
        return .init(update: .init(sequence: envelope.sequence, baseSequence: base.envelope.sequence,
            snapshot: payload, chatPatches: patches), baseline: baseline)
    }

    func restoring(base: SessionRuntimeSnapshotBaseline?,
                   maximumBytes: Int = SessionRuntimeTransport.maximumSnapshotBytes) throws -> SessionRuntimeSnapshotBaseline {
        guard sequence > 0 else { throw invalidSnapshotUpdate() }
        guard let baseSequence else {
            guard chatPatches.isEmpty else { throw invalidSnapshotUpdate() }
            return try .init(envelope: .init(sequence: sequence, snapshot: snapshot), previous: nil, maximumBytes: maximumBytes)
        }
        guard let base, baseSequence == base.envelope.sequence, sequence > baseSequence else { throw invalidSnapshotUpdate() }
        let oldSessions = try indexedSessions(base.envelope.snapshot.sessions)
        let currentSessions = try indexedSessions(snapshot.sessions)
        guard Set(chatPatches.map(\.id)).count == chatPatches.count else { throw invalidSnapshotUpdate() }
        let expected = Set(snapshot.sessions.compactMap { entry -> SessionID? in
            guard case .chat(let chat) = entry, case .chat(let old)? = oldSessions[chat.id],
                  sameExecution(chat, old) else { return nil }
            return chat.id
        })
        guard Set(chatPatches.map(\.id)) == expected else { throw invalidSnapshotUpdate() }
        var restored = snapshot
        var replacements: [SessionID: SessionRuntimeChatSnapshot] = [:]
        for patch in chatPatches {
            guard case .chat(var chat)? = currentSessions[patch.id],
                  case .chat(let old)? = oldSessions[patch.id], sameExecution(chat, old),
                  patch.executionID == chat.executionID, chat.transcript.isEmpty else { throw invalidSnapshotUpdate() }
            let sharedChildren = Set(chat.subAgents.transcripts.keys).intersection(old.subAgents.transcripts.keys)
            guard Set(patch.subAgentTranscripts.keys) == sharedChildren else { throw invalidSnapshotUpdate() }
            chat.transcript = try patch.transcript.applying(to: old.transcript)
            for (id, childPatch) in patch.subAgentTranscripts {
                guard let empty = chat.subAgents.transcripts[id], empty.isEmpty,
                      let previous = old.subAgents.transcripts[id] else { throw invalidSnapshotUpdate() }
                chat.subAgents.transcripts[id] = try childPatch.applying(to: previous)
            }
            guard chat.rawEventLog.isEmpty else { throw invalidSnapshotUpdate() }
            chat.rawEventLog = try patch.rawEventLog.applying(to: old.rawEventLog)
            if patch.reusedSkillSelection {
                guard chat.skillSelection == nil else { throw invalidSnapshotUpdate() }
                chat.skillSelection = old.skillSelection
            }
            if patch.reusedHistoryEntries {
                guard chat.historyEntries.isEmpty else { throw invalidSnapshotUpdate() }
                chat.historyEntries = old.historyEntries
            }
            if patch.reusedHistorySummaries {
                guard chat.historySummaries.isEmpty else { throw invalidSnapshotUpdate() }
                chat.historySummaries = old.historySummaries
            }
            replacements[chat.id] = chat
        }
        for index in restored.sessions.indices {
            if let chat = replacements[restored.sessions[index].id] { restored.sessions[index] = .chat(chat) }
        }
        return try .init(envelope: .init(sequence: sequence, snapshot: restored), previous: base, maximumBytes: maximumBytes)
    }
}

struct SessionRuntimeSnapshotBaseline: Sendable {
    let envelope: SessionRuntimeSnapshotEnvelope
    let encodedByteCount: Int
    private let chatSizes: [SessionID: RuntimeChatEncodedSizes]

    init(envelope: SessionRuntimeSnapshotEnvelope, previous: SessionRuntimeSnapshotBaseline?,
         maximumBytes: Int = SessionRuntimeTransport.maximumSnapshotBytes) throws {
        let oldSessions = try indexedSessions(previous?.envelope.snapshot.sessions ?? [])
        _ = try indexedSessions(envelope.snapshot.sessions)
        var shell = envelope.snapshot
        var sizes: [SessionID: RuntimeChatEncodedSizes] = [:]
        var omittedBytes = 0
        for index in shell.sessions.indices {
            guard case .chat(var chat) = shell.sessions[index] else { continue }
            let old: SessionRuntimeChatSnapshot?
            if case .chat(let value)? = oldSessions[chat.id], sameExecution(chat, value) { old = value }
            else { old = nil }
            let previousSizes = old == nil ? nil : previous?.chatSizes[chat.id]
            let current = try RuntimeChatEncodedSizes(chat, previous: old, sizes: previousSizes, maximumBytes: maximumBytes)
            try addBounded(current.omittedBytes, to: &omittedBytes, maximumBytes: maximumBytes)
            sizes[chat.id] = current
            chat.transcript = []
            chat.rawEventLog = []
            chat.skillSelection = nil
            chat.historyEntries = []
            chat.historySummaries = [:]
            for id in chat.subAgents.transcripts.keys { chat.subAgents.transcripts[id] = [] }
            shell.sessions[index] = .chat(chat)
        }
        let shellBytes = try JSONEncoder().encode(SessionRuntimeSnapshotEnvelope(sequence: envelope.sequence, snapshot: shell)).count
        try addBounded(shellBytes, to: &omittedBytes, maximumBytes: maximumBytes)
        self.envelope = envelope
        self.encodedByteCount = omittedBytes
        self.chatSizes = sizes
    }
}

private struct RuntimeArrayEncodedSizes: Sendable {
    let elementPrefixBytes: [Int]
    var encodedByteCount: Int {
        2 + (elementPrefixBytes.last ?? 0) + max(0, elementPrefixBytes.count - 2)
    }

    init(_ value: [ChatItem], previous: [ChatItem]?, sizes: RuntimeArrayEncodedSizes?, maximumBytes: Int) throws {
        if let previous, let sizes, sharesStorage(previous, value) {
            self = sizes
            return
        }
        let prefix: Int
        if let previous, sizes != nil {
            prefix = try RuntimeArrayPatch(replacing: previous, with: value, areEquivalent: sameChatItem).prefixCount
        }
        else { prefix = 0 }
        try self.init(retaining: 0..<prefix, from: sizes, appending: Array(value.dropFirst(prefix)), maximumBytes: maximumBytes)
    }

    init(rawEventLog value: [String], previous: [String]?, sizes: RuntimeArrayEncodedSizes?, maximumBytes: Int) throws {
        if let previous, let sizes, sharesStorage(previous, value) {
            self = sizes
            return
        }
        let patch = RuntimeLogPatch(replacing: previous ?? [], with: value)
        let previousCount = previous?.count ?? 0
        try self.init(retaining: (previousCount - patch.retainedSuffixCount)..<previousCount,
            from: sizes, appending: patch.appended, maximumBytes: maximumBytes)
    }

    private init<Element: Encodable>(retaining range: Range<Int>, from sizes: RuntimeArrayEncodedSizes?,
                                     appending suffix: [Element], maximumBytes: Int) throws {
        var bytes = [0]
        if let sizes {
            guard range.lowerBound >= 0, range.upperBound < sizes.elementPrefixBytes.count else { throw invalidSnapshotUpdate() }
            let offset = sizes.elementPrefixBytes[range.lowerBound]
            bytes = sizes.elementPrefixBytes[range.lowerBound...range.upperBound].map { $0 - offset }
        } else {
            guard range.isEmpty else { throw invalidSnapshotUpdate() }
        }
        var total = bytes.last ?? 0
        let encoder = JSONEncoder()
        for item in suffix {
            try addBounded(try encoder.encode(item).count, to: &total, maximumBytes: maximumBytes)
            bytes.append(total)
        }
        self.elementPrefixBytes = bytes
        guard encodedByteCount <= maximumBytes else { throw SessionRuntimeConnectionError.responseTooLarge }
    }
}

private struct RuntimeChatEncodedSizes: Sendable {
    let transcript: RuntimeArrayEncodedSizes
    let children: [String: RuntimeArrayEncodedSizes]
    let rawEventLog: RuntimeArrayEncodedSizes
    let skillsProperty: Int
    let historyEntries: Int
    let historySummaries: Int
    let omittedBytes: Int

    init(_ chat: SessionRuntimeChatSnapshot, previous: SessionRuntimeChatSnapshot?,
         sizes: RuntimeChatEncodedSizes?, maximumBytes: Int) throws {
        transcript = try .init(chat.transcript, previous: previous?.transcript, sizes: sizes?.transcript, maximumBytes: maximumBytes)
        var children: [String: RuntimeArrayEncodedSizes] = [:]
        for (id, items) in chat.subAgents.transcripts {
            children[id] = try .init(items, previous: previous?.subAgents.transcripts[id], sizes: sizes?.children[id], maximumBytes: maximumBytes)
        }
        self.children = children
        let encoder = JSONEncoder()
        rawEventLog = try .init(rawEventLog: chat.rawEventLog, previous: previous?.rawEventLog,
            sizes: sizes?.rawEventLog, maximumBytes: maximumBytes)
        if let previous, let sizes, try sameSkills(chat.skillSelection, previous.skillSelection) { skillsProperty = sizes.skillsProperty }
        else if let selection = chat.skillSelection {
            // 省略したoptionalのキーと区切りのカンマも元のサイズに含める。
            skillsProperty = try encoder.encode(["skillSelection": selection]).count - 1
        } else { skillsProperty = 0 }
        if let previous, let sizes, try sameHistoryEntries(chat.historyEntries, previous.historyEntries) { historyEntries = sizes.historyEntries }
        else { historyEntries = try encoder.encode(chat.historyEntries).count }
        if let previous, let sizes, sameHistorySummaries(chat.historySummaries, previous.historySummaries) { historySummaries = sizes.historySummaries }
        else { historySummaries = try encoder.encode(chat.historySummaries).count }
        var total = 0
        for bytes in [transcript.encodedByteCount - 2, rawEventLog.encodedByteCount - 2, skillsProperty, historyEntries - 2, historySummaries - 2] {
            try addBounded(bytes, to: &total, maximumBytes: maximumBytes)
        }
        for child in children.values { try addBounded(child.encodedByteCount - 2, to: &total, maximumBytes: maximumBytes) }
        omittedBytes = total
    }
}

actor SessionRuntimeSnapshotEncoder {
    private var baselines: [SessionRuntimeSnapshotBaseline] = []

    func encode(_ envelope: SessionRuntimeSnapshotEnvelope, baseSequence: UInt64?, updates: Bool) throws -> Data {
        try Task.checkCancellation()
        let data: Data
        if updates {
            let base = baseSequence.flatMap { sequence in baselines.first { $0.envelope.sequence == sequence } }
            let prepared = try SessionRuntimeSnapshotUpdate.prepare(envelope, base: base)
            data = try JSONEncoder().encode(prepared.update)
            guard data.count <= SessionRuntimeTransport.maximumSnapshotBytes else { throw SessionRuntimeConnectionError.responseTooLarge }
            try Task.checkCancellation()
            baselines.append(prepared.baseline)
            baselines.sort { $0.envelope.sequence < $1.envelope.sequence }
            if baselines.count > 2 { baselines.removeFirst(baselines.count - 2) }
        } else {
            data = try JSONEncoder().encode(envelope)
            guard data.count <= SessionRuntimeTransport.maximumSnapshotBytes else { throw SessionRuntimeConnectionError.responseTooLarge }
            try Task.checkCancellation()
        }
        return data
    }
}

private func sharesStorage<Element>(_ lhs: [Element], _ rhs: [Element]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return lhs.withUnsafeBufferPointer { left in
        rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
    }
}

private func sameUTF8(_ lhs: String, _ rhs: String) -> Bool {
    var left = lhs
    var right = rhs
    return left.withUTF8 { leftBytes in
        right.withUTF8 { rightBytes in
            guard leftBytes.count == rightBytes.count else { return false }
            guard let leftAddress = leftBytes.baseAddress, let rightAddress = rightBytes.baseAddress else {
                return leftBytes.isEmpty
            }
            return leftAddress == rightAddress || memcmp(leftAddress, rightAddress, leftBytes.count) == 0
        }
    }
}

private func sameUTF8(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): true
    case (.some(let lhs), .some(let rhs)): sameUTF8(lhs, rhs)
    default: false
    }
}

private func sameEncodedValue<Value: Encodable>(_ lhs: Value, _ rhs: Value) throws -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(lhs) == encoder.encode(rhs)
}

private func sameChatItem(_ lhs: ChatItem, _ rhs: ChatItem) throws -> Bool {
    guard lhs.timestamp.timeIntervalSinceReferenceDate.bitPattern == rhs.timestamp.timeIntervalSinceReferenceDate.bitPattern else { return false }
    switch (lhs, rhs) {
    case let (.agentMessage(leftID, leftText, _), .agentMessage(rightID, rightText, _)),
         let (.reasoning(leftID, leftText, _), .reasoning(rightID, rightText, _)),
         let (.error(leftID, leftText, _), .error(rightID, rightText, _)):
        return sameUTF8(leftID, rightID) && sameUTF8(leftText, rightText)
    case let (.commandExecution(leftID, leftCommand, leftOutput, _, leftCompletedAt, leftIntent),
              .commandExecution(rightID, rightCommand, rightOutput, _, rightCompletedAt, rightIntent)):
        return sameUTF8(leftID, rightID) && sameUTF8(leftCommand, rightCommand) && sameUTF8(leftOutput, rightOutput)
            && leftCompletedAt == rightCompletedAt && sameUTF8(leftIntent, rightIntent)
    case let (.userMessage(leftID, leftText, _, leftAttachments, leftTurnEnd), .userMessage(rightID, rightText, _, rightAttachments, rightTurnEnd)):
        guard sameUTF8(leftID, rightID), sameUTF8(leftText, rightText), leftTurnEnd == rightTurnEnd else { return false }
        if sharesStorage(leftAttachments, rightAttachments) { return true }
        return try sameEncodedValue(leftAttachments, rightAttachments)
    case let (.subAgentMarker(leftID, leftType, leftDescription, leftStatus),
              .subAgentMarker(rightID, rightType, rightDescription, rightStatus)):
        return sameUTF8(leftID, rightID) && sameUTF8(leftType, rightType)
            && sameUTF8(leftDescription, rightDescription) && leftStatus == rightStatus
    case let (.turnCost(leftID, leftCost, _), .turnCost(rightID, rightCost, _)):
        return sameUTF8(leftID, rightID) && leftCost.bitPattern == rightCost.bitPattern
    case let (.fileChange(leftID, leftChanges, _, leftCompletedAt), .fileChange(rightID, rightChanges, _, rightCompletedAt)):
        guard sameUTF8(leftID, rightID), leftCompletedAt == rightCompletedAt else { return false }
        if sharesStorage(leftChanges, rightChanges) { return true }
        return try sameEncodedValue(leftChanges, rightChanges)
    case let (.taskList(leftID, leftTasks, _), .taskList(rightID, rightTasks, _)):
        guard sameUTF8(leftID, rightID) else { return false }
        if sharesStorage(leftTasks, rightTasks) { return true }
        return try sameEncodedValue(leftTasks, rightTasks)
    default:
        guard lhs == rhs else { return false }
        return try sameEncodedValue(lhs, rhs)
    }
}

private func sameSkills(_ lhs: SessionRuntimeSkillSnapshot?, _ rhs: SessionRuntimeSkillSnapshot?) throws -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let lhs), .some(let rhs)):
        guard lhs.isLoading == rhs.isLoading, lhs.isStale == rhs.isStale,
              sameUTF8(lhs.errorMessage, rhs.errorMessage), lhs.fingerprints.count == rhs.fingerprints.count else { return false }
        for (key, value) in lhs.fingerprints {
            guard let index = rhs.fingerprints.index(forKey: key) else { return false }
            let other = rhs.fingerprints[index]
            guard sameUTF8(key, other.key), sameUTF8(value, other.value) else { return false }
        }
        if sharesStorage(lhs.skills, rhs.skills) { return true }
        return try sameEncodedValue(lhs.skills, rhs.skills)
    default: return false
    }
}

private func sameHistoryEntries(_ lhs: [ClaudeSessionHistoryEntry], _ rhs: [ClaudeSessionHistoryEntry]) throws -> Bool {
    if sharesStorage(lhs, rhs) { return true }
    return try sameEncodedValue(lhs, rhs)
}

private func sameHistorySummaries(_ lhs: [String: ChatHistorySummary], _ rhs: [String: ChatHistorySummary]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, value) in lhs {
        guard let index = rhs.index(forKey: key) else { return false }
        let other = rhs[index]
        guard sameUTF8(key, other.key), value.messageCount == other.value.messageCount,
              value.reachesLimit == other.value.reachesLimit, sameUTF8(value.lastMessage, other.value.lastMessage) else { return false }
    }
    return true
}

private func sameExecution(_ lhs: SessionRuntimeChatSnapshot, _ rhs: SessionRuntimeChatSnapshot) -> Bool {
    lhs.id == rhs.id && lhs.executionID == rhs.executionID && lhs.startedAt == rhs.startedAt
        && lhs.agentRef == rhs.agentRef && lhs.workingDirectory == rhs.workingDirectory
}

private func indexedSessions(_ sessions: [SessionRuntimeSessionSnapshot]) throws -> [SessionID: SessionRuntimeSessionSnapshot] {
    var result: [SessionID: SessionRuntimeSessionSnapshot] = [:]
    for session in sessions {
        guard result.updateValue(session, forKey: session.id) == nil else { throw invalidSnapshotUpdate() }
    }
    return result
}

private func addBounded(_ bytes: Int, to total: inout Int, maximumBytes: Int) throws {
    guard bytes >= 0, bytes <= maximumBytes - total else { throw SessionRuntimeConnectionError.responseTooLarge }
    total += bytes
}

private func invalidSnapshotUpdate() -> SessionRuntimeConnectionError {
    .runtimeUnavailable("画面状態の差分が基準の履歴と一致しません。")
}
