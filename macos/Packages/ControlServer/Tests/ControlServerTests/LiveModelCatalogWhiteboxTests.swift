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

    @Test("cursor-agent models の実形式から ID を取り出す")
    func cursorParserHandlesCLIOutput() {
        let output = """
        Available models

        auto - Auto (default)
        gpt-5.3-codex-low - GPT-5.3 Codex Low
        composer-2.5 - Composer 2.5 (current)
        """
        #expect(CursorModelListParser.parse(output) == ["auto", "gpt-5.3-codex-low", "composer-2.5"])
    }

    @Test("Cursor parser はヘッダ、空行、不正行を除外する")
    func cursorParserExcludesHeaderBlankAndMalformedLines() {
        let output = "Available models\n\nauto - Auto\n\ngarbage-line-without-separator\n - missing-id\ngpt-5.3-codex - GPT-5.3 Codex\n"
        #expect(CursorModelListParser.parse(output) == ["auto", "gpt-5.3-codex"])
    }

    @Test("Cursor parser は空出力で空を返す")
    func cursorParserReturnsEmptyForEmptyOutput() {
        #expect(CursorModelListParser.parse("").isEmpty)
    }

    @Test("Cursor provider は models サブコマンドを使い、パース結果を返す")
    func cursorProviderRunsModelsSubcommandAndReturnsParsedIDs() async throws {
        let calls = CommandCalls()
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { command, arguments in
                await calls.record(command: command, arguments: arguments)
                return "Available models\n\nauto - Auto (default)\ncomposer-2.5 - Composer 2.5 (current)\n"
            }
        )

        let models = try await provider.fetchModels(for: .cursor)

        #expect(models.map(\.id) == ["auto", "composer-2.5"])
        #expect(await calls.arguments == [["models"]])
    }

    @Test("CLI 子プロセスには PATH だけでなく HOME を渡す（cursor-agent は HOME 必須）")
    func childEnvironmentAlwaysCarriesRequiredVariables() {
        let environment = LiveAgentModelProvider.childEnvironment(base: ["PATH": "/usr/bin:/bin"])
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(!(environment["HOME"] ?? "").isEmpty)
        #expect(!(environment["USER"] ?? "").isEmpty)
        #expect(!(environment["LANG"] ?? "").isEmpty)
    }
}

private actor CountingProvider: AgentModelListProviding {
    private(set) var calls = 0

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        calls += 1
        return [ControlModelOption(id: "model-\(calls)", displayName: "model")]
    }
}

private actor CommandCalls {
    private(set) var arguments: [[String]] = []

    func record(command _: String, arguments: [String]) {
        self.arguments.append(arguments)
    }
}
