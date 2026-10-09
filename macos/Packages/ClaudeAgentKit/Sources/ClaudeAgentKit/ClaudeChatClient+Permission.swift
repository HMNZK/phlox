import Foundation
import StructuredChatKit

extension ClaudeChatClient {
    /// 公式 SDK の set_permission_mode と同じライブ変更。応答で確認した値だけ保持する。
    public func setPermissionMode(_ mode: String) async throws {
        guard pendingPermissionRequest == nil else {
            throw ClaudeChatClientError.permissionRequestInProgress
        }
        guard currentPermissionMode != mode else { return }
        guard let transport else {
            currentPermissionMode = mode
            return
        }
        let generation = spawnGeneration
        let requestID = "set_permission_mode-\(UUID().uuidString)"
        var line = try JSONSerialization.data(withJSONObject: [
            "type": "control_request", "request_id": requestID,
            "request": ["subtype": "set_permission_mode", "mode": mode],
        ])
        line.append(0x0A)
        let requestLine = line
        let timeout = permissionRequestTimeout
        try await withCheckedThrowingContinuation { continuation in
            pendingPermissionRequest = PendingPermissionRequest(
                id: requestID, mode: mode, generation: generation,
                continuation: continuation
            )
            pendingPermissionRequest?.timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                await self?.invalidatePermissionRequest(
                    id: requestID, error: ClaudeChatClientError.permissionRequestTimedOut
                )
            }
            Task { [weak self] in
                do { try await transport.send(requestLine) }
                catch { await self?.invalidatePermissionRequest(id: requestID, error: error) }
            }
        }
    }

    func setPermissionRequestTimeoutForTesting(_ timeout: Duration) {
        permissionRequestTimeout = timeout
    }

    func handlePermissionResponse(_ envelope: [String: Any]) -> Bool {
        guard transport != nil, let pending = pendingPermissionRequest,
              envelope["request_id"] as? String == pending.id,
              pending.generation == spawnGeneration else { return false }
        if envelope["subtype"] as? String == "success" {
            currentPermissionMode = pending.mode
            pendingPermissionRequest = nil
            pending.timeoutTask?.cancel()
            pending.continuation.resume()
        } else {
            failPendingPermissionRequest(ClaudeChatClientError.permissionRequestFailed(
                envelope["error"] as? String ?? "Claude permission request failed"
            ))
        }
        return true
    }

    func failPendingPermissionRequest(_ error: Error) {
        guard let pending = pendingPermissionRequest else { return }
        pendingPermissionRequest = nil
        pending.timeoutTask?.cancel()
        pending.continuation.resume(throwing: error)
    }

    /// 応答が不明なら旧権限を表示したまま実行し続けない。次ターンは確認済みの値で起動する。
    private func invalidatePermissionRequest(id: String, error: Error) async {
        guard let pending = pendingPermissionRequest, pending.id == id,
              let oldTransport = transport else { return }
        let wasRunning = currentTurnOpen
        transport = nil
        receiveTask?.cancel()
        receiveTask = nil
        currentTurnOpen = false
        currentTurnLine = nil
        failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
        await expirePendingUserQuestions(sendDeny: false)
        await oldTransport.close()
        guard pendingPermissionRequest?.id == id,
              pending.generation == spawnGeneration else { return }
        if wasRunning {
            eventContinuation.yield(.turnInterrupted(nativeSessionId: currentSessionId))
        }
        failPendingPermissionRequest(error)
    }
}
