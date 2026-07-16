import Foundation

public enum SubAgentStatus: String, Equatable, Sendable, Codable {
    case running
    case completed
    case failed
}

public struct SubAgentControlSummary: Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: SubAgentStatus
    public let messageCount: Int
    public let markerMessageId: String?

    public init(
        id: String,
        name: String,
        status: SubAgentStatus,
        messageCount: Int,
        markerMessageId: String?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.messageCount = messageCount
        self.markerMessageId = markerMessageId
    }
}

public struct SubAgentRef: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var subagentType: String
    public var description: String
    public var status: SubAgentStatus
    public var startedAt: Date
    public var summary: String?
    public var outputFile: String?

    public init(
        id: String,
        subagentType: String,
        description: String,
        status: SubAgentStatus,
        startedAt: Date,
        summary: String? = nil,
        outputFile: String? = nil
    ) {
        self.id = id
        self.subagentType = subagentType
        self.description = description
        self.status = status
        self.startedAt = startedAt
        self.summary = summary
        self.outputFile = outputFile
    }
}

public enum SubAgentTranscriptLoader {
    public static func parse(jsonl: String) -> [ChatItem] {
        let lines = jsonl.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return [] }

        var items: [ChatItem] = []
        // tool_use が作った commandExecution の位置を tool_use_id で引く。tool_result は
        // 同一 id の別項目を **追加せず**、この既存項目に output をマージする。これで
        // 「tool_use と tool_result が同一 id の別 ChatItem 2個」になる duplicate id を無くし
        // （ForEach/LazyVStack 破綻＝スクロール CPU 暴走・reasoning 脱落・呼び出しと結果の
        // 隙間の根因）、メイン transcript と同じ「1 ツールコール = 1 セル」に揃える。
        var commandIndexByToolUseId: [String: Int] = [:]

        func appendToolUse(_ block: [String: Any], index: Int) {
            let item = toolUseItem(from: block, index: index)
            guard case .commandExecution(let id, let command, _, _) = item else {
                items.append(item)
                return
            }
            // 万一 tool_result が先行して同 id の項目が既にある（孤児登録）場合は、追加せず
            // 既存項目に command を補う。これで tool_use/tool_result の順序が逆でも duplicate id を作らない。
            if let existing = commandIndexByToolUseId[id],
               case .commandExecution(let eid, _, let existingOutput, let ets) = items[existing] {
                items[existing] = .commandExecution(id: eid, command: command, output: existingOutput, timestamp: ets)
                return
            }
            items.append(item)
            commandIndexByToolUseId[id] = items.count - 1
        }

        func mergeToolResult(_ block: [String: Any], index: Int) {
            let output = text(from: block["content"])
            if let toolUseId = block["tool_use_id"] as? String,
               let existing = commandIndexByToolUseId[toolUseId],
               case .commandExecution(let id, let command, let prevOutput, let ts) = items[existing] {
                let merged: String
                if prevOutput.isEmpty { merged = output }
                else if output.isEmpty { merged = prevOutput }
                else { merged = prevOutput + "\n" + output }
                items[existing] = .commandExecution(id: id, command: command, output: merged, timestamp: ts)
            } else {
                // 対応する tool_use を見つけられない孤児 tool_result は単独セルとして追加。
                let item = toolResultItem(from: block, index: index)
                items.append(item)
                if case .commandExecution(let id, _, _, _) = item {
                    commandIndexByToolUseId[id] = items.count - 1
                }
            }
        }

        for (index, line) in lines.enumerated() {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            switch type {
            case "user":
                if let text = messageText(from: object), !text.isEmpty {
                    items.append(.userMessage(id: itemId(object, prefix: "subagent-user", index: index), text: text, timestamp: .distantPast))
                }
                // 実 Claude 形式ではツール結果が user メッセージに tool_result ブロックとしてネストされる。
                if let message = object["message"] as? [String: Any],
                   let blocks = message["content"] as? [[String: Any]] {
                    for (offset, block) in blocks.enumerated() where block["type"] as? String == "tool_result" {
                        mergeToolResult(block, index: index * 1_000 + offset)
                    }
                }
            case "assistant":
                if let message = object["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    let messageId = message["id"] as? String
                    for (offset, block) in content.enumerated() {
                        guard let blockType = block["type"] as? String else { continue }
                        // text/thinking は block に id を持たないため message.id ベースで生成するが、
                        // 実データでは複数行が同一 message.id を共有する（streaming 由来）。行 index を
                        // 混ぜて衝突を防ぎ、id を一意に保つ（duplicate id 再発の防止）。
                        let fallbackId = "\(messageId ?? "subagent-assistant"):\(blockType):\(index):\(offset)"
                        let blockId = block["id"] as? String ?? fallbackId
                        switch blockType {
                        case "text":
                            if let text = block["text"] as? String, !text.isEmpty {
                                items.append(.agentMessage(id: blockId, text: text, timestamp: .distantPast))
                            }
                        case "thinking":
                            if let text = block["thinking"] as? String ?? block["text"] as? String, !text.isEmpty {
                                items.append(.reasoning(id: blockId, text: text, timestamp: .distantPast))
                            }
                        case "tool_use":
                            appendToolUse(block, index: index * 1_000 + offset)
                        case "tool_result":
                            mergeToolResult(block, index: index * 1_000 + offset)
                        default:
                            break
                        }
                    }
                }
            case "tool_use":
                appendToolUse(object, index: index)
            case "tool_result":
                mergeToolResult(object, index: index)
            default:
                break
            }
        }
        return items
    }

    private static func messageText(from object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any] else { return nil }
        switch message["content"] {
        case let text as String:
            return text
        case let blocks as [[String: Any]]:
            return blocks.compactMap { block in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
        default:
            return nil
        }
    }

    private static func toolUseItem(from object: [String: Any], index: Int) -> ChatItem {
        let name = object["name"] as? String ?? "Tool"
        let id = object["id"] as? String ?? "subagent-tool-\(index)"
        let input = object["input"] as? [String: Any] ?? [:]
        let command = input.isEmpty
            ? name
            : "\(name) \((try? stableJSONString(input)) ?? String(describing: input))"
        return .commandExecution(id: id, command: command, output: "", timestamp: .distantPast)
    }

    private static func toolResultItem(from object: [String: Any], index: Int) -> ChatItem {
        let id = object["tool_use_id"] as? String ?? object["id"] as? String ?? "subagent-tool-result-\(index)"
        return .commandExecution(id: id, command: nil, output: text(from: object["content"]), timestamp: .distantPast)
    }

    private static func text(from content: Any?) -> String {
        switch content {
        case let text as String:
            return text
        case let blocks as [[String: Any]]:
            return blocks.compactMap { block in
                block["text"] as? String ?? block["content"] as? String
            }
            .joined()
        case let value?:
            return (try? stableJSONString(value)) ?? String(describing: value)
        case nil:
            return ""
        }
    }

    private static func itemId(_ object: [String: Any], prefix: String, index: Int) -> String {
        object["uuid"] as? String ?? object["id"] as? String ?? "\(prefix)-\(index)"
    }

    private static func stableJSONString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? String(describing: value)
    }
}

