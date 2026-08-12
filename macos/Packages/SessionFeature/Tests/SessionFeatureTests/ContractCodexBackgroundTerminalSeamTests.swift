import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Contract: Codex background terminal seam")
struct ContractCodexBackgroundTerminalSeamTests {
    @Test("list requestはthreadId/cursor/limitをlosslessに送る")
    func listRequestIsLossless() throws {
        let expected: JSONValue = .object([
            "threadId": .string("thread-1"),
            "cursor": .null,
            "limit": .number(20),
        ])
        let params = try JSONDecoder().decode(
            ThreadBackgroundTerminalsListParams.self,
            from: JSONEncoder().encode(expected)
        )
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(params))
        #expect(raw == expected)
    }

    @Test("list responseはoptional statsのnull/欠落を区別する")
    func responsePreservesOptionalStats() throws {
        let raw: JSONValue = .object([
            "data": .array([.object([
                "itemId": .string("item-1"),
                "processId": .string("process-1"),
                "command": .string("echo contract"),
                "cwd": .string("/contract"),
                "osPid": .null,
            ])]),
            "nextCursor": .null,
        ])
        let response = try JSONDecoder().decode(
            ThreadBackgroundTerminalsListResponse.self,
            from: JSONEncoder().encode(raw)
        )
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        #expect(encoded == raw)
        #expect(response.data.first?.itemId == "item-1")
        #expect(response.data.first?.processId == "process-1")
        #expect(response.data.first?.osPid == nil)
    }

    @Test("terminate responseのfalseを成功扱いしない")
    func terminateFalseRemainsFalse() throws {
        let response = ThreadBackgroundTerminalsTerminateResponse(terminated: false)
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        #expect(raw["terminated"] == .bool(false))
    }

    @Test("実CodexAppServerClientはbackground terminalのlist/terminateを実DTOへ橋渡しする")
    func clientBridgesBackgroundTerminalMethods() async throws {
        let transport = ContractBackgroundTerminalTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()

        let response = try await client.threadBackgroundTerminalsList(
            ThreadBackgroundTerminalsListParams(threadId: "thread-parent", cursor: nil, limit: 20)
        )
        #expect(response.data.map(\.itemId) == ["item-1"])
        #expect(response.data.first?.processId == "process-1")

        let terminated = try await client.threadBackgroundTerminalsTerminate(
            ThreadBackgroundTerminalsTerminateParams(threadId: "thread-parent", processId: "process-1")
        )
        #expect(terminated.terminated == false)

        let requests = await transport.requests.all()
        #expect(requests.map { $0["method"]?.stringValue } == [
            "thread/backgroundTerminals/list",
            "thread/backgroundTerminals/terminate",
        ])
        #expect(requests[0]["params"]?["threadId"] == .string("thread-parent"))
        #expect(requests[1]["params"]?["processId"] == .string("process-1"))
        await client.close()
    }

    @Test("実CodexAppServerClientのitem/startedはtyped ThreadEventでidentityを保持する")
    func clientEventsPreserveBackgroundTerminalIdentity() async throws {
        let transport = ContractBackgroundTerminalTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        var events = client.events.makeAsyncIterator()

        transport.receive(#"{"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-parent","turnId":"turn-1","item":{"type":"backgroundTerminal","id":"item-1","itemId":"item-1","processId":"process-1","command":"echo contract","cwd":"/contract"}}}"#)

        guard case .itemStarted(let threadId, let turnId, let item) = await events.next() else {
            Issue.record("item/started が typed ThreadEvent へ到達していない")
            await client.close()
            return
        }
        #expect(threadId == "thread-parent")
        #expect(turnId == "turn-1")
        #expect(item.itemId == "item-1")
        #expect(item.raw?["processId"] == .string("process-1"))
        await client.close()
    }

}

private final class ContractBackgroundTerminalTransport: AppServerTransport, @unchecked Sendable {
    let requests = ContractBackgroundTerminalRequests()
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await requests.append(request)
        guard let id = request["id"] else { return }

        let result: JSONValue
        switch request["method"]?.stringValue {
        case "thread/backgroundTerminals/list":
            result = .object([
                "data": .array([.object([
                    "itemId": .string("item-1"),
                    "processId": .string("process-1"),
                    "command": .string("echo contract"),
                    "cwd": .string("/contract"),
                ])]),
                "nextCursor": .null,
            ])
        case "thread/backgroundTerminals/terminate":
            result = .object(["terminated": .bool(false)])
        default:
            result = .object([:])
        }

        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }

    func close() async {
        continuation.finish()
    }
}

private actor ContractBackgroundTerminalRequests {
    private var values: [JSONValue] = []

    func append(_ value: JSONValue) {
        values.append(value)
    }

    func all() -> [JSONValue] {
        values
    }
}
