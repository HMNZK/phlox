import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor SettingsRoutingStub {
    var action: ControlRequest.Action?
    var calls = 0
    func handle(_ request: ControlRequest) -> ControlResponse {
        action = request.action
        calls += 1
        return .status(200)
    }
}

extension ModelCatalogTestIsolation {
@Suite struct ComposerSettingsRoutingTests {
    private func send(_ method: String, _ path: String, _ body: String = "{}") async throws -> (ControlResponse, ControlRequest.Action?, Int) {
        let store = SessionTokenStore()
        await store.register("settings-test", for: SessionID())
        let stub = SettingsRoutingStub()
        let server = ControlServer(tokenStore: store) { await stub.handle($0) }
        let port = try await server.start()
        defer { withExtendedLifetime(server) {} }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer settings-test", forHTTPHeaderField: "Authorization")
        request.httpBody = method == "GET" ? nil : Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        return (ControlResponse(statusCode: http.statusCode, body: data), await stub.action, await stub.calls)
    }

    @Test func spawnCarriesNormalizedInitialSettings() async throws {
        let (response, action, _) = try await send("POST", "/sessions", #"{"kind":"claudeCode","backend":"appServer","model":"opus[1m]","effort":" high ","permission":" manual ","planMode":false}"#)
        #expect(response.statusCode == 200)
        guard case let .spawn(ref, backend, _, _, settings) = action else { Issue.record("missing spawn"); return }
        #expect(ref == .builtin(.claudeCode))
        #expect(backend == .appServer)
        #expect(settings == CodexAppServerSessionSettings(selectedModel: "opus[1m]", selectedEffort: "high", selectedPermissionProfile: "manual", isPlanMode: false))
    }

    @Test func legacySpawnHasNilSettings() async throws {
        let (_, action, _) = try await send("POST", "/sessions", #"{"kind":"claudeCode"}"#)
        guard case let .spawn(_, backend, _, _, settings) = action else { Issue.record("missing spawn"); return }
        #expect(backend == .pty)
        #expect(settings == nil)
    }

    @Test(arguments: ["appServer", "pty"])
    func spawnNullPermissionMatchesOmittedPermission(backend: String) async throws {
        let body = "{\"kind\":\"claudeCode\",\"backend\":\"\(backend)\""
        let (response, action, calls) = try await send("POST", "/sessions", body + ",\"permission\":null}")
        let (omittedResponse, omittedAction, _) = try await send("POST", "/sessions", body + "}")
        #expect(response.statusCode == 200)
        #expect(response.statusCode == omittedResponse.statusCode)
        #expect(calls == 1)
        guard case let .spawn(ref, actualBackend, directory, projectID, settings) = action,
              case let .spawn(omittedRef, omittedBackend, omittedDirectory, omittedProjectID, omittedSettings) = omittedAction
        else { Issue.record("missing spawn"); return }
        #expect(ref == omittedRef)
        #expect(actualBackend == omittedBackend)
        #expect(directory == omittedDirectory)
        #expect(projectID == omittedProjectID)
        #expect(settings == omittedSettings)
        #expect(settings == nil)
    }

    @Test func spawnEffortWithNullPermissionHasDefaultPermission() async throws {
        let (response, action, calls) = try await send("POST", "/sessions", #"{"kind":"claudeCode","backend":"appServer","effort":"high","permission":null}"#)
        #expect(response.statusCode == 200)
        #expect(calls == 1)
        guard case let .spawn(_, _, _, _, settings) = action else { Issue.record("missing spawn"); return }
        #expect(settings == CodexAppServerSessionSettings(selectedModel: AgentModelCatalog.defaultModel(for: .claudeCode), selectedEffort: "high", selectedPermissionProfile: nil, isPlanMode: nil))
    }

    @Test(arguments: [#""effort":1"#, #""effort":null"#, #""permission":false"#, #""planMode":"yes"#, #""planMode":null"#])
    func spawnRejectsWrongTypes(field: String) async throws {
        let (response, _, calls) = try await send("POST", "/sessions", "{\"kind\":\"claudeCode\",\"backend\":\"appServer\",\(field)}")
        #expect(response.statusCode == 400)
        #expect(calls == 0)
    }

    @Test(arguments: ["effort", "permission"], ["", "   ", "high\n", "x\u{1B}", "x\u{7F}", String(repeating: "x", count: 129)])
    func invalidStrings(field: String, value: String) async throws {
        let body = String(decoding: try JSONSerialization.data(withJSONObject: ["kind": "claudeCode", "backend": "appServer", field: value]), as: UTF8.self)
        for (method, path) in [("POST", "/sessions"), ("PATCH", "/sessions/\(SessionID())/settings")] {
            let (response, _, calls) = try await send(method, path, body)
            #expect(response.statusCode == 400)
            #expect(try JSONSerialization.jsonObject(with: response.body) as? [String: String] == ["error": "invalid \(field)"])
            #expect(calls == 0)
        }
    }

    @Test(arguments: [#""effort":"high""#, #""permission":"manual""#, #""planMode":false"#])
    func ptyRejectsSettings(field: String) async throws {
        let (response, _, calls) = try await send("POST", "/sessions", "{\"kind\":\"claudeCode\",\(field)}")
        #expect(response.statusCode == 400)
        #expect(try JSONSerialization.jsonObject(with: response.body) as? [String: String] == ["error": "settings require appServer backend"])
        #expect(calls == 0)
    }

    @Test func patchDistinguishesOmittedAndNullPermissionAndRename() async throws {
        let id = SessionID()
        let (_, action, _) = try await send("PATCH", "/sessions/\(id)/settings", #"{"permission":null,"planMode":true}"#)
        guard case let .setSettings(target, settings) = action else { Issue.record("missing settings"); return }
        #expect(target == id)
        #expect(settings.permission != nil)
        #expect(settings.permission! == nil)
        #expect(settings.effort == nil)
        #expect(settings.planMode == true)
        let (_, rename, _) = try await send("PATCH", "/sessions/\(id)", #"{"name":"test"}"#)
        guard case let .rename(target, name) = rename else { Issue.record("missing rename"); return }
        #expect(target == id)
        #expect(name == "test")
    }

    @Test(arguments: ["{}", #"{"effort":null}"#, #"{"effort":false}"#, #"{"permission":1}"#, #"{"planMode":1}"#])
    func invalidPatchBody(body: String) async throws {
        let (response, _, calls) = try await send("PATCH", "/sessions/\(SessionID())/settings", body)
        #expect(response.statusCode == 400)
        #expect(calls == 0)
    }

    @Test func newGetRoutes() async throws {
        for kind in AgentKind.allCases {
            let (response, action, _) = try await send("GET", "/agents/\(kind.rawValue)/settings")
            #expect(response.statusCode == 200)
            guard case .agentSettings(let parsed) = action else { Issue.record("missing agent settings"); continue }
            #expect(parsed == kind)
        }
        let (response, action, _) = try await send("GET", "/projects")
        #expect(response.statusCode == 200)
        guard case .listProjects = action else { Issue.record("missing projects"); return }
    }

    @Test(arguments: ["/agents/unknown/settings", "/agents/codex/settings?x=1", "/projects?x=1"])
    func unknownAndQueryGetRoutes(path: String) async throws {
        let (response, _, calls) = try await send("GET", path)
        #expect(response.statusCode == 404)
        #expect(calls == 0)
    }

    @Test func patchQueryAndInvalidID() async throws {
        let (query, _, _) = try await send("PATCH", "/sessions/\(SessionID())/settings?x=1", #"{"planMode":true}"#)
        #expect(query.statusCode == 404)
        let (invalid, _, calls) = try await send("PATCH", "/sessions/bad/settings", #"{"planMode":true}"#)
        #expect(invalid.statusCode == 400)
        #expect(calls == 0)
    }
}

}
