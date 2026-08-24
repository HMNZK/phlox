import Foundation
import Observation
import StructuredChatKit

// Hidden secret: sub-agent streams and output files are merged without owning parent transcript.
@MainActor
@Observable
final class ChatSubAgentModel {
    struct StreamActivity {
        let toolUseId: String
        let kind: SubAgentActivityKind
        let itemId: String
        let text: String
    }

    struct DedupScanMetrics: Equatable {
        let callCount: Int
        let characterCount: Int
    }

    public private(set) var subAgents: [SubAgentRef] = []
    public var stripSubAgents: [SubAgentRef] {
        subAgents.filter {
            $0.status != .completed && !dismissedSubAgentIDs.contains($0.id)
        }
    }
    public private(set) var selectedSubAgentId: String?

    private var dismissedSubAgentIDs: Set<String> = []
    private var subAgentTranscripts: [String: [ChatItem]] = [:]
    @ObservationIgnored private var subAgentTranscriptCache: [String: CachedSubAgentTranscript] = [:]
    @ObservationIgnored private var dedupTextCache: [String: CachedDedupText] = [:]
    @ObservationIgnored private(set) var dedupScanMetricsForTesting = DedupScanMetrics(callCount: 0, characterCount: 0)
    @ObservationIgnored private var markerSink: (@MainActor (ChatItem) -> Void)?
    @ObservationIgnored private var outputTouched: (@MainActor () -> Void)?

    private struct CachedDedupText {
        let source: String
        let stripped: String
    }

    var dedupTextCacheCountForTesting: Int {
        dedupTextCache.count
    }

    func configure(
        markerSink: @escaping @MainActor (ChatItem) -> Void,
        outputTouched: @escaping @MainActor () -> Void
    ) {
        self.markerSink = markerSink
        self.outputTouched = outputTouched
    }

    func resetDedupScanMetricsForTesting() {
        dedupScanMetricsForTesting = DedupScanMetrics(callCount: 0, characterCount: 0)
    }

    func selectSubAgent(_ id: String?) {
        selectedSubAgentId = id
    }

    func dismissSubAgent(_ id: String) {
        dismissedSubAgentIDs.insert(id)
        if selectedSubAgentId == id {
            selectedSubAgentId = nil
        }
    }

    /// 表示する transcript を選ぶ。規則は2通り＋例外1つ（ADR 0113）:
    /// 1. 永続ファイル（parsed）が読めれば parsed（＝権威）。
    /// 2. 読めなければライブ。
    /// 例外: 片方だけが reasoning を持つならそれを失わない側（ADR 0025。暗号化されず
    /// ライブにだけ推論本文が残る個体を救う）。
    func transcript(for id: String) -> [ChatItem] {
        let live = subAgentTranscripts[id] ?? []
        let parsed: [ChatItem]? = subAgents.first(where: { $0.id == id })?.outputFile
            .flatMap { cachedParsedSubAgentTranscript(at: $0) }
        guard let parsed else { return live }

        let liveHasReasoning = live.contains { if case .reasoning = $0 { return true } else { return false } }
        let parsedHasReasoning = parsed.contains { if case .reasoning = $0 { return true } else { return false } }
        if liveHasReasoning && !parsedHasReasoning { return live }

        return parsed
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
        clearDedupTextCache(for: toolUseId)
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
            // 完了と同様に dedup キャッシュ（本文の完全コピー）を解放する。
            // failed になったサブエージェントの本文が残り続けるのを防ぐ。
            clearDedupTextCache(for: existing.id)
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
            appendSubAgentActivities([StreamActivity(
                toolUseId: toolUseId,
                kind: kind,
                itemId: itemId,
                text: text
            )])
            return
        }
        if let itemId, kind == .tool || kind == .toolResult {
            appendMergeableSubAgentToolActivity(toolUseId: toolUseId, kind: kind, childToolUseId: itemId, text: text)
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
        case .tool, .toolResult:
            item = .commandExecution(id: "\(toolUseId)-tool-\(subAgentTranscripts[toolUseId, default: []].count)", command: nil, output: text, timestamp: Date())
        }
        appendSubAgentTranscriptItem(toolUseId: toolUseId, item: item)
    }

    func appendSubAgentActivities(_ activities: [StreamActivity]) {
        guard !activities.isEmpty else { return }

        struct ActivityKey: Hashable {
            let toolUseId: String
            let isMessage: Bool
            let itemId: String
        }

        var order: [ActivityKey] = []
        var mergedText: [ActivityKey: String] = [:]
        for activity in activities {
            let key = ActivityKey(
                toolUseId: activity.toolUseId,
                isMessage: activity.kind == .message,
                itemId: activity.itemId
            )
            if mergedText[key] == nil {
                order.append(key)
            }
            mergedText[key, default: ""] += activity.text
        }

        var updatedTranscripts = subAgentTranscripts
        var didChange = false
        for key in order {
            let activity = StreamActivity(
                toolUseId: key.toolUseId,
                kind: key.isMessage ? .message : .reasoning,
                itemId: key.itemId,
                text: mergedText[key] ?? ""
            )
            guard !activity.text.isEmpty,
                  activity.kind == .message || activity.kind == .reasoning
            else { continue }

            let stableId = mergeableSubAgentActivityId(
                toolUseId: activity.toolUseId,
                kind: activity.kind,
                itemId: activity.itemId
            )
            let existing = updatedTranscripts[activity.toolUseId, default: []].first { $0.id == stableId }
            let timestamp = Date()
            let item: ChatItem
            let normalizedText: String
            switch (activity.kind, existing) {
            case (.message, .agentMessage(_, let existingText, _)):
                let fullText = existingText + activity.text
                normalizedText = normalizedStreamText(
                    itemId: stableId,
                    existingText: existingText,
                    appendedText: activity.text,
                    fullText: fullText
                )
                item = .agentMessage(id: stableId, text: fullText, timestamp: timestamp)
            case (.reasoning, .reasoning(_, let existingText, _)):
                let fullText = existingText + activity.text
                normalizedText = normalizedStreamText(
                    itemId: stableId,
                    existingText: existingText,
                    appendedText: activity.text,
                    fullText: fullText
                )
                item = .reasoning(id: stableId, text: fullText, timestamp: timestamp)
            case (.message, _):
                normalizedText = whitespaceStrippedForDedup(activity.text)
                item = .agentMessage(id: stableId, text: activity.text, timestamp: timestamp)
            case (.reasoning, _):
                normalizedText = whitespaceStrippedForDedup(activity.text)
                item = .reasoning(id: stableId, text: activity.text, timestamp: timestamp)
            default:
                continue
            }

            if appendSubAgentTranscriptItem(
                toolUseId: activity.toolUseId,
                item: item,
                normalizedAgentText: normalizedText,
                to: &updatedTranscripts
            ) {
                didChange = true
            }
        }

        guard didChange else { return }
        subAgentTranscripts = updatedTranscripts
        outputTouched?()
    }

    /// 子のツール呼び出しと結果を、tool_use_id ごとの 1 セルへマージする。
    /// `SubAgentTranscriptLoader.parse` と同じ「1 ツールコール = 1 セル」に揃えるためのライブ側実装で、
    /// 順序逆転（結果が先着する resume・途中接続）にも非依存。
    private func appendMergeableSubAgentToolActivity(
        toolUseId: String,
        kind: SubAgentActivityKind,
        childToolUseId: String,
        text: String
    ) {
        guard !text.isEmpty else { return }

        // id 空間を itemId nil 経路の `-tool-\(連番)` と分ける。同じ接頭辞にすると、子の
        // tool_use_id がたまたま数字文字列だったときに連番セルと衝突して別ツールが混ざる。
        let stableId = "\(toolUseId)-toolcall-\(childToolUseId)"
        let existing = subAgentTranscripts[toolUseId, default: []].first { $0.id == stableId }
        let item: ChatItem
        switch (kind, existing) {
        case (.tool, .commandExecution(_, _, let existingOutput, let timestamp)):
            item = .commandExecution(id: stableId, command: text, output: existingOutput, timestamp: timestamp)
        case (.tool, _):
            item = .commandExecution(id: stableId, command: text, output: "", timestamp: Date())
        case (.toolResult, .commandExecution(_, let existingCommand, let existingOutput, let timestamp)):
            item = .commandExecution(
                id: stableId,
                command: existingCommand,
                output: Self.mergedToolOutput(existingOutput, text),
                timestamp: timestamp
            )
        case (.toolResult, _):
            item = .commandExecution(id: stableId, command: nil, output: text, timestamp: Date())
        default:
            return
        }
        appendSubAgentTranscriptItem(toolUseId: toolUseId, item: item)
    }

    private static func mergedToolOutput(_ previous: String, _ next: String) -> String {
        if previous.isEmpty { return next }
        if next.isEmpty { return previous }
        return previous + "\n" + next
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

    /// ストリーム追記分だけを正規化し、累積本文の再走査を避ける。
    private func normalizedStreamText(
        itemId: String,
        existingText: String,
        appendedText: String,
        fullText: String
    ) -> String {
        let previous = normalizedDedupText(itemId: itemId, source: existingText)
        let stripped = previous + whitespaceStrippedForDedup(appendedText)
        dedupTextCache[itemId] = CachedDedupText(source: fullText, stripped: stripped)
        return stripped
    }

    private func normalizedDedupText(itemId: String, source: String) -> String {
        if let cached = dedupTextCache[itemId], cached.source == source {
            return cached.stripped
        }
        let stripped = whitespaceStrippedForDedup(source)
        dedupTextCache[itemId] = CachedDedupText(source: source, stripped: stripped)
        return stripped
    }

    /// Dedup 比較専用: スペース・タブ・改行を全て除去した本文。表示・保存には使わない。
    private func whitespaceStrippedForDedup(_ text: String) -> String {
        dedupScanMetricsForTesting = DedupScanMetrics(
            callCount: dedupScanMetricsForTesting.callCount + 1,
            characterCount: dedupScanMetricsForTesting.characterCount + text.count
        )
        return text.filter { !$0.isWhitespace }
    }

    private func appendSubAgentTranscriptItem(toolUseId: String, item: ChatItem) {
        var updatedTranscripts = subAgentTranscripts
        guard appendSubAgentTranscriptItem(
            toolUseId: toolUseId,
            item: item,
            to: &updatedTranscripts
        ) else { return }
        subAgentTranscripts = updatedTranscripts
        outputTouched?()
    }

    private func clearDedupTextCache(for toolUseId: String) {
        var itemIDs = Set((subAgentTranscripts[toolUseId] ?? []).map(\.id))
        // output と summary が同一本文で重複排除された場合、採用されなかった側の
        // item は transcript に存在しないため、既知の完了レポート ID も消す。
        itemIDs.insert("\(toolUseId)-output")
        itemIDs.insert("\(toolUseId)-summary")
        for itemID in itemIDs {
            dedupTextCache.removeValue(forKey: itemID)
        }
    }

    @discardableResult
    private func appendSubAgentTranscriptItem(
        toolUseId: String,
        item: ChatItem,
        normalizedAgentText: String? = nil,
        to transcripts: inout [String: [ChatItem]]
    ) -> Bool {
        if case .agentMessage(_, let newText, _) = item {
            let stripped = normalizedAgentText
                ?? normalizedDedupText(itemId: item.id, source: newText)
            dedupTextCache[item.id] = CachedDedupText(source: newText, stripped: stripped)
            if !stripped.isEmpty {
                let newIsReportChannel = Self.isCompletionReportId(item.id)
                let alreadyPresent = transcripts[toolUseId, default: []].contains { existing in
                    if case .agentMessage(let existingId, let existingText, _) = existing, existingId != item.id {
                        guard newIsReportChannel || Self.isCompletionReportId(existingId) else { return false }
                        return normalizedDedupText(itemId: existingId, source: existingText) == stripped
                    }
                    return false
                }
                if alreadyPresent { return false }
            }
        }
        if let index = transcripts[toolUseId, default: []].firstIndex(where: { $0.id == item.id }) {
            transcripts[toolUseId, default: []][index] = item
        } else {
            transcripts[toolUseId, default: []].append(item)
        }
        return true
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
