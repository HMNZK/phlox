import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor SpawnProjectIdHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct SpawnProjectIdWhiteboxTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test(arguments: ["My Repo", ""])
    func malformedProjectIdReturns400WithContractErrorBody(projectId: String) async throws {
        let stub = SpawnProjectIdHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let response = try await request(
            port: port,
            body: #"{"kind":"codex","projectId":"\#(projectId)"}"#
        )

        #expect(response.status == 400)
        let json = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(json["error"] as? String == "invalid projectId")
        #expect(await stub.callCount == 0)
    }

    @Test("custom agent kind also carries projectId in Action.spawn")
    func customAgentKindCarriesProjectId() async throws {
        let projectID = ProjectID()
        let custom = AgentDescriptor(
            ref: .custom("aider"),
            displayName: "Aider",
            binaryName: "aider",
            symbolName: "wrench.and.screwdriver",
            colorRGB: AgentRGB(0xE5, 0xA5, 0x3F),
            bypassKey: "phlox.bypass.aider",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
        let stub = SpawnProjectIdHandlerStub()
        let (port, server) = try await startServer(
            stub: stub,
            agentCatalog: AgentCatalog(customDescriptors: [custom])
        )
        _ = server

        let response = try await request(
            port: port,
            body: #"{"kind":"aider","projectId":"\#(projectID.rawValue.uuidString)"}"#
        )

        #expect(response.status == 200)
        let request = try #require(await stub.lastRequest)
        guard case .spawn(let ref, _, _, let receivedProjectID) = request.action else {
            Issue.record("expected spawn, got \(request.action)")
            return
        }
        #expect(ref == .custom("aider"))
        #expect(receivedProjectID == projectID)
    }

    private func startServer(
        stub: SpawnProjectIdHandlerStub,
        agentCatalog: AgentCatalog = .builtins
    ) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store, agentCatalog: agentCatalog) { request in
            await stub.handle(request)
        }
        return (try await server.start(), server)
    }

    private func request(port: Int, body: String) async throws -> (status: Int, body: Data) {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sessions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}
