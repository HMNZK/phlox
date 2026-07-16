import Foundation
import StructuredChatKit
import Testing
import ClaudeAgentKit

// task-2 受け入れテスト（PM 著・実装役編集禁止）。
// 契約: ClaudeChatClient.fetchRateLimits() は常駐 -p プロセスへ
// {"type":"control_request","request_id":<一意>,"request":{"subtype":"get_usage"}}
// を1行で送り、request_id が一致する control_response を
// AgentRateLimitsSnapshot（utilization→usedPercentage, resets_at(ISO8601)→Date）
// に写像して返す。control_response はチャットイベントへ一切漏らさない。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

// MARK: - ハーネス

private final class UsageMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        lock.withLock { sent.append(data) }
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private struct AcceptanceTimeout: Error {}

/// fetchRateLimits がハングする実装を fail として検出するためのタイムアウト付き await。
private func withTimeout<T: Sendable>(
    seconds: Double = 5,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw AcceptanceTimeout()
        }
        guard let first = try await group.next() else { throw AcceptanceTimeout() }
        group.cancelAll()
        return first
    }
}

/// mock へ get_usage の control_request が書かれるまで待ち、その request_id を返す。
/// `skipping` は既に観測済みの request_id（並行テストで2件目を待つ用）。
private func waitForGetUsageRequestID(
    in mock: UsageMockTransport,
    skipping: Set<String> = [],
    timeoutSeconds: Double = 3
) async throws -> String {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        for line in mock.sentStrings() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "control_request",
                  let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "get_usage",
                  let requestID = object["request_id"] as? String,
                  !requestID.isEmpty,
                  !skipping.contains(requestID)
            else { continue }
            return requestID
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw AcceptanceTimeout()
}

/// 実 CLI（claude 2.1.205, 2026-07-10 実測）の応答形を模した control_response 行。
/// 実応答同様、rate_limits の未知フィールドや余分なトップレベルキーを含む
/// （実装は寛容にパースしなければならない）。
private func usageResponseLine(
    requestID: String,
    fiveHourUtilization: Double = 12,
    fiveHourResetsAt: String = "2026-07-09T22:50:00.500462+00:00",
    sevenDayUtilization: Double = 3,
    sevenDayResetsAt: String = "2026-07-16T12:00:00.500500+00:00"
) -> String {
    """
    {"type":"control_response","response":{"subtype":"success","request_id":"\(requestID)","response":{"session":{"total_cost_usd":0,"total_api_duration_ms":0,"model_usage":{}},"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":\(fiveHourUtilization),"resets_at":"\(fiveHourResetsAt)","limit_dollars":null},"seven_day":{"utilization":\(sevenDayUtilization),"resets_at":"\(sevenDayResetsAt)","limit_dollars":null},"seven_day_opus":null,"tangelo":null,"extra_usage":{"is_enabled":false,"used_credits":0},"limits":[{"kind":"session","percent":\(fiveHourUtilization),"severity":"normal"}],"model_scoped":[{"display_name":"Fable","utilization":\(sevenDayUtilization)}]},"behaviors":{"day":{"request_count":1}}}}}
    """
}

private func isoDate(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: text) else {
        fatalError("acceptance harness: invalid ISO8601 fixture: \(text)")
    }
    return date
}

private func makeClient(_ mock: UsageMockTransport) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "44444444-4444-4444-8444-444444444444"],
        transportFactory: { _, _, _, _ in mock }
    )
}

// MARK: - 受け入れテスト

@Test func getUsageSendsControlRequestAndMapsResponseToSnapshot() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    let fetch = Task { try await client.fetchRateLimits() }
    let requestID = try await waitForGetUsageRequestID(in: mock)
    mock.receive(usageResponseLine(requestID: requestID))

    let snapshot = try await withTimeout { try await fetch.value }
    #expect(snapshot.fiveHour?.usedPercentage == 12)
    #expect(snapshot.sevenDay?.usedPercentage == 3)
    let expectedFiveHourReset = isoDate("2026-07-09T22:50:00.500462+00:00")
    let expectedSevenDayReset = isoDate("2026-07-16T12:00:00.500500+00:00")
    let fiveHourReset = try #require(snapshot.fiveHour?.resetsAt)
    let sevenDayReset = try #require(snapshot.sevenDay?.resetsAt)
    #expect(abs(fiveHourReset.timeIntervalSince(expectedFiveHourReset)) < 0.01)
    #expect(abs(sevenDayReset.timeIntervalSince(expectedSevenDayReset)) < 0.01)
    #expect(abs(snapshot.asOf.timeIntervalSinceNow) < 30)
    await client.close()
}

@Test func getUsageConcurrentRequestsCorrelateByRequestID() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    let first = Task { try await client.fetchRateLimits() }
    let firstID = try await waitForGetUsageRequestID(in: mock)
    let second = Task { try await client.fetchRateLimits() }
    let secondID = try await waitForGetUsageRequestID(in: mock, skipping: [firstID])
    #expect(firstID != secondID)

    // 逆順で応答しても request_id で正しく相関すること。
    mock.receive(usageResponseLine(requestID: secondID, fiveHourUtilization: 55, sevenDayUtilization: 44))
    mock.receive(usageResponseLine(requestID: firstID, fiveHourUtilization: 12, sevenDayUtilization: 3))

    let firstSnapshot = try await withTimeout { try await first.value }
    let secondSnapshot = try await withTimeout { try await second.value }
    #expect(firstSnapshot.fiveHour?.usedPercentage == 12)
    #expect(firstSnapshot.sevenDay?.usedPercentage == 3)
    #expect(secondSnapshot.fiveHour?.usedPercentage == 55)
    #expect(secondSnapshot.sevenDay?.usedPercentage == 44)
    await client.close()
}

@Test func getUsageControlResponseDoesNotLeakIntoChatEvents() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()
    // AsyncStream はイベントをバッファするため、先に読み手 Task を立てておけば
    // 以後に yield されたイベントの最初の1件を確実に観測できる。
    let firstEvent = Task { () -> NormalizedChatEvent? in
        for await event in client.events {
            return event
        }
        return nil
    }

    // 相関済み応答・未知 request_id の応答のどちらもイベントへ漏れないこと。
    let fetch = Task { try await client.fetchRateLimits() }
    let requestID = try await waitForGetUsageRequestID(in: mock)
    mock.receive(usageResponseLine(requestID: requestID))
    _ = try await withTimeout { try await fetch.value }
    mock.receive(usageResponseLine(requestID: "unmatched-request-id-should-be-ignored"))

    // 番兵: 実装が未知 type を .warning にする既存挙動を利用し、
    // 「最初に観測されるイベントが番兵の warning である」ことで
    // control_response 由来のイベントが先行しないことを凍結する。
    mock.receive(#"{"type":"phlox_acceptance_sentinel_unknown"}"#)
    let event = try await withTimeout { await firstEvent.value }
    guard case .warning(let message)? = event else {
        Issue.record("expected sentinel warning, got: \(String(describing: event))")
        await client.close()
        return
    }
    #expect(message.contains("phlox_acceptance_sentinel_unknown"))
    await client.close()
}

@Test func getUsageResolvesWhileTurnIsInFlight() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    try await client.turnStart([.text("hello")])
    let fetch = Task { try await client.fetchRateLimits() }
    let requestID = try await waitForGetUsageRequestID(in: mock)
    mock.receive(usageResponseLine(requestID: requestID, fiveHourUtilization: 21))

    let snapshot = try await withTimeout { try await fetch.value }
    #expect(snapshot.fiveHour?.usedPercentage == 21)

    // ターン自体も通常どおり完了できること（result を受けても fetch 側と混線しない）。
    mock.receive(#"{"type":"result","subtype":"success","session_id":"44444444-4444-4444-8444-444444444444","is_error":false}"#)
    await client.close()
}

@Test func getUsageErrorResponseThrows() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    let fetch = Task { try await client.fetchRateLimits() }
    let requestID = try await waitForGetUsageRequestID(in: mock)
    mock.receive(
        #"{"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"get_usage failed"}}"#
    )

    await #expect(throws: (any Error).self) {
        try await withTimeout { try await fetch.value }
    }
    await client.close()
}

@Test func getUsageFailsPendingRequestOnCloseInsteadOfHanging() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    let fetch = Task { try await client.fetchRateLimits() }
    _ = try await waitForGetUsageRequestID(in: mock)
    await client.close()

    await #expect(throws: (any Error).self) {
        try await withTimeout { try await fetch.value }
    }
}

@Test func getUsageThrowsWhenClientIsNotStarted() async throws {
    let mock = UsageMockTransport()
    let client = makeClient(mock)

    await #expect(throws: (any Error).self) {
        try await withTimeout(seconds: 2) { try await client.fetchRateLimits() }
    }
}
