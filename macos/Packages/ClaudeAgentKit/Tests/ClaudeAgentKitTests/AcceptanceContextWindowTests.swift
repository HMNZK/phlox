// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — result(success) の modelUsage[<model>].contextWindow を
// TurnUsage.contextWindowTokens として yield する。Claude 側では contextUsedTokens は設定しない。
// ハーネスは AcceptanceTurnUsageTests と同型（mock transport + タイムアウト付き収集）。

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class ContextWindowMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

private final class ContextWindowEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { events.append(event) } }
    func snapshot() -> [NormalizedChatEvent] { lock.withLock { events } }
}

private func collectContextWindowEvents(
    from client: ClaudeChatClient,
    count: Int,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async -> [NormalizedChatEvent] {
    let box = ContextWindowEventBox()
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

private func makeContextWindowClient(_ mock: ContextWindowMockTransport) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "22222222-2222-4222-8222-222222222222"],
        transportFactory: { _, _, _, _ in mock }
    )
}

@Test func contextWindow_singleModelUsageEntry_populatesContextWindowTokens() async throws {
    let mock = ContextWindowMockTransport()
    let client = makeContextWindowClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-cw1","is_error":false,\
    "total_cost_usd":1.23,"usage":{"input_tokens":10,"output_tokens":20,\
    "cache_read_input_tokens":5,"cache_creation_input_tokens":7},\
    "modelUsage":{"claude-opus-4-8":{"inputTokens":10,"outputTokens":20,\
    "cacheReadInputTokens":5,"cacheCreationInputTokens":7,"costUSD":1.23,\
    "contextWindow":200000,"maxOutputTokens":32000}}}
    """)

    let events = await collectContextWindowEvents(from: client, count: 2)
    #expect(events == [
        .turnUsage(TurnUsage(
            costUSD: 1.23,
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 5,
            cacheCreationTokens: 7,
            contextUsedTokens: nil,
            contextWindowTokens: 200000
        )),
        .turnCompleted(nativeSessionId: "session-cw1"),
    ])
    await client.close()
}

@Test func contextWindow_multipleEntries_picksLargestConsumptionEntry() async throws {
    let mock = ContextWindowMockTransport()
    let client = makeContextWindowClient(mock)
    await client.start()

    // 主モデル（消費 50000 = 1000+45000+4000, window 1000000）とサブモデル（消費 500, window 200000）。
    // 消費合計が最大のエントリの contextWindow（1000000）を採用する。
    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-cw2","is_error":false,\
    "total_cost_usd":0.5,"usage":{"input_tokens":1000,"output_tokens":99,\
    "cache_read_input_tokens":45000,"cache_creation_input_tokens":4000},\
    "modelUsage":{\
    "claude-sonnet-5":{"inputTokens":1000,"outputTokens":99,"cacheReadInputTokens":45000,\
    "cacheCreationInputTokens":4000,"costUSD":0.4,"contextWindow":1000000,"maxOutputTokens":64000},\
    "claude-haiku-4-5-20251001":{"inputTokens":500,"outputTokens":10,"cacheReadInputTokens":0,\
    "cacheCreationInputTokens":0,"costUSD":0.1,"contextWindow":200000,"maxOutputTokens":32000}}}
    """)

    let events = await collectContextWindowEvents(from: client, count: 2)
    try #require(events.count == 2)
    guard case .turnUsage(let usage) = events[0] else {
        Issue.record("expected .turnUsage first, got \(String(describing: events[0]))")
        return
    }
    #expect(usage.contextWindowTokens == 1000000)
    #expect(usage.contextUsedTokens == nil)
    await client.close()
}

@Test func contextWindow_missingModelUsage_leavesContextFieldsNil() async throws {
    let mock = ContextWindowMockTransport()
    let client = makeContextWindowClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-cw3","is_error":false,\
    "total_cost_usd":2.5,"usage":{"input_tokens":10,"output_tokens":20,\
    "cache_read_input_tokens":5,"cache_creation_input_tokens":7}}
    """)

    let events = await collectContextWindowEvents(from: client, count: 2)
    #expect(events == [
        .turnUsage(TurnUsage(
            costUSD: 2.5,
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 5,
            cacheCreationTokens: 7
        )),
        .turnCompleted(nativeSessionId: "session-cw3"),
    ])
    await client.close()
}

@Test func contextWindow_malformedModelUsage_leavesContextFieldsNilWithoutCrash() async throws {
    let mock = ContextWindowMockTransport()
    let client = makeContextWindowClient(mock)
    await client.start()

    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-cw4","is_error":false,\
    "total_cost_usd":0.1,"usage":{"input_tokens":1},"modelUsage":"not-a-dictionary"}
    """)

    let events = await collectContextWindowEvents(from: client, count: 2)
    try #require(events.count == 2)
    guard case .turnUsage(let usage) = events[0] else {
        Issue.record("expected .turnUsage first, got \(String(describing: events[0]))")
        return
    }
    #expect(usage.contextWindowTokens == nil)
    #expect(usage.inputTokens == 1)
    await client.close()
}
