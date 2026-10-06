import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// live モデルカタログと spawn 受理。
///
///  1. モデル一覧は live provider から取得でき、Codex も非空になりうる。
///  2. live 一覧が返した ID は、静的な内蔵既定に無くても spawn の実引数へそのまま渡る
///     （`ControlServer.normalizedSpawnModel` が内蔵カタログ外を無言で nil に落とすと「選べるが効かない」になる）。
///  3. live 一覧にも内蔵既定にも無い ID は従来どおり落とす。
///  4. provider が失敗したら内蔵既定へフォールバックし、フォールバックしたことが観測できる。
///  5. Claude の `/model` 実出力からモデル ID 一覧を取り出せる。パースできない出力では空を返す（＝フォールバックが働く）。
///
/// `models(for:)` は同期のスナップショット読み取り（`ControlServer.route()` は同期文脈で `normalizedSpawnModel` を呼ぶ）。
/// `AgentModelCatalog` を触る全 suite は共通の `ModelCatalogTestIsolation` 配下で直列実行する
/// （suite ごとの `.serialized` では別 suite と並列になり、スナップショットを壊す）。
extension ModelCatalogTestIsolation {
@Suite("live モデルカタログと spawn 受理")
struct LiveModelCatalogTests {

    private let token = "live-model-catalog-token"
    private let sessionID = SessionID()

    // MARK: - 契約1: live provider の一覧が反映される（Codex 含む）

    @Test("live provider の一覧がスナップショットへ反映される（Codex も非空になりうる）")
    func liveProviderPopulatesCatalogIncludingCodex() async {
        let provider = StubModelProvider(models: [
            .claudeCode: [option("opus"), option("best"), option("opus[1m]")],
            .codex: [option("gpt-5.3-codex"), option("gpt-5.2")],
            .cursor: [option("composer-2.5")],
        ])
        AgentModelCatalog.configure(provider: provider)
        defer { AgentModelCatalog.configure(provider: nil) }

        await AgentModelCatalog.refresh()

        #expect(AgentModelCatalog.models(for: .claudeCode).map(\.id) == ["opus", "best", "opus[1m]"])
        #expect(
            !AgentModelCatalog.models(for: .codex).isEmpty,
            "Codex のモデル選択を解禁する（ADR 0085/0087 を新 ADR で supersede 済み）"
        )
        #expect(AgentModelCatalog.models(for: .codex).map(\.id) == ["gpt-5.3-codex", "gpt-5.2"])
        #expect(AgentModelCatalog.models(for: .cursor).map(\.id) == ["composer-2.5"])
    }

    // MARK: - 契約2: live 一覧の ID が spawn へそのまま渡る（本タスクの核心）

    @Test("live 一覧が返した新しい ID は spawn の実引数へそのまま渡る")
    func liveCatalogModelReachesSpawnArgument() async throws {
        let provider = StubModelProvider(models: [
            .claudeCode: [option("best")],           // 内蔵既定には無い新しい ID
            .codex: [option("gpt-5.3-codex")],       // 従来は空カタログで必ず捨てられていた
            .cursor: [option("composer-2.5")],
        ])
        AgentModelCatalog.configure(provider: provider)
        defer { AgentModelCatalog.configure(provider: nil) }
        await AgentModelCatalog.refresh()

        let recorder = SpawnRecorder()
        let (port, server) = try await startServer(recorder: recorder)
        _ = server

        let claudeStatus = try await post(
            port: port,
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer","model":"best"}"#
        )
        let codexStatus = try await post(
            port: port,
            path: "/sessions",
            body: #"{"kind":"codex","backend":"appServer","model":"gpt-5.3-codex"}"#
        )

        #expect(claudeStatus == 201)
        #expect(codexStatus == 201)

        let seen = await recorder.spawnModels
        #expect(seen.count == 2)
        #expect(
            seen[0] == "best",
            "live 一覧に載っている ID は無言で捨てず spawn へ渡す（選べるが効かない状態を作らない）"
        )
        #expect(
            seen[1] == "gpt-5.3-codex",
            "Codex のモデルも spawn へ渡す（従来は空カタログで必ず nil に落ちていた）"
        )
    }

    // MARK: - 契約3: 未知 ID は従来どおり落とす

    @Test("live 一覧にも内蔵既定にも無い ID は従来どおり落とす")
    func unknownModelIsStillRejected() async throws {
        let provider = StubModelProvider(models: [
            .claudeCode: [option("opus")],
            .codex: [],
            .cursor: [],
        ])
        AgentModelCatalog.configure(provider: provider)
        defer { AgentModelCatalog.configure(provider: nil) }
        await AgentModelCatalog.refresh()

        let recorder = SpawnRecorder()
        let (port, server) = try await startServer(recorder: recorder)
        _ = server

        let status = try await post(
            port: port,
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer","model":"not-a-model"}"#
        )

        #expect(status == 201, "未知モデルでも spawn 自体は成功する（既存の寛容な挙動を維持）")
        let seen = await recorder.spawnModels
        #expect(seen == [nil], "一覧に無い ID は spawn 引数に渡さない（既存の安全性）")
    }

    @Test("model 省略の spawn は model を nil のまま渡す。指定ありも省略も 201")
    func spawnWithoutModelKeepsModelNil() async throws {
        AgentModelCatalog.configure(provider: StubModelProvider(models: [.claudeCode: [option("default")]]))
        defer { AgentModelCatalog.configure(provider: nil) }
        await AgentModelCatalog.refresh()

        let recorder = SpawnRecorder()
        let (port, server) = try await startServer(recorder: recorder)
        _ = server

        let withModel = try await post(
            port: port,
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer","model":"default"}"#
        )
        let withoutModel = try await post(
            port: port,
            path: "/sessions",
            body: #"{"kind":"claudeCode","backend":"appServer"}"#
        )

        #expect(withModel == 201)
        #expect(withoutModel == 201)
        #expect(await recorder.spawnModels == ["default", nil])
    }

    @Test("spawn 後のモデル適用は生成済み session ID を対象にする")
    func spawnedSessionModelApplicationTargetsSpawnedSession() async {
        let applications = ModelApplicationRecorder()
        let spawnedID = SessionID()

        let result = await ControlSpawnModelApplier.apply("opus", to: spawnedID) { model, sessionID in
            await applications.apply(model: model, to: sessionID)
        }

        #expect(result == true)
        let recorded = await applications.applications
        #expect(recorded.count == 1)
        #expect(recorded[0].sessionID == spawnedID)
        #expect(recorded[0].model == "opus")
    }

    // MARK: - 契約4: フォールバックと観測手段

    @Test("provider が失敗したら内蔵既定へフォールバックし、それが観測できる")
    func providerFailureFallsBackObservably() async {
        AgentModelCatalog.configure(provider: AlwaysFailingModelProvider())
        defer { AgentModelCatalog.configure(provider: nil) }

        await AgentModelCatalog.refresh()

        #expect(
            AgentModelCatalog.models(for: .claudeCode).map(\.id)
                == AgentModelCatalog.builtinModels(for: .claudeCode).map(\.id),
            "取得に失敗したら内蔵既定へフォールバックする（起動と API 応答を妨げない）"
        )
        #expect(
            AgentModelCatalog.kindsUsingFallback().contains(.claudeCode),
            "フォールバックしたことが観測できる（静かに常態化すると自動追随の目的が死ぬ）"
        )
    }

    @Test("内蔵既定は Claude と Cursor で非空（CLI が無い環境でも選択肢が残る）")
    func builtinDefaultsRemainUsable() {
        #expect(!AgentModelCatalog.builtinModels(for: .claudeCode).isEmpty)
        #expect(!AgentModelCatalog.builtinModels(for: .cursor).isEmpty)
    }

    // MARK: - 契約5: Claude の /model 出力パース

    @Test("claude --bare -p \"/model\" の実出力からモデル ID 一覧を取り出せる")
    func parsesRealClaudeModelOutput() {
        // 2026-08-31 に実測した実出力（`--output-format json` の result フィールド）。
        // CLI はモデル名を Markdown のバッククォートで囲んで返す。
        let resultText = """
        Current model: `Opus 5 (1M context)` (effort: xhigh)
        Usage: /model <name>. Available: sonnet, opus, haiku, fable, best, sonnet[1m], opus[1m], fable[1m], opusplan, default, or a full model ID.
        """

        let ids = ClaudeModelListParser.parse(resultText: resultText)

        #expect(ids.contains("sonnet"))
        #expect(ids.contains("opus"))
        #expect(ids.contains("haiku"))
        #expect(ids.contains("fable"))
        #expect(ids.contains("best"), "新しく増えた alias も自動で拾う（これが本タスクの目的）")
        #expect(ids.contains("opus[1m]"), "[1m] 付きの alias も落とさない")
        #expect(
            !ids.contains("or a full model ID"),
            "末尾の説明文（'or a full model ID.'）を ID として拾わない"
        )
        #expect(!ids.contains(""), "空文字を含めない")
        #expect(ids.allSatisfy { !$0.hasSuffix(".") }, "末尾のピリオドを ID に含めない")
    }

    @Test("想定外の出力ではモデル一覧を空で返す（フォールバックへ倒す）")
    func parsesUnexpectedOutputAsEmpty() {
        #expect(ClaudeModelListParser.parse(resultText: "").isEmpty)
        #expect(ClaudeModelListParser.parse(resultText: "command not found: claude").isEmpty)
        #expect(
            ClaudeModelListParser.parse(resultText: "Current model: Opus 5 (1M context)").isEmpty,
            "Available: 行が無ければ空（誤ったパースで壊れた一覧を配らない）"
        )
    }

    // MARK: - helpers

    private func option(_ id: String) -> ControlModelOption {
        ControlModelOption(id: id, displayName: id)
    }

    private func startServer(recorder: SpawnRecorder) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store) { request in
            await recorder.handle(request)
        }
        let port = try await server.start()
        return (port, server)
    }

    /// 応答待ちの上限を明示する。既定（60 秒）のままだと、**ビルド直後の初回実行**で
    /// ローカル接続が一度だけ長時間ブロックされたときにテスト全体が 60 秒ハングし、
    /// 失敗の原因が読み取れなくなる（2026-07-26 に 61.191 秒の fail を実測。
    /// 以後ビルド済みバイナリでの連続実行では再現しない）。
    /// 上限を短く切ったうえで 1 度だけ再試行し、恒常的な不通だけを失敗として扱う。
    /// 検証している内容（ステータスコードと spawn 引数）は一切変えていない。
    private func post(port: Int, path: String, body: String) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = Data(body.utf8)
        urlRequest.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: urlRequest)
            return (response as? HTTPURLResponse)?.statusCode ?? -1
        } catch let error as URLError where error.code == .timedOut {
            let (_, response) = try await URLSession.shared.data(for: urlRequest)
            return (response as? HTTPURLResponse)?.statusCode ?? -1
        }
    }
}
}

// MARK: - stubs

private struct StubModelProvider: AgentModelListProviding {
    let models: [AgentKind: [ControlModelOption]]

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        models[kind] ?? []
    }
}

private struct AlwaysFailingModelProvider: AgentModelListProviding {
    struct Failure: Error {}

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        throw Failure()
    }
}

private actor SpawnRecorder {
    private(set) var spawnModels: [String?] = []

    func handle(_ request: ControlRequest) -> ControlResponse {
        guard case .spawn = request.action else { return .status(200) }
        spawnModels.append(ControlSpawnContext.model)
        return .json(201, SpawnResponseBody(id: UUID().uuidString))
    }
}

private struct SpawnResponseBody: Encodable {
    let id: String
}

private actor ModelApplicationRecorder {
    private(set) var applications: [(sessionID: SessionID, model: String)] = []

    func apply(model: String, to sessionID: SessionID) -> Bool {
        applications.append((sessionID, model))
        return true
    }
}

extension ModelCatalogTestIsolation {
@Suite("live モデル provider と CLI 出力パーサ")
struct LiveModelProviderTests {
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
                resultText: "Current model: `Opus 5 (1M context)` (effort: xhigh)\nUsage: /model <name>."
            ) == "Opus 5 (1M context)"
        )
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "Current model: Sonnet 5") == "Sonnet 5")
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "command not found: claude") == nil)
        #expect(ClaudeModelListParser.parseCurrentModelName(resultText: "Current model:   (effort: high)") == nil)
    }

    @Test("Claude provider は対話型 /model と同じ5件を同じ順序で返す")
    func claudeProviderMatchesInteractivePicker() async throws {
        let calls = CommandCalls()
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { command, arguments in
                await calls.record(command: command, arguments: arguments)
                guard let index = arguments.firstIndex(of: "--model") else {
                    return claudeModelJSON(
                        "Current model: Opus 5 (effort: xhigh)\n"
                            + "Usage: /model <name>. Available: sonnet, opus, haiku, fable, best, sonnet[1m], opus[1m], fable[1m], opusplan, default, or a full model ID."
                    )
                }
                let names = [
                    "default": "Opus 5.5 (1M context)",
                    "opus[1m]": "Opus 5.5 (1M context)",
                    "fable": "Fable 5.1",
                    "sonnet": "Sonnet 5",
                    "haiku": "Haiku 4.5",
                ]
                let alias = arguments[index + 1]
                return claudeModelJSON("Current model: \(names[alias] ?? alias) (effort: xhigh)")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models == [
            ControlModelOption(id: "default", displayName: "Default: Opus 5.5 (1M context)"),
            ControlModelOption(id: "opus[1m]", displayName: "Opus 5.5 (1M context)"),
            ControlModelOption(id: "fable", displayName: "Fable 5.1"),
            ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
            ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
        ])
        #expect(
            await calls.arguments.contains(["--bare", "--model", "default", "-p", "/model", "--output-format", "json"]),
            "alias の表示名は --model 付きの /model 実行から得る（バージョンを埋め込まない）"
        )
        #expect(await calls.arguments.count == 6, "一覧取得1回と表示中の5モデルだけを問い合わせる")
    }

    @Test("Claude provider は対話型に無い内部 alias を表示しない")
    func claudeProviderExcludesInternalAliases() async throws {
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { _, arguments in
                guard let index = arguments.firstIndex(of: "--model") else {
                    return claudeModelJSON(
                        "Usage: /model <name>. Available: fable, best, fable[1m], opusplan, or a full model ID."
                    )
                }
                let names = ["fable": "Fable 5.1"]
                return claudeModelJSON("Current model: \(names[arguments[index + 1]] ?? "?") (effort: xhigh)")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(models == [
            ControlModelOption(id: "fable", displayName: "Fable 5.1"),
        ])
    }

    @Test("Claude provider は表示名の解決に失敗した alias を alias 表示のまま残す")
    func claudeProviderKeepsAliasWhenDisplayNameLookupFails() async throws {
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { _, arguments in
                guard !arguments.contains("--model") else { throw StubCommandFailure() }
                return claudeModelJSON("Usage: /model <name>. Available: default, opus[1m], fable, sonnet, haiku, or a full model ID.")
            }
        )

        let models = try await provider.fetchModels(for: .claudeCode)

        #expect(
            models == [
                ControlModelOption(id: "default", displayName: "Default"),
                ControlModelOption(id: "opus[1m]", displayName: "Opus (1M context)"),
                ControlModelOption(id: "fable", displayName: "Fable 5.1"),
                ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
                ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
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

    @Test("Cursor provider はCLIを確認し、対話型 /model と同じ一覧を同じ順序で返す")
    func cursorProviderReturnsInteractiveModelSnapshot() async throws {
        let calls = CommandCalls()
        let provider = LiveAgentModelProvider(
            environment: ["PATH": "/usr/bin:/bin"],
            commandRunner: { command, arguments in
                await calls.record(command: command, arguments: arguments)
                return "Available models\n\ncomposer-2.5 - Composer 2.5 (current)\nauto - Auto (default)\ngpt-5.6-sol-high - GPT-5.6 Sol High\n"
            }
        )

        let models = try await provider.fetchModels(for: .cursor)

        #expect(models == AgentModelCatalog.builtinModels(for: .cursor))
        #expect(models.count == 38)
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
