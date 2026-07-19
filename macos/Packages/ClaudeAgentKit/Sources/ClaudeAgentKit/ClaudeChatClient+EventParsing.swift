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
        default:
            break
        }
    }

    func handleResultEvent(_ event: [String: Any], generation: Int) {
        if let sessionId = event["session_id"] as? String {
            currentSessionId = sessionId
        }
        recordConversationEvidenceFromResult(event)

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
