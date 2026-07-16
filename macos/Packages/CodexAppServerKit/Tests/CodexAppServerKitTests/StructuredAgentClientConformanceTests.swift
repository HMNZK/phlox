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

@Test func codexStructuredAdapterSeparatesWarningAndInterruptedEvents() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    var iterator = adapter.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"warning","params":{"threadId":"thread-1","message":"heads up"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/interrupted","params":{"threadId":"thread-1","turnId":"turn-1"}}
    """)

    #expect(await iterator.next() == .warning(message: "heads up"))
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: "thread-1"))
    await adapter.close()
}
