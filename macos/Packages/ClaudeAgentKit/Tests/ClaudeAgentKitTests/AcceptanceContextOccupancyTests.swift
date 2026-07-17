// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — Claude セッションの「現在のコンテキスト占有量」は、
// ターン内 API ラウンドトリップ横断の累積（result.usage の合算）ではなく、
// 直近の「メインターン」assistant メッセージの usage
// (input_tokens + cache_read_input_tokens + cache_creation_input_tokens) で近似し、
// `TurnUsage.contextUsedTokens` として明示設定する（Codex 経路と同じ last 主義）。
// サブエージェント（parent_tool_use_id 付き）の assistant メッセージは親の占有量に数えない。
//
// 注: 期待イベントが来ない実装でもハングしないよう、タイムアウト付きで収集する。

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class ContextOccupancyMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

private final class ContextOccupancyEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { events.append(event) } }
    func snapshot() -> [NormalizedChatEvent] { lock.withLock { events } }
}

/// `.turnUsage` を観測するか timeout までに収集したイベントを返す。
private func collectUntilTurnUsage(
    from client: ClaudeChatClient,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async -> [NormalizedChatEvent] {
    let box = ContextOccupancyEventBox()
    func sawTurnUsage() -> Bool {
        box.snapshot().contains { if case .turnUsage = $0 { true } else { false } }
    }
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for await event in client.events {
                box.append(event)
                if case .turnUsage = event { break }
            }
        }
        group.addTask {
            var waited: UInt64 = 0
            let step: UInt64 = 50_000_000
            while waited < timeoutNanoseconds, !sawTurnUsage() {
                try? await Task.sleep(nanoseconds: step)
                waited += step
            }
        }
        _ = await group.next()
        group.cancelAll()
    }
    return box.snapshot()
}

private func turnUsage(in events: [NormalizedChatEvent]) -> TurnUsage? {
    for event in events {
        if case .turnUsage(let usage) = event { return usage }
    }
    return nil
}

private func makeContextOccupancyClient(_ mock: ContextOccupancyMockTransport) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "22222222-2222-4222-8222-222222222222"],
        transportFactory: { _, _, _, _ in mock }
    )
}

// AT1: 現在占有量は「直近メインターン assistant の usage」で近似し、
//      result.usage の累積合算にはしない。
@Test func contextOccupancy_usesLatestAssistantUsage_notCumulativeResultUsage() async throws {
    let mock = ContextOccupancyMockTransport()
    let client = makeContextOccupancyClient(mock)
    await client.start()

    // メインターンの assistant は実 stream-json では parent_tool_use_id:null を持つ
    // （JSONSerialization は JSON null を NSNull にするため、判定は「文字列の親IDが無い」で行う必要がある）。
    // 1回目の API コール（占有 5 + 40000 + 1000 = 41005）
    mock.receive("""
    {"type":"assistant","parent_tool_use_id":null,"message":{"id":"m1","content":[{"type":"text","text":"a"}],\
    "usage":{"input_tokens":5,"output_tokens":10,"cache_read_input_tokens":40000,"cache_creation_input_tokens":1000}}}
    """)
    // 2回目＝最終 API コール（占有 8 + 52000 + 100 = 52108）
    mock.receive("""
    {"type":"assistant","parent_tool_use_id":null,"message":{"id":"m2","content":[{"type":"text","text":"b"}],\
    "usage":{"input_tokens":8,"output_tokens":12,"cache_read_input_tokens":52000,"cache_creation_input_tokens":100}}}
    """)
    // result の usage は累積（cache_read=92000 は往復横断の累積）。占有量に使ってはならない。
    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-occ","is_error":false,\
    "total_cost_usd":1.0,\
    "usage":{"input_tokens":13,"output_tokens":22,"cache_read_input_tokens":92000,"cache_creation_input_tokens":1100},\
    "modelUsage":{"claude-opus-4-8[1m]":{"contextWindow":1000000,"inputTokens":13,\
    "cacheReadInputTokens":92000,"cacheCreationInputTokens":1100,"costUSD":1.0,"maxOutputTokens":64000}}}
    """)

    let events = await collectUntilTurnUsage(from: client)
    let usage = try #require(turnUsage(in: events))
    // 直近 API コールの占有量（累積 93113 でも 640k 相当でもない）
    #expect(usage.contextUsedTokens == 52108)
    // 分母は従来どおり正しく取れる（回帰なし）
    #expect(usage.contextWindowTokens == 1000000)
    await client.close()
}

// AT2: サブエージェント（parent_tool_use_id 付き）assistant の usage は親の占有量に数えない。
@Test func contextOccupancy_excludesSubAgentAssistantUsage() async throws {
    let mock = ContextOccupancyMockTransport()
    let client = makeContextOccupancyClient(mock)
    await client.start()

    // サブエージェント tool_use_id "sub1" を登録する。
    mock.receive("""
    {"type":"system","subtype":"task_started","task_id":"t1","task_type":"local_agent",\
    "tool_use_id":"sub1","subagent_type":"explore","description":"child work"}
    """)
    // サブエージェントの assistant（巨大占有 800001）。親に数えてはならない。
    mock.receive("""
    {"type":"assistant","parent_tool_use_id":"sub1","message":{"id":"c1",\
    "content":[{"type":"text","text":"child"}],\
    "usage":{"input_tokens":1,"output_tokens":3,"cache_read_input_tokens":800000,"cache_creation_input_tokens":0}}}
    """)
    // メインターンの assistant（実 stream-json どおり parent_tool_use_id:null。占有 3 + 30000 + 0 = 30003）。
    mock.receive("""
    {"type":"assistant","parent_tool_use_id":null,"message":{"id":"m1","content":[{"type":"text","text":"main"}],\
    "usage":{"input_tokens":3,"output_tokens":9,"cache_read_input_tokens":30000,"cache_creation_input_tokens":0}}}
    """)
    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-sub","is_error":false,\
    "total_cost_usd":0.5,\
    "usage":{"input_tokens":4,"output_tokens":12,"cache_read_input_tokens":830000,"cache_creation_input_tokens":0},\
    "modelUsage":{"claude-opus-4-8[1m]":{"contextWindow":1000000,"inputTokens":4,\
    "cacheReadInputTokens":830000,"cacheCreationInputTokens":0,"costUSD":0.5,"maxOutputTokens":64000}}}
    """)

    let events = await collectUntilTurnUsage(from: client)
    let usage = try #require(turnUsage(in: events))
    // メインの占有（30003）であって、サブエージェントの 800001 ではない。
    #expect(usage.contextUsedTokens == 30003)
    #expect(usage.contextWindowTokens == 1000000)
    await client.close()
}
