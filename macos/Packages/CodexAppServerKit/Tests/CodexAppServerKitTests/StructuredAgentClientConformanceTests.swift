import Foundation
import Testing
import StructuredChatKit
@testable import CodexAppServerKit

@Test func codexClientEventsAPIRemainsThreadEvents() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"warning","params":{"threadId":"thread-1","message":"heads up"}}
    """)

    #expect(await iterator.next() == .warning(threadId: "thread-1", message: "heads up"))
    await client.close()
}

@Test func codexStructuredAdapterExposesNormalizedChatEvents() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    var iterator = adapter.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"hello"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    #expect(await iterator.next() == .agentMessageDelta(itemId: "agent-1", "hello"))
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: "thread-1"))
    await adapter.close()
}

@Test func codexStructuredAdapterSeparatesWarningAndInterruptedCompletionEvents() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    var iterator = adapter.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"warning","params":{"threadId":"thread-1","message":"heads up"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"interrupted"}}}
    """)

    #expect(await iterator.next() == .warning(message: "heads up"))
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: "thread-1"))
    await adapter.close()
}

// interrupted の turn/completed は、thread/start で確定した thread の threadEvents へ取りこぼさず届く。
@Test func interruptedTurnCompletionIsDeliveredAfterThreadStart() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    // thread/start で currentThreadId を "thread-1" に確定させる。
    let startTask = Task { try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work")) }
    let startSent = await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/start" }
    }
    #expect(startSent)
    let startRequest = try #require(await transport.sent.first { $0["method"]?.stringValue == "thread/start" })
    let startId = try #require(startRequest["id"]?.intValue)
    transport.receive("""
    {"jsonrpc":"2.0","id":\(startId),"result":{"thread":{"id":"thread-1","status":{"type":"idle"}}}}
    """)
    _ = try await startTask.value

    // 現行契約では停止完了は turn/completed の interrupted status で通知される。
    let eventBox = ThreadEventBox()
    let consumer = Task {
        var iterator = adapter.threadEvents.makeAsyncIterator()
        if let event = await iterator.next() {
            await eventBox.set(event)
        }
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"interrupted"}}}
    """)

    let received = await waitUntil(events: eventBox.changes) {
        await eventBox.value != nil
    }
    #expect(received)
    if case .turnCompleted(let threadId, let turn)? = await eventBox.value {
        #expect(threadId == "thread-1")
        #expect(turn.id == "turn-1")
        #expect(turn.status == "interrupted")
    } else {
        Issue.record("Expected interrupted turnCompleted event to be delivered, got \(String(describing: await eventBox.value))")
    }

    consumer.cancel()
    await adapter.close()
}

private actor ThreadEventBox {
    private(set) var value: ThreadEvent?
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func set(_ newValue: ThreadEvent) {
        value = newValue
        changeContinuation.yield()
    }
}
