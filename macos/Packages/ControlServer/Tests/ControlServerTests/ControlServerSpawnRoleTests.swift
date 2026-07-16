import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor RoleHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var capturedSpawnRole: String?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        capturedSpawnRole = ControlSpawnContext.role
        callCount += 1
        return .status(200)
    }
}

@Suite struct ControlServerSpawnRoleTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test func postSessionsCarriesRoleViaTaskLocal() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","role":"批判者"}"#
        )
        #expect(status == 200)

        let role = await stub.capturedSpawnRole
        #expect(role == "批判者")
    }

    @Test func postSessionsWithoutRoleLeavesTaskLocalNil() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor"}"#
        )
        #expect(status == 200)

        let role = await stub.capturedSpawnRole
        #expect(role == nil)
    }

    @Test func postSessionsRejectsEmptyRole400() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","role":""}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postSessionsRejectsControlCharactersInRole400() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","role":"bad\nrole"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - role 付き spawn の backend 既定（フェーズ4 統合検証のリグレッション。
    // 討論招集の participant は appServer transcript の観測が前提のため、
    // role 付き claudeCode spawn は明示指定が無ければ appServer で起動する）

    @Test func 役割付きclaudeCodeのspawnはbackend省略時にappServerで起動する() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"claudeCode","role":"批判者"}"#
        )
        #expect(status == 200)
        let action = try #require(await stub.lastRequest?.action)
        guard case let .spawn(_, backend, _) = action else {
            Issue.record("expected spawn action, got \(action)")
            return
        }
        #expect(backend == .appServer)
    }

    @Test func 役割なしclaudeCodeのspawnは従来どおりptyで起動する() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"claudeCode"}"#
        )
        #expect(status == 200)
        let action = try #require(await stub.lastRequest?.action)
        guard case let .spawn(_, backend, _) = action else {
            Issue.record("expected spawn action, got \(action)")
            return
        }
        #expect(backend == .pty)
    }

    @Test func 役割付きでも明示のbackend指定が優先される() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"claudeCode","role":"批判者","backend":"pty"}"#
        )
        #expect(status == 200)
        let action = try #require(await stub.lastRequest?.action)
        guard case let .spawn(_, backend, _) = action else {
            Issue.record("expected spawn action, got \(action)")
            return
        }
        #expect(backend == .pty)
    }

    @Test func 役割付きでもclaudeCode以外のspawnはptyで起動する() async throws {
        let stub = RoleHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","role":"批判者"}"#
        )
        #expect(status == 200)
        let action = try #require(await stub.lastRequest?.action)
        guard case let .spawn(_, backend, _) = action else {
            Issue.record("expected spawn action, got \(action)")
            return
        }
        #expect(backend == .pty)
    }

    // MARK: - harness

    private func startServer(stub: RoleHandlerStub) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store, agentCatalog: .builtins) { request in
            await stub.handle(request)
        }
        let port = try await server.start()
        return (port, server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        bearer: String? = nil,
        body: String? = nil
    ) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = method
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(body.utf8)
        }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
