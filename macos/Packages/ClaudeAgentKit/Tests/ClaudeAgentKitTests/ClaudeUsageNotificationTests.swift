import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

struct ClaudeUsageNotificationTests {
    // 実受信の形式。セッション識別子は匿名化し時刻は固定する。
    static let notification = """
    {"type":"rate_limit_event","session_id":"anonymous","rate_limit_info":{
      "status":"allowed","unifiedWindows":{
        "five_hour":{"utilization":0.09,"resetsAt":2000001000},
        "seven_day":{"utilization":0.39,"resetsAt":2000600000}}}}
    """

    @Test func percentagesAndDates() throws {
        let object = try #require(JSONSerialization.jsonObject(with: Data(Self.notification.utf8)) as? [String: Any])
        let snapshot = try #require(ClaudeChatClient.rateLimitsNotification(object, now: Date(timeIntervalSince1970: 2000000000)))
        #expect(snapshot.fiveHour?.usedPercentage == 9)
        #expect(snapshot.sevenDay?.usedPercentage == 39)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 2000001000))
    }

    @Test func ignoresMissingAndInvalidWindows() throws {
        let now = Date(timeIntervalSince1970: 100)
        for value in [Double.nan, .infinity, -0.1] {
            let event: [String: Any] = ["rate_limit_info": ["unifiedWindows": ["five_hour": ["utilization": value, "resetsAt": 200.0]]]]
            #expect(ClaudeChatClient.rateLimitsNotification(event, now: now) == nil)
        }
        #expect(ClaudeChatClient.rateLimitsNotification(["rate_limit_info": ["rateLimitType": "five_hour"]], now: now) == nil)
        let expired: [String: Any] = ["rate_limit_info": ["unifiedWindows": ["five_hour": ["utilization": 0.1, "resetsAt": 99.0]]]]
        #expect(ClaudeChatClient.rateLimitsNotification(expired, now: now) == nil)
    }

    @Test func notificationIsDeliveredAsAnIndependentEventAndOldGenerationIsIgnored() async throws {
        let transport = UsageTestTransport()
        let client = ClaudeChatClient(transportFactory: { _, _, _, _ in transport })
        try await client.start()
        await client.handleLine(Data(Self.notification.utf8), generation: 0)
        await client.handleLine(Data(Self.notification.utf8), generation: 1)
        var events = client.events.makeAsyncIterator()
        guard case .rateLimitsUpdated(let value) = await events.next() else { Issue.record("notification missing"); await client.close(); return }
        #expect(value.fiveHour?.usedPercentage == 9)
        await client.close()
        #expect(await events.next() == nil)
    }

    @Test func dedicatedProcessReusesOneClientAndOnlySendsControlRequests() async throws {
        let transport = UsageTestTransport()
        let process = ClaudeUsageProcess(command: "claude", environment: [:], transportFactory: { _, arguments, _, directory in
            #expect(arguments == ClaudeUsageProcess.arguments)
            #expect(directory == nil)
            return transport
        })
        let first = try await process.fetchRateLimits()
        let second = try await process.fetchRateLimits()
        #expect(first.fiveHour?.usedPercentage == 9)
        #expect(second.sevenDay?.usedPercentage == 39)
        #expect(transport.starts == 1)
        #expect(transport.requestTypes == ["control_request", "control_request"])
        await process.shutdown()
        #expect(transport.closes == 1)
        await #expect(throws: ClaudeChatClientError.transportClosed) { try await process.fetchRateLimits() }
        #expect(transport.starts == 1)
    }

    @Test func unavailableResponseDoesNotBecomeSuccessfulUsage() async {
        let transport = UsageTestTransport(available: false)
        let process = ClaudeUsageProcess(command: "claude", environment: [:], transportFactory: { _, _, _, _ in transport })
        await #expect(throws: ClaudeChatClientError.malformedUsageResponse) { try await process.fetchRateLimits() }
        await process.shutdown()
        #expect(transport.closes == 1)
    }

    @Test func explicitRetryDelayIsPreserved() async {
        let transport = UsageTestTransport(retryAfter: 600)
        let process = ClaudeUsageProcess(command: "claude", environment: [:], transportFactory: { _, _, _, _ in transport })
        await #expect(throws: ClaudeChatClientError.usageRequestThrottled(retryAfter: 600)) { try await process.fetchRateLimits() }
        await process.shutdown()
    }
}

private final class UsageTestTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var closeCount = 0
    private var types: [String] = []
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let available: Bool
    private let retryAfter: Double?
    init(available: Bool = true, retryAfter: Double? = nil) {
        self.available = available
        self.retryAfter = retryAfter
        (receivedLines, continuation) = AsyncStream.makeStream()
    }
    var starts: Int { lock.withLock { startCount } }
    var closes: Int { lock.withLock { closeCount } }
    var requestTypes: [String] { lock.withLock { types } }
    func start() throws { lock.withLock { startCount += 1 } }
    func send(_ data: Data) async throws {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let type = try #require(object["type"] as? String)
        let id = try #require(object["request_id"] as? String)
        lock.withLock { types.append(type) }
        let response: [String: Any] = ["type": "control_response", "response": ["subtype": "success", "request_id": id,
            "response": ["rate_limits_available": available, "rate_limits": [
                "five_hour": ["utilization": 9, "resets_at": "2033-05-18T03:33:20Z"],
                "seven_day": ["utilization": 39, "resets_at": "2033-05-25T03:33:20Z"]]]]]
        if let retryAfter {
            continuation.yield(try JSONSerialization.data(withJSONObject: ["type": "control_response",
                "response": ["subtype": "error", "request_id": id, "error": "rate limited", "retry_after": retryAfter]]))
        } else { continuation.yield(try JSONSerialization.data(withJSONObject: response)) }
    }
    func interrupt() async {}
    func close() async { lock.withLock { closeCount += 1 }; continuation.finish() }
}
