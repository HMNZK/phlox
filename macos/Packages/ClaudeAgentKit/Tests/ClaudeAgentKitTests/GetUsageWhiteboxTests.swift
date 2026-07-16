import Foundation
import StructuredChatKit
import Testing
@testable import ClaudeAgentKit

private final class UsageWhiteboxTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    private var closed = false

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    var didClose: Bool {
        lock.withLock { closed }
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        lock.withLock { sent.append(data) }
    }

    func interrupt() async {}

    func close() async {
        lock.withLock { closed = true }
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private final class UsageWhiteboxTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [UsageWhiteboxTransport] = []

    var recordedTransports: [UsageWhiteboxTransport] {
        lock.withLock { transports }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = UsageWhiteboxTransport()
        lock.withLock { transports.append(transport) }
        return transport
    }
}

private struct UsageWhiteboxTimeout: Error {}

private func waitForUsageRequestID(
    in transport: UsageWhiteboxTransport,
    skipping skippedIDs: Set<String> = [],
    timeout: Duration = .seconds(2)
) async throws -> String {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        for line in transport.sentStrings() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "control_request",
                  let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "get_usage",
                  let requestID = object["request_id"] as? String,
                  !requestID.isEmpty,
                  !skippedIDs.contains(requestID)
            else { continue }
            return requestID
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw UsageWhiteboxTimeout()
}

private func usageSuccessLine(requestID: String, utilization: Double = 9) -> String {
    """
    {"type":"control_response","response":{"subtype":"success","request_id":"\(requestID)","response":{"rate_limits":{"five_hour":{"utilization":\(utilization),"resets_at":"2026-07-09T22:50:00.500462+00:00"},"seven_day":null}}}}
    """
}

private func waitForTaskResult<T: Sendable>(
    timeout: Duration = .seconds(2),
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw UsageWhiteboxTimeout()
        }
        guard let result = try await group.next() else { throw UsageWhiteboxTimeout() }
        group.cancelAll()
        return result
    }
}

@Test func getUsagePendingRequestFailsWhenRespawnClosesTransport() async throws {
    let recorder = UsageWhiteboxTransportRecorder()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "22222222-2222-4222-8222-222222222222"],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    let firstTransport = try #require(recorder.recordedTransports.first)

    let fetch = Task { try await client.fetchRateLimits() }
    _ = try await waitForUsageRequestID(in: firstTransport)

    await client.updateSettings(model: "opus", permissionMode: nil as String?)
    try await client.turnStart([.text("respawn")])

    #expect(firstTransport.didClose)
    await #expect(throws: (any Error).self) {
        try await waitForTaskResult { try await fetch.value }
    }
    await client.close()
}

@Test func getUsageTimesOutInternallyWhenNoControlResponseArrives() async throws {
    let recorder = UsageWhiteboxTransportRecorder()
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()
    // 契約どおりタイムアウトは注入可能（本番既定値との結合を避け、テストを高速化する）。
    await client.setUsageRequestTimeoutForTesting(.milliseconds(200))
    let transport = try #require(recorder.recordedTransports.first)

    let fetch = Task { try await client.fetchRateLimits() }
    _ = try await waitForUsageRequestID(in: transport)

    await #expect(throws: ClaudeChatClientError.usageRequestTimedOut) {
        try await waitForTaskResult(timeout: .seconds(4)) { try await fetch.value }
    }
    await client.close()
}

@Test func getUsageIgnoresControlResponseFromStaleGeneration() async throws {
    let recorder = UsageWhiteboxTransportRecorder()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "33333333-3333-4333-8333-333333333333"],
        transportFactory: recorder.makeTransport
    )
    await client.start()

    await client.resetConversation()
    let secondTransport = try #require(recorder.recordedTransports.last)

    let fetch = Task { try await client.fetchRateLimits() }
    let requestID = try await waitForUsageRequestID(in: secondTransport)

    await client.handleLine(Data(usageSuccessLine(requestID: requestID, utilization: 77).utf8), generation: 1)
    try await Task.sleep(for: .milliseconds(100))
    #expect(!fetch.isCancelled)

    secondTransport.receive(usageSuccessLine(requestID: requestID, utilization: 31))
    let snapshot = try await waitForTaskResult { try await fetch.value }
    #expect(snapshot.fiveHour?.usedPercentage == 31)
    await client.close()
}

// close() を任意のタイミングまで suspend させ、reentrant actor の
// 「await transport.close() 窓」を決定論的に再現するためのトランスポート。
private final class SuspendingCloseUsageTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    private var closeStarted = false
    private var closeGate: CheckedContinuation<Void, Never>?
    private var gateReleased = false

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
        lock.withLock { closeStarted = true }
        await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
            let alreadyReleased = lock.withLock { () -> Bool in
                if gateReleased { return true }
                closeGate = gate
                return false
            }
            if alreadyReleased { gate.resume() }
        }
        continuation?.finish()
    }

    func releaseClose() {
        let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            gateReleased = true
            let captured = closeGate
            closeGate = nil
            return captured
        }
        gate?.resume()
    }

    func waitUntilCloseStarted(timeout: Duration = .seconds(2)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if lock.withLock({ closeStarted }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw UsageWhiteboxTimeout()
    }

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private final class SuspendingCloseUsageTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [SuspendingCloseUsageTransport] = []

    var recordedTransports: [SuspendingCloseUsageTransport] {
        lock.withLock { transports }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = SuspendingCloseUsageTransport()
        lock.withLock { transports.append(transport) }
        return transport
    }
}

// stage2 レビュー MUST の再現: spawn() が await transport.close() で actor を
// 明け渡している窓で fetchRateLimits が旧 transport・旧世代のまま pending を
// 登録しても、respawn 完了時に速やかに transportClosed で fail し、hang も
// 黙殺（continuation リーク）もしないこと。既定タイムアウト(10s)より十分
// 短い 1 秒以内の失敗を要求することで、timeout 経路でなく failAll 経路での
// 即時解決を凍結する。
@Test func getUsageFailsPromptlyWhenRequestedDuringRespawnCloseWindow() async throws {
    let recorder = SuspendingCloseUsageTransportRecorder()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "22222222-2222-4222-8222-222222222222"],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    let firstTransport = try #require(recorder.recordedTransports.first)

    await client.updateSettings(model: "opus", permissionMode: nil as String?)
    let respawn = Task { try await client.turnStart([.text("respawn")]) }
    try await firstTransport.waitUntilCloseStarted()

    let fetch = Task { try await client.fetchRateLimits() }
    do {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline,
              !firstTransport.sentStrings().contains(where: { $0.contains("get_usage") }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(firstTransport.sentStrings().contains { $0.contains("get_usage") })
    }

    firstTransport.releaseClose()
    _ = try? await respawn.value

    do {
        _ = try await waitForTaskResult(timeout: .seconds(1)) { try await fetch.value }
        Issue.record("expected fetchRateLimits to fail during respawn close window")
    } catch is UsageWhiteboxTimeout {
        Issue.record("fetchRateLimits hung after respawn (pending continuation leaked)")
    } catch let error as ClaudeChatClientError {
        #expect(error == .transportClosed)
    }

    for transport in recorder.recordedTransports {
        transport.releaseClose()
    }
    await client.close()
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
