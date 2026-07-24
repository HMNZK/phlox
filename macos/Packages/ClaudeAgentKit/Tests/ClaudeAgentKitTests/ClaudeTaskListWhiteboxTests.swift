import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

@Test func todoWriteHandlesEmptyUnknownAndDuplicateTasksSafely() async throws {
    let transport = TaskListWhiteboxTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    await client.start()

    transport.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_empty","name":"TodoWrite","input":{"todos":[]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    transport.receive(#"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"toolu_duplicates","name":"TodoWrite","input":{"todos":[{"content":"同じ項目","status":"unknown"},{"content":"同じ項目","status":"pending"}]}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    var snapshots: [[AgentTaskItem]] = []
    var iterator = client.events.makeAsyncIterator()
    for _ in 0..<10 {
        guard let event = await iterator.next() else { break }
        if case .taskListUpdated(let tasks) = event {
            snapshots.append(tasks)
        }
        if case .turnCompleted = event { break }
    }

    #expect(snapshots.count == 2)
    let emptySnapshot = try #require(snapshots.first)
    let duplicateSnapshot = try #require(snapshots.last)
    #expect(emptySnapshot.isEmpty)
    #expect(duplicateSnapshot.map(\.title) == ["同じ項目", "同じ項目"])
    #expect(duplicateSnapshot.map(\.status) == [.pending, .pending])
    #expect(duplicateSnapshot[0].id != duplicateSnapshot[1].id)
    await client.close()
}

@Test func taskCreateAndUpdateUseTaskIdentifierFromRealToolResultShape() async throws {
    let transport = TaskListWhiteboxTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    await client.start()

    transport.receive(#"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"create-1","name":"TaskCreate","input":{"subject":"実装する"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    transport.receive(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"create-1","content":"Task #42 created successfully: 実装する"}]},"toolUseResult":{"task":{"id":"42","subject":"実装する"}}}"#)
    transport.receive(#"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"update-1","name":"TaskUpdate","input":{"taskId":"42","status":"completed"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    var snapshots: [[AgentTaskItem]] = []
    var iterator = client.events.makeAsyncIterator()
    for _ in 0..<10 {
        guard let event = await iterator.next() else { break }
        if case .taskListUpdated(let tasks) = event {
            snapshots.append(tasks)
        }
        if case .turnCompleted = event { break }
    }

    #expect(snapshots.count == 2)
    let created = try #require(snapshots.first?.first)
    let updated = try #require(snapshots.last?.first)
    #expect(created.id == "42")
    #expect(created.title == "実装する")
    #expect(updated.status == .completed)
    await client.close()
}

private final class TaskListWhiteboxTransport: LineDelimitedTransport, @unchecked Sendable {
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
