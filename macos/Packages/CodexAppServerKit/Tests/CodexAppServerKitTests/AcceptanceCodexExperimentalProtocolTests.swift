import Foundation
import Testing
@testable import CodexAppServerKit

private let experimentalFixtureRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CodexSchema/0.147.0", isDirectory: true)

private func experimentalFixture(_ relativePath: String) throws -> JSONValue {
    let url = experimentalFixtureRoot.appendingPathComponent(relativePath)
    return try JSONDecoder.appServer.decode(JSONValue.self, from: Data(contentsOf: url))
}

private func experimentalRuntimeRoundTrip<Value: Codable & Sendable>(
    _ type: Value.Type,
    raw: JSONValue
) throws -> JSONValue {
    let data = try JSONEncoder.appServer.encode(raw)
    let decoded = try JSONDecoder.appServer.decode(type, from: data)
    return try encodeToJSONValue(decoded)
}

@Test("experimental schema は turn/interrupt の threadId と turnId を必須にする")
func experimentalSchemasPinInterruptIdentifiers() throws {
    let interrupt = try experimentalFixture("v2/TurnInterruptParams.json")
    #expect(interrupt["required"]?.arrayValue == [
        .string("threadId"),
        .string("turnId"),
    ])
}

@Test("turn/interrupt は threadId と active turnId を必須にする")
func interruptRequestIncludesThreadAndTurnIDs() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "threadId": .string("thread-child"),
        "turnId": .string("turn-9"),
    ])
    async let response = rpc.requestJSON(method: "turn/interrupt", params: params)
    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "turn/interrupt" }
    })
    let request = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "turn/interrupt"
    })
    #expect(request["params"] == params)
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    _ = try await response
    await rpc.close()
}

@Test("obsolete turn/interrupted notification を停止完了の根拠にしない")
func obsoleteTurnInterruptedNotificationIsNotAcceptedAsCompletion() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()
    let notifications = await rpc.notifications
    var iterator = notifications.makeAsyncIterator()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/interrupted","params":{
      "threadId":"thread-child","turnId":"turn-9"
    }}
    """)
    guard let notification = await iterator.next() else {
        #expect(Bool(false), "obsolete notification が nil へ破棄されている")
        await rpc.close()
        return
    }
    guard case .unknown(let method, let params) = notification else {
        #expect(Bool(false), "obsolete notification が専用 typed completion へ変換されている")
        await rpc.close()
        return
    }
    #expect(method == "turn/interrupted")
    #expect(params?["threadId"]?.stringValue == "thread-child")
    #expect(params?["turnId"]?.stringValue == "turn-9")
    await rpc.close()
}

@Test("experimental DTO は turn/interrupt の wire を lossless にする")
func experimentalInterruptDTOsDecodeAndEncodeLosslessly() throws {
    let interruptParams: JSONValue = .object([
        "threadId": .string("thread-child"),
        "turnId": .string("turn-9"),
    ])
    #expect(try experimentalRuntimeRoundTrip(
        TurnInterruptParams.self,
        raw: interruptParams
    ) == interruptParams)
    let interruptResponse: JSONValue = .object([:])
    #expect(try experimentalRuntimeRoundTrip(
        TurnInterruptResponse.self,
        raw: interruptResponse
    ) == interruptResponse)
}

@Test("experimental server error は unsupported を成功へ丸めない")
func unsupportedExperimentalRequestRemainsServerError() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let requestTask = Task {
        try await rpc.requestJSON(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string("thread-child"),
                "turnId": .string("turn-9"),
            ])
        )
    }
    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains {
            $0["method"]?.stringValue == "turn/interrupt"
        }
    })
    transport.receive("""
    {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method unavailable"}}
    """)

    switch await requestTask.result {
    case .success:
        #expect(Bool(false), "unsupported API が fake success へ変換されている")
    case .failure(let error):
        if let error = error as? JSONRPCClientError {
            #expect(error == .serverError(code: -32601, message: "method unavailable"))
        } else {
            #expect(Bool(false), "予期しないエラー: \(error)")
        }
    }
    await rpc.close()
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}
