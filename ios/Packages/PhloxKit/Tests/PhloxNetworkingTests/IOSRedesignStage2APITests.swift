import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

@Suite("iOS 再設計 段階 2 API", .serialized)
struct IOSRedesignStage2APITests {
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    private func makeClient() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IOSRedesignStage2URLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }

    private func response(_ status: Int, _ body: String = "") -> Stage2StubOutcome {
        .status(status, Data(body.utf8), [:])
    }

    private func requestBody() throws -> [String: Any] {
        let data = try #require(IOSRedesignStage2URLProtocol.lastRequestBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("sessions は新しい一覧項目を読み、Mac の応答順を保つ")
    func sessionListReadsMetadataAndPreservesOrder() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200, """
        {"sessions":[
          {"id":"pty-first","name":"Terminal","kind":"codex","status":"running","backend":"pty","isStalled":true,"hasUnseenCompletion":false,"parentSessionId":"parent","statusEnteredAt":"1970-01-01T00:00:00Z"},
          {"id":"chat-second","name":"Chat","kind":"claudeCode","status":"idle","backend":"appServer","isStalled":false,"hasUnseenCompletion":true}
        ]}
        """)]

        let sessions = try await makeClient().listSessions()

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "GET")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/sessions")
        #expect(sessions.map(\.id) == ["pty-first", "chat-second"])
        #expect(sessions[0].backend == "pty")
        #expect(sessions[0].isStalled)
        #expect(!sessions[0].hasUnseenCompletion)
        #expect(sessions[0].parentSessionId == "parent")
        #expect(sessions[0].statusEnteredAt == Date(timeIntervalSince1970: 0))
        #expect(sessions[0].isPTY)
        #expect(sessions[1].backend == "appServer")
        #expect(sessions[1].hasUnseenCompletion)
        #expect(sessions[1].parentSessionId == nil)
        #expect(!sessions[1].isPTY)
    }

    @Test("古い Mac の sessions は新しい項目の既定値で読める")
    func oldSessionDTOUsesCompatibilityDefaults() throws {
        let dto = try JSONDecoder().decode(
            SessionDTO.self,
            from: Data(#"{"id":"s1","name":"Rose","kind":"claudeCode","status":"running"}"#.utf8)
        )
        let session = try #require(dto.toDomain(now: Date(timeIntervalSince1970: 1)))

        #expect(session.backend == "appServer")
        #expect(!session.isStalled)
        #expect(!session.hasUnseenCompletion)
        #expect(session.parentSessionId == nil)
        #expect(session.statusEnteredAt == nil)
    }

    @Test("session settings を取得し、Mac の displayName と全項目を読む")
    func agentSettingsGetsKindPathAndDecodes() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200, """
        {"availableEfforts":{"opus":[{"value":"xhigh","displayName":"非常に高"}],"haiku":[]},
         "availablePermissions":[{"value":null,"displayName":"既定"},{"value":"ask","displayName":"確認"}],
         "planModeAvailable":true}
        """)]

        let settings = try #require(try await makeClient().agentSettings(kind: .claudeCode))

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "GET")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/agents/claudeCode/settings")
        #expect(settings.availableEfforts["opus"] == [AgentSettingOption(value: "xhigh", displayName: "非常に高")])
        #expect(settings.availableEfforts["haiku"] == [])
        #expect(settings.availablePermissions == [
            AgentSettingOption(value: nil, displayName: "既定"),
            AgentSettingOption(value: "ask", displayName: "確認"),
        ])
        #expect(settings.planModeAvailable)
    }

    @Test("古い Mac の agent settings 404 は非対応 nil")
    func oldMacAgentSettings404ReturnsNil() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(404)]

        let settings = try await makeClient().agentSettings(kind: .codex)

        #expect(settings == nil)
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/agents/codex/settings")
    }

    @Test("projects の取得口と応答順を保つ")
    func projectsGetsAndDecodesInResponseOrder() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200, """
        {"projects":[{"id":"P-2","name":"Second"},{"id":"P-1","name":"First"}]}
        """)]

        let projects = try #require(try await makeClient().projects())

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "GET")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/projects")
        #expect(projects == [ProjectSummary(id: "P-2", name: "Second"), ProjectSummary(id: "P-1", name: "First")])
    }

    @Test("古い Mac の projects 404 は非対応 nil")
    func oldMacProjects404ReturnsNil() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(404)]

        let projects = try await makeClient().projects()

        #expect(projects == nil)
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/projects")
    }

    @Test("session settings の追加項目を読む")
    func sessionSettingsDecodesExtendedFields() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200, """
        {"selectedModel":"opus","availableModels":[{"id":"opus","displayName":"Opus"}],
         "selectedEffort":"high","availableEfforts":[{"value":"high","displayName":"高"}],
         "selectedPermission":"acceptEdits","availablePermissions":[{"value":"acceptEdits","displayName":"編集を許可"}],
         "planMode":false,"planModeAvailable":true}
        """)]

        let settings = try await makeClient().sessionSettings(sessionID: "session-1")

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "GET")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/sessions/session-1/settings")
        #expect(settings.selectedModel == "opus")
        #expect(settings.selectedEffort == "high")
        #expect(settings.availableEfforts == [AgentSettingOption(value: "high", displayName: "高")])
        #expect(settings.selectedPermission == "acceptEdits")
        #expect(settings.availablePermissions == [AgentSettingOption(value: "acceptEdits", displayName: "編集を許可")])
        #expect(!settings.planMode)
        #expect(settings.planModeAvailable)
    }

    @Test("古い Mac の session settings は選択肢なし・Plan 不可")
    func oldSessionSettingsMissingNewKeysUsesUnavailableDefaults() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200, """
        {"selectedModel":null,"availableModels":[]}
        """)]

        let settings = try await makeClient().sessionSettings(sessionID: "session-2")

        #expect(settings.selectedEffort == nil)
        #expect(settings.availableEfforts.isEmpty)
        #expect(settings.selectedPermission == nil)
        #expect(settings.availablePermissions.isEmpty)
        #expect(!settings.planMode)
        #expect(!settings.planModeAvailable)
    }

    @Test("spawn は設定値を POST body に含める")
    func spawnSendsOptionalSettings() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(201, #"{"id":"s-new"}"#)]

        _ = try await makeClient().spawn(SpawnRequest(
            agent: .codex,
            workspace: "repo",
            projectID: "P-1",
            model: "gpt-5",
            effort: "high",
            permission: ":workspace",
            planMode: true
        ))

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "POST")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/sessions")
        let body = try requestBody()
        #expect(body["kind"] as? String == "codex")
        #expect(body["backend"] as? String == "appServer")
        #expect(body["projectId"] as? String == "P-1")
        #expect(body["model"] as? String == "gpt-5")
        #expect(body["effort"] as? String == "high")
        #expect(body["permission"] as? String == ":workspace")
        #expect(body["planMode"] as? Bool == true)
    }

    @Test("spawn の新項目が nil なら旧 Mac と同じ body")
    func spawnOmitsNilOptionalSettings() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(201, #"{"id":"s-new"}"#)]

        _ = try await makeClient().spawn(SpawnRequest(agent: .claudeCode, workspace: "repo"))

        let body = try requestBody()
        #expect(Set(body.keys) == ["kind", "backend"])
        #expect(body["effort"] == nil)
        #expect(body["permission"] == nil)
        #expect(body["planMode"] == nil)
    }

    @Test("PATCH settings は指定されたキーだけを送り permission null を保つ")
    func updateSessionSettingsSendsSelectedKeysAndExplicitNull() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200)]

        try await makeClient().updateSessionSettings(
            sessionID: "session-3",
            update: SessionSettingsUpdate(effort: "medium", permission: .some(nil), planMode: true)
        )

        #expect(IOSRedesignStage2URLProtocol.lastRequest?.httpMethod == "PATCH")
        #expect(IOSRedesignStage2URLProtocol.lastRequest?.url?.path == "/sessions/session-3/settings")
        let body = try requestBody()
        #expect(Set(body.keys) == ["effort", "permission", "planMode"])
        #expect(body["effort"] as? String == "medium")
        #expect(body["permission"] is NSNull)
        #expect(body["planMode"] as? Bool == true)
    }

    @Test("PATCH settings の未指定キーは body から省く")
    func updateSessionSettingsOmitsUnspecifiedKeys() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(200)]

        try await makeClient().updateSessionSettings(
            sessionID: "session-4",
            update: SessionSettingsUpdate(effort: "low")
        )

        let body = try requestBody()
        #expect(body["effort"] as? String == "low")
        #expect(body["permission"] == nil)
        #expect(body["planMode"] == nil)
    }

    @Test("旧 Mac の PATCH 400 は非対応として返す")
    func oldMacPatch400MapsToUnsupported() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(400)]

        do {
            try await makeClient().updateSessionSettings(
                sessionID: "session-5",
                update: SessionSettingsUpdate(effort: "high")
            )
            Issue.record("expected unsupported")
        } catch let error as PhloxError {
            #expect(error == .unsupported)
        }
    }

    @Test("PATCH 400 validation error は理由付き server error")
    func patchValidation400RetainsReason() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(400, #"{"error":"unknown effort: nope"}"#)]

        do {
            try await makeClient().updateSessionSettings(
                sessionID: "session-6",
                update: SessionSettingsUpdate(effort: "nope")
            )
            Issue.record("expected server error")
        } catch let error as PhloxError {
            #expect(error == .server(status: 400, message: "unknown effort: nope"))
        }
    }

    @Test("PATCH の 409 in-progress と各 unsupported を区別する")
    func patch409ReasonsRemainDistinct() async throws {
        let reasons = [
            "settings update in progress",
            "effort unsupported",
            "permission unsupported",
            "plan mode unavailable",
        ]

        for reason in reasons {
            IOSRedesignStage2URLProtocol.reset()
            IOSRedesignStage2URLProtocol.outcomes = [response(409, "{\"error\":\"\(reason)\"}")]
            do {
                try await makeClient().updateSessionSettings(
                    sessionID: "session-7",
                    update: SessionSettingsUpdate(effort: "high")
                )
                Issue.record("expected 409 for \(reason)")
            } catch let error as PhloxError {
                #expect(error == .server(status: 409, message: reason))
            }
        }
    }

    @Test("PATCH は 404・425・500 を既存 PhloxError で区別する")
    func patchMapsNotFoundNotReadyAndServerFailure() async throws {
        let cases: [(Int, String, PhloxError)] = [
            (404, "", .notFound),
            (425, #"{"error":"session not ready"}"#, .server(status: 425, message: "session not ready")),
            (500, "", .server(status: 500, message: nil)),
        ]

        for (status, body, expected) in cases {
            IOSRedesignStage2URLProtocol.reset()
            IOSRedesignStage2URLProtocol.outcomes = [response(status, body)]
            do {
                try await makeClient().updateSessionSettings(
                    sessionID: "session-8",
                    update: SessionSettingsUpdate(planMode: true)
                )
                Issue.record("expected HTTP \(status)")
            } catch let error as PhloxError {
                #expect(error == expected)
            }
        }
    }

    @Test("spawn の 422 settings not applied は spawnRejected")
    func spawn422MapsSettingsFailure() async throws {
        IOSRedesignStage2URLProtocol.reset()
        IOSRedesignStage2URLProtocol.outcomes = [response(422, #"{"error":"settings not applied"}"#)]

        do {
            _ = try await makeClient().spawn(SpawnRequest(
                agent: .claudeCode,
                workspace: "repo",
                effort: "high"
            ))
            Issue.record("expected spawn rejection")
        } catch let error as PhloxError {
            #expect(error == .spawnRejected(reason: "settings not applied"))
        }
    }

    @Test("新しい wire 定数が Mac 契約のキーと一致")
    func wireConstantsMatchMacNames() {
        #expect(PhloxModelWireContract.settingsPathSuffix == "settings")
        #expect(PhloxModelWireContract.projectsPath == "projects")
        #expect(PhloxModelWireContract.availableEffortsKey == "availableEfforts")
        #expect(PhloxModelWireContract.selectedEffortKey == "selectedEffort")
        #expect(PhloxModelWireContract.selectedPermissionKey == "selectedPermission")
        #expect(PhloxModelWireContract.availablePermissionsKey == "availablePermissions")
        #expect(PhloxModelWireContract.planModeKey == "planMode")
        #expect(PhloxModelWireContract.planModeAvailableKey == "planModeAvailable")
        #expect(PhloxModelWireContract.effortKey == "effort")
        #expect(PhloxModelWireContract.permissionKey == "permission")
        #expect(PhloxModelWireContract.projectsKey == "projects")
        #expect(PhloxModelWireContract.projectIDKey == "id")
        #expect(PhloxModelWireContract.projectNameKey == "name")
        #expect(PhloxQuestionWireContract.toolNameKey == "toolName")
        #expect(PhloxQuestionWireContract.toolDetailKey == "toolDetail")
    }
}

private enum Stage2StubOutcome {
    case status(Int, Data, [String: String])
}

private final class IOSRedesignStage2URLProtocol: URLProtocol {
    nonisolated(unsafe) static var outcomes: [Stage2StubOutcome] = []
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        outcomes = []
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        IOSRedesignStage2URLProtocol.lastRequest = request
        IOSRedesignStage2URLProtocol.lastRequestBody = request.readBodyForTesting()
        guard let outcome = IOSRedesignStage2URLProtocol.outcomes.first else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        guard case let .status(status, data, headers) = outcome,
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
