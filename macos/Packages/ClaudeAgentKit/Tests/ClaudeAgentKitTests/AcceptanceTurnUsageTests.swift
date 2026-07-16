// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — result(success) の total_cost_usd / usage を
// `.turnUsage` として `.turnCompleted` の直前に yield する。
// 注: 期待イベントが来ない実装でもハングしないよう、タイムアウト付きで収集する。

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class TurnUsageMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }
}

/// 観測イベントの共有バッファ（タイムアウト時も部分結果を失わない）。
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { events.append(event) } }
    func snapshot() -> [NormalizedChatEvent] { lock.withLock { events } }
}

/// `count` 件そろうか timeout までに観測できたイベントを返す（不足時はその時点の配列）。
private func collectEvents(
    from client: ClaudeChatClient,
    count: Int,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async -> [NormalizedChatEvent] {
    let box = EventBox()
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for await event in client.events {
                box.append(event)
                if box.snapshot().count >= count { break }
            }
        }
        group.addTask {
            var waited: UInt64 = 0
            let step: UInt64 = 50_000_000
            while waited < timeoutNanoseconds, box.snapshot().count < count {
                try? await Task.sleep(nanoseconds: step)
                waited += step
            }
        }
        _ = await group.next()
        group.cancelAll()
    }
    return box.snapshot()
}

private func makeClient(_ mock: TurnUsageMockTransport) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111"],
        transportFactory: { _, _, _, _ in mock }
    )
}

@Test func turnUsage_successResultWithCostAndUsage_yieldsTurnUsageBeforeTurnCompleted() async throws {
    let mock = TurnUsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-abc","is_error":false,\
    "total_cost_usd":1.23,"usage":{"input_tokens":10,"output_tokens":20,\
    "cache_read_input_tokens":5,"cache_creation_input_tokens":7}}
    """)

    let events = await collectEvents(from: client, count: 2)
    #expect(events == [
        .turnUsage(TurnUsage(
            costUSD: 1.23,
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 5,
            cacheCreationTokens: 7
        )),
        .turnCompleted(nativeSessionId: "session-abc"),
    ])
    await client.close()
}

@Test func turnUsage_costOnlyResult_yieldsTurnUsageWithNilTokens() async throws {
    let mock = TurnUsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-abc","is_error":false,"total_cost_usd":2.5}
    """)

    let events = await collectEvents(from: client, count: 2)
    #expect(events == [
        .turnUsage(TurnUsage(costUSD: 2.5)),
        .turnCompleted(nativeSessionId: "session-abc"),
    ])
    await client.close()
}

@Test func turnUsage_successResultWithoutCostOrUsage_yieldsNoTurnUsage() async throws {
    let mock = TurnUsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-xyz","is_error":false}
    """)

    let events = await collectEvents(from: client, count: 1)
    #expect(events == [.turnCompleted(nativeSessionId: "session-xyz")])
    await client.close()
}

@Test func turnUsage_errorResult_yieldsErrorWithoutTurnUsage() async throws {
    let mock = TurnUsageMockTransport()
    let client = makeClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"error","is_error":true,"total_cost_usd":0.5,"result":"boom"}
    """)

    let events = await collectEvents(from: client, count: 1)
    try #require(events.count == 1)
    if case .error = events[0] {
        // ok: コスト付きでもエラー result からは turnUsage を出さない
    } else {
        Issue.record("expected .error, got \(String(describing: events[0]))")
    }
    await client.close()
}
