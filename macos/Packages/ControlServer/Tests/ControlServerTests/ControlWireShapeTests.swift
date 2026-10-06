import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// Control API のワイヤ形状: session 一覧（所属 project）・CLI usage（agents/buckets と nullable 日付）・
/// エンコード失敗時の応答。CLI と iOS が読む JSON の形を固定する。
@Suite struct ControlWireShapeTests {
    private let token = "wire-shape-token"
    private let requester = SessionID()

    @Test("session 一覧は所属 project を含み、未所属ではキーを省略する")
    func sessionListProjectWireShape() throws {
        let response = ControlSessionListResponse(sessions: [
            ControlSessionListItem(
                id: "session-1",
                name: "Claude",
                kind: "claudeCode",
                status: "running",
                workspace: "repo",
                projectId: "P-123",
                projectName: "My Repo"
            ),
            ControlSessionListItem(
                id: "session-2",
                name: "Codex",
                kind: "codex",
                status: "idle",
                workspace: "other"
            ),
        ])

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any]
        )
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        #expect(sessions[0]["projectId"] as? String == "P-123")
        #expect(sessions[0]["projectName"] as? String == "My Repo")
        #expect(sessions[1]["projectId"] == nil)
        #expect(sessions[1]["projectName"] == nil)
    }

    @Test("CLI usage は agents/buckets 形と nullable 日付を産出する")
    func cliUsageWireShape() throws {
        let response = ControlCLIUsageResponse(agents: [
            ControlCLIUsageAgent(
                kind: "claudeCode",
                state: "ok",
                updatedAt: "2026-07-14T09:00:00Z",
                dataAsOf: "2026-07-14T08:55:00Z",
                buckets: [
                    ControlCLIUsageBucket(
                        id: "5h",
                        label: "5-hour",
                        usedPercent: 42.0,
                        resetsAt: "2026-07-14T12:00:00Z"
                    ),
                ]
            ),
            ControlCLIUsageAgent(
                kind: "codex",
                state: "unavailable",
                updatedAt: nil,
                dataAsOf: nil,
                buckets: []
            ),
        ])

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any]
        )
        let agents = try #require(object["agents"] as? [[String: Any]])
        let buckets = try #require(agents[0]["buckets"] as? [[String: Any]])
        #expect(agents[0]["state"] as? String == "ok")
        #expect(buckets[0]["id"] as? String == "5h")
        #expect(buckets[0]["usedPercent"] as? Double == 42.0)
        #expect(agents[1]["updatedAt"] is NSNull)
        #expect(agents[1]["dataAsOf"] is NSNull)
        #expect((agents[1]["buckets"] as? [Any])?.isEmpty == true)
    }

    @Test("GET /usage はアカウント単位 usage アクションを配送する")
    func cliUsageEndpointRoutes() async throws {
        let (port, server) = try await startServer { request in
            guard case .cliUsage = request.action else {
                return .status(500)
            }
            return .json(200, ControlCLIUsageResponse(agents: []))
        }
        _ = server

        let response = try await request(port: port, method: "GET", path: "/usage")

        #expect(response.status == 200)
        let object = try #require(
            JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        )
        #expect((object["agents"] as? [Any])?.isEmpty == true)
    }

    /// ControlResponse.json(_:_:) がエンコード失敗を握りつぶして 200 + 空 body を返さず、500 にする。
    @Test func jsonEncodingFailureReturns500() {
        struct FailingEncodable: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    0,
                    EncodingError.Context(codingPath: [], debugDescription: "boom")
                )
            }
        }
        let response = ControlResponse.json(200, FailingEncodable())
        #expect(response.statusCode == 500)
    }

    private func startServer(
        handler: @escaping @Sendable (ControlRequest) async -> ControlResponse
    ) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: requester)
        let server = ControlServer(tokenStore: store, handler: handler)
        return (try await server.start(), server)
    }

    private func request(
        port: Int,
        method: String,
        path: String
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}
