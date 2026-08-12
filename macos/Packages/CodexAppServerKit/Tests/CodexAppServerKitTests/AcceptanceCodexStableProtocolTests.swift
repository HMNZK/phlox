import Foundation
import Testing
@testable import CodexAppServerKit

private let codexSchemaFixtureRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CodexSchema/0.147.0", isDirectory: true)

private func fixtureJSON(_ relativePath: String) throws -> JSONValue {
    let url = codexSchemaFixtureRoot.appendingPathComponent(relativePath)
    return try JSONDecoder.appServer.decode(JSONValue.self, from: Data(contentsOf: url))
}

private func runtimeRoundTrip<Value: Codable & Sendable>(
    _ type: Value.Type,
    raw: JSONValue
) throws -> JSONValue {
    let data = try JSONEncoder.appServer.encode(raw)
    let decoded = try JSONDecoder.appServer.decode(type, from: data)
    return try encodeToJSONValue(decoded)
}

@Test("生成 schema の実ファイルと JSON path が固定されている")
func codexSchemaFixturePinsGeneratedFilesAndNativePaths() throws {
    let manifest = try fixtureJSON("manifest.json")
    #expect(manifest["codexVersion"]?.stringValue == "0.147.0")
    #expect(manifest["generatedWith"]?.stringValue?.contains("generate-json-schema") == true)
    #expect(manifest["schemaVersion"]?.stringValue == "v2")

    let files = manifest["files"]
    #expect(files?.arrayValue?.contains(.string("v2/TurnStartParams.json")) == true)
    #expect(files?.arrayValue?.contains(.string("v2/SkillsListResponse.json")) == true)
    #expect(files?.arrayValue?.contains(.string("v2/ThreadBackgroundTerminalsListResponse.json")) == true)

    let turnStartSchema = try fixtureJSON("v2/TurnStartParams.json")
    #expect(turnStartSchema["title"]?.stringValue == "TurnStartParams")
    let skillsSchema = try fixtureJSON("v2/SkillsListParams.json")
    #expect(skillsSchema["properties"]?["cwds"]?["type"] == .string("array"))
    #expect(skillsSchema["properties"]?["cwds"]?["items"]?["type"] == .string("string"))
    let interruptSchema = try fixtureJSON("v2/TurnInterruptParams.json")
    #expect(interruptSchema["required"]?.arrayValue == [.string("threadId"), .string("turnId")])

    let requiredThreadFields = [
        "id", "cliVersion", "createdAt", "cwd", "ephemeral", "modelProvider",
        "preview", "sessionId", "source", "status", "turns", "updatedAt",
    ]
    for relativePath in [
        "payloads/thread-read-full.json",
        "payloads/thread-read-active-in-progress.json",
        "payloads/thread-list-full.json",
        "payloads/thread-resume-mismatch-full.json",
    ] {
        let payload = try fixtureJSON(relativePath)
        let thread = relativePath.hasSuffix("thread-list-full.json")
            ? try #require(payload["data"]?.arrayValue?.first)
            : try #require(payload["thread"])
        for field in requiredThreadFields {
            #expect(thread[field] != nil)
        }
    }
}

@Test("UserInput は localImage と skill を旧 text/image_url へ丸めない")
func userInputNativeImageAndSkillRoundTripWithoutLegacyLoss() throws {
    let nativeLocalImage: JSONValue = .object([
        "type": .string("localImage"),
        "path": .string("/tmp/phlox-image.png"),
        "detail": .string("high"),
    ])
    let nativeSkill: JSONValue = .object([
        "type": .string("skill"),
        "name": .string("swift-ui"),
        "path": .string("/Users/ryosuke/.codex/skills/swift-ui/SKILL.md"),
    ])

    let decodedImage = try decodeFromJSONValue(nativeLocalImage, as: UserInput.self)
    let decodedSkill = try decodeFromJSONValue(nativeSkill, as: UserInput.self)

    #expect(try encodeToJSONValue(decodedImage) == nativeLocalImage)
    #expect(try encodeToJSONValue(decodedSkill) == nativeSkill)
}

@Test("未知の UserInput discriminator は空 text に変換せず raw を保持する")
func unknownUserInputRoundTripPreservesDiscriminatorAndFields() throws {
    let futureInput: JSONValue = .object([
        "type": .string("futureInputKind"),
        "opaque": .object([
            "nested": .array([.string("keep-me"), .number(42)]),
        ]),
    ])

    let decoded = try decodeFromJSONValue(futureInput, as: UserInput.self)
    let encoded = try encodeToJSONValue(decoded)
    #expect(encoded == futureInput)
    #expect(encoded["type"]?.stringValue == "futureInputKind")
    #expect(encoded["opaque"]?["nested"]?.arrayValue?.count == 2)
}

@Test("Codex wire に旧 image_url discriminator を出さない")
func legacyImageURLWireShapeIsRejected() throws {
    let legacyInput: JSONValue = .object([
        "type": .string("image_url"),
        "image_url": .string("https://example.invalid/image.png"),
    ])
    let decoded = try decodeFromJSONValue(legacyInput, as: UserInput.self)
    let encoded = try encodeToJSONValue(decoded)
    #expect(encoded["type"] != .string("image_url"))
    #expect(encoded["image_url"] == nil)
    #expect(encoded["text"] != .string(""))
}

@Test("model/list の inputModalities は decode される")
func modelListPreservesInputModalities() throws {
    let data = Data("""
    {
      "data": [{
        "id": "gpt-5-codex",
        "model": "gpt-5-codex",
        "displayName": "GPT-5 Codex",
        "description": "",
        "hidden": false,
        "supportedReasoningEfforts": ["medium"],
        "defaultReasoningEffort": "medium",
        "isDefault": true,
        "inputModalities": ["text", "image"]
      }],
      "nextCursor": null
    }
    """.utf8)

    let response = try JSONDecoder.appServer.decode(ModelListResponse.self, from: data)
    #expect(response.data.count == 1)
    #expect(response.data[0].inputModalities == ["text", "image"])
}

@Test("thread/read は source・parentThreadId・canAcceptDirectInput を失わない")
func threadReadPreservesSourceParentAndDirectInputCapability() throws {
    let raw = try fixtureJSON("payloads/thread-read-full.json")
    let response = try decodeFromJSONValue(raw, as: ThreadReadResponse.self)
    let encoded = try encodeToJSONValue(response)

    #expect(encoded["thread"]?["source"] == .string("appServer"))
    #expect(encoded["thread"]?["parentThreadId"] == .string("parent-thread"))
    #expect(encoded["thread"]?["canAcceptDirectInput"] == .bool(false))
    #expect(encoded["thread"]?["cwd"] == .string("/tmp/project"))
}

@Test("schema-valid thread/read は欠落 optional、parent、direct input false、active turn を保持する")
func threadReadRoundTripsActiveTurnAndOptionalAbsence() throws {
    let raw = try fixtureJSON("payloads/thread-read-active-in-progress.json")
    let response = try decodeFromJSONValue(raw, as: ThreadReadResponse.self)
    let activeTurn = try #require(response.thread.turns?.first)
    #expect(activeTurn.id == "turn-active")
    #expect(activeTurn.status == "inProgress")

    let encoded = try encodeToJSONValue(response)
    #expect(encoded["thread"]?["parentThreadId"] == .string("parent-thread"))
    #expect(encoded["thread"]?["canAcceptDirectInput"] == .bool(false))
    #expect(encoded["thread"]?["turns"] == .array([
        .object([
            "id": .string("turn-active"),
            "items": .array([]),
            "status": .string("inProgress"),
        ]),
    ]))
    #expect(encoded["thread"]?["name"] == nil)
    #expect(encoded["thread"]?["path"] == nil)
    #expect(encoded["thread"]?["recencyAt"] == nil)
    #expect(encoded["thread"]?["threadSource"] == nil)
}

@Test("unknown source/status と null/欠落 optional field を丸めず保持する")
func threadReadPreservesUnknownSourceStatusAndNullOptionals() throws {
    let raw: JSONValue = .object([
        "thread": .object([
            "id": .string("future-thread"),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1700000000),
            "cwd": .string("/tmp/project"),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string("future preview"),
            "sessionId": .string("session-1"),
            "source": .string("futureSource"),
            "status": .object([
                "type": .string("futureStatus"),
                "futureFlag": .bool(true),
            ]),
            "turns": .array([]),
            "updatedAt": .number(1700000001),
            "parentThreadId": .null,
            "canAcceptDirectInput": .null,
            "path": .null,
            "recencyAt": .null,
        ]),
    ])
    let response = try decodeFromJSONValue(raw, as: ThreadReadResponse.self)
    let encoded = try encodeToJSONValue(response)

    #expect(encoded["thread"]?["source"] == .string("futureSource"))
    #expect(encoded["thread"]?["status"] == .object([
        "type": .string("futureStatus"),
        "futureFlag": .bool(true),
    ]))
    #expect(encoded["thread"]?["parentThreadId"] == .null)
    #expect(encoded["thread"]?["canAcceptDirectInput"] == .null)
    #expect(encoded["thread"]?["path"] == .null)
    #expect(encoded["thread"]?["recencyAt"] == .null)
    #expect(encoded["thread"]?["name"] == nil)
}

@Test("ThreadListParams と SkillsListParams の typed request を wire encode する")
func typedStableRequestDTOsEncodeExpectedWireShape() throws {
    let threadList: JSONValue = .object([
        "cwd": .string("/tmp/project"),
        "sourceKinds": .array([
            .string("cli"),
            .string("vscode"),
            .string("appServer"),
        ]),
        "limit": .number(20),
        "parentThreadId": .string("parent-thread"),
    ])
    let skillsList: JSONValue = .object([
        "cwds": .array([.string("/tmp/project")]),
        "forceReload": .bool(true),
    ])

    #expect(try runtimeRoundTrip(ThreadListParams.self, raw: threadList) == threadList)
    #expect(try runtimeRoundTrip(SkillsListParams.self, raw: skillsList) == skillsList)

    let ancestorThreadList: JSONValue = .object([
        "cwd": .string("/tmp/project"),
        "sourceKinds": .array([.string("subAgent")]),
        "ancestorThreadId": .string("ancestor-thread"),
    ])
    #expect(try runtimeRoundTrip(ThreadListParams.self, raw: ancestorThreadList) == ancestorThreadList)
}

@Test("thread/list の cwd・sourceKinds・main thread 条件をそのまま送る")
func threadListRequestUsesSessionCwdAndInteractiveSources() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    let params: JSONValue = .object([
        "cwd": .array([.string("/tmp/project")]),
        "sourceKinds": .array([
            .string("cli"),
            .string("vscode"),
            .string("appServer"),
        ]),
        "parentThreadId": .null,
        "ancestorThreadId": .null,
    ])
    async let response = rpc.requestJSON(method: "thread/list", params: params)

    #expect(await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/list" }
    })
    let request = try #require(await transport.sent.first { $0["method"]?.stringValue == "thread/list" })
    #expect(request["params"] == params)

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"data":[],"nextCursor":null}}
    """)
    #expect(try await response == .object(["data": .array([]), "nextCursor": .null]))
    await rpc.close()
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}
