import Foundation
import Testing
@testable import CodexAppServerKit

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
    #expect(await waitUntil(events: transport.sent.changes) {
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
