import AgentDomain
import Testing
@testable import ControlServer

@Suite("Live model catalog white-box tests", .serialized)
struct LiveModelCatalogWhiteboxTests {
    @Test("TTL 内は provider を再起動せずキャッシュした一覧を返す")
    func cacheAvoidsRepeatedProviderCallsBeforeTTLExpires() async throws {
        let source = CountingProvider()
        let cache = CachingAgentModelProvider(source: source, ttl: 60)

        _ = try await cache.fetchModels(for: .claudeCode)
        _ = try await cache.fetchModels(for: .claudeCode)

        #expect(await source.calls == 1)
    }

    @Test("Claude parser は CLI が提示した特殊 alias をそのまま保持する")
    func claudeParserKeepsCLIProvidedSpecialAliases() {
        let result = "Usage: /model <name>. Available: default, opusplan, haiku[1m], or a full model ID."
        #expect(ClaudeModelListParser.parse(resultText: result) == ["default", "opusplan", "haiku[1m]"])
    }
}

private actor CountingProvider: AgentModelListProviding {
    private(set) var calls = 0

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        calls += 1
        return [ControlModelOption(id: "model-\(calls)", displayName: "model")]
    }
}
