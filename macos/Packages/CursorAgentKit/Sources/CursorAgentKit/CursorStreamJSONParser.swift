import Foundation
import StructuredChatKit

struct CursorStreamJSONParser {
    private struct PendingToolCall {
        var displayCommand: String?
        var filePath: String?
        var streamContent: String?
        var isFileEdit: Bool
        var fileChangeKind: String?
    }

    private var sessionId: String?
    private var pendingToolCalls: [String: PendingToolCall] = [:]
    private var textSegmentSeq = 0
    private var sawResultLine = false

    /// Per-turn prefix that namespaces text-derived itemIds ("reasoning" /
    /// "assistant-N") so they do not collide across turns. Empty for the default
    /// (no-salt) initializer, which keeps existing parser tests' fixed itemIds.
    private let itemIdPrefix: String

    /// - Parameter turnSalt: A per-turn unique token. When non-nil/non-empty it is
    ///   prefixed to text-derived itemIds; when nil (the default) itemIds stay bare
    ///   ("reasoning"/"assistant-0") for backward compatibility.
    init(turnSalt: String? = nil) {
        if let turnSalt, !turnSalt.isEmpty {
            itemIdPrefix = "\(turnSalt)-"
        } else {
            itemIdPrefix = ""
        }
    }

    /// True once a `result` line (success or not) has been ingested. The client
    /// uses this to avoid emitting the generic "completed without result/success"
    /// fallback when a non-success result already surfaced its own error.
    var sawResult: Bool { sawResultLine }

    mutating func ingest(line: Data) throws -> [NormalizedChatEvent] {
        guard let json = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw CursorStreamJSONParserError.invalidJSON
        }
        guard let type = json["type"] as? String else {
            return []
        }

        if let eventSessionId = json["session_id"] as? String {
            sessionId = eventSessionId
        }

        switch type {
        case "system":
            return handleSystem(json)
        case "thinking":
            return handleThinking(json)
        case "assistant":
            return handleAssistant(json)
        case "tool_call":
            return try handleToolCall(json)
        case "result":
            return handleResult(json)
        default:
            return []
        }
    }

    var nativeSessionId: String? { sessionId }

    private mutating func handleSystem(_ json: [String: Any]) -> [NormalizedChatEvent] {
        guard json["subtype"] as? String == "init" else { return [] }
        if let id = json["session_id"] as? String {
            sessionId = id
        }
        return []
    }

    private func handleThinking(_ json: [String: Any]) -> [NormalizedChatEvent] {
        guard json["subtype"] as? String == "delta",
              let text = json["text"] as? String,
              !text.isEmpty else {
            return []
        }
        return [.reasoningDelta(itemId: "\(itemIdPrefix)reasoning", text)]
    }

    private func handleAssistant(_ json: [String: Any]) -> [NormalizedChatEvent] {
        guard let text = extractAssistantText(from: json), !text.isEmpty else {
            return []
        }
        return [.agentMessageDelta(itemId: "\(itemIdPrefix)assistant-\(textSegmentSeq)", text)]
    }

    private mutating func handleToolCall(_ json: [String: Any]) throws -> [NormalizedChatEvent] {
        guard let subtype = json["subtype"] as? String,
              let callId = json["call_id"] as? String ?? json["toolCallId"] as? String,
              let toolCall = json["tool_call"] as? [String: Any] else {
            return []
        }

        switch subtype {
        case "started":
            let pending = Self.describeStartedToolCall(toolCall)
            pendingToolCalls[callId] = pending
            // ツール呼び出しを境界に、後続のテキストを別バブルへ分ける（テキストとツールを時系列で交互に並べるため）
            textSegmentSeq += 1
            // 呼び出された時点で行を描画する（Claude/Codex と同じ。出力は completed で埋める）
            return [Self.toolCallEvent(callId: callId, pending: pending, output: nil)]
        case "completed":
            guard let pending = pendingToolCalls.removeValue(forKey: callId) else {
                return []
            }
            if pending.fileChangeKind == "delete",
               let change = Self.deleteFileChange(callId: callId, pending: pending, json: json) {
                return [change]
            }
            let output = Self.extractToolOutput(from: json)
            return [Self.toolCallEvent(callId: callId, pending: pending, output: output)]
        default:
            return []
        }
    }

    private static func toolCallEvent(
        callId: String,
        pending: PendingToolCall,
        output: String?
    ) -> NormalizedChatEvent {
        if pending.isFileEdit, let path = pending.filePath {
            let content = pending.streamContent ?? (output ?? "")
            let diff = unifiedDiff(path: path, newContent: content)
            return .fileChange(itemId: callId, [FilePatchChange(path: path, diff: diff)])
        }
        return .commandExecution(
            itemId: callId,
            command: pending.displayCommand,
            outputDelta: output ?? ""
        )
    }

    private mutating func handleResult(_ json: [String: Any]) -> [NormalizedChatEvent] {
        sawResultLine = true
        if let id = json["session_id"] as? String {
            sessionId = id
        }
        let subtype = json["subtype"] as? String
        guard subtype == "success" else {
            // Non-success result: surface the failure reason as an error instead of
            // dropping it silently (which previously left the turn to only emit the
            // generic "completed without result/success" fallback).
            return [.error(message: Self.resultFailureMessage(json, subtype: subtype))]
        }
        return [.turnCompleted(nativeSessionId: sessionId)]
    }

    private static func resultFailureMessage(_ json: [String: Any], subtype: String?) -> String {
        let subtypeLabel = subtype ?? "unknown"
        if let detail = resultFailureDetail(json), !detail.isEmpty {
            return "cursor-agent result failed (\(subtypeLabel)): \(detail)"
        }
        return "cursor-agent result failed: \(subtypeLabel)"
    }

    private static func resultFailureDetail(_ json: [String: Any]) -> String? {
        if let result = json["result"] as? String { return result }
        if let error = json["error"] as? String { return error }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String { return message }
        return nil
    }

    private func extractAssistantText(from json: [String: Any]) -> String? {
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let parts = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            if !parts.isEmpty {
                return parts.joined()
            }
        }
        return json["text"] as? String
    }

    private static func describeStartedToolCall(_ toolCall: [String: Any]) -> PendingToolCall {
        if let shell = toolCall["shellToolCall"] as? [String: Any],
           let args = shell["args"] as? [String: Any],
           let command = args["command"] as? String {
            // enum キー名 "shellToolCall" ではなく実コマンドを表示する（Claude/Codex と同様）
            return PendingToolCall(displayCommand: command, filePath: nil, streamContent: nil, isFileEdit: false, fileChangeKind: nil)
        }
        if let read = toolCall["readToolCall"] as? [String: Any],
           let args = read["args"] as? [String: Any],
           let path = args["path"] as? String {
            return PendingToolCall(displayCommand: "Read \(path)", filePath: nil, streamContent: nil, isFileEdit: false, fileChangeKind: nil)
        }
        if let ls = toolCall["lsToolCall"] as? [String: Any],
           let args = ls["args"] as? [String: Any] {
            let path = args["path"] as? String ?? "."
            return PendingToolCall(displayCommand: "ls \(path)", filePath: nil, streamContent: nil, isFileEdit: false, fileChangeKind: nil)
        }
        if let grep = toolCall["grepToolCall"] as? [String: Any],
           let args = grep["args"] as? [String: Any] {
            let pattern = args["pattern"] as? String ?? ""
            let path = args["path"] as? String ?? "."
            return PendingToolCall(displayCommand: "grep \(pattern) \(path)", filePath: nil, streamContent: nil, isFileEdit: false, fileChangeKind: nil)
        }
        if let edit = toolCall["editToolCall"] as? [String: Any],
           let args = edit["args"] as? [String: Any],
           let path = args["path"] as? String {
            let streamContent = args["streamContent"] as? String ?? ""
            return PendingToolCall(displayCommand: "Edit \(path)", filePath: path, streamContent: streamContent, isFileEdit: true, fileChangeKind: nil)
        }
        if let write = toolCall["writeToolCall"] as? [String: Any],
           let args = write["args"] as? [String: Any],
           let path = args["path"] as? String {
            let streamContent = args["streamContent"] as? String ?? ""
            return PendingToolCall(displayCommand: "Write \(path)", filePath: path, streamContent: streamContent, isFileEdit: true, fileChangeKind: nil)
        }
        if let delete = toolCall["deleteToolCall"] as? [String: Any],
           let args = delete["args"] as? [String: Any] {
            let path = args["path"] as? String
            return PendingToolCall(displayCommand: "Delete", filePath: path, streamContent: nil, isFileEdit: false, fileChangeKind: "delete")
        }
        let toolName = toolKindKey(in: toolCall).map(displayName(forToolKindKey:)) ?? "Tool"
        return PendingToolCall(displayCommand: toolName, filePath: nil, streamContent: nil, isFileEdit: false, fileChangeKind: nil)
    }

    private static func extractToolOutput(from json: [String: Any]) -> String {
        // 実 cursor-agent の completed イベントでは result は tool_call の種別キー配下
        // (例: tool_call.shellToolCall.result / tool_call.readToolCall.result) にネストする。
        // 種別キーはツールごとに異なるため、result を持つサブ辞書を辿って出力を取り出す。
        guard let toolCall = json["tool_call"] as? [String: Any] else { return "" }
        for value in toolCall.values {
            guard let subCall = value as? [String: Any],
                  let result = subCall["result"] as? [String: Any] else {
                continue
            }
            if let output = extractOutput(fromResult: result) {
                return output
            }
        }
        return ""
    }

    private static func extractOutput(fromResult result: [String: Any]) -> String? {
        if let success = result["success"] as? [String: Any] {
            if let stdout = success["stdout"] as? String { return stdout }
            if let content = success["content"] as? String { return content }
            if let output = success["output"] as? String { return output }
            if let files = success["files"] as? [String] { return files.joined(separator: "\n") }
        }
        if let error = result["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    static func unifiedDiff(path: String, newContent: String) -> String {
        let newLines = newContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var diff = "--- a/\(path)\n+++ b/\(path)\n"
        for line in newLines {
            diff += "+\(line)\n"
        }
        return diff
    }

    private static func deleteFileChange(
        callId: String,
        pending: PendingToolCall,
        json: [String: Any]
    ) -> NormalizedChatEvent? {
        guard let success = deleteSuccess(from: json),
              let prevContent = success["prevContent"] as? String else {
            return nil
        }
        let path = pending.filePath ?? success["path"] as? String ?? success["deletedFile"] as? String
        guard let path else { return nil }
        return .fileChange(
            itemId: callId,
            [FilePatchChange(path: path, diff: deletionDiff(path: path, oldContent: prevContent), kind: "delete")]
        )
    }

    private static func deleteSuccess(from json: [String: Any]) -> [String: Any]? {
        guard let toolCall = json["tool_call"] as? [String: Any],
              let delete = toolCall["deleteToolCall"] as? [String: Any],
              let result = delete["result"] as? [String: Any] else {
            return nil
        }
        return result["success"] as? [String: Any]
    }

    private static func deletionDiff(path: String, oldContent: String) -> String {
        var lines = oldContent.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        var diff = "--- a/\(path)\n+++ b/\(path)\n"
        for line in lines {
            diff += "-\(line)\n"
        }
        return diff
    }

    private static func toolKindKey(in toolCall: [String: Any]) -> String? {
        let metadataKeys: Set<String> = [
            "hookAdditionalContexts",
            "toolCallId",
            "startedAtMs",
            "completedAtMs",
            "result",
        ]
        let candidates = toolCall.keys.filter { key in
            guard !metadataKeys.contains(key) else { return false }
            if key.hasSuffix("ToolCall") { return true }
            guard let value = toolCall[key] as? [String: Any] else { return false }
            return value["args"] != nil || value["result"] != nil
        }
        return candidates.sorted().first
    }

    private static func displayName(forToolKindKey key: String) -> String {
        let suffix = "ToolCall"
        let stem = key.hasSuffix(suffix) ? String(key.dropLast(suffix.count)) : key
        guard let first = stem.first else { return "Tool" }
        var words = String(first).uppercased()
        for character in stem.dropFirst() {
            if character.isUppercase {
                words += " "
            }
            words.append(character)
        }
        return words
    }
}

enum CursorStreamJSONParserError: Error, Equatable {
    case invalidJSON
}
