import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

// task-3 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 6。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

private actor DeltaHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct MessagesDeltaRoutingAcceptanceTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test func messagesWithoutQueryRoutesWithNilSinceAndWait() async throws {
        let stub = DeltaHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/messages",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .messages(let id, let since, let wait)? = last?.action else {
            Issue.record("expected messages, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
        #expect(since == nil)
        #expect(wait == nil)
    }

    @Test func sinceQueryIsForwardedOpaquely() async throws {
        let stub = DeltaHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/messages?since=c-000042",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .messages(_, let since, let wait)? = last?.action else {
            Issue.record("expected messages")
            return
        }
        #expect(since == "c-000042")
        #expect(wait == nil)
    }

    @Test func waitQueryIsForwardedAsInteger() async throws {
        let stub = DeltaHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/messages?since=c-1&wait=5",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .messages(_, let since, let wait)? = last?.action else {
            Issue.record("expected messages")
            return
        }
        #expect(since == "c-1")
        #expect(wait == 5)
    }

    @Test func emptySinceReturns400() async throws {
        let stub = DeltaHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/messages?since=",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func nonIntegerWaitReturns400() async throws {
        let stub = DeltaHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/messages?since=c-1&wait=abc",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - Helpers（自己完結）

    private func startServer(stub: DeltaHandlerStub) async throws -> (port: Int, server: ControlServer) {
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
        bearer: String? = nil
    ) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = method
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
