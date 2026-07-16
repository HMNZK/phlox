import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// task-1 受け入れテスト（PM 著・凍結。アサーションの変更は禁止。ハーネス欠陥を
/// 発見した場合は PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
///
/// 契約: POST /sessions の body に省略可能な `workingDirectory`（文字列）を追加する。
/// パース層は値を検証せず **そのまま** `Action.spawn(ref:backend:workingDirectory:)` に
/// 載せる（検証は AppBootstrap のハンドラ層が単一の関所として行う）。
/// 省略時は nil（現行挙動の維持）。kind 必須は従来どおり。
private actor WDHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct SpawnWorkingDirectoryAcceptanceTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test func postSessionsCarriesWorkingDirectoryVerbatim() async throws {
        let stub = WDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        // パース層は存在検証をしない（不存在パスでもそのまま運ぶ）ことも本契約に含む。
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"cursor","workingDirectory":"/nonexistent/parse-layer-does-not-validate"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(let ref, _, let workingDirectory)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(ref == .builtin(.cursor))
        #expect(workingDirectory == "/nonexistent/parse-layer-does-not-validate")
    }

    @Test func postSessionsWithoutWorkingDirectoryYieldsNil() async throws {
        let stub = WDHandlerStub()
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
        guard case .spawn(_, _, let workingDirectory)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(workingDirectory == nil)
    }

    @Test func postSessionsCarriesBackendAndWorkingDirectoryTogether() async throws {
        let stub = WDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"codex","backend":"appServer","workingDirectory":"/tmp"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(_, let backend, let workingDirectory)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(backend == .appServer)
        #expect(workingDirectory == "/tmp")
    }

    @Test func postSessionsMissingKindStillRejected400() async throws {
        let stub = WDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"workingDirectory":"/tmp"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - harness（ControlServerIntegrationTests と同形の最小複製）

    private func startServer(stub: WDHandlerStub) async throws -> (port: Int, server: ControlServer) {
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
