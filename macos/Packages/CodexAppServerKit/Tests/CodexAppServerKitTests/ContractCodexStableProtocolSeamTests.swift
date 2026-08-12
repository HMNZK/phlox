import Foundation
import Testing
@testable import CodexAppServerKit

private let stableFixtureRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CodexSchema/0.147.0", isDirectory: true)

private func stableFixtureJSON(_ relativePath: String) throws -> JSONValue {
    try JSONDecoder.appServer.decode(
        JSONValue.self,
        from: Data(contentsOf: stableFixtureRoot.appendingPathComponent(relativePath))
    )
}

@Test("real CodexAppServerClient seam は native image/skill input を turn/start へ渡す")
func codexClientTurnStartSendsNativeImageAndSkillItems() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    let localImage: JSONValue = .object([
        "type": .string("localImage"),
        "path": .string("/tmp/request-image.png"),
    ])
    let skill: JSONValue = .object([
        "type": .string("skill"),
        "name": .string("swift-ui"),
        "path": .string("/tmp/skills/swift-ui/SKILL.md"),
    ])
    let imageInput = try decodeFromJSONValue(localImage, as: UserInput.self)
    let skillInput = try decodeFromJSONValue(skill, as: UserInput.self)

    async let turn: TurnStartResponse = client.turnStart(TurnStartParams(
        threadId: "thread-1",
        input: [.text("inspect"), imageInput, skillInput]
    ))

    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "turn/start" }
    })
    let request = try #require(await transport.sent.first { $0["method"]?.stringValue == "turn/start" })
    #expect(request["params"]?["input"] == .array([
        .object(["type": .string("text"), "text": .string("inspect")]),
        localImage,
        skill,
    ]))

    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    _ = try await turn
    await client.close()
}

@Test("real client seam は thread/read の選択 ID と source 系 metadata を保持する")
func codexClientThreadReadPreservesSelectedIDAndMetadata() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    async let read: ThreadReadResponse = client.threadRead(
        ThreadReadParams(threadId: "thread-child", includeTurns: true)
    )
    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/read" }
    })
    let request = try #require(await transport.sent.first { $0["method"]?.stringValue == "thread/read" })
    #expect(request["params"] == .object([
        "threadId": .string("thread-child"),
        "includeTurns": .bool(true),
    ]))

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"thread":{
      "id":"thread-child",
      "cliVersion":"0.147.0",
      "createdAt":1700000000,
      "ephemeral":false,
      "modelProvider":"openai",
      "name":"worker",
      "status":{"type":"idle"},
      "turns":[],
      "source":"appServer",
      "parentThreadId":"thread-parent",
      "canAcceptDirectInput":false,
      "cwd":"/tmp/project",
      "sessionId":"session-1",
      "preview":"worker preview",
      "updatedAt":1700000001
    }}}
    """)
    let response = try await read
    #expect(response.thread.id == "thread-child")
    let encoded = try encodeToJSONValue(response)
    #expect(encoded["thread"]?["source"] == .string("appServer"))
    #expect(encoded["thread"]?["parentThreadId"] == .string("thread-parent"))
    #expect(encoded["thread"]?["canAcceptDirectInput"] == .bool(false))
    await client.close()
}

@Test("thread/resume が別 ID を返した場合は成功扱いにしない")
func codexClientRejectsThreadResumeIDMismatch() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    let resumeTask = Task {
        try await client.threadResume(ThreadResumeParams(threadId: "selected-thread"))
    }
    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/resume" }
    })
    let mismatchResult = try stableFixtureJSON("payloads/thread-resume-mismatch-full.json")
    let requiredThreadFields = [
        "id", "cliVersion", "createdAt", "cwd", "ephemeral", "modelProvider",
        "preview", "sessionId", "source", "status", "turns", "updatedAt",
    ]
    for field in requiredThreadFields {
        #expect(mismatchResult["thread"]?[field] != nil)
    }
    let mismatchLine = try jsonLine(.object([
        "jsonrpc": .string("2.0"),
        "id": .number(1),
        "result": mismatchResult,
    ]))
    transport.receive(mismatchLine)

    let outcome = await resumeTask.result
    switch outcome {
    case .success:
        #expect(Bool(false), "thread/resume の ID mismatch が成功扱いになっている")
    case .failure(let error):
        let mismatchErrorDescription = String(describing: error)
        #expect(mismatchErrorDescription.contains("threadIDMismatch"))
        #expect(mismatchErrorDescription.contains("selected-thread"))
        #expect(mismatchErrorDescription.contains("different-thread"))
    }
    await client.close()
}

@Test("skills/list の cwd 配列は session cwd だけを送る")
func skillsListRequestUsesOnlySessionCwd() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "cwds": .array([.string("/tmp/project")]),
        "forceReload": .bool(false),
    ])
    async let response = rpc.requestJSON(method: "skills/list", params: params)

    #expect(await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["method"]?.stringValue == "skills/list" }
    })
    let request = try #require(await transport.sent.first { $0["method"]?.stringValue == "skills/list" })
    #expect(request["params"] == params)
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{"data":[]}}"#)
    #expect(try await response == .object(["data": .array([])]))
    await rpc.close()
}
