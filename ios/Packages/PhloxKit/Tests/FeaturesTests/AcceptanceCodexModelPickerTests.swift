import Foundation
import Testing
import PhloxCore
@testable import Features

/// task-7 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 背景: ADR 0085 / 0087 で「Codex はモデル選択非対応」と決めていたが、ユーザー裁定により解禁した
/// （新 ADR 0122 で supersede 済み。サーバ側は task-2 で Codex のモデル一覧を返せるようにした）。
/// iOS 側は `SessionDetailViewModel.prepareDraft` が Codex だけカタログを無視し、
/// `ModelPickerEntry(kind: .codex, modelID: nil, ...)` を1行だけ足す実装のままである。
/// このままでは、サーバが Codex のモデルを返しても**モバイルの入力欄では選べない**。
///
/// 凍結する契約:
///  1. Codex のカタログが非空なら、Claude / Cursor と同じくモデル行が一覧に並ぶ。
///  2. Codex のモデル行を選んで送信すると、その ID が spawn の `model` へ渡る。
///  3. Codex のカタログが**空**のときは従来どおり agent-only 行（`modelID: nil`）が残り、
///     送信時の `model` は nil（CLI が無い環境で Codex が選べなくなる回帰を防ぐ・既存契約の維持）。
///  4. 3 エージェントすべてが一覧に現れる。
@MainActor
@Suite(.serialized)
struct AcceptanceCodexModelPickerTests {
    private let draft = SessionComposeDraft(project: "phlox")

    // MARK: - 契約1・4: Codex のモデル行が一覧に並ぶ

    @Test func codexModelsAppearInPickerWhenCatalogIsNotEmpty() async {
        let api = CodexCatalogAPI(codexModels: [
            SessionModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex"),
            SessionModelOption(id: "gpt-5.2", displayName: "GPT-5.2"),
        ])
        let viewModel = makeViewModel(api: api)

        await viewModel.prepareDraft(draft)

        let codexEntries = viewModel.modelPickerEntries.filter { $0.kind == .codex }
        #expect(
            codexEntries.map(\.modelID) == ["gpt-5.3-codex", "gpt-5.2"],
            "Codex もカタログのモデルを一覧に並べる（ADR 0122 で解禁済み）"
        )
        #expect(
            codexEntries.map(\.displayName) == ["GPT-5.3 Codex", "GPT-5.2"],
            "表示名はカタログのものを使う"
        )
        #expect(
            Set(viewModel.modelPickerEntries.map(\.kind)) == [.claudeCode, .cursor, .codex],
            "3 エージェントすべてが一覧に出る"
        )
    }

    // MARK: - 契約2: 選んだ Codex モデルが spawn へ渡る

    @Test func selectedCodexModelReachesSpawnRequest() async throws {
        let api = CodexCatalogAPI(codexModels: [
            SessionModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex"),
        ])
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let codex = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .codex && $0.modelID == "gpt-5.3-codex"
        })
        viewModel.selectDraftModel(entryID: codex.id)
        viewModel.inputText = "Codex で開始"

        await viewModel.sendMessage()

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .codex)
        #expect(
            request.model == "gpt-5.3-codex",
            "選べるのに効かない状態を作らない（選択した ID がそのまま spawn へ渡る）"
        )
    }

    // MARK: - 契約3: 空カタログでは従来どおり agent-only 行が残る

    @Test func codexRemainsSelectableWithAgentOnlyRowWhenCatalogIsEmpty() async throws {
        let api = CodexCatalogAPI(codexModels: [])
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)

        let codex = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .codex && $0.modelID == nil
        })
        viewModel.selectDraftModel(entryID: codex.id)
        viewModel.inputText = "Codex で開始"

        await viewModel.sendMessage()

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .codex)
        #expect(
            request.model == nil,
            "CLI が無い等でカタログが空でも Codex を選べる（既存契約の維持）"
        )
    }

    // MARK: - helpers

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

private actor CodexCatalogAPI: PhloxAPI {
    private let codexModels: [SessionModelOption]
    private(set) var spawnRequest: SpawnRequest?

    init(codexModels: [SessionModelOption]) {
        self.codexModels = codexModels
    }

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        switch kind {
        case .claudeCode:
            AgentModels(
                models: [SessionModelOption(id: "sonnet", displayName: "Sonnet")],
                defaultModel: "sonnet"
            )
        case .cursor:
            AgentModels(
                models: [SessionModelOption(id: "composer-2.5", displayName: "Composer 2.5")],
                defaultModel: "composer-2.5"
            )
        case .codex:
            AgentModels(models: codexModels, defaultModel: codexModels.first?.id)
        }
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
