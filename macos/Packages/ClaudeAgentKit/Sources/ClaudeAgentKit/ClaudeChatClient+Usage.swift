import Foundation
import StructuredChatKit

extension ClaudeChatClient: UsageQuerying {
    public func fetchRateLimits() async throws -> AgentRateLimitsSnapshot {
        guard let transport else {
            throw ClaudeChatClientError.notStarted
        }

        let requestID = "get_usage-\(nextUsageRequestID)"
        nextUsageRequestID += 1
        let generation = spawnGeneration
        let timeout = usageRequestTimeout

        return try await withCheckedThrowingContinuation { continuation in
            pendingUsageRequests[requestID] = PendingUsageRequest(
                continuation: continuation,
                generation: generation,
                timeoutTask: nil
            )
            pendingUsageRequests[requestID]?.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expireUsageRequest(id: requestID)
            }

            Task { [weak self] in
                do {
                    try await transport.send(Self.usageControlRequestLine(requestID: requestID))
                } catch {
                    await self?.resumeUsageRequest(id: requestID, result: .failure(error))
                }
            }
        }
    }

    func handleControlResponse(_ event: [String: Any], generation: Int) {
        guard generation == spawnGeneration else { return }
        guard let envelope = event["response"] as? [String: Any],
              let requestID = envelope["request_id"] as? String,
              pendingUsageRequests[requestID] != nil
        else { return }

        guard envelope["subtype"] as? String == "success" else {
            let message = envelope["error"] as? String ?? "Claude get_usage request failed"
            resumeUsageRequest(id: requestID, result: .failure(ClaudeChatClientError.usageRequestFailed(message)))
            return
        }

        guard let response = envelope["response"] as? [String: Any],
              let rateLimits = response["rate_limits"] as? [String: Any]
        else {
            resumeUsageRequest(id: requestID, result: .failure(ClaudeChatClientError.malformedUsageResponse))
            return
        }

        let snapshot = AgentRateLimitsSnapshot(
            fiveHour: Self.usageBucket(from: rateLimits["five_hour"]),
            sevenDay: Self.usageBucket(from: rateLimits["seven_day"]),
            asOf: Date()
        )
        resumeUsageRequest(id: requestID, result: .success(snapshot))
    }

    func expireUsageRequest(id: String) {
        // 世代ガードは置かない: respawn 窓で旧世代のまま登録された pending の
        // timeout まで黙殺すると continuation が永久リークする（stage2 MUST）。
        // resume は pendingUsageRequests からの removeValue で冪等なので、
        // 世代に関係なく必ず fail させて安全（既に解決済みなら no-op）。
        resumeUsageRequest(id: id, result: .failure(ClaudeChatClientError.usageRequestTimedOut))
    }

    func resumeUsageRequest(id: String, result: Result<AgentRateLimitsSnapshot, Error>) {
        guard let pending = pendingUsageRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask?.cancel()
        switch result {
        case .success(let snapshot):
            pending.continuation.resume(returning: snapshot)
        case .failure(let error):
            pending.continuation.resume(throwing: error)
        }
    }

    func failAllPendingUsageRequests(_ error: Error) {
        let pending = pendingUsageRequests
        pendingUsageRequests.removeAll()
        for request in pending.values {
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private static func usageControlRequestLine(requestID: String) throws -> Data {
        let payload: [String: Any] = [
            "type": "control_request",
            "request_id": requestID,
            "request": [
                "subtype": "get_usage",
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: payload, options: [])
        data.append(0x0A)
        return data
    }

    private static func usageBucket(from value: Any?) -> AgentRateLimitsSnapshot.Bucket? {
        guard let object = value as? [String: Any],
              let utilization = object["utilization"] as? Double
        else { return nil }

        return AgentRateLimitsSnapshot.Bucket(
            usedPercentage: utilization,
            resetsAt: parseUsageDate(object["resets_at"] as? String)
        )
    }

    private static func parseUsageDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
