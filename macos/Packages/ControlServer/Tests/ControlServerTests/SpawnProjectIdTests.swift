import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// 契約（wire-contract.md §1・§2）: POST /sessions の body に省略可能な `projectId` を
/// 追加する。パース層は UUID 形式だけを検証し、成功時のみ `ProjectID` にして
/// `Action.spawn(ref:backend:workingDirectory:projectID:initialSettings:)` に載せる。
/// UUID として parse できない値は 400 で spawn 自体を行わない（存在検査はハンドラ層の責務）。
private actor ProjectIDHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct SpawnProjectIdTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test("projectId が UUID なら ProjectID として Action.spawn に載る")
    func postSessionsCarriesProjectIdAsProjectID() async throws {
        let uuid = UUID()
        let stub = ProjectIDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"codex","backend":"appServer","projectId":"\#(uuid.uuidString)"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(let ref, let backend, _, let projectID, _)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(ref == .builtin(.codex))
        #expect(backend == .appServer)
        #expect(projectID == ProjectID(rawValue: uuid))
    }

    @Test("画面の起動メニューをなくしても、組込ハーネスの Control API から PTY セッションを作れる")
    func postSessionsWithPTYKeepsBuiltInTerminalSpawn() async throws {
        let stub = ProjectIDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"claudeCode","backend":"pty"}"#
        )

        #expect(status == 200)
        guard case .spawn(let ref, let backend, _, _, _)? = await stub.lastRequest?.action else {
            Issue.record("expected PTY spawn request")
            return
        }
        #expect(ref == .builtin(.claudeCode))
        #expect(backend == .pty)
    }

    @Test("projectId 省略時は projectID が nil（後方互換）")
    func postSessionsWithoutProjectIdYieldsNil() async throws {
        let stub = ProjectIDHandlerStub()
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
        guard case .spawn(_, _, _, let projectID, _)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(projectID == nil)
    }

    @Test("projectId と workingDirectory は同時に運べる（優先順位はハンドラ層の責務）")
    func postSessionsCarriesProjectIdAndWorkingDirectoryTogether() async throws {
        let uuid = UUID()
        let stub = ProjectIDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"codex","workingDirectory":"/tmp","projectId":"\#(uuid.uuidString)"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(_, _, let workingDirectory, let projectID, _)? = last?.action else {
            Issue.record("expected spawn, got \(String(describing: last?.action))")
            return
        }
        #expect(workingDirectory == "/tmp")
        #expect(projectID == ProjectID(rawValue: uuid))
    }

    @Test(arguments: ["My Repo", ""])
    func malformedProjectIdReturns400WithContractErrorBody(projectId: String) async throws {
        let stub = ProjectIDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let response = try await postSessions(
            port: port,
            body: #"{"kind":"codex","projectId":"\#(projectId)"}"#
        )

        #expect(response.status == 400)
        let json = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(json["error"] as? String == "invalid projectId")
        #expect(await stub.callCount == 0)
    }

    @Test("組込でない kind は 400 で拒否し spawn しない")
    func unknownAgentKindReturns400() async throws {
        let stub = ProjectIDHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let response = try await postSessions(
            port: port,
            body: #"{"kind":"aider"}"#
        )

        #expect(response.status == 400)
        let json = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(json["error"] as? String == "unknown agent kind: aider")
        #expect(await stub.callCount == 0)
    }

    // MARK: - harness

    private func startServer(
        stub: ProjectIDHandlerStub
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

    private func postSessions(port: Int, body: String) async throws -> (status: Int, body: Data) {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sessions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}
