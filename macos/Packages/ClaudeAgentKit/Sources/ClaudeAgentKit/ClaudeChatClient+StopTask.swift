import Foundation
import StructuredChatKit

/// サブエージェントを 1 つだけ止める（stream-json の control_request `stop_task`）。
/// 送ると system/task_updated → system/task_notification(status: "stopped") → control_response(success) の順に届く。
/// 停止の確認は task_notification（`subAgentCompleted(status: "stopped")`）で取り、
/// control_response は error のときだけ停止中の解除に使う。
extension ClaudeChatClient: SubAgentStopping {
    public func stopSubAgent(toolUseId: String, attempt: Int) async throws {
        guard let transport else { throw ClaudeChatClientError.notStarted }
        guard let taskId = subAgentTaskIDs[toolUseId] else { throw ClaudeChatClientError.subAgentTaskUnknown }

        let requestID = "stop_task-\(nextStopTaskRequestID)"
        nextStopTaskRequestID += 1
        pendingStopTaskRequests[requestID] = (toolUseId, attempt)
        do {
            try await transport.send(Self.stopTaskControlRequestLine(requestID: requestID, taskId: taskId))
        } catch {
            pendingStopTaskRequests.removeValue(forKey: requestID)
            throw error
        }
    }

    /// stop_task への control_response を処理する。stop_task のものなら true。
    func handleStopTaskResponse(_ event: [String: Any]) -> Bool {
        guard let envelope = event["response"] as? [String: Any],
              let requestID = envelope["request_id"] as? String,
              let pending = pendingStopTaskRequests.removeValue(forKey: requestID)
        else { return false }
        if envelope["subtype"] as? String != "success" {
            eventContinuation.yield(.subAgentStopFailed(toolUseId: pending.toolUseId, attempt: pending.attempt))
        }
        return true
    }

    /// プロセスの再起動・終了・停止で、stop_task の宛先と未応答の要求を捨てる。
    /// 応答はもう来ないので、未応答の要求は失敗として知らせて表示側の停止中を解除する。
    func releaseStopTasks() {
        for pending in pendingStopTaskRequests.values {
            eventContinuation.yield(.subAgentStopFailed(toolUseId: pending.toolUseId, attempt: pending.attempt))
        }
        pendingStopTaskRequests.removeAll()
        subAgentTaskIDs.removeAll()
        stoppedSubAgentToolUseIds.removeAll()
    }

    private static func stopTaskControlRequestLine(requestID: String, taskId: String) throws -> Data {
        let payload: [String: Any] = [
            "type": "control_request",
            "request_id": requestID,
            "request": [
                "subtype": "stop_task",
                "task_id": taskId,
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: payload, options: [])
        data.append(0x0A)
        return data
    }
}
