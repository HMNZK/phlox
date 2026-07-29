import AgentDomain
import Foundation
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

    @Test("Claude parser は Current model 行から表示名を取り出し effort を落とす")
    func claudeParserExtractsCurrentModelName() {
        #expect(
            ClaudeModelListParser.parseCurrentModelName(
                resultText: "Current model: Opus 5 (1M context) (effort: xhigh)\nUsage: /model <name>."
            ) == "Opus 5 (1M context)"
        )
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "Current model: Sonnet 5") == "Sonnet 5")
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "command not found: claude") == nil)
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "Current model:   (effort: high)") == nil)
    }

    @Test("Claude provider は alias ごとに CLI へ表示名を問い合わせる")
    func claudeProviderResolvesDisplayNamesFromCLI() async throws {
        let calls = CommandCalls()
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { command, arguments in
                await calls.record(command: command, arguments: arguments)
                guard let index = arguments.firstIndex(of: "--model") else {
                    return claudeModelJSON(
                        "Current model: Opus 5 (effort: xhigh)\n"
                            + "Usage: /model <name>. Available: opus, haiku, opusplan, or a full model ID."
                    )
                }
                let names = [
                    "opus": "Opus 5 (1M context)",
                    "haiku": "Haiku 4.5",
                    "opusplan": "Opus in plan mode, else Sonnet",
                ]
                let alias = arguments[index + 1]
                return claudeModelJSON("Current model: \(names[alias] ?? alias) (effort: xhigh)")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models == [
            ControlModelOption(id: "opus", displayName: "Opus 5 (1M context)"),
            ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
            ControlModelOption(id: "opusplan", displayName: "Opus in plan mode, else Sonnet"),
        ])
        #expect(
            await calls.arguments.contains(["--bare", "--model", "opus", "-p", "/model", "--output-format", "json"]),
            "alias の表示名は --model 付きの /model 実行から得る（バージョンを埋め込まない）"
        )
    }

    @Test("Claude provider は同じ表示名になる alias だけ alias を添えて区別する")
    func claudeProviderDisambiguatesAliasesSharingOneProductName() async throws {
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { _, arguments in
                guard let index = arguments.firstIndex(of: "--model") else {
                    return claudeModelJSON(
                        "Usage: /model <name>. Available: fable, best, haiku, or a full model ID."
                    )
                }
                let names = ["fable": "Fable 5", "best": "Fable 5", "haiku": "Haiku 4.5"]
                return claudeModelJSON("Current model: \(names[arguments[index + 1]] ?? "?") (effort: xhigh)")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models == [
            ControlModelOption(id: "fable", displayName: "Fable 5 (fable)"),
            ControlModelOption(id: "best", displayName: "Fable 5 (best)"),
            ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
        ])
    }

    @Test("Claude provider は表示名の解決に失敗した alias を alias 表示のまま残す")
    func claudeProviderKeepsAliasWhenDisplayNameLookupFails() async throws {
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { _, arguments in
                guard !arguments.contains("--model") else { throw StubCommandFailure() }
                return claudeModelJSON("Usage: /model <name>. Available: opus, haiku, or a full model ID.")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(
            models == [
                ControlModelOption(id: "opus", displayName: "opus"),
                ControlModelOption(id: "haiku", displayName: "haiku"),
            ],
            "表示名が取れなくても選択肢を落とさない（一覧全体を失敗させない）"
        )
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

/// `claude --bare … --output-format json` の応答形（result フィールドだけを使う）。
private func claudeModelJSON(_ result: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: ["result": result])) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
}

private struct StubCommandFailure: Error {}

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
