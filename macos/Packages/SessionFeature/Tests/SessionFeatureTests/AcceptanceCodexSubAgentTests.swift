import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex サブエージェント一覧・詳細")
struct AcceptanceCodexSubAgentTests {
    private func childJSON(
        _ id: String,
        parent: String,
        turnID: String? = "turn-1",
        directInput: Bool? = false
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string("/workspace"),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string(id),
            "sessionId": .string("session-\(id)"),
            "source": .object(["subAgent": .object(["parentThreadId": .string(parent)])]),
            "status": .object(["type": .string("active")]),
            "turns": turnID.map { .array([.object(["id": .string($0), "status": .string("inProgress"), "items": .array([])])]) } ?? .array([]),
            "updatedAt": .number(2),
            "parentThreadId": .string(parent),
        ]
        if let directInput { object["canAcceptDirectInput"] = .bool(directInput) }
        return .object(object)
    }

    @Test("現在の親に属する複数 child だけを実DTOから一覧化できる")
    func listsChildrenByParentIdentity() throws {
        let raw = [
            childJSON("child-1", parent: "parent-1"),
            childJSON("child-2", parent: "parent-1", turnID: "turn-2"),
            childJSON("other-parent", parent: "parent-2"),
        ]
        let values = try raw.map { try JSONDecoder().decode(ThreadSummary.self, from: JSONEncoder().encode($0)) }
        let children = values.filter { $0.parentThreadId == "parent-1" }

        #expect(children.map(\.id) == ["child-1", "child-2"])
        #expect(children.allSatisfy { $0.parentThreadId == "parent-1" })
    }

    @Test("childの重複通知はIDで置換でき、配列位置をidentityにしない")
    func duplicateChildIDsRemainDistinctByValue() throws {
        let first = try JSONDecoder().decode(ThreadSummary.self, from: JSONEncoder().encode(childJSON("child-1", parent: "parent-1")))
        let second = try JSONDecoder().decode(ThreadSummary.self, from: JSONEncoder().encode(childJSON("child-1", parent: "parent-1", turnID: "turn-2")))
        #expect(first.id == second.id)
        #expect(first.id == "child-1")
        #expect(second.turns?.first?.id == "turn-2")
    }

    @Test("active turnとcanAcceptDirectInput=falseをlosslessに保持する")
    func childDetailsPreserveActiveTurnAndInputCapability() throws {
        let child = try JSONDecoder().decode(
            ThreadSummary.self,
            from: JSONEncoder().encode(childJSON("child-1", parent: "parent-1", turnID: "turn-1", directInput: false))
        )
        #expect(child.turns?.first?.id == "turn-1")
        #expect(child.turns?.first?.status == "inProgress")
        #expect(child.canAcceptDirectInput == false)
    }

    @Test("child停止のwireはchild threadIdとactive turnIdを同時指定する")
    func childStopUsesExactThreadAndTurnIDs() throws {
        let params = TurnInterruptParams(threadId: "child-1", turnId: "turn-1")
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(params))
        #expect(raw == .object(["threadId": .string("child-1"), "turnId": .string("turn-1")]))
    }

    @Test("実client eventはchildのthread/turn/item identityを保持する")
    func clientEventPreservesChildIdentity() async throws {
        let transport = SubAgentEventTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"child-1","turnId":"turn-1","itemId":"item-1","delta":"child output"}}"#)
        let event = try #require(await iterator.next())
        guard case .agentMessageDelta(let threadId, let turnId, let itemId, let delta) = event else {
            Issue.record("child agent message が実client eventへ届いていない")
            await client.close()
            return
        }
        #expect(threadId == "child-1")
        #expect(turnId == "turn-1")
        #expect(itemId == "item-1")
        #expect(delta == "child output")
        await client.close()
    }

}

private final class SubAgentEventTransport: AppServerTransport, @unchecked Sendable {
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
