import Foundation
import StructuredChatKit

// 隠している秘密: stream-json の生JSON行を `type`/`subtype` でどう振り分けるか
extension ClaudeChatClient {
    func handleLine(_ data: Data, generation: Int) async {
        guard generation == spawnGeneration else { return }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let event = object as? [String: Any] else {
                eventContinuation.yield(.error(message: "Failed to parse Claude stream-json line"))
                return
            }
            await handleEvent(event, generation: generation)
        } catch {
            eventContinuation.yield(.error(message: "Failed to parse Claude stream-json line"))
        }
    }

    func handleEvent(_ event: [String: Any], generation: Int) async {
        guard let type = event["type"] as? String else { return }

        switch type {
        case "system":
            handleSystemEvent(event)
        case "assistant":
            handleAssistantEvent(event)
        case "stream_event":
            handleStreamEvent(event)
        case "user":
            handleUserEvent(event)
        case "result":
            handleResultEvent(event, generation: generation)
        case "control_response":
            handleControlResponse(event, generation: generation)
        case "control_request":
            if !(await handleControlRequest(event, generation: generation)) {
                eventContinuation.yield(.warning(message: "Unknown Claude event type: \(type)"))
            }
        case "rate_limit_event", "tool_progress":
            // 無害な情報イベント（利用量ステータス・ツール進捗）。ターン処理に影響しないため黙って無視する。
            break
        default:
            eventContinuation.yield(.warning(message: "Unknown Claude event type: \(type)"))
        }
    }

    func handleSystemEvent(_ event: [String: Any]) {
        guard let subtype = event["subtype"] as? String else { return }
        switch subtype {
        case "init":
            if let sessionId = event["session_id"] as? String {
                currentSessionId = sessionId
            }
            if let commands = event["slash_commands"] as? [String], !commands.isEmpty {
                eventContinuation.yield(.availableCommandsUpdated(commands: commands))
            }
            if let message = mcpServerWarningMessage(from: event["mcp_server_errors"]) {
                eventContinuation.yield(.warning(message: message))
            }
        case "task_started":
            guard let taskId = event["task_id"] as? String else { return }
            let taskType = event["task_type"] as? String ?? ""
            let toolUseId = event["tool_use_id"] as? String
            if taskType == "local_agent", let toolUseId {
                // 実サブエージェントはサブエージェントイベントのみ放出し、
                // バックグラウンドタスク・チップとの二重表現を避ける（local_bash 等は従来どおり）。
                markSubAgentToolUse(toolUseId)
                yieldSubAgentStartedIfNeeded(
                    toolUseId: toolUseId,
                    subagentType: event["subagent_type"] as? String ?? "local_agent",
                    description: event["description"] as? String ?? ""
                )
            } else {
                eventContinuation.yield(.backgroundTaskStarted(
                    taskId: taskId,
                    taskType: taskType,
                    description: event["description"] as? String ?? "",
                    toolUseId: toolUseId
                ))
            }
        case "task_notification":
            guard let taskId = event["task_id"] as? String else { return }
            if let toolUseId = event["tool_use_id"] as? String,
               subAgentToolUseIds.contains(toolUseId) {
                // 実サブエージェントは完了もサブエージェント側のみ（二重表現回避）。
                observeSubAgentCompletion(toolUseId)
                eventContinuation.yield(.subAgentCompleted(
                    toolUseId: toolUseId,
                    status: event["status"] as? String ?? "",
                    summary: event["summary"] as? String ?? "",
                    outputFile: event["output_file"] as? String
                ))
            } else {
                eventContinuation.yield(.backgroundTaskCompleted(
                    taskId: taskId,
                    status: event["status"] as? String ?? "",
                    summary: event["summary"] as? String ?? ""
                ))
            }
        case "compact_boundary":
            let metadata = event["compact_metadata"] as? [String: Any]
            let trigger = metadata?["trigger"] as? String
            let preTokens = metadata?["pre_tokens"] as? Int
            eventContinuation.yield(.compactionBoundary(trigger: trigger, preTokens: preTokens))
        default:
            break
        }
    }

    func handleStreamEvent(_ wrapper: [String: Any]) {
        // stream_event 自体を無視する一次ゲート。下の shouldSuppress... は
        // include-partial-messages が有効な場合の完成 assistant だけを抑制する規則であり、役割が異なる。
        guard
            includePartialMessages,
            let event = wrapper["event"] as? [String: Any],
            let type = event["type"] as? String
        else { return }

        let parentToolUseId = wrapper["parent_tool_use_id"] as? String
        if let parentToolUseId {
            // 親 ID がまだ完全な assistant イベントで登録されていなくても、メインへ漏らさず隔離する。
            markSubAgentToolUse(parentToolUseId)
        }

        switch type {
        case "message_start":
            guard
                let message = event["message"] as? [String: Any],
                let messageId = message["id"] as? String
            else { return }
            let parentKey = partialParentKey(parentToolUseId)
            partialMessageIdsByParent[parentKey] = messageId
            removePartialBlocks(for: parentKey)
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any] else { return }
            guard let blockType = block["type"] as? String else { return }
            if parentToolUseId != nil,
               blockType == "tool_use",
               let toolUseId = block["id"] as? String,
               let name = block["name"] as? String,
               isSubAgentTool(name) {
                // tool_use の完全イベントより先に孫の stream_event が来ても取りこぼさない。
                markSubAgentToolUse(toolUseId)
            }
        case "content_block_delta":
            let index = event["index"] as? Int ?? 0
            guard let delta = event["delta"] as? [String: Any] else { return }
            switch delta["type"] as? String {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return }
                yieldPartialContent(
                    text,
                    parentToolUseId: parentToolUseId,
                    index: index,
                    type: "text",
                    kind: .message
                )
            case "thinking_delta":
                guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else { return }
                yieldPartialContent(
                    thinking,
                    parentToolUseId: parentToolUseId,
                    index: index,
                    type: "thinking",
                    kind: .reasoning
                )
            default:
                break
            }
        default:
            break
        }
    }

    func yieldPartialContent(
        _ text: String,
        parentToolUseId: String?,
        index: Int,
        type: String,
        kind: SubAgentActivityKind
    ) {
        let itemId = partialItemId(parentToolUseId: parentToolUseId, index: index, type: type)
        if let parentToolUseId {
            eventContinuation.yield(.subAgentActivity(
                toolUseId: parentToolUseId,
                kind: kind,
                itemId: itemId,
                text: text
            ))
        } else if kind == .message {
            eventContinuation.yield(.agentMessageDelta(itemId: itemId, text))
        } else {
            eventContinuation.yield(.reasoningDelta(itemId: itemId, text))
        }
    }

    func partialParentKey(_ parentToolUseId: String?) -> String {
        parentToolUseId ?? "<main>"
    }

    func partialBlockKey(_ parentToolUseId: String?, index: Int) -> String {
        "\(partialParentKey(parentToolUseId))|\(index)"
    }

    func partialItemKey(_ parentToolUseId: String?, index: Int, type: String) -> String {
        "\(partialBlockKey(parentToolUseId, index: index))|\(type)"
    }

    func partialContentKey(_ parentToolUseId: String?, messageId: String, type: String) -> String {
        "\(partialParentKey(parentToolUseId))|\(messageId)|\(type)"
    }

    func partialItemId(parentToolUseId: String?, index: Int, type: String) -> String {
        let key = partialItemKey(parentToolUseId, index: index, type: type)
        if let itemId = partialItemIdsByKey[key] {
            return itemId
        }

        let itemId: String
        if let messageId = partialMessageIdsByParent[partialParentKey(parentToolUseId)] {
            itemId = "\(messageId):\(type)"
            partialContentKeys.insert(partialContentKey(parentToolUseId, messageId: messageId, type: type))
        } else {
            itemId = generatedItemId(
                prefix: parentToolUseId == nil ? "assistant" : "subagent",
                index: index
            )
        }
        partialItemIdsByKey[key] = itemId
        partialItemIds.insert(itemId)
        return itemId
    }

    func removePartialBlocks(for parentKey: String) {
        let prefix = "\(parentKey)|"
        let removedItemIds = partialItemIdsByKey
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
        partialItemIdsByKey.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { partialItemIdsByKey.removeValue(forKey: $0) }
        partialItemIds.subtract(removedItemIds)
        partialContentKeys = partialContentKeys.filter { !$0.hasPrefix(prefix) }
    }

    func pruneSubAgentPartialBlocks() {
        // result は launcher のターン境界であり、background の子ターンの境界ではない。
        // 完了を観測した ID だけを解放し、result 後も流れ続ける本文の抑制キーを残す。
        let completedParentKeys = completedSubAgentToolUseIds
        for parentKey in completedParentKeys {
            removePartialBlocks(for: parentKey)
            partialMessageIdsByParent.removeValue(forKey: parentKey)
        }
        completedSubAgentToolUseIds.subtract(completedParentKeys)
    }

    func observeSubAgentCompletion(_ toolUseId: String) {
        completedSubAgentToolUseIds.insert(toolUseId)
        // ここでは解放しない。完了通知が最終 assistant メッセージより先に届くと、
        // 抑制キーが先に消えて完成本文が再送され二重表示になるため。
        // 解放は result 境界の pruneSubAgentPartialBlocks() に委ねる。
    }

    func mcpServerWarningMessage(from raw: Any?) -> String? {
        guard let entries = raw as? [Any] else { return nil }
        let messages = entries.compactMap { mcpServerErrorDescription($0) }
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "\n")
    }

    func mcpServerErrorDescription(_ raw: Any) -> String? {
        guard
            let entry = raw as? [String: Any],
            let name = entry["name"] as? String,
            let message = entry["message"] as? String
        else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedMessage.isEmpty else { return nil }
        return "MCPサーバー「\(trimmedName)」: \(trimmedMessage)"
    }

    func handleResultEvent(_ event: [String: Any], generation: Int) {
        if let sessionId = event["session_id"] as? String {
            currentSessionId = sessionId
        }
        recordConversationEvidenceFromResult(event)
        pruneSubAgentPartialBlocks()

        if event["is_error"] as? Bool == true || event["subtype"] as? String == "error" {
            if shouldAbsorbInterruptedResultError(event, generation: generation) {
                // FIFO means the first error_during_execution result after an
                // interrupted turn in the same process generation is the CLI's
                // cleanup for that turn. interrupt() has already closed the
                // interrupted turn; this branch may run after the next turnStart,
                // so it must not touch currentTurnOpen/currentTurnLine.
                // We intentionally keep this armed across the next turnStart; if
                // the CLI never sends cleanup, the next real error_during_execution
                // may be absorbed once, which is the accepted tradeoff from the
                // task-24 decision log.
                interruptedResultSuppression = nil
                pendingResultError = nil
                return
            }
            if shouldDeferResultError(event) {
                pendingResultError = PendingResultError(
                    message: resultErrorMessage(from: event),
                    resumeSessionId: activeResumeSessionId()
                )
                return
            }
            currentTurnOpen = false
            currentTurnLine = nil
            eventContinuation.yield(.error(message: resultErrorMessage(from: event)))
            return
        }

        if event["subtype"] as? String == "success" {
            currentTurnOpen = false
            currentTurnLine = nil
            pendingResultError = nil
            if let usage = parseTurnUsage(from: event) {
                eventContinuation.yield(.turnUsage(usage))
            }
            eventContinuation.yield(.turnCompleted(nativeSessionId: currentSessionId))
        }
    }

    func parseTurnUsage(from event: [String: Any]) -> TurnUsage? {
        let costUSD = event["total_cost_usd"] as? Double
        let usageDict = event["usage"] as? [String: Any]

        guard costUSD != nil || usageDict != nil else { return nil }

        return TurnUsage(
            costUSD: costUSD,
            inputTokens: usageDict?["input_tokens"] as? Int,
            outputTokens: usageDict?["output_tokens"] as? Int,
            cacheReadTokens: usageDict?["cache_read_input_tokens"] as? Int,
            cacheCreationTokens: usageDict?["cache_creation_input_tokens"] as? Int,
            contextUsedTokens: currentTurnLatestContextTokens,
            contextWindowTokens: selectedContextWindow(from: event["modelUsage"])
        )
    }

    private func selectedContextWindow(from rawModelUsage: Any?) -> Int? {
        guard let modelUsage = rawModelUsage as? [String: [String: Any]] else { return nil }

        return modelUsage.values.max { lhs, rhs in
            let lhsConsumption = contextConsumption(from: lhs)
            let rhsConsumption = contextConsumption(from: rhs)
            if lhsConsumption == rhsConsumption {
                return (lhs["contextWindow"] as? Int ?? 0) < (rhs["contextWindow"] as? Int ?? 0)
            }
            return lhsConsumption < rhsConsumption
        }?["contextWindow"] as? Int
    }

    private func contextConsumption(from usage: [String: Any]) -> Int {
        (usage["inputTokens"] as? Int ?? 0)
            + (usage["cacheReadInputTokens"] as? Int ?? 0)
            + (usage["cacheCreationInputTokens"] as? Int ?? 0)
    }
}
