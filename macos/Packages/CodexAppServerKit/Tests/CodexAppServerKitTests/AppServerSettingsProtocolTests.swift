import Foundation
import Testing
@testable import CodexAppServerKit

@Test func collaborationModeSettingsEncodeSnakeCaseNulls() throws {
    let mode = CollaborationMode(
        mode: .plan,
        settings: CollaborationModeSettings(
            model: "gpt-5-codex",
            reasoningEffort: "medium",
            developerInstructions: nil
        )
    )

    let json = try encodeToJSONValue(mode)
    #expect(json["mode"]?.stringValue == "plan")
    #expect(json["settings"]?["model"]?.stringValue == "gpt-5-codex")
    #expect(json["settings"]?["reasoning_effort"]?.stringValue == "medium")
    #expect(json["settings"]?["developer_instructions"] == .null)
    #expect(json["settings"]?["reasoningEffort"] == nil)
    #expect(json["settings"]?["developerInstructions"] == nil)
}

@Test func threadSettingsUpdateParamsEncodeExpectedProtocolShape() throws {
    let params = ThreadSettingsUpdateParams(
        threadId: "thread-1",
        model: "gpt-5-codex",
        effort: "high",
        approvalPolicy: .named("on-request"),
        permissions: ":workspace",
        collaborationMode: CollaborationMode(
            mode: .plan,
            settings: CollaborationModeSettings(
                model: "gpt-5-codex",
                reasoningEffort: "high",
                developerInstructions: nil
            )
        )
    )

    let json = try encodeToJSONValue(params)
    #expect(json["threadId"]?.stringValue == "thread-1")
    #expect(json["model"]?.stringValue == "gpt-5-codex")
    #expect(json["effort"]?.stringValue == "high")
    #expect(json["approvalPolicy"]?.stringValue == "on-request")
    #expect(json["permissions"]?.stringValue == ":workspace")
    #expect(json["sandboxPolicy"] == nil)
    #expect(json["collaborationMode"]?["mode"]?.stringValue == "plan")
    #expect(json["collaborationMode"]?["settings"]?["reasoning_effort"]?.stringValue == "high")
    #expect(json["collaborationMode"]?["settings"]?["developer_instructions"] == .null)
}

@Test func modelListResponseDecodesReasoningEffortObjects() throws {
    let response = try JSONDecoder.appServer.decode(
        ModelListResponse.self,
        from: Data("""
        {
          "data": [
            {
              "id": "gpt-5-codex",
              "model": "gpt-5-codex",
              "displayName": "GPT-5 Codex",
              "description": "Coding model",
              "hidden": false,
              "supportedReasoningEfforts": [
                {"reasoningEffort": "low", "description": "Fast"},
                {"reasoningEffort": "medium", "description": "Balanced"}
              ],
              "defaultReasoningEffort": "medium",
              "isDefault": true
            }
          ],
          "nextCursor": null
        }
        """.utf8)
    )

    #expect(response.data.count == 1)
    #expect(response.data[0].id == "gpt-5-codex")
    #expect(response.data[0].supportedReasoningEfforts.map(\.reasoningEffort) == ["low", "medium"])
    #expect(response.data[0].defaultReasoningEffort == "medium")
    #expect(response.data[0].isDefault)
}

@Test func threadResponseDecodesOptionalReasoningAndPermissionProfile() throws {
    let response = try JSONDecoder.appServer.decode(
        ThreadResponse.self,
        from: Data("""
        {
          "thread": {"id": "thread-1"},
          "model": "gpt-5-codex",
          "modelProvider": "openai",
          "reasoningEffort": "medium",
          "activePermissionProfile": {"id": ":workspace", "extends": null},
          "approvalPolicy": "never",
          "sandbox": {"type": "workspaceWrite"}
        }
        """.utf8)
    )

    #expect(response.thread.id == "thread-1")
    #expect(response.reasoningEffort == "medium")
    #expect(response.activePermissionProfile?.id == ":workspace")
}

@Test func threadSettingsUpdatedNotificationDecodesTopLevelThreadSettings() throws {
    let notification = try JSONDecoder.appServer.decode(
        ThreadSettingsUpdatedNotification.self,
        from: Data("""
        {
          "threadId": "thread-1",
          "threadSettings": {
            "cwd": "/tmp/project",
            "model": "gpt-5-codex",
            "modelProvider": "openai",
            "effort": "medium",
            "approvalPolicy": "never",
            "approvalsReviewer": "user",
            "sandboxPolicy": {"type": "workspaceWrite", "networkAccess": false},
            "activePermissionProfile": {"id": ":workspace", "extends": null},
            "serviceTier": null,
            "collaborationMode": {
              "mode": "plan",
              "settings": {
                "model": "gpt-5-codex",
                "reasoning_effort": "medium",
                "developer_instructions": null
              }
            }
          }
        }
        """.utf8)
    )

    #expect(notification.threadId == "thread-1")
    #expect(notification.threadSettings.model == "gpt-5-codex")
    #expect(notification.threadSettings.effort == "medium")
    #expect(notification.threadSettings.activePermissionProfile?.id == ":workspace")
    #expect(notification.threadSettings.collaborationMode.mode == .plan)
    #expect(notification.threadSettings.collaborationMode.settings.reasoningEffort == "medium")
}

@Test func clientRequestsSettingsMethods() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    async let models: ModelListResponse = client.listModels(ModelListParams(limit: 20))
    let sentModelRequest = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "model/list" }
    }
    #expect(sentModelRequest)
    let modelRequest = try #require(await transport.sent.first { $0["method"]?.stringValue == "model/list" })
    #expect(modelRequest["params"]?["limit"]?.intValue == 20)
    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"data":[{"id":"gpt-5-codex","model":"gpt-5-codex","displayName":"GPT-5 Codex","description":"","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"medium","description":"Balanced"}],"defaultReasoningEffort":"medium","isDefault":true}],"nextCursor":null}}
    """)
    #expect(try await models.data.first?.id == "gpt-5-codex")

    async let profiles: PermissionProfileListResponse = client.listPermissionProfiles(
        PermissionProfileListParams(cwd: "/tmp/project")
    )
    let sentProfileRequest = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "permissionProfile/list" }
    }
    #expect(sentProfileRequest)
    let profileRequest = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "permissionProfile/list"
    })
    #expect(profileRequest["params"]?["cwd"]?.stringValue == "/tmp/project")
    transport.receive("""
    {"jsonrpc":"2.0","id":2,"result":{"data":[{"id":":read-only","description":"Read Only"},{"id":":workspace","description":"Auto"}],"nextCursor":null}}
    """)
    #expect(try await profiles.data.map(\.id) == [":read-only", ":workspace"])

    async let modes: CollaborationModeListResponse = client.listCollaborationModes()
    let sentModesRequest = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "collaborationMode/list" }
    }
    #expect(sentModesRequest)
    transport.receive("""
    {"jsonrpc":"2.0","id":3,"result":{"data":[{"name":"Plan","mode":"plan","model":null,"reasoning_effort":null},{"name":"Default","mode":"default","model":null,"reasoning_effort":null}]}}
    """)
    #expect(try await modes.data.map(\.mode) == [.plan, .default])

    async let update: ThreadSettingsUpdateResponse = client.updateThreadSettings(
        ThreadSettingsUpdateParams(
            threadId: "thread-1",
            model: "gpt-5-codex",
            effort: "medium",
            permissions: ":workspace"
        )
    )
    let sentUpdateRequest = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/settings/update" }
    }
    #expect(sentUpdateRequest)
    let updateRequest = try #require(await transport.sent.first {
        $0["method"]?.stringValue == "thread/settings/update"
    })
    #expect(updateRequest["params"]?["threadId"]?.stringValue == "thread-1")
    #expect(updateRequest["params"]?["permissions"]?.stringValue == ":workspace")
    transport.receive("""
    {"jsonrpc":"2.0","id":4,"result":{}}
    """)
    _ = try await update

    await client.close()
}

@Test func clientNormalizesThreadSettingsUpdatedNotification() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/settings/updated","params":{"threadId":"thread-1","threadSettings":{"cwd":"/tmp/project","model":"gpt-5-codex","modelProvider":"openai","effort":"medium","approvalPolicy":"never","approvalsReviewer":"user","sandboxPolicy":{"type":"workspaceWrite"},"activePermissionProfile":{"id":":workspace","extends":null},"serviceTier":null,"collaborationMode":{"mode":"plan","settings":{"model":"gpt-5-codex","reasoning_effort":"medium","developer_instructions":null}}}}}
    """)

    let event = await iterator.next()
    guard case .threadSettingsUpdated(let threadId, let settings) = event else {
        Issue.record("Expected thread settings updated event")
        return
    }
    #expect(threadId == "thread-1")
    #expect(settings.model == "gpt-5-codex")
    #expect(settings.activePermissionProfile?.id == ":workspace")
    await client.close()
}
