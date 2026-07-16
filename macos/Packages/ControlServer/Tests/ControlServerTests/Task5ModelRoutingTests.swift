import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor Task5RoutingHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct Task5ModelRoutingTests {
    private let requester = SessionID()
    private let bearer = "task-5-bearer"

    @Test func getSettingsRoutesSessionID() async throws {
        let stub = Task5RoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlModelWireContract.settingsPathSuffix)"
        )

        #expect(response.statusCode == 200)
        let last = await stub.lastRequest
        guard case .sessionSettings(let id)? = last?.action else {
            Issue.record("expected sessionSettings, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
        #expect(last?.requester == requester)
    }

    @Test func postModelRoutesTrimmedModel() async throws {
        let stub = Task5RoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlModelWireContract.modelPathSuffix)",
            body: #"{"model":"  sonnet  "}"#
        )

        #expect(response.statusCode == 200)
        let last = await stub.lastRequest
        guard case .setModel(let id, let model)? = last?.action else {
            Issue.record("expected setModel, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
        #expect(model == "sonnet")
    }

    @Test(arguments: ["{}", #"{"model":""}"#, #"{"model":"   "}"#, "not-json"])
    func invalidModelBodyReturns400WithoutCallingHandler(body: String) async throws {
        let stub = Task5RoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)\(ControlModelWireContract.modelPathSuffix)",
            body: body
        )

        #expect(response.statusCode == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func unrelatedSessionSuffixReturns404() async throws {
        let stub = Task5RoutingHandlerStub()
        let (port, server) = try await startServer(stub)
        _ = server
        let target = SessionID()

        let response = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/unknown-model-route"
        )

        #expect(response.statusCode == 404)
        #expect(await stub.callCount == 0)
    }

    private func startServer(_ stub: Task5RoutingHandlerStub) async throws -> (Int, ControlServer) {
        let store = SessionTokenStore()
        await store.register(bearer, for: requester)
        let server = ControlServer(tokenStore: store) { request in
            await stub.handle(request)
        }
        return (try await server.start(), server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        body: String? = nil
    ) async throws -> HTTPURLResponse {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return try #require(response as? HTTPURLResponse)
    }
}
