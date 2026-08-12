import Foundation
import Testing
@testable import CodexAppServerKit

@Test("experimental background terminal request は実 JSON-RPC transport seam を通る")
func backgroundTerminalListRequestUsesExperimentalMethodAndIDs() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "threadId": .string("thread-1"),
        "cursor": .null,
        "limit": .number(50),
    ])
    async let response = rpc.requestJSON(
        method: "thread/backgroundTerminals/list",
        params: params
    )
    #expect(await waitUntil {
        await transport.sent.all().contains {
            $0["method"]?.stringValue == "thread/backgroundTerminals/list"
        }
    })
    let sent = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "thread/backgroundTerminals/list"
    })
    #expect(sent["params"] == params)

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"data":[
      {"itemId":"item-1","processId":"process-1","command":"sleep 10","cwd":"/tmp"}
    ],"nextCursor":null}}
    """)
    let result = try await response
    let item = try #require(result["data"]?.arrayValue?.first)
    #expect(item["itemId"]?.stringValue == "item-1")
    #expect(item["processId"]?.stringValue == "process-1")
    await rpc.close()
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

@Test("experimental terminate seam は terminated=false を成功へ丸めない")
func backgroundTerminalTerminatePreservesFalseResult() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    async let response = rpc.requestJSON(
        method: "thread/backgroundTerminals/terminate",
        params: .object([
            "threadId": .string("thread-1"),
            "processId": .string("stale-process"),
        ])
    )
    #expect(await waitUntil {
        await transport.sent.all().contains {
            $0["method"]?.stringValue == "thread/backgroundTerminals/terminate"
        }
    })
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{"terminated":false}}"#)
    let result = try await response
    #expect(result["terminated"] == .bool(false))
    await rpc.close()
}

@Test("interrupt seam は process/item ID ではなく thread/turn ID を送る")
func interruptSeamUsesThreadAndTurnIdentifiers() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "threadId": .string("thread-1"),
        "turnId": .string("turn-1"),
    ])
    async let response = rpc.requestJSON(method: "turn/interrupt", params: params)
    #expect(await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "turn/interrupt" }
    })
    let sent = try #require(await transport.sent.first { $0["method"]?.stringValue == "turn/interrupt" })
    #expect(sent["params"] == params)
    #expect(sent["params"]?["processId"] == nil)
    #expect(sent["params"]?["itemId"] == nil)
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    _ = try await response
    await rpc.close()
}
