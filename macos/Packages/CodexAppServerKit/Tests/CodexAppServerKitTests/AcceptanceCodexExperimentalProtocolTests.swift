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

private protocol ExperimentalRuntimeEncodableBox {
    func encodedJSON() throws -> JSONValue
}

private struct ConcreteExperimentalRuntimeEncodableBox<Value: Encodable>:
    ExperimentalRuntimeEncodableBox
{
    let value: Value

    func encodedJSON() throws -> JSONValue {
        let data = try JSONEncoder.appServer.encode(value)
        return try JSONDecoder.appServer.decode(JSONValue.self, from: data)
    }
}

private func eraseExperimentalRuntimeEncodable<Value: Encodable>(
    _ value: Value
) -> any ExperimentalRuntimeEncodableBox {
    ConcreteExperimentalRuntimeEncodableBox(value: value)
}

private func experimentalRuntimeRoundTrip(
    typeNames: [String],
    raw: JSONValue
) throws -> JSONValue? {
    guard let type = typeNames.lazy.compactMap({ name in
        _typeByName(name).flatMap { $0 as? any Decodable.Type }
    }).first else {
        return nil
    }
    let data = try JSONEncoder.appServer.encode(raw)
    let decoded = try JSONDecoder.appServer.decode(type, from: data)
    guard let encodable = decoded as? any Encodable else { return nil }
    return try eraseExperimentalRuntimeEncodable(encodable).encodedJSON()
}

@Test("experimental schema は process/item/thread/turn の ID を別フィールドで固定する")
func experimentalSchemasPinDistinctIdentifiers() throws {
    let background = try experimentalFixture("v2/ThreadBackgroundTerminalsListResponse.json")
    let backgroundDefinition = background["definitions"]?["ThreadBackgroundTerminal"]
    #expect(backgroundDefinition?["properties"]?["itemId"]?["type"] == .string("string"))
    #expect(backgroundDefinition?["properties"]?["processId"]?["type"] == .string("string"))
    #expect(backgroundDefinition?["required"]?.arrayValue?.contains(.string("itemId")) == true)
    #expect(backgroundDefinition?["required"]?.arrayValue?.contains(.string("processId")) == true)

    let terminate = try experimentalFixture("v2/ThreadBackgroundTerminalsTerminateParams.json")
    #expect(terminate["required"]?.arrayValue == [
        .string("processId"),
        .string("threadId"),
    ])

    let interrupt = try experimentalFixture("v2/TurnInterruptParams.json")
    #expect(interrupt["required"]?.arrayValue == [
        .string("threadId"),
        .string("turnId"),
    ])
}

@Test("background terminal list は processId と itemId を取り違えずに返す")
func backgroundTerminalListResponsePreservesProcessAndItemIDs() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "threadId": .string("thread-parent"),
        "cursor": .null,
        "limit": .number(20),
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
    let request = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "thread/backgroundTerminals/list"
    })
    #expect(request["params"] == params)

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"data":[{
      "itemId":"item-terminal-1",
      "processId":"process-42",
      "command":"swift test",
      "cwd":"/tmp/project",
      "osPid":4242,
      "cpuPercent":1.25,
      "rssKb":2048
    }],"nextCursor":null}}
    """)
    let result = try await response
    let item = try #require(result["data"]?.arrayValue?.first)
    #expect(item["itemId"]?.stringValue == "item-terminal-1")
    #expect(item["processId"]?.stringValue == "process-42")
    #expect(item["itemId"]?.stringValue != item["processId"]?.stringValue)
    await rpc.close()
}

@Test("background terminal terminate は threadId と processId を両方送る")
func backgroundTerminalTerminateUsesTargetThreadAndProcess() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "threadId": .string("thread-child"),
        "processId": .string("process-42"),
    ])
    async let response = rpc.requestJSON(
        method: "thread/backgroundTerminals/terminate",
        params: params
    )
    #expect(await waitUntil {
        await transport.sent.all().contains {
            $0["method"]?.stringValue == "thread/backgroundTerminals/terminate"
        }
    })
    let request = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "thread/backgroundTerminals/terminate"
    })
    #expect(request["params"] == params)

    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{"terminated":false}}"#)
    let result = try await response
    #expect(result["terminated"] == .bool(false))
    await rpc.close()
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
    #expect(await waitUntil {
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

@Test("task-8 experimental DTO は background/terminate/interrupt の wire を lossless にする")
func experimentalDTOsDecodeAndEncodeLosslessly() throws {
    let requiredOnlyBackgroundList = try experimentalFixture(
        "payloads/background-terminals-list-required-only.json"
    )
    let cases: [([String], JSONValue, String)] = [
        (
            ["CodexAppServerKit.ThreadBackgroundTerminalsListParams"],
            .object([
                "threadId": .string("thread-parent"),
                "cursor": .null,
                "limit": .number(20),
            ]),
            "ThreadBackgroundTerminalsListParams"
        ),
        (
            ["CodexAppServerKit.ThreadBackgroundTerminalsListResponse"],
            .object([
                "data": .array([
                    .object([
                        "itemId": .string("item-terminal-1"),
                        "processId": .string("process-42"),
                        "command": .string("swift test"),
                        "cwd": .string("/tmp/project"),
                        "osPid": .number(4242),
                        "cpuPercent": .number(1.25),
                        "rssKb": .number(2048),
                    ]),
                ]),
                "nextCursor": .null,
            ]),
            "ThreadBackgroundTerminalsListResponse"
        ),
        (
            ["CodexAppServerKit.ThreadBackgroundTerminalsListResponse"],
            requiredOnlyBackgroundList,
            "ThreadBackgroundTerminalsListResponse (required fields; optional fields omitted)"
        ),
        (
            ["CodexAppServerKit.ThreadBackgroundTerminalsTerminateParams"],
            .object([
                "threadId": .string("thread-child"),
                "processId": .string("process-42"),
            ]),
            "ThreadBackgroundTerminalsTerminateParams"
        ),
        (
            ["CodexAppServerKit.ThreadBackgroundTerminalsTerminateResponse"],
            .object(["terminated": .bool(false)]),
            "ThreadBackgroundTerminalsTerminateResponse"
        ),
        (
            ["CodexAppServerKit.TurnInterruptParams"],
            .object([
                "threadId": .string("thread-child"),
                "turnId": .string("turn-9"),
            ]),
            "TurnInterruptParams"
        ),
        (
            ["CodexAppServerKit.TurnInterruptResponse"],
            .object([:]),
            "TurnInterruptResponse"
        ),
    ]

    for (typeNames, raw, label) in cases {
        guard let encoded = try experimentalRuntimeRoundTrip(
            typeNames: typeNames,
            raw: raw
        ) else {
            #expect(Bool(false), "DTO が未実装: \(label)")
            continue
        }
        #expect(encoded == raw)
    }
}

@Test("experimental server error は unsupported を成功へ丸めない")
func unsupportedExperimentalRequestRemainsServerError() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let requestTask = Task {
        try await rpc.requestJSON(
            method: "thread/backgroundTerminals/terminate",
            params: .object([
                "threadId": .string("thread-child"),
                "processId": .string("stale-process"),
            ])
        )
    }
    #expect(await waitUntil {
        await transport.sent.all().contains {
            $0["method"]?.stringValue == "thread/backgroundTerminals/terminate"
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
