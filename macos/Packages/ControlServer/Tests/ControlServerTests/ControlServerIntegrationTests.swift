import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

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

    var wasCalled: Bool {
        callCount > 0
    }
}

@Suite struct ControlServerIntegrationTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test func listSessionsWithValidBearer() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        if case .listSessions? = last?.action {
        } else {
            Issue.record("expected listSessions, got \(String(describing: last?.action))")
        }
    }

    @Test func missingBearerReturns401WithoutCallingHandler() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(port: port, method: "GET", path: "/sessions")
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    @Test func invalidBearerReturns401WithoutCallingHandler() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions",
            bearer: "unknown-token"
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    @Test func postSendToName() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"agent-alpha","text":"hello","submit":false}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/send",
            bearer: token,
            body: body
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        guard case .sendText(let to, let text, let submit, let inReplyTo, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(to == .name("agent-alpha"))
        #expect(text == "hello")
        #expect(submit == false)
        #expect(inReplyTo == nil)
        #expect(images.isEmpty)
    }

    @Test func postSendToSessionID() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"\(targetID.rawValue.uuidString)","text":"ping"}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/send",
            bearer: token,
            body: body
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(let to, let text, let submit, let inReplyTo, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(to == .id(targetID))
        #expect(text == "ping")
        #expect(submit == true)
        #expect(inReplyTo == nil)
        #expect(images.isEmpty)
    }

    @Test func postSendWithValidInReplyTo() async throws {
        let replyID = UUID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"agent-alpha","text":"hello","inReplyTo":"\(replyID.uuidString)"}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/send",
            bearer: token,
            body: body
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, _, let inReplyTo, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(inReplyTo == replyID)
        #expect(images.isEmpty)
    }

    @Test func postSendInvalidInReplyToReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/send",
            bearer: token,
            body: #"{"to":"agent-alpha","text":"hello","inReplyTo":"not-a-uuid"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postSendInvalidJSONReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/send",
            bearer: token,
            body: "{not json"
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postSessionsSpawnBuiltinKindResolvesBuiltinRef() async throws {
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
        guard case .spawn(let ref, _, _)? = last?.action else {
            Issue.record("expected spawn")
            return
        }
        #expect(ref == .builtin(.cursor))
    }

    @Test func postSessionsSpawnCustomKindResolvesCustomRef() async throws {
        let custom = makeCustomDescriptor(id: "aider")
        let stub = HandlerStub()
        let (port, server) = try await startServer(
            stub: stub,
            agentCatalog: AgentCatalog(customDescriptors: [custom])
        )
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"aider"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .spawn(let ref, _, _)? = last?.action else {
            Issue.record("expected spawn")
            return
        }
        #expect(ref == .custom("aider"))
    }

    @Test func postSessionsInvalidKindReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            bearer: token,
            body: #"{"kind":"unknown-agent"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func deleteSessionByID() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "DELETE",
            path: "/sessions/\(targetID.rawValue.uuidString)",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .remove(let id)? = last?.action else {
            Issue.record("expected remove")
            return
        }
        #expect(id == targetID)
    }

    @Test func deleteSessionInvalidPathsReturn400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server

        let badPaths = [
            "/sessions/",
            "/sessions/not-a-uuid",
            "/sessions",
            "/sessions/\(sessionID.rawValue.uuidString)/extra",
            "/sessions/\(sessionID.rawValue.uuidString)?foo=bar",
        ]

        for path in badPaths {
            let status = try await request(
                port: port,
                method: "DELETE",
                path: path,
                bearer: token
            )
            #expect(status == 400, "path \(path) should be 400")
        }
        #expect(await stub.callCount == 0)
    }

    @Test func patchSessionRename() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "PATCH",
            path: "/sessions/\(targetID.rawValue.uuidString)",
            bearer: token,
            body: #"{"name":"Backend"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .rename(let id, let name)? = last?.action else {
            Issue.record("expected rename")
            return
        }
        #expect(id == targetID)
        #expect(name == "Backend")
    }

    @Test func patchSessionRenameInvalidBodyReturns400() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "PATCH",
            path: "/sessions/\(targetID.rawValue.uuidString)",
            bearer: token,
            body: #"{"title":"Backend"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionOutputDefaultsToScreenMode() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/output",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .output(let id, let mode)? = last?.action else {
            Issue.record("expected output")
            return
        }
        #expect(id == targetID)
        #expect(mode == .screen)
    }

    @Test func getSessionOutputParsesScrollbackMode() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/output?mode=scrollback",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .output(let id, let mode)? = last?.action else {
            Issue.record("expected output")
            return
        }
        #expect(id == targetID)
        #expect(mode == .scrollback)
    }

    @Test func getSessionMessagesRoutesToMessagesAction() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/messages",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .messages(let id, let since, let wait)? = last?.action else {
            Issue.record("expected messages")
            return
        }
        #expect(id == targetID)
        #expect(since == nil)
        #expect(wait == nil)
    }

    @Test func getSessionReadyDefaultsToTenSecondTimeout() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/ready",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .waitReady(let id, let timeoutSeconds)? = last?.action else {
            Issue.record("expected waitReady")
            return
        }
        #expect(id == targetID)
        #expect(timeoutSeconds == 10)
    }

    @Test func getSessionReadyParsesTimeoutQuery() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/ready?timeout=5",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .waitReady(let id, let timeoutSeconds)? = last?.action else {
            Issue.record("expected waitReady")
            return
        }
        #expect(id == targetID)
        #expect(timeoutSeconds == 5)
    }

    @Test func getSessionReadyInvalidUUIDReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/not-a-uuid/ready",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionReadyInvalidTimeoutReturns400() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/ready?timeout=abc",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionWaitParsesTimeoutQuery() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/wait?timeout=300",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .wait(let id, let timeoutSeconds, let sentinel)? = last?.action else {
            Issue.record("expected wait")
            return
        }
        #expect(id == targetID)
        #expect(timeoutSeconds == 300)
        #expect(sentinel == nil)
    }

    @Test func getSessionWaitMissingTimeoutReturns400() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/wait",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionWaitInvalidTimeoutReturns400() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/wait?timeout=abc",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionWaitParsesSentinelQuery() async throws {
        let targetID = SessionID()
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/\(targetID.rawValue.uuidString)/wait?timeout=300&sentinel=%3C%3CDONE%3E%3E",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .wait(_, _, let sentinel)? = last?.action else {
            Issue.record("expected wait")
            return
        }
        #expect(sentinel == "<<DONE>>")
    }

    @Test func getSessionWaitInvalidUUIDReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/not-a-uuid/wait?timeout=300",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func getSessionOutputInvalidUUIDReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/sessions/not-a-uuid/output",
            bearer: token
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - GET /approvals

    @Test func getApprovalsWithValidBearerRoutesToListApprovals() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/approvals",
            bearer: token
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        if case .listApprovals? = last?.action {
        } else {
            Issue.record("expected listApprovals, got \(String(describing: last?.action))")
        }
    }

    @Test func getApprovalsWithoutBearerReturns401() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/approvals"
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    // MARK: - POST /approvals/{id}

    @Test func postApprovalWithValidDecisionRoutesToRespondApproval() async throws {
        let approvalID = "approval-abc"
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/approvals/\(approvalID)",
            bearer: token,
            body: #"{"decision":"accept"}"#
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        guard case .respondApproval(let id, let decision)? = last?.action else {
            Issue.record("expected respondApproval, got \(String(describing: last?.action))")
            return
        }
        #expect(id == approvalID)
        #expect(decision == .accept)
    }

    @Test(arguments: ["accept", "decline", "acceptForSession", "cancel"])
    func postApprovalParsesAllFourDecisionValues(decisionString: String) async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/approvals/some-id",
            bearer: token,
            body: "{\"decision\":\"\(decisionString)\"}"
        )
        #expect(status == 200)
        #expect(await stub.callCount == 1)
    }

    @Test func postApprovalWithoutBearerReturns401() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/approvals/some-id",
            body: #"{"decision":"accept"}"#
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    @Test func postApprovalInvalidDecisionReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/approvals/some-id",
            bearer: token,
            body: #"{"decision":"invalid-decision"}"#
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postApprovalMissingBodyReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/approvals/some-id",
            bearer: token,
            body: "{}"
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func unknownPathReturns404() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "GET",
            path: "/unknown",
            bearer: token
        )
        #expect(status == 404)
        #expect(await stub.callCount == 0)
    }

    @Test func postSendBodyExceedingMaxLengthReturns413() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        // ControlServer は Content-Length ヘッダだけで上限超過を判定し、本文を1バイトも読まずに
        // 即 413 を返して接続を閉じる（CWE-400 準拠・正しい挙動。上限は契約5 /send images のため
        // 16MiB = ControlServer.maxRequestBodyLength）。したがって上限を超過する Content-Length を
        // 宣言すれば本文の実サイズに依らず 413 になる。
        //
        // 実本文を 16MiB 積むと、サーバが未読のまま接続を閉じる際に abortive close（RST）となり、
        // クライアントがバッファ済みの 413 を読む前に RST が到達して 413 が破棄され ECONNRESET で
        // 落ちる（実装ではなくテスト送信機構起因のフレーク）。サーバが本文を読まない設計に合わせ、
        // 超過長のみ宣言して本文は最小にし、graceful close 下で 413 を決定的に観測する。
        // 併せて POST /send ルートで transport がハンドラ到達前に上限超過を弾く（callCount==0）ことを検証する。
        let raw = "POST /send HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Authorization: Bearer \(token)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(ControlServer.maxRequestBodyLength + 1)\r\n"
            + "\r\n"
            + "{}"
        let status = try await rawRequest(port: port, Data(raw.utf8))
        #expect(status == 413)
        #expect(await stub.callCount == 0)
    }

    @Test func hugeContentLengthWithSmallBodyReturns413() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let raw = "POST /send HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Authorization: Bearer \(token)\r\n"
            + "Content-Length: \(ControlServer.maxRequestBodyLength + 1)\r\n"
            + "\r\n"
            + "{}"
        let status = try await rawRequest(port: port, Data(raw.utf8))
        #expect(status == 413)
        #expect(await stub.callCount == 0)
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

    private func makeCustomDescriptor(id: String) -> AgentDescriptor {
        AgentDescriptor(
            ref: .custom(id),
            displayName: "Aider",
            binaryName: "aider",
            symbolName: "wrench.and.screwdriver",
            colorRGB: AgentRGB(0xE5, 0xA5, 0x3F),
            bypassKey: "phlox.bypass.\(id)",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
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

    /// URLSession では送れない生の HTTP バイト列を送り、レスポンスのステータスコードを返す。
    private func rawRequest(port: Int, _ requestData: Data) async throws -> Int {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        defer { connection.cancel() }
        connection.start(queue: DispatchQueue(label: "rawRequest"))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: requestData, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }

        let statusLine = String(decoding: responseData.prefix(16), as: UTF8.self)
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else {
            return -1
        }
        return status
    }
}
