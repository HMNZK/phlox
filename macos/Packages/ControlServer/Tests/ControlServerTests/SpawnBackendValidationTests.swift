import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

/// POST /sessions の backend が未知の文字列のとき、silent に .pty へフォールバックせず 400 で拒否する。
/// （省略時の既定 .pty と、明示指定の透過は ControlServerSpawnRoleTests / SpawnWorkingDirectoryAcceptanceTests が守る。）
private actor HandlerStub {
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        callCount += 1
        return .status(200)
    }
}

@Suite struct SpawnBackendValidationTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    /// 未知の文字列も空文字列も「省略」とは別の値として明示送信されたとみなし、不正値(400)として扱う。
    @Test(arguments: ["totally-bogus", ""])
    func postSessionsInvalidBackendReturns400WithoutCallingHandler(backend: String) async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","backend":"\#(backend)"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - Helpers

    private func startServer(
        stub: HandlerStub
    ) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store) { request in
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
