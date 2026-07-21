import Foundation
import StructuredChatKit

// 隠している秘密: どのツール呼び出し/コンテンツがメインの会話に属し、どれが子（サブエージェント）に属して隔離表示すべきか
extension ClaudeChatClient {
    func handleAssistantEvent(_ event: [String: Any]) {
        guard let message = event["message"] as? [String: Any] else { return }

        // メインターンの assistant のみ現在コンテキスト占有量として記録する（サブエージェントは除外）。
        // 実 stream-json のメインイベントは parent_tool_use_id:null を持ち、JSONSerialization はこれを
        // NSNull にするため `== nil` では判定できない。下の隔離分岐と同じく `as? String` で「文字列の親IDが
        // 無い＝メイン」を判定する。
        if (event["parent_tool_use_id"] as? String) == nil,
           let usage = message["usage"] as? [String: Any] {
            currentTurnLatestContextTokens = (usage["input_tokens"] as? Int ?? 0)
                + (usage["cache_read_input_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
        }

        guard let content = message["content"] as? [[String: Any]] else { return }

        // バックグラウンドサブエージェントは子のターン（thinking/text/tool_use）を
        // parent_tool_use_id 付きでインライン流入させる。これをメインに出さず隔離する。
        if let parentToolUseId = event["parent_tool_use_id"] as? String,
           subAgentToolUseIds.contains(parentToolUseId) {
            let messageId = message["id"] as? String
            for (index, item) in content.enumerated() {
                yieldSubAgentAssistantActivity(
                    item,
                    parentToolUseId: parentToolUseId,
                    messageId: messageId,
                    index: index
                )
            }
            return
        }

        let messageId = message["id"] as? String
        for (index, item) in content.enumerated() {
            handleAssistantContent(item, messageId: messageId, index: index)
        }
    }

    /// 子（サブエージェント）の assistant content を subAgentActivity へ隔離する。
    func yieldSubAgentAssistantActivity(
        _ item: [String: Any],
        parentToolUseId: String,
        messageId: String?,
        index: Int
    ) {
        guard let type = item["type"] as? String else { return }
        switch type {
        case "text":
            if let text = item["text"] as? String, !text.isEmpty {
                eventContinuation.yield(.subAgentActivity(
                    toolUseId: parentToolUseId,
                    kind: .message,
                    itemId: assistantContentItemId(item, messageId: messageId, type: type, index: index),
                    text: text
                ))
            }
        case "thinking":
            if let thinking = item["thinking"] as? String ?? item["text"] as? String, !thinking.isEmpty {
                eventContinuation.yield(.subAgentActivity(
                    toolUseId: parentToolUseId,
                    kind: .reasoning,
                    itemId: assistantContentItemId(item, messageId: messageId, type: type, index: index),
                    text: thinking
                ))
            }
        case "tool_use":
            if let name = item["name"] as? String {
                let input = item["input"] as? [String: Any] ?? [:]
                // 子の tool_use.id を itemId に載せる。対になる tool_result（.toolResult）が
                // 同じ id で届き、受け側が 1 ツールコール = 1 セルへマージできる。
                eventContinuation.yield(.subAgentActivity(
                    toolUseId: parentToolUseId,
                    kind: .tool,
                    itemId: item["id"] as? String,
                    text: commandDescription(toolName: name, input: input)
                ))
            }
        default:
            break
        }
    }

    func handleAssistantContent(_ item: [String: Any], messageId: String?, index: Int) {
        guard let type = item["type"] as? String else { return }
        let itemId = assistantContentItemId(item, messageId: messageId, type: type, index: index)

        switch type {
        case "text":
            if let text = item["text"] as? String {
                eventContinuation.yield(.agentMessageDelta(itemId: itemId, text))
            }
        case "thinking":
            if let thinking = item["thinking"] as? String ?? item["text"] as? String {
                eventContinuation.yield(.reasoningDelta(itemId: itemId, thinking))
            }
        case "tool_use":
            handleToolUse(item, itemId: itemId)
        default:
            break
        }
    }

    func handleToolUse(_ item: [String: Any], itemId: String) {
        guard let name = item["name"] as? String else { return }
        if let toolUseId = item["id"] as? String {
            toolUseItemIds[toolUseId] = itemId
        }
        let input = item["input"] as? [String: Any] ?? [:]

        if isSubAgentTool(name), let toolUseId = item["id"] as? String {
            let subagentType = input["subagent_type"] as? String ?? name
            let prompt = input["prompt"] as? String
            let runsInBackground = input["run_in_background"] as? Bool == true
            let description: String
            if let explicitDescription = input["description"] as? String {
                description = explicitDescription
            } else {
                description = commandDescription(toolName: name, input: input)
            }

            markSubAgentToolUse(toolUseId)
            // 抑制フラグは常に「現在の tool_use の run_in_background」に束縛する。false 時に
            // remove することで、万一 tool_use_id が再利用されてもフォアグラウンドの正当出力を
            // 巻き添え抑制しない（状態を sticky にしない）。
            if runsInBackground {
                backgroundSubAgentToolUseIds.insert(toolUseId)
            } else {
                backgroundSubAgentToolUseIds.remove(toolUseId)
            }
            yieldSubAgentStartedIfNeeded(
                toolUseId: toolUseId,
                subagentType: subagentType,
                description: description
            )
            if let prompt, !prompt.isEmpty {
                eventContinuation.yield(.subAgentActivity(toolUseId: toolUseId, kind: .prompt, itemId: nil, text: prompt))
            }
            return
        }

        if let fileChange = fileChangeEvent(toolName: name, input: input, itemId: itemId) {
            eventContinuation.yield(fileChange)
        } else {
            eventContinuation.yield(.commandExecution(
                itemId: itemId,
                command: commandDescription(toolName: name, input: input),
                outputDelta: ""
            ))
        }
    }

    func handleUserEvent(_ event: [String: Any]) {
        guard
            let message = event["message"] as? [String: Any],
            let content = message["content"] as? [[String: Any]]
        else { return }

        // 子（サブエージェント）のインライン user イベント（プロンプトのエコー・tool_result 等）は
        // parent_tool_use_id で識別し、メインに出さず隔離して return する。子内部ツールの
        // tool_use_id は launcher と異なるため、下の tool_result ループでは拾えない（漏洩する）。
        if let parentToolUseId = event["parent_tool_use_id"] as? String,
           subAgentToolUseIds.contains(parentToolUseId) {
            for item in content {
                if item["type"] as? String == "tool_result" {
                    let text = toolResultText(from: item["content"])
                    if !text.isEmpty {
                        // 呼び出し（.tool）と同じ tool_use_id を運ぶ。種別を分けることで、
                        // 受け側が「command 欄へ入れるか output 欄へ入れるか」を判別できる。
                        eventContinuation.yield(.subAgentActivity(
                            toolUseId: parentToolUseId,
                            kind: .toolResult,
                            itemId: item["tool_use_id"] as? String,
                            text: text
                        ))
                    }
                } else if let text = item["text"] as? String, !text.isEmpty {
                    eventContinuation.yield(.subAgentActivity(
                        toolUseId: parentToolUseId,
                        kind: .prompt,
                        itemId: nil,
                        text: text
                    ))
                }
            }
            return
        }

        for item in content where item["type"] as? String == "tool_result" {
            guard let toolUseId = item["tool_use_id"] as? String else { continue }
            if subAgentToolUseIds.contains(toolUseId) {
                let text = toolResultText(from: item["content"])
                // 起動確認メタデータ（非同期 Agent 起動の ack）は出力ではないので表示しない。
                // 非同期 Agent ツールは run_in_background フラグを持たない（実データで確認）ため、
                // フラグ判定だけでは捕捉できない。Claude 自身が "This tool result is internal
                // metadata — never quote" と自己記述する固定署名で判定して抑制する。
                if backgroundSubAgentToolUseIds.contains(toolUseId)
                    || Self.isAsyncLaunchMetadata(text) {
                    continue
                }
                eventContinuation.yield(.subAgentOutput(
                    toolUseId: toolUseId,
                    text: text
                ))
                continue
            }
            let itemId = toolUseItemIds[toolUseId] ?? toolUseId
            eventContinuation.yield(.commandExecution(
                itemId: itemId,
                command: nil,
                outputDelta: toolResultText(from: item["content"])
            ))
        }
    }

    func isSubAgentTool(_ name: String) -> Bool {
        name == "Task" || name == "Agent"
    }

    /// 非同期 Agent/Task 起動時に返る「起動確認メタデータ」の署名判定。
    /// Claude Code は本文を必ず "Async agent launched successfully" で**始め**、"This tool result
    /// is internal metadata — never quote or paste …" と自己記述する固定形式で返す（実データで確認）。
    /// hasPrefix を要件にすることで、正当なフォアグラウンド出力が本文の**途中で**この2フレーズを
    /// 引用しただけのケース（このリポジトリを調査する Explore 等）を silent に抑制する誤検出を避ける。
    static func isAsyncLaunchMetadata(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Async agent launched successfully")
            && trimmed.contains("This tool result is internal metadata")
    }

    func markSubAgentToolUse(_ toolUseId: String) {
        subAgentToolUseIds.insert(toolUseId)
    }

    func assistantContentItemId(_ item: [String: Any], messageId: String?, type: String, index: Int) -> String {
        if let explicitId = item["id"] as? String {
            return explicitId
        }
        if let messageId {
            return "\(messageId):\(type)"
        }
        return generatedItemId(prefix: "assistant", index: index)
    }

    func yieldSubAgentStartedIfNeeded(
        toolUseId: String,
        subagentType: String,
        description: String
    ) {
        guard !emittedSubAgentStarts.contains(toolUseId) else { return }
        emittedSubAgentStarts.insert(toolUseId)
        eventContinuation.yield(.subAgentStarted(
            toolUseId: toolUseId,
            subagentType: subagentType,
            description: description
        ))
    }
}
