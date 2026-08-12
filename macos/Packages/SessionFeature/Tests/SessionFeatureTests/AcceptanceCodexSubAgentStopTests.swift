import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex サブエージェント停止")
struct AcceptanceCodexSubAgentStopTests {
    @Test("停止requestはchild threadIdとactive turnIdを同時指定する")
    func stopTargetsChildAndActiveTurn() throws {
        let request = TurnInterruptParams(threadId: "child-1", turnId: "turn-1")
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(raw["threadId"] == .string("child-1"))
        #expect(raw["turnId"] == .string("turn-1"))
    }

    @Test("interrupt responseだけではcompleted statusを捏造しない")
    func interruptResponseDoesNotRepresentCompletion() throws {
        let response = try JSONDecoder().decode(
            TurnInterruptResponse.self,
            from: Data("{}".utf8)
        )
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        #expect(raw == .object([:]))
        #expect(raw["status"] == nil)
    }

    @Test("停止完了はturn/completedのinterrupted statusで到着する")
    func interruptedCompletionIsTheAuthoritativeStopSignal() throws {
        let raw: JSONValue = .object([
            "threadId": .string("child-1"),
            "turn": .object([
                "id": .string("turn-1"),
                "status": .string("interrupted"),
                "items": .array([]),
            ]),
        ])
        let notification = try JSONDecoder().decode(
            TurnLifecycleNotification.self,
            from: JSONEncoder().encode(raw)
        )
        #expect(notification.threadId == "child-1")
        #expect(notification.turn.id == "turn-1")
        #expect(notification.turn.status == "interrupted")
    }

    @Test("実client eventはinterrupted completionのchild identityを保持する")
    func clientEventPreservesInterruptedChildCompletion() async throws {
        let transport = SubAgentStopEventTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"child-1","turn":{"id":"turn-1","status":"interrupted","items":[]}}}"#)
        let event = try #require(await iterator.next())
        guard case .turnCompleted(let threadId, let turn) = event else {
            Issue.record("interrupted completion が実client eventへ届いていない")
            await client.close()
            return
        }
        #expect(threadId == "child-1")
        #expect(turn.id == "turn-1")
        #expect(turn.status == "interrupted")
        await client.close()
    }

}

private final class SubAgentStopEventTransport: AppServerTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {}

    func close() async {
        continuation.finish()
    }

    func receive(_ line: String) {
        continuation.yield(Data(line.utf8))
    }
}
