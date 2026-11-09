import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// エージェント状態カードが読むイベント（agent-status-card-design.md §3.1・§3.2・§3.5）。
// Bash の説明（intent）、作業の終了（itemCompleted）、巻き戻し後にタスクの記憶が残らないこと。

private final class StatusMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

/// spawn のたびに新しい transport を返し、作った順に覚える。
private final class StatusTransportList: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [StatusMockTransport] = []

    var transports: [StatusMockTransport] {
        lock.lock(); defer { lock.unlock() }
        return made
    }

    func make(_: String, _: [String], _: [String: String], _: URL?) -> any LineDelimitedTransport {
        let transport = StatusMockTransport()
        lock.lock(); made.append(transport); lock.unlock()
        return transport
    }
}

private func events(upTo isLast: (NormalizedChatEvent) -> Bool, from client: ClaudeChatClient) async -> [NormalizedChatEvent] {
    var collected: [NormalizedChatEvent] = []
    var iterator = client.events.makeAsyncIterator()
    while let event = await iterator.next() {
        collected.append(event)
        if isLast(event) { break }
    }
    return collected
}

private let bashToolUse = #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_B1","name":"Bash","input":{"command":"swift test","description":"テストを実行する"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
private let bashResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B1","content":"all passed"}]},"parent_tool_use_id":null}"#

@Test func bashDescriptionIsCarriedAsIntent() async throws {
    let transport = StatusMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()

    transport.receive(bashToolUse)
    let collected = await events(upTo: { if case .commandExecution = $0 { true } else { false } }, from: client)

    guard case .commandExecution(_, let command, _, let intent)? = collected.last else {
        Issue.record("commandExecution が届かない: \(collected)")
        return
    }
    #expect(command == "swift test")
    #expect(intent == "テストを実行する")
    await client.close()
}

@Test func bashWithoutDescriptionHasNoIntent() async throws {
    let transport = StatusMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()

    transport.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_B2","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    let collected = await events(upTo: { if case .commandExecution = $0 { true } else { false } }, from: client)

    guard case .commandExecution(_, _, _, let intent)? = collected.last else {
        Issue.record("commandExecution が届かない: \(collected)")
        return
    }
    #expect(intent == nil)
    await client.close()
}

@Test func toolResultYieldsItemCompletedForTheSameItem() async throws {
    let transport = StatusMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()

    transport.receive(bashToolUse)
    transport.receive(bashResult)
    let collected = await events(upTo: { if case .itemCompleted = $0 { true } else { false } }, from: client)

    let startedItemIDs = collected.compactMap { event -> String? in
        if case .commandExecution(let itemId, let command, _, _) = event, command != nil { return itemId }
        return nil
    }
    guard case .itemCompleted(let completedItemID)? = collected.last else {
        Issue.record("itemCompleted が届かない: \(collected)")
        return
    }
    #expect(startedItemIDs.count == 1)
    #expect(completedItemID == startedItemIDs.first)
    await client.close()
}

@Test func taskToolResultDoesNotYieldItemCompleted() async throws {
    let transport = StatusMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()

    transport.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_T1","name":"TodoWrite","input":{"todos":[{"content":"調査する","status":"in_progress"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    transport.receive(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_T1","content":"ok"}]},"parent_tool_use_id":null}"#)
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)
    let collected = await events(upTo: { if case .turnCompleted = $0 { true } else { false } }, from: client)

    #expect(!collected.contains { if case .itemCompleted = $0 { true } else { false } })
    await client.close()
}

@Test func updateForTaskFromBeforeResetDoesNotBringTheTaskBack() async throws {
    let list = StatusTransportList()
    let client = ClaudeChatClient(environment: [:], transportFactory: list.make)
    try await client.start()
    let first = try #require(list.transports.first)
    first.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"create-1","name":"TaskCreate","input":{"subject":"実装する"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    first.receive(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"create-1","content":"Task #42 created"}]},"parent_tool_use_id":null,"session_id":"S1","tool_use_result":{"task":{"id":"42","subject":"実装する"}}}"#)
    let beforeReset = await events(upTo: { if case .taskListUpdated = $0 { true } else { false } }, from: client)
    #expect(beforeReset.count == 1, "巻き戻し前に 1 件のタスクが作られる")

    await client.resetConversation()
    let second = try #require(list.transports.last)
    second.receive(#"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"update-1","name":"TaskUpdate","input":{"taskId":"42","status":"completed"}}]},"parent_tool_use_id":null,"session_id":"S2"}"#)
    second.receive(#"{"type":"result","subtype":"success","is_error":false}"#)
    let afterReset = await events(upTo: { if case .turnCompleted = $0 { true } else { false } }, from: client)

    let resurrected = afterReset.filter { if case .taskListUpdated = $0 { true } else { false } }
    #expect(resurrected.isEmpty, "古い会話の id 宛ての TaskUpdate でタスクが戻らない。events=\(afterReset)")
    await client.close()
}
