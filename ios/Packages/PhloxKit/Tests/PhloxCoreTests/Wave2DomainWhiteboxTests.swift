import Foundation
import PhloxCore
import Testing

struct Wave2DomainWhiteboxTests {
    private func identity<Value: Identifiable>(of value: Value) -> Value.ID {
        value.id
    }

    @Test("Session の既存初期化は project 情報なしで互換性を保つ")
    func sessionLegacyInitializationRemainsCompatible() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            needsAttention: false,
            subtitle: "repo",
            updatedAt: updatedAt
        )
        let convenienceSession = Session(
            id: "s2",
            name: "Lily",
            agent: .codex,
            status: .idle,
            updatedAt: updatedAt
        )

        #expect(session.projectId == nil)
        #expect(session.projectName == nil)
        #expect(convenienceSession.projectId == nil)
        #expect(convenienceSession.projectName == nil)
        #expect(identity(of: session) == "s1")
        #expect(
            session == Session(
                id: "s1",
                name: "Rose",
                agent: .claudeCode,
                status: .running,
                needsAttention: false,
                subtitle: "repo",
                updatedAt: updatedAt
            )
        )
    }

    @Test("Session は project 情報を保持し Equatable に反映する")
    func sessionProjectFieldsParticipateInEquality() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            projectId: "P-123",
            projectName: "My Repo",
            updatedAt: updatedAt
        )
        let differentProject = Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            projectId: "P-456",
            projectName: "Other Repo",
            updatedAt: updatedAt
        )

        #expect(session.projectId == "P-123")
        #expect(session.projectName == "My Repo")
        #expect(session != differentProject)
    }

    @Test("AgentModels はモデル一覧と既定モデルをデコードする")
    func agentModelsDecodableContract() throws {
        let data = Data(
            #"{"models":[{"id":"opus","displayName":"Opus 4.8"},{"id":"sonnet","displayName":"Sonnet 4.5"}],"defaultModel":"sonnet"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(AgentModels.self, from: data)

        #expect(
            decoded.models == [
                SessionModelOption(id: "opus", displayName: "Opus 4.8"),
                SessionModelOption(id: "sonnet", displayName: "Sonnet 4.5"),
            ]
        )
        #expect(decoded.defaultModel == "sonnet")
    }

    @Test("AgentModels は null の既定モデルを許容する")
    func agentModelsAllowsNullDefaultModel() throws {
        let data = Data(#"{"models":[],"defaultModel":null}"#.utf8)

        let decoded = try JSONDecoder().decode(AgentModels.self, from: data)

        #expect(decoded.models.isEmpty)
        #expect(decoded.defaultModel == nil)
    }

    @Test("CLIUsage は状態・使用量・ISO8601 日付をデコードする")
    func cliUsageDecodableContract() throws {
        let data = Data(
            #"{"kind":"claudeCode","state":"ok","updatedAt":"2026-07-14T09:00:00Z","dataAsOf":"2026-07-14T08:55:00Z","buckets":[{"id":"5h","label":"5-hour","usedPercent":42.0,"resetsAt":"2026-07-14T12:00:00Z"},{"id":"weekly","label":"Weekly","usedPercent":12.5,"resetsAt":null}]}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CLIUsage.self, from: data)

        #expect(decoded.kind == .claudeCode)
        #expect(decoded.state == .ok)
        #expect(decoded.updatedAt == Date(timeIntervalSince1970: 1_784_019_600))
        #expect(decoded.dataAsOf == Date(timeIntervalSince1970: 1_784_019_300))
        #expect(decoded.buckets.count == 2)
        #expect(decoded.buckets[0].id == "5h")
        #expect(decoded.buckets[0].usedPercent == 42.0)
        #expect(decoded.buckets[0].resetsAt == Date(timeIntervalSince1970: 1_784_030_400))
        #expect(decoded.buckets[1].resetsAt == nil)
    }

    @Test("CLIUsage は unavailable と null 日付を許容する")
    func cliUsageAllowsUnavailableAndNullDates() throws {
        let data = Data(
            #"{"kind":"codex","state":"unavailable","updatedAt":null,"dataAsOf":null,"buckets":[]}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CLIUsage.self, from: data)

        #expect(decoded.kind == .codex)
        #expect(decoded.state == .unavailable)
        #expect(decoded.updatedAt == nil)
        #expect(decoded.dataAsOf == nil)
        #expect(decoded.buckets.isEmpty)
    }
}
