import Foundation
import Testing
@testable import CodexAppServerKit

@Test("実 client bridge は interrupted turn の completed payload を保持する")
func clientBridgePreservesInterruptedCompletedPayload() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{
      "threadId":"thread-1",
      "turn":{"id":"turn-1","status":"interrupted","items":[]}
    }}
    """)
    let event = try #require(await iterator.next())
    guard case .turnCompleted(let threadId, let turn) = event else {
        #expect(Bool(false), "completed payload が typed bridge に届いていない")
        await client.close()
        return
    }
    #expect(threadId == "thread-1")
    #expect(turn.id == "turn-1")
    #expect(turn.status == "interrupted")
    await client.close()
}

@Test("実 client bridge は親子通知の thread/turn/item identity を保持する")
func clientBridgePreservesThreadTurnAndItemIdentity() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    transport.receive(#"{"jsonrpc":"2.0","method":"item/commandExecution/outputDelta","params":{"threadId":"thread-child","turnId":"turn-child","itemId":"item-terminal","delta":"output"}}"#)
    let event = try #require(await iterator.next())
    guard case .commandOutputDelta(let threadId, let turnId, let itemId, let delta) = event else {
        #expect(Bool(false), "command output event が typed bridge に届いていない")
        await client.close()
        return
    }
    #expect(threadId == "thread-child")
    #expect(turnId == "turn-child")
    #expect(itemId == "item-terminal")
    #expect(delta == "output")
    await client.close()
}
