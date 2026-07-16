import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

// task-1 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 1〜4。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

private actor MobileHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0
    let response: ControlResponse

    init(response: ControlResponse = .status(200)) {
        self.response = response
    }

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return response
    }
}

@Suite struct MobileControlRoutingAcceptanceTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    // MARK: - 契約1 POST /sessions/{id}/interrupt

    @Test func interruptRoutesToInterruptAction() async throws {
        let stub = MobileHandlerStub(response: .status(204))
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)/interrupt",
            bearer: token
        )
        #expect(status == 204)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        guard case .interrupt(let id)? = last?.action else {
            Issue.record("expected interrupt, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
    }

    @Test func interruptWithQueryReturns404WithoutCallingHandler() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)/interrupt?force=1",
            bearer: token
        )
        #expect(status == 404)
        #expect(await stub.callCount == 0)
    }

    @Test func interruptWithInvalidUUIDReturns400() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions/not-a-uuid/interrupt",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func interruptWithoutBearerReturns401() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions/\(target.rawValue.uuidString)/interrupt"
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    // MARK: - 契約2 GET /sessions/{id}/subagents

    @Test func subAgentsRoutesToSubAgentsAction() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/subagents",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .subAgents(let id)? = last?.action else {
            Issue.record("expected subAgents, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
    }

    @Test func subAgentsWithInvalidUUIDReturns400() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/nope/subagents",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - 契約3 GET /sessions/{id}/subagents/{subAgentId}/messages

    @Test func subAgentMessagesRoutesWithOpaqueId() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/subagents/sa-1/messages",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .subAgentMessages(let id, let subAgentID)? = last?.action else {
            Issue.record("expected subAgentMessages, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
        #expect(subAgentID == "sa-1")
    }

    @Test func subAgentMessagesPercentDecodesSubAgentId() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/subagents/sa%201/messages",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .subAgentMessages(_, let subAgentID)? = last?.action else {
            Issue.record("expected subAgentMessages, got \(String(describing: last?.action))")
            return
        }
        #expect(subAgentID == "sa 1")
    }

    @Test func subAgentMessagesWithEmptySubAgentIdReturns404() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/subagents//messages",
            bearer: token
        )
        #expect(status == 404)
        #expect(await stub.callCount == 0)
    }

    @Test func fiveSegmentSubagentsPathReturns404() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/subagents/messages",
            bearer: token
        )
        // 5 セグメント（subAgentId が "messages" 扱いになる 6 セグメント形ではない）は
        // 「/subagents/{subAgentId}/messages」に一致しない → subAgentId="messages" の
        // 4+1 形ではなく、末尾 "messages" 欠落の不完全パスなので 404。
        #expect(status == 404)
        #expect(await stub.callCount == 0)
    }

    // MARK: - 契約4 GET /sessions/{id}/usage

    @Test func usageRoutesToUsageAction() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/usage",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .usage(let id)? = last?.action else {
            Issue.record("expected usage, got \(String(describing: last?.action))")
            return
        }
        #expect(id == target)
    }

    @Test func usageWithoutBearerReturns401() async throws {
        let stub = MobileHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let target = SessionID()
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(target.rawValue.uuidString)/usage"
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    // MARK: - Helpers（ControlServerIntegrationTests と同流儀の自己完結コピー）

    private func startServer(stub: MobileHandlerStub) async throws -> (port: Int, server: ControlServer) {
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
