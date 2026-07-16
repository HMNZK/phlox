import Testing
import Foundation
import AgentDomain
import PhloxCore
@testable import PhloxNetworking

/// task-2 受け入れテスト（PM 著・実装役は編集禁止）。
/// 越境シーム（docs/agent-output/wire-contract.md）の consumer 側デコード契約。
/// task-1 が産出する新規ワイヤ（GET /agents/{kind}/models・GET /usage）の JSON を
/// iOS ドメイン型へ過不足なくデコードできることを凍結する。両側が同一の JSON リテラルに
/// 対して検証することでワイヤのドリフトを防ぐ。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
struct Wave2WireDecodeContractTests {

    @Test("GET /agents/{kind}/models の JSON を AgentModels へデコードする")
    func decodesAgentModels() throws {
        let json = """
        {"models":[{"id":"opus","displayName":"Opus 4.8"},{"id":"sonnet","displayName":"Sonnet 4.5"}],"defaultModel":"sonnet"}
        """
        let models = try JSONDecoder().decode(AgentModels.self, from: Data(json.utf8))
        #expect(models.models.count == 2)
        #expect(models.models.first?.id == "opus")
        #expect(models.models.first?.displayName == "Opus 4.8")
        #expect(models.defaultModel == "sonnet")
    }

    @Test("空カタログ（codex 相当）の JSON をデコードする")
    func decodesEmptyAgentModels() throws {
        let json = #"{"models":[],"defaultModel":null}"#
        let models = try JSONDecoder().decode(AgentModels.self, from: Data(json.utf8))
        #expect(models.models.isEmpty)
        #expect(models.defaultModel == nil)
    }

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
