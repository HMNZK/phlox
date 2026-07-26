import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// task-2 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 凍結する契約:
///  1. モデル一覧は live provider から取得でき、**Codex も非空になりうる**（旧 ADR 0085/0087 の
///     「Codex はモデル選択非対応」はユーザー裁定により覆す）。
///  2. **live 一覧が返した ID は、静的な内蔵既定に無くても spawn の実引数へそのまま渡る。**
///     （現状 `ControlServer.normalizedSpawnModel` が内蔵カタログ外を無言で nil に落としており、
///      一覧だけ live 化すると「選べるが効かない」半端な修正になる。ここが本タスクの核心。）
///  3. live 一覧にも内蔵既定にも無い ID は従来どおり落とす（既存の安全性を壊さない）。
///  4. provider が失敗したら内蔵既定へフォールバックし、**フォールバックしたことが観測できる**。
///  5. Claude の `/model` 実出力からモデル ID 一覧を取り出せる。パースできない出力では空を返す
///     （＝フォールバックが働く）。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること。
/// 置き場所は `macos/Packages/ControlServer/Sources/ControlServer/AgentModelProviders.swift`）:
/// ```swift
/// public protocol AgentModelListProviding: Sendable {
///     func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption]
/// }
///
/// public extension AgentModelCatalog {
///     /// 現在のスナップショット（**同期読み取り**。spawn 受理の検証もこれを使う）
///     static func models(for kind: AgentKind) -> [ControlModelOption]
///     /// CLI 取得に失敗したときのフォールバック（内蔵既定）
///     static func builtinModels(for kind: AgentKind) -> [ControlModelOption]
///     /// live provider を登録する（アプリ起動時に配線。nil で解除＝テストの後始末用）
///     static func configure(provider: AgentModelListProviding?)
///     /// live 取得を 1 回走らせてスナップショットを更新する（失敗した kind は内蔵既定のまま）
///     static func refresh() async
///     /// 直近の refresh でフォールバックに落ちた kind（観測手段。静かな常態化を防ぐ）
///     static func kindsUsingFallback() -> Set<AgentKind>
/// }
///
/// public enum ClaudeModelListParser {
///     /// `claude --bare -p "/model" --output-format json` の result 文字列からモデル ID を取り出す。
///     static func parse(resultText: String) -> [String]
/// }
/// ```
/// 注: `models(for:)` を同期のまま保つこと。`ControlServer.route()` は同期文脈で
/// `normalizedSpawnModel` を呼ぶため、ここを async にすると経路全体を書き換える羽目になる。
/// live 取得は `refresh()` で背景更新し、`models(for:)` はスナップショットを返す設計にする。
@Suite("Acceptance: live モデルカタログと spawn 受理（task-2）")
struct AcceptanceLiveModelCatalogTests {

    private let token = "task-2-token"
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
        // 2026-07-26 に PM が実測した実出力（`--output-format json` の result フィールド）。
        let resultText = """
        Current model: Opus 5 (1M context) (effort: xhigh)
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

    // MARK: - helpers（受け入れテスト専用）

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

    private func post(port: Int, path: String, body: String) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = Data(body.utf8)
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}

// MARK: - stubs（受け入れテスト専用。実装役は編集しない）

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
