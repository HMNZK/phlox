import Foundation
import Testing
import AgentDomain
import PhloxCore
@testable import PhloxNetworking

/// project 情報・エージェント別モデル一覧（GET /agents/{kind}/models）・CLI 使用量（GET /usage）の
/// ワイヤ解釈と API クライアント配線。
@Suite("Project / agent catalog / usage client", .serialized)
struct ProjectCatalogUsageClientTests {
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    private func makeClient() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogStubURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }

    @Test("SessionDTO の project 情報を Session へ写す")
    func sessionDTOMapsProjectFields() throws {
        let data = Data("""
        {"id":"s1","name":"Rose","kind":"claudeCode","status":"running","workspace":"repo","projectId":"P-123","projectName":"My Repo"}
        """.utf8)

        let dto = try JSONDecoder().decode(SessionDTO.self, from: data)
        let session = try #require(dto.toDomain(now: Date(timeIntervalSince1970: 0)))

        #expect(session.projectId == "P-123")
        #expect(session.projectName == "My Repo")
    }

    @Test("SessionDTO は project キー省略を nil として許容する")
    func sessionDTOAllowsMissingProjectFields() throws {
        let data = Data("""
        {"id":"s1","name":"Rose","kind":"claudeCode","status":"running","workspace":"repo"}
        """.utf8)

        let dto = try JSONDecoder().decode(SessionDTO.self, from: data)
        let session = try #require(dto.toDomain(now: Date(timeIntervalSince1970: 0)))

        #expect(session.projectId == nil)
        #expect(session.projectName == nil)
    }

    @Test("agentModels は kind を path に載せてモデル一覧をデコードする")
    func agentModelsUsesExpectedPathAndDecodes() async throws {
        CatalogStubURLProtocol.reset()
        CatalogStubURLProtocol.outcomes = [
            .status(
                200,
                Data(#"{"models":[{"id":"opus","displayName":"Opus 4.8"}],"defaultModel":"opus"}"#.utf8),
                [:]
            ),
        ]

        let result = try await makeClient().agentModels(kind: .claudeCode)

        #expect(CatalogStubURLProtocol.lastRequest?.url?.path == "/agents/claudeCode/models")
        #expect(CatalogStubURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(result.models == [SessionModelOption(id: "opus", displayName: "Opus 4.8")])
        #expect(result.defaultModel == "opus")
    }

    @Test("cliUsage は /usage の ISO8601 日付をデコードする")
    func cliUsageUsesExpectedPathAndISO8601Decoder() async throws {
        CatalogStubURLProtocol.reset()
        CatalogStubURLProtocol.outcomes = [
            .status(
                200,
                Data("""
                {"agents":[{"kind":"claudeCode","state":"ok","updatedAt":"2026-07-14T09:00:00Z","dataAsOf":null,"buckets":[{"id":"5h","label":"5-hour","usedPercent":42.5,"resetsAt":"2026-07-14T12:00:00Z"}]}]}
                """.utf8),
                [:]
            ),
        ]

        let result = try await makeClient().cliUsage()

        #expect(CatalogStubURLProtocol.lastRequest?.url?.path == "/usage")
        #expect(CatalogStubURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(result.count == 1)
        #expect(result[0].kind == .claudeCode)
        #expect(result[0].state == .ok)
        #expect(result[0].updatedAt != nil)
        #expect(result[0].dataAsOf == nil)
        #expect(result[0].buckets[0].id == "5h")
        #expect(result[0].buckets[0].label == "5-hour")
        #expect(result[0].buckets[0].usedPercent == 42.5)
        #expect(result[0].buckets[0].resetsAt != nil)
    }

    /// 越境シーム（docs/agent-output/wire-contract.md）の consumer 側デコード契約。
    @Test("GET /usage の JSON を CLIUsageResponse へデコードする（state/buckets/日付/null）")
    func decodesCLIUsage() throws {
        let json = """
        {"agents":[\
        {"kind":"claudeCode","state":"ok","updatedAt":"2026-07-14T09:00:00Z","dataAsOf":"2026-07-14T08:55:00Z",\
        "buckets":[{"id":"5h","label":"5-hour","usedPercent":42.0,"resetsAt":"2026-07-14T12:00:00Z"},\
        {"id":"weekly","label":"Weekly","usedPercent":12.5,"resetsAt":null}]},\
        {"kind":"codex","state":"unavailable","updatedAt":null,"dataAsOf":null,"buckets":[]}\
        ]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(CLIUsageResponse.self, from: Data(json.utf8))

        #expect(resp.agents.count == 2)

        let claude = resp.agents[0]
        #expect(claude.kind == .claudeCode)
        #expect(claude.state == .ok)
        #expect(claude.buckets.count == 2)
        #expect(claude.buckets[0].id == "5h")
        #expect(claude.buckets[0].usedPercent == 42.0)
        #expect(claude.buckets[0].resetsAt != nil)
        #expect(claude.buckets[1].resetsAt == nil)

        let codex = resp.agents[1]
        #expect(codex.kind == .codex)
        #expect(codex.state == .unavailable)
        #expect(codex.buckets.isEmpty)
    }
}

private enum CatalogStubOutcome {
    case status(Int, Data, [String: String])
}

private final class CatalogStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var outcomes: [CatalogStubOutcome] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        outcomes = []
        requestCount = 0
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = min(Self.requestCount, Self.outcomes.count - 1)
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastRequestBody = request.readBodyForTesting()

        guard index >= 0, Self.outcomes.indices.contains(index) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch Self.outcomes[index] {
        case let .status(code, data, headers):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
