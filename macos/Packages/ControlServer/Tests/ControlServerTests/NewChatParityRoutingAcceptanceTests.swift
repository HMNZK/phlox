import AgentDomain
import Foundation
import Testing
@testable import ControlServer

struct NewChatParityRoutingAcceptanceTests {
    private let projectID = "6C2F0E2A-1111-4222-8333-444455556666"
    private let token = "new-chat-parity-token"

    @Test("完了確認も認証と対象ID・tokenを検証する")
    func completionAcknowledgementIsAuthenticatedAndValidated() async throws {
        let harness = try await harness()
        let path = "/sessions/\(UUID().uuidString)/completion-seen"
        let unauthenticated = try await request(port: harness.port, method: "POST", path: path,
                                                 bearer: nil, body: #"{"completionToken":"exec:1"}"#)
        #expect(unauthenticated.status == 401)
        for body in ["{}", #"{"completionToken":""}"#, #"{"completionToken":42}"#] {
            let response = try await request(port: harness.port, method: "POST", path: path, bearer: token, body: body)
            #expect(response.status == 400)
        }
        let malformedID = try await request(port: harness.port, method: "POST", path: "/sessions/not-a-uuid/completion-seen",
                                              bearer: token, body: #"{"completionToken":"exec:1"}"#)
        #expect(malformedID.status == 400)
        #expect(await harness.handler.callCount == 0)
        let valid = try await request(port: harness.port, method: "POST", path: path,
                                       bearer: token, body: #"{"completionToken":"exec:1"}"#)
        #expect(valid.status == 204)
        #expect(await harness.handler.callCount == 1)
        withExtendedLifetime(harness.server) {}
    }

    @Test("起点と履歴の取得にも認証が必要で、拒否時はハンドラを呼ばない")
    func projectCatalogsRequireAuthentication() async throws {
        let harness = try await harness()
        for suffix in ["start-points", "history?kind=codex"] {
            let response = try await request(port: harness.port, method: "GET",
                                             path: "/projects/\(projectID)/\(suffix)", bearer: nil)
            #expect(response.status == 401)
        }
        #expect(await harness.handler.callCount == 0)
        withExtendedLifetime(harness.server) {}
    }

    @Test("不正なプロジェクトIDとエージェント指定をハンドラ到達前に拒否する")
    func malformedCatalogRequestsAreRejected() async throws {
        let harness = try await harness()
        for path in ["/projects/not-a-uuid/start-points", "/projects/not-a-uuid/history?kind=codex",
                     "/projects/\(projectID)/history?kind=unknown-agent"] {
            let response = try await request(port: harness.port, method: "GET", path: path, bearer: token)
            #expect(response.status == 400)
        }
        #expect(await harness.handler.callCount == 0)
        withExtendedLifetime(harness.server) {}
    }

    @Test("認証済みの起点・履歴取得はControlハンドラへ届く")
    func authorizedCatalogRequestsReachHandler() async throws {
        let harness = try await harness()
        for suffix in ["start-points", "history?kind=claudeCode", "history?kind=codex"] {
            let response = try await request(port: harness.port, method: "GET",
                                             path: "/projects/\(projectID)/\(suffix)", bearer: token)
            #expect(response.status == 204)
        }
        #expect(await harness.handler.callCount == 3)
        withExtendedLifetime(harness.server) {}
    }

    @Test("不正な起動オプションを黙って無視して通常起動しない")
    func malformedSpawnOptionsDoNotFallBackToOrdinarySpawn() async throws {
        let harness = try await harness()
        let invalidOptions = [
            #""usesWorktree":"yes""#,
            #""startPoint":{"kind":"unknown","value":"dev"}"#,
            #""startPoint":{"kind":"commit"}"#,
            #""resumeHistoryID":42"#,
        ]
        for options in invalidOptions {
            let body = #"{"kind":"codex","projectId":"\#(projectID)",\#(options)}"#
            let response = try await request(port: harness.port, method: "POST", path: "/sessions", bearer: token, body: body)
            #expect(response.status == 400)
        }
        #expect(await harness.handler.callCount == 0)
        withExtendedLifetime(harness.server) {}
    }

    @Test("新しい指定をしない従来起動と有効なworktree起動を受け付ける")
    func legacyAndWorktreeSpawnBothReachHandler() async throws {
        let harness = try await harness()
        for body in [#"{"kind":"codex"}"#,
                     #"{"kind":"codex","backend":"appServer","projectId":"\#(projectID)","usesWorktree":true,"startPoint":{"kind":"tag","value":"release/1.0"}}"#] {
            let response = try await request(port: harness.port, method: "POST", path: "/sessions", bearer: token, body: body)
            #expect(response.status == 204)
        }
        #expect(await harness.handler.callCount == 2)
        withExtendedLifetime(harness.server) {}
    }

    private func harness() async throws -> (port: Int, server: ControlServer, handler: ParityRoutingHandler) {
        let tokenStore = SessionTokenStore()
        await tokenStore.register(token, for: SessionID())
        let handler = ParityRoutingHandler()
        let server = ControlServer(tokenStore: tokenStore) { request in await handler.handle(request) }
        return (try await server.start(), server, handler)
    }

    private func request(port: Int, method: String, path: String, bearer: String?, body: String? = nil) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}

private actor ParityRoutingHandler {
    private(set) var callCount = 0
    func handle(_ request: ControlRequest) -> ControlResponse {
        callCount += 1
        return .status(204)
    }
}
