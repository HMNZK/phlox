import Foundation
import Testing
import PhloxCore
@testable import Features

/// task-8 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 背景（レビューが実測で見つけた実害バグ）:
/// `prepareDraft` は送信時にも再実行される（`SessionDetailView` → `sendMessage(composeDraft:)` →
/// `prepareDraft`）。選択は「エントリ ID（`kind::modelID`）」で保持されているため、その間に
/// あるエージェントのモデル一覧取得が一度失敗して一覧が欠落すると、**選択 ID が一覧から消え、
/// 既定へ静かに巻き戻って「ユーザーが選んだのと違うエージェントが起動する」**。
/// task-7 で Codex については応急処置したが、Claude と Cursor には同じ穴が残っている
/// （Cursor は空カタログで行自体が消えるため、同 kind への引き継ぎだけでは直らない）。
///
/// 凍結する契約:
///  1. **選択したエージェント種別（kind）は、その一覧が空になっても絶対に変わらない。**
///     3 エージェント（claudeCode / cursor / codex）すべてで成り立つこと。
///  2. 同じ kind に同じモデル ID が残っていれば、モデルの選択も維持される。
///  3. モデルが消えて kind だけ残った場合、その kind の**既定モデル**へ収める
///     （一覧の先頭ではない。先頭は最高価モデルになりうるため）。
///  4. kind ごと一覧が空になった場合でも、その kind で spawn できる（`model` は nil）。
///  5. ユーザーがまだ何も選んでいないときの既定選択は従来どおり（この契約では変えない）。
///
/// 実装役への指示:
/// 選択の保持を「エントリ ID の文字列」から **`(kind, modelID?)` の組**へ変えること。
/// 一覧を作り直すときは、まず同じ (kind, modelID) を探し、無ければ同じ kind の既定モデル、
/// それも無ければ kind だけを保持する、の順で解決すること。
/// **どの経路でも kind を別の値へ落とさないこと**が本タスクの核心である。
@MainActor
@Suite(.serialized)
struct AcceptanceDraftSelectionStabilityTests {
    private let draft = SessionComposeDraft(project: "phlox")

    // MARK: - 契約1・4: 一覧が空に転じても kind は変わらない（3 エージェント全部）

    @Test("Codex を選んだあと一覧が空になっても Codex で起動する")
    func codexKindSurvivesCatalogLoss() async throws {
        try await assertKindSurvivesCatalogLoss(kind: .codex, modelID: "gpt-5.3-codex")
    }

    @Test("Cursor を選んだあと一覧が空になっても Cursor で起動する")
    func cursorKindSurvivesCatalogLoss() async throws {
        try await assertKindSurvivesCatalogLoss(kind: .cursor, modelID: "composer-2.5")
    }

    @Test("Claude を選んだあと一覧が空になっても Claude で起動する")
    func claudeKindSurvivesCatalogLoss() async throws {
        try await assertKindSurvivesCatalogLoss(kind: .claudeCode, modelID: "opus")
    }

    // MARK: - 契約1: 「選んだ kind だけ」取得に失敗した場合（他の kind は健在）
    //
    // レビューが名指しした実害シナリオ。他の kind の行が残っているため、
    // 選択が消えたときに**別の kind の行へ滑り落ちる**余地がある。

    @Test("Claude だけ取得に失敗しても、Claude で起動する（他の kind へ滑り落ちない）")
    func claudeKindSurvivesWhenOnlyClaudeCatalogIsLost() async throws {
        try await assertKindSurvivesPartialCatalogLoss(kind: .claudeCode, modelID: "opus")
    }

    @Test("Cursor だけ取得に失敗しても、Cursor で起動する（他の kind へ滑り落ちない）")
    func cursorKindSurvivesWhenOnlyCursorCatalogIsLost() async throws {
        try await assertKindSurvivesPartialCatalogLoss(kind: .cursor, modelID: "composer-2.5")
    }

    @Test("Codex だけ取得に失敗しても、Codex で起動する（他の kind へ滑り落ちない）")
    func codexKindSurvivesWhenOnlyCodexCatalogIsLost() async throws {
        try await assertKindSurvivesPartialCatalogLoss(kind: .codex, modelID: "gpt-5.3-codex")
    }

    // MARK: - 契約2: 同じモデルが残っていれば選択は維持される

    @Test("一覧が作り直されても、同じモデルが残っていれば選択は変わらない")
    func selectionIsPreservedWhenModelStillExists() async throws {
        let api = FlippingCatalogAPI(full: Self.fullCatalog)
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let entry = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .cursor && $0.modelID == "composer-2.5"
        })
        viewModel.selectDraftModel(entryID: entry.id)
        viewModel.inputText = "Cursor で開始"

        await viewModel.sendMessage(composeDraft: draft)

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .cursor)
        #expect(request.model == "composer-2.5", "同じモデルが残っていれば選択は維持する")
    }

    // MARK: - 契約3: モデルだけ消えたら kind の既定モデルへ収める

    @Test("選んだモデルだけ消えたら、その kind の既定モデルへ収める（一覧の先頭ではない）")
    func fallsBackToKindDefaultModelNotTheFirstEntry() async throws {
        // claude の一覧は [expensive-first, opus, haiku]、既定は opus。
        // 選んだ expensive-first が消えたら opus へ収まること（先頭の別モデルへ倒れないこと）。
        let full: [AgentKind: AgentModels] = [
            .claudeCode: AgentModels(
                models: [
                    SessionModelOption(id: "expensive-first", displayName: "Expensive"),
                    SessionModelOption(id: "opus", displayName: "Opus"),
                    SessionModelOption(id: "haiku", displayName: "Haiku"),
                ],
                defaultModel: "opus"
            ),
            .cursor: AgentModels(models: [], defaultModel: nil),
            .codex: AgentModels(models: [], defaultModel: nil),
        ]
        let reduced: [AgentKind: AgentModels] = [
            .claudeCode: AgentModels(
                models: [
                    SessionModelOption(id: "opus", displayName: "Opus"),
                    SessionModelOption(id: "haiku", displayName: "Haiku"),
                ],
                defaultModel: "opus"
            ),
            .cursor: AgentModels(models: [], defaultModel: nil),
            .codex: AgentModels(models: [], defaultModel: nil),
        ]
        let api = FlippingCatalogAPI(full: full, afterFirstFetch: reduced)
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let entry = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .claudeCode && $0.modelID == "expensive-first"
        })
        viewModel.selectDraftModel(entryID: entry.id)
        viewModel.inputText = "Claude で開始"

        await viewModel.sendMessage(composeDraft: draft)

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .claudeCode, "kind は変わらない")
        #expect(
            request.model == "opus",
            "モデルが消えたら kind の既定モデルへ収める（一覧の先頭に倒れて最高価モデルを選ばない）"
        )
    }

    // MARK: - helpers

    /// 「一覧が非空 → 選択 → 2 回目の取得で全 kind が空 → 送信」で kind が保たれることを検証する。
    private func assertKindSurvivesCatalogLoss(kind: AgentKind, modelID: String) async throws {
        let empty: [AgentKind: AgentModels] = [
            .claudeCode: AgentModels(models: [], defaultModel: nil),
            .cursor: AgentModels(models: [], defaultModel: nil),
            .codex: AgentModels(models: [], defaultModel: nil),
        ]
        let api = FlippingCatalogAPI(full: Self.fullCatalog, afterFirstFetch: empty)
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let entry = try #require(viewModel.modelPickerEntries.first {
            $0.kind == kind && $0.modelID == modelID
        })
        viewModel.selectDraftModel(entryID: entry.id)
        viewModel.inputText = "開始"

        await viewModel.sendMessage(composeDraft: draft)

        let request = try #require(await api.spawnRequest)
        #expect(
            request.agent == kind,
            "一覧が空になっても、ユーザーが選んだエージェント種別で起動すること（黙って別のエージェントに変えない）"
        )
    }

    /// 「選んだ kind の一覧だけが 2 回目の取得で空になる（他の kind は健在）」で
    /// kind が保たれることを検証する。他の kind の行が残っているぶん、滑り落ちやすい。
    private func assertKindSurvivesPartialCatalogLoss(kind: AgentKind, modelID: String) async throws {
        var reduced = Self.fullCatalog
        reduced[kind] = AgentModels(models: [], defaultModel: nil)
        let api = FlippingCatalogAPI(full: Self.fullCatalog, afterFirstFetch: reduced)
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let entry = try #require(viewModel.modelPickerEntries.first {
            $0.kind == kind && $0.modelID == modelID
        })
        viewModel.selectDraftModel(entryID: entry.id)
        viewModel.inputText = "開始"

        await viewModel.sendMessage(composeDraft: draft)

        let request = try #require(await api.spawnRequest)
        #expect(
            request.agent == kind,
            "選んだ kind の一覧だけが失われても、他の kind へ滑り落ちないこと"
        )
    }

    private static let fullCatalog: [AgentKind: AgentModels] = [
        .claudeCode: AgentModels(
            models: [
                SessionModelOption(id: "opus", displayName: "Opus"),
                SessionModelOption(id: "haiku", displayName: "Haiku"),
            ],
            defaultModel: "opus"
        ),
        .cursor: AgentModels(
            models: [SessionModelOption(id: "composer-2.5", displayName: "Composer 2.5")],
            defaultModel: "composer-2.5"
        ),
        .codex: AgentModels(
            models: [SessionModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex")],
            defaultModel: "gpt-5.3-codex"
        ),
    ]

    private func makeViewModel(api: PhloxAPI) -> SessionDetailViewModel {
        SessionDetailViewModel(
            session: Session(
                id: "draft-compose",
                name: "phlox",
                agent: .claudeCode,
                status: .running,
                subtitle: "phlox",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: api
        )
    }
}

// MARK: - stub（受け入れテスト専用。実装役は編集しない）

/// 1 回目の取得と 2 回目以降の取得で別のカタログを返す API スタブ。
/// `prepareDraft` が送信時に再実行されることを模す。
private actor FlippingCatalogAPI: PhloxAPI {
    private let full: [AgentKind: AgentModels]
    private let afterFirstFetch: [AgentKind: AgentModels]?
    private var fetchedKinds: Set<AgentKind> = []
    private(set) var spawnRequest: SpawnRequest?

    init(full: [AgentKind: AgentModels], afterFirstFetch: [AgentKind: AgentModels]? = nil) {
        self.full = full
        self.afterFirstFetch = afterFirstFetch
    }

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        let empty = AgentModels(models: [], defaultModel: nil)
        if fetchedKinds.contains(kind), let afterFirstFetch {
            return afterFirstFetch[kind] ?? empty
        }
        fetchedKinds.insert(kind)
        return full[kind] ?? empty
    }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        spawnRequest = request
        return Session(
            id: "real-session",
            name: "Real Session",
            agent: request.agent,
            status: .starting,
            subtitle: request.workspace,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func listSessions() async throws -> [Session] { [] }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
