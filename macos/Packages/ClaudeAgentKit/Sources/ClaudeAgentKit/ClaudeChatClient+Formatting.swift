import Foundation
import StructuredChatKit

// 隠している秘密: ツール入出力・エラー辞書を人間可読な1行テキストへどう畳み込むか
extension ClaudeChatClient {
    func processEndedMessage(stderrTail: String?) -> String {
        let base = "Claude process ended before completing the current turn"
        guard let stderrTail = stderrTail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stderrTail.isEmpty
        else {
            return base
        }
        return "\(base): \(stderrTail)"
    }

    func fileChangeEvent(toolName: String, input: [String: Any], itemId: String) -> NormalizedChatEvent? {
        switch toolName {
        case "Edit":
            guard
                let path = input["file_path"] as? String,
                let oldString = input["old_string"] as? String,
                let newString = input["new_string"] as? String
            else { return nil }
            return .fileChange(itemId: itemId, [
                FilePatchChange(path: path, diff: diff(path: path, old: oldString, new: newString), kind: "edit"),
            ])
        case "Write":
            guard let path = input["file_path"] as? String else { return nil }
            let content = input["content"] as? String ?? ""
            return .fileChange(itemId: itemId, [
                FilePatchChange(path: path, diff: diff(path: path, old: nil, new: content), kind: "write"),
            ])
        case "MultiEdit":
            guard let path = input["file_path"] as? String else { return nil }
            let edits = input["edits"] as? [[String: Any]] ?? []
            let combinedDiff = edits.map { edit in
                diff(
                    path: path,
                    old: edit["old_string"] as? String,
                    new: edit["new_string"] as? String ?? ""
                )
            }.joined(separator: "\n")
            return .fileChange(itemId: itemId, [
                FilePatchChange(path: path, diff: combinedDiff, kind: "edit"),
            ])
        default:
            return nil
        }
    }

    func commandDescription(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? "Bash"
        case "Read":
            return ["Read", input["file_path"] as? String].compactMap { $0 }.joined(separator: " ")
        case "Glob":
            return ["Glob", input["pattern"] as? String].compactMap { $0 }.joined(separator: " ")
        case "Grep":
            let pattern = input["pattern"] as? String
            let path = input["path"] as? String
            return ["Grep", pattern, path].compactMap { $0 }.joined(separator: " ")
        case "LS":
            return ["LS", input["path"] as? String].compactMap { $0 }.joined(separator: " ")
        default:
            if input.isEmpty {
                return toolName
            }
            let inputText = (try? stableJSONString(input)) ?? String(describing: input)
            return "\(toolName) \(inputText)"
        }
    }

    func toolResultText(from content: Any?) -> String {
        switch content {
        case let text as String:
            return text
        case let blocks as [[String: Any]]:
            return blocks.compactMap { block in
                block["text"] as? String ?? block["content"] as? String
            }.joined()
        case let value?:
            return (try? stableJSONString(value)) ?? String(describing: value)
        case nil:
            return ""
        }
    }

    func resultErrorMessage(from event: [String: Any]) -> String {
        if let message = event["message"] as? String {
            return message
        }
        if let error = event["error"] as? String {
            return error
        }
        if let result = event["result"] as? String {
            return result
        }

        let subtype = event["subtype"] as? String ?? "unknown"
        let diagnostics = resultErrorDiagnostics(from: event)
        var message = "Claude error (subtype: \(subtype))"
        if !diagnostics.isEmpty {
            message += ": " + diagnostics.joined(separator: ", ")
        }
        return message
    }

    func resultErrorDiagnostics(from event: [String: Any]) -> [String] {
        [
            "permission_denials",
            "api_error_status",
            "api_error_message",
            "api_error_type",
        ].compactMap { key in
            guard let value = event[key] else { return nil }
            return "\(key): \(diagnosticDescription(value))"
        }
    }

    func diagnosticDescription(_ value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if value is NSNull {
            return "null"
        }
        if let bool = value as? Bool {
            return String(describing: bool)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            return String(describing: value)
        }
        return (try? stableJSONString(value)) ?? String(describing: value)
    }

    func diff(path: String, old: String?, new: String) -> String {
        var output = ""
        output += "--- \(old == nil ? "/dev/null" : path)\n"
        output += "+++ \(path)\n"
        output += "@@\n"
        if let old {
            output += old.diffLines(prefix: "-")
        }
        output += new.diffLines(prefix: "+")
        return output
    }

    func generatedItemId(prefix: String, index: Int) -> String {
        generatedItemCounter += 1
        return "\(prefix)-\(generatedItemCounter)-\(index)"
    }
}

private extension String {
    func diffLines(prefix: String) -> String {
        guard !isEmpty else { return "" }

        let hasFinalNewline = hasSuffix("\n")
        let parts = split(separator: "\n", omittingEmptySubsequences: false)
        let contentLines = hasFinalNewline ? parts.dropLast() : parts[...]
        var output = contentLines.map { "\(prefix)\($0)\n" }.joined()
        if !hasFinalNewline {
            output += "\\ No newline at end of file\n"
        }
        return output
    }
}

private func stableJSONString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? String(describing: value)
}
