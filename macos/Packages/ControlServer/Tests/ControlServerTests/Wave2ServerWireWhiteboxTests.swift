import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor Wave2RequestRecorder {
    private(set) var spawnModels: [String?] = []
    private(set) var modelApplications: [(sessionID: SessionID, model: String)] = []

    func handle(_ request: ControlRequest) -> ControlResponse {
        guard case .spawn = request.action else {
            return .status(200)
        }
        spawnModels.append(ControlSpawnContext.model)
        return .json(201, Wave2SpawnResponse(id: UUID().uuidString))
    }

    func apply(model: String, to sessionID: SessionID) -> Bool {
        modelApplications.append((sessionID, model))
        return true
    }
}

private struct Wave2SpawnResponse: Encodable {
    let id: String
}

@Suite struct Wave2ServerWireWhiteboxTests {
    private let token = "wave-2-token"
    private let requester = SessionID()

    @Test("spawn は model の有無を保持し、どちらも 201 を返せる")
    func spawnCarriesOptionalModel() async throws {
        let recorder = Wave2RequestRecorder()
        let (port, server) = try await startServer { request in
            await recorder.handle(request)
        }
        _ = server

        let withModel = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer","model":"opus"}"#
        )
        let withoutModel = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer"}"#
        )
        let invalidModel = try await request(
            port: port,
            method: "POST",
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer","model":"not-a-model"}"#
        )

        #expect(withModel.status == 201)
        #expect(withoutModel.status == 201)
        #expect(invalidModel.status == 201)
        let models = await recorder.spawnModels
        #expect(models.count == 3)
        #expect(models[0] == "opus")
        #expect(models[1] == nil)
        #expect(models[2] == nil)
    }

    @Test("spawn 後のモデル適用は生成済み session ID を対象にする")
    func spawnedSessionModelApplicationTargetsSpawnedSession() async {
        let recorder = Wave2RequestRecorder()
        let spawnedID = SessionID()

        let result = await ControlSpawnModelApplier.apply("opus", to: spawnedID) { model, sessionID in
            await recorder.apply(model: model, to: sessionID)
        }

        #expect(result == true)
        let applications = await recorder.modelApplications
        #expect(applications.count == 1)
        #expect(applications[0].sessionID == spawnedID)
        #expect(applications[0].model == "opus")
    }

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

    @Test("agent models は既知 kind を配送し未知 kind を 404 にする")
    func agentModelsRoutingAndUnknownKind() async throws {
        let (port, server) = try await startServer { request in
            guard case let .agentModels(kind) = request.action else {
                return .status(500)
            }
            return .json(200, ControlAgentModelsResponse(
                models: AgentModelCatalog.models(for: kind),
                defaultModel: AgentModelCatalog.defaultModel(for: kind)
            ))
        }
        _ = server

        let known = try await request(port: port, method: "GET", path: "/agents/claudeCode/models")
        let unknown = try await request(port: port, method: "GET", path: "/agents/unknown/models")

        #expect(known.status == 200)
        let knownObject = try #require(
            JSONSerialization.jsonObject(with: known.body) as? [String: Any]
        )
        #expect((knownObject["models"] as? [[String: Any]])?.isEmpty == false)
        #expect(knownObject["defaultModel"] is String)
        #expect(unknown.status == 404)
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
        path: String,
        body: String? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}
