import Foundation
import Observation
import StructuredChatKit

// Hidden secret: sub-agent streams and output files are merged without owning parent transcript.
@MainActor
@Observable
final class ChatSubAgentModel {
    public private(set) var subAgents: [SubAgentRef] = []
    public var stripSubAgents: [SubAgentRef] {
        subAgents.filter { $0.status != .completed }
    }
    public private(set) var selectedSubAgentId: String?

    private var subAgentTranscripts: [String: [ChatItem]] = [:]
    @ObservationIgnored private var subAgentTranscriptCache: [String: CachedSubAgentTranscript] = [:]
    @ObservationIgnored private var markerSink: (@MainActor (ChatItem) -> Void)?
    @ObservationIgnored private var outputTouched: (@MainActor () -> Void)?

    func configure(
        markerSink: @escaping @MainActor (ChatItem) -> Void,
        outputTouched: @escaping @MainActor () -> Void
    ) {
        self.markerSink = markerSink
        self.outputTouched = outputTouched
    }

    func selectSubAgent(_ id: String?) {
        selectedSubAgentId = id
    }

    func transcript(for id: String) -> [ChatItem] {
        let live = subAgentTranscripts[id] ?? []
        let parsed: [ChatItem]? = subAgents.first(where: { $0.id == id })?.outputFile
            .flatMap { cachedParsedSubAgentTranscript(at: $0) }
        guard let parsed else { return live }

        let liveHasReasoning = live.contains { if case .reasoning = $0 { return true } else { return false } }
        let parsedHasReasoning = parsed.contains { if case .reasoning = $0 { return true } else { return false } }
        if liveHasReasoning && !parsedHasReasoning { return live }
        if parsedHasReasoning && !liveHasReasoning { return parsed }

        return parsed.count >= live.count ? parsed : live
    }

    func upsertSubAgent(
        toolUseId: String,
        subagentType: String,
        description: String,
        status: SubAgentStatus,
        summary: String?,
        outputFile: String?
    ) {
        if let index = subAgents.firstIndex(where: { $0.id == toolUseId }) {
            let existing = subAgents[index]
            subAgents[index] = SubAgentRef(
                id: existing.id,
                subagentType: subagentType.isEmpty ? existing.subagentType : subagentType,
                description: description.isEmpty ? existing.description : description,
                status: status,
                startedAt: existing.startedAt,
                summary: summary ?? existing.summary,
                outputFile: outputFile ?? existing.outputFile
            )
        } else {
            subAgents.append(SubAgentRef(
                id: toolUseId,
                subagentType: subagentType.isEmpty ? "subagent" : subagentType,
                description: description.isEmpty ? "Sub-agent" : description,
                status: status,
                startedAt: Date(),
                summary: summary,
                outputFile: outputFile
            ))
        }
        upsertSubAgentMarker(toolUseId: toolUseId)
        outputTouched?()
    }

    func completeSubAgent(
        toolUseId: String,
        status: String,
        summary: String,
        outputFile: String?
    ) {
        let mappedStatus = subAgentStatus(from: status)
        if subAgents.contains(where: { $0.id == toolUseId }) {
            upsertSubAgent(
                toolUseId: toolUseId,
                subagentType: "",
                description: "",
                status: mappedStatus,
                summary: summary,
                outputFile: outputFile
            )
        } else {
            upsertSubAgent(
                toolUseId: toolUseId,
                subagentType: "subagent",
                description: "Sub-agent",
                status: mappedStatus,
                summary: summary,
                outputFile: outputFile
            )
        }
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendSubAgentTranscriptItem(
                toolUseId: toolUseId,
                item: .agentMessage(id: "\(toolUseId)-summary", text: summary, timestamp: Date())
            )
        }
    }

    func failRunningSubAgents() {
        var didChange = false
        for index in subAgents.indices where subAgents[index].status == .running {
            let existing = subAgents[index]
            subAgents[index] = SubAgentRef(
                id: existing.id,
                subagentType: existing.subagentType,
                description: existing.description,
                status: .failed,
                startedAt: existing.startedAt,
                summary: existing.summary,
                outputFile: existing.outputFile
            )
            upsertSubAgentMarker(toolUseId: existing.id)
            didChange = true
        }
        if didChange {
            outputTouched?()
        }
    }

    func appendSubAgentActivity(
        toolUseId: String,
        kind: SubAgentActivityKind,
        itemId: String?,
        text: String
    ) {
        if let itemId, kind == .message || kind == .reasoning {
            appendMergeableSubAgentActivity(toolUseId: toolUseId, kind: kind, itemId: itemId, text: text)
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item: ChatItem
        switch kind {
        case .prompt:
            item = .userMessage(id: "\(toolUseId)-prompt", text: text, timestamp: Date())
        case .message:
            item = .agentMessage(id: "\(toolUseId)-message-\(subAgentTranscripts[toolUseId, default: []].count)", text: text, timestamp: Date())
        case .reasoning:
            item = .reasoning(id: "\(toolUseId)-reasoning-\(subAgentTranscripts[toolUseId, default: []].count)", text: text, timestamp: Date())
        case .tool:
            item = .commandExecution(id: "\(toolUseId)-tool-\(subAgentTranscripts[toolUseId, default: []].count)", command: nil, output: text, timestamp: Date())
        }
        appendSubAgentTranscriptItem(toolUseId: toolUseId, item: item)
    }

    private func appendMergeableSubAgentActivity(
        toolUseId: String,
        kind: SubAgentActivityKind,
        itemId: String,
        text: String
    ) {
        guard !text.isEmpty else { return }

        let stableId = mergeableSubAgentActivityId(toolUseId: toolUseId, kind: kind, itemId: itemId)
        let existing = subAgentTranscripts[toolUseId, default: []].first { $0.id == stableId }
        let timestamp = Date()
        let item: ChatItem
        switch (kind, existing) {
        case (.message, .agentMessage(_, let existingText, _)):
            item = .agentMessage(id: stableId, text: existingText + text, timestamp: timestamp)
        case (.reasoning, .reasoning(_, let existingText, _)):
            item = .reasoning(id: stableId, text: existingText + text, timestamp: timestamp)
        case (.message, _):
            item = .agentMessage(id: stableId, text: text, timestamp: timestamp)
        case (.reasoning, _):
            item = .reasoning(id: stableId, text: text, timestamp: timestamp)
        case (.prompt, _), (.tool, _):
            return
        }
        appendSubAgentTranscriptItem(toolUseId: toolUseId, item: item)
    }

    private func mergeableSubAgentActivityId(
        toolUseId: String,
        kind: SubAgentActivityKind,
        itemId: String
    ) -> String {
        "\(toolUseId)-\(kind)-\(itemId)-stream"
    }

    func appendSubAgentOutput(toolUseId: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appendSubAgentTranscriptItem(
            toolUseId: toolUseId,
            item: .agentMessage(id: "\(toolUseId)-output", text: text, timestamp: Date())
        )
    }

    private func upsertSubAgentMarker(toolUseId: String) {
        guard let ref = subAgents.first(where: { $0.id == toolUseId }) else { return }
        markerSink?(.subAgentMarker(
            id: ref.id,
            subagentType: ref.subagentType,
            description: ref.description,
            status: ref.status
        ))
    }

    private static func isCompletionReportId(_ id: String) -> Bool {
        id.hasSuffix("-output") || id.hasSuffix("-summary")
    }

    /// Dedup 比較専用: スペース・タブ・改行を全て除去した本文。表示・保存には使わない。
    private static func whitespaceStrippedForDedup(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private func appendSubAgentTranscriptItem(toolUseId: String, item: ChatItem) {
        if case .agentMessage(_, let newText, _) = item {
            let stripped = Self.whitespaceStrippedForDedup(newText)
            if !stripped.isEmpty {
                let newIsReportChannel = Self.isCompletionReportId(item.id)
                let alreadyPresent = subAgentTranscripts[toolUseId, default: []].contains { existing in
                    if case .agentMessage(let existingId, let existingText, _) = existing, existingId != item.id {
                        guard newIsReportChannel || Self.isCompletionReportId(existingId) else { return false }
                        return Self.whitespaceStrippedForDedup(existingText) == stripped
                    }
                    return false
                }
                if alreadyPresent { return }
            }
        }
        if let index = subAgentTranscripts[toolUseId, default: []].firstIndex(where: { $0.id == item.id }) {
            subAgentTranscripts[toolUseId, default: []][index] = item
        } else {
            subAgentTranscripts[toolUseId, default: []].append(item)
        }
        outputTouched?()
    }

    private func cachedParsedSubAgentTranscript(at path: String) -> [ChatItem]? {
        let metadata = subAgentTranscriptFileMetadata(at: path)
        if let cached = subAgentTranscriptCache[path] {
            guard let metadata else { return cached.items }
            if cached.metadata == metadata {
                return cached.items
            }
        }
        guard let metadata,
              let parsed = parsedSubAgentTranscript(at: path),
              !parsed.isEmpty
        else { return nil }
        subAgentTranscriptCache[path] = CachedSubAgentTranscript(metadata: metadata, items: parsed)
        return parsed
    }

    private func parsedSubAgentTranscript(at path: String) -> [ChatItem]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= 5_000_000,
              let jsonl = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        return SubAgentTranscriptLoader.parse(jsonl: jsonl)
    }

    private func subAgentTranscriptFileMetadata(at path: String) -> SubAgentTranscriptFileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= 5_000_000
        else { return nil }
        return SubAgentTranscriptFileMetadata(
            modifiedAt: attributes[.modificationDate] as? Date,
            size: fileSize.intValue
        )
    }

    private func subAgentStatus(from status: String) -> SubAgentStatus {
        switch status.lowercased() {
        case "completed", "success", "succeeded":
            return .completed
        case "failed", "error", "cancelled", "canceled":
            return .failed
        default:
            return .running
        }
    }
}
