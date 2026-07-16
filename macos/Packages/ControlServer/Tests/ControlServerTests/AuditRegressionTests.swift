import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

/// task-4 の監査回帰テスト。
/// - I5: parseSpawn の backend が未知文字列のとき silent に .pty へフォールバックしていた
///   → 未知文字列は 400、省略時のみ既定 .pty。
/// - nit: ControlResponse.json(_:_:) がエンコード失敗を `try?` で握り 200 + 空 body を返していた
///   → エンコード失敗時は 500。
private actor HandlerStub {
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

@Suite struct AuditRegressionTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    // MARK: - I5: backend 不正値は 400（silent fallback しない）

    @Test func postSessionsOmittedBackendDefaultsToPty() async throws {
        let stub = HandlerStub()
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

        let last = await stub.lastRequest
        guard case .spawn(_, let backend, _)? = last?.action else {
            Issue.record("expected spawn")
            return
        }
        #expect(backend == .pty)
    }

    @Test func postSessionsExplicitKnownBackendIsUsed() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","backend":"appServer"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(_, let backend, _)? = last?.action else {
            Issue.record("expected spawn")
            return
        }
        #expect(backend == .appServer)
    }

    @Test func postSessionsUnknownBackendReturns400WithoutCallingHandler() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","backend":"totally-bogus"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    /// 空文字列は「省略」とは別の値として明示送信されたとみなし、不正値(400)として扱う。
    @Test func postSessionsEmptyStringBackendReturns400WithoutCallingHandler() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","backend":""}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - nit: エンコード失敗は 500（200 + 空 body にしない）

    private struct FailingEncodable: Encodable {
        func encode(to encoder: Encoder) throws {
            throw EncodingError.invalidValue(
                0,
                EncodingError.Context(codingPath: [], debugDescription: "boom")
            )
        }
    }

    @Test func jsonEncodingFailureReturns500() {
        let response = ControlResponse.json(200, FailingEncodable())
        #expect(response.statusCode == 500)
    }

    // MARK: - Helpers

    private func startServer(
        stub: HandlerStub,
        agentCatalog: AgentCatalog = .builtins
    ) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store, agentCatalog: agentCatalog) { request in
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
