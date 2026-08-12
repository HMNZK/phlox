import Foundation
import Testing
@testable import CodexAppServerKit

private actor PublicEventDescriptionBox {
    private var stored: String?
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func store(_ value: String) {
        guard stored == nil else { return }
        stored = value
        changeContinuation.yield()
    }

    func value() -> String? {
        stored
    }
}

@Test("turn/plan/updated は unknown notification のまま捨てない")
func planUpdatedNotificationReachesTypedBridge() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()
    let notifications = await rpc.notifications
    var iterator = notifications.makeAsyncIterator()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/plan/updated","params":{
      "threadId":"thread-parent","turnId":"turn-1","explanation":null,
      "plan":[
        {"step":"inspect","status":"pending"},
        {"step":"implement","status":"inProgress"},
        {"step":"verify","status":"completed"}
      ]
    }}
    """)
    guard let notification = await iterator.next() else {
        #expect(Bool(false), "plan notification が届いていない")
        await rpc.close()
        return
    }
    let description = String(describing: notification)
    let isDedicatedNotification = !description.contains("unknown")
    #expect(isDedicatedNotification, "plan notification が unknown のまま公開されている")
    guard isDedicatedNotification else {
        await rpc.close()
        return
    }
    #expect(description.contains("thread-parent"))
    #expect(description.contains("turn-1"))
    #expect(description.contains("pending"))
    #expect(description.contains("inProgress"))
    #expect(description.contains("completed"))
    await rpc.close()
}

@Test("public structured client は plan notification を taskListUpdated まで橋渡しする")
func publicStructuredClientBridgesPlanNotification() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let structured = CodexStructuredAgentClient(client: client)
    await structured.start()
    let box = PublicEventDescriptionBox()
    let consumer = Task {
        for await event in structured.events {
            await box.store(String(describing: event))
            break
        }
    }

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/plan/updated","params":{
      "threadId":"thread-parent","turnId":"turn-1","explanation":null,
      "plan":[
        {"step":"inspect","status":"pending"},
        {"step":"implement","status":"inProgress"},
        {"step":"verify","status":"completed"}
      ]
    }}
    """)
    let received = await waitUntil(
        timeoutNanoseconds: 500_000_000,
        events: box.changes
    ) {
        await box.value() != nil
    }
    #expect(received, "public structured client eventへplanが届いていない")
    await structured.close()
    consumer.cancel()

    guard let description = await box.value() else { return }
    #expect(description.contains("taskListUpdated"))
    #expect(description.contains("inspect"))
    #expect(description.contains("implement"))
    #expect(description.contains("verify"))
    #expect(description.contains("pending"))
    #expect(description.contains("inProgress"))
    #expect(description.contains("completed"))
}

@Test("skills/changed は stale 再取得用の typed bridge へ到達する")
func skillsChangedNotificationReachesTypedBridge() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()
    let notifications = await rpc.notifications
    var iterator = notifications.makeAsyncIterator()

    transport.receive(#"{"jsonrpc":"2.0","method":"skills/changed","params":{}}"#)
    guard let notification = await iterator.next() else {
        #expect(Bool(false), "skills/changed notification が届いていない")
        await rpc.close()
        return
    }
    let description = String(describing: notification)
    #expect(!description.contains("unknown"), "skills/changed が unknown のまま公開されている")
    await rpc.close()
}

@Test("親・子 thread と別 turn の通知 identity を混線させない")
func codexClientPreservesParentChildAndTurnIdentity() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    transport.receive(#"{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-parent","turnId":"turn-parent","itemId":"item-parent","delta":"parent"}}"#)
    transport.receive(#"{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-child","turnId":"turn-child","itemId":"item-child","delta":"child"}}"#)
    transport.receive(#"{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-parent","turnId":"turn-second","itemId":"item-second","delta":"second"}}"#)

    var observed: [(String, String, String, String)] = []
    for _ in 0..<3 {
        guard let event = await iterator.next() else {
            #expect(Bool(false), "通知が3件届いていない")
            break
        }
        if case .agentMessageDelta(let threadId, let turnId, let itemId, let delta) = event {
            observed.append((threadId, turnId, itemId, delta))
        } else {
            #expect(Bool(false), "agent message delta 以外の event が混入した")
        }
    }
    #expect(observed.map { $0.0 } == ["thread-parent", "thread-child", "thread-parent"])
    #expect(observed.map { $0.1 } == ["turn-parent", "turn-child", "turn-second"])
    #expect(observed.map { $0.2 } == ["item-parent", "item-child", "item-second"])
    #expect(observed.map { $0.3 } == ["parent", "child", "second"])
    await client.close()
}

@Test("public client events は active/inProgress turn の identity を保持する")
func publicClientEventsPreserveActiveInProgressTurn() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{
      "threadId":"thread-child",
      "turn":{"id":"turn-active","status":"inProgress","items":[]}
    }}
    """)
    guard let event = await iterator.next() else {
        #expect(Bool(false), "active turn/started がpublic client eventへ届いていない")
        await client.close()
        return
    }
    guard case .turnStarted(let threadId, let turn) = event else {
        #expect(Bool(false), "active turn/started がtyped eventへ変換されていない")
        await client.close()
        return
    }
    #expect(threadId == "thread-child")
    #expect(turn.id == "turn-active")
    #expect(turn.status == "inProgress")
    await client.close()
}

@Test("public client の experimental interrupt bridge はJSON-RPC methodを送る")
func publicClientExperimentalInterruptBridgeUsesTransport() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    let interruptTask = Task {
        try await client.turnInterrupt(
            TurnInterruptParams(threadId: "thread-child", turnId: "turn-9")
        )
    }
    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "turn/interrupt" }
    })
    let request = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "turn/interrupt"
    })
    #expect(request["params"]?["threadId"] == .string("thread-child"))
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    _ = try await interruptTask.value
    await client.close()
}

@Test("停止完了は turn/completed の interrupted status を保持する")
func interruptedTurnCompletionPreservesTurnStatus() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{
      "threadId":"thread-child",
      "turn":{"id":"turn-9","status":"interrupted","items":[]}
    }}
    """)
    guard let event = await iterator.next() else {
        #expect(Bool(false), "turn/completed が届いていない")
        await client.close()
        return
    }
    guard case .turnCompleted(let threadId, let turn) = event else {
        #expect(Bool(false), "停止完了を turn/completed として扱っていない")
        await client.close()
        return
    }
    #expect(threadId == "thread-child")
    #expect(turn.id == "turn-9")
    #expect(turn.status == "interrupted")
    await client.close()
}
