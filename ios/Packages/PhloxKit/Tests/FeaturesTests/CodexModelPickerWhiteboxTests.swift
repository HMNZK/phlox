import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite(.serialized)
struct CodexModelPickerWhiteboxTests {
    @Test func codexSelectionSurvivesCatalogFlipBetweenPrepareCalls() async throws {
        let api = FlippingCatalogAPI(flippingKind: .codex)
        let viewModel = SessionDetailViewModel(
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
        let draft = SessionComposeDraft(project: "phlox")

        await viewModel.prepareDraft(draft)
        let codex = try #require(viewModel.modelPickerEntries.first { $0.kind == .codex })
        viewModel.selectDraftModel(entryID: codex.id)
        viewModel.inputText = "Codex で開始"

        await viewModel.sendMessage(composeDraft: draft)

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .codex, "カタログが揺れても選んだエージェントは変わらない")
    }

    @Test func nonEmptyCodexCatalogCreatesModelEntriesInsteadOfAgentOnlyEntry() async {
        let viewModel = SessionDetailViewModel(
            session: Session(
                id: "draft-compose",
                name: "phlox",
                agent: .claudeCode,
                status: .running,
                subtitle: "phlox",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: NonEmptyCodexCatalogAPI()
        )

        await viewModel.prepareDraft(SessionComposeDraft(project: "phlox"))

        let codexEntries = viewModel.modelPickerEntries.filter { $0.kind == .codex }
        #expect(codexEntries.map(\.modelID) == ["gpt-5.3-codex", "gpt-5.2"])
        #expect(codexEntries.map(\.displayName) == ["GPT-5.3 Codex", "GPT-5.2"])
    }
}

private actor FlippingCatalogAPI: PhloxAPI {
    private let flippingKind: AgentKind
    private var flippingCatalogCallCount = 0
    private(set) var spawnRequest: SpawnRequest?

    init(flippingKind: AgentKind) {
        self.flippingKind = flippingKind
    }

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        if kind == flippingKind {
            defer { flippingCatalogCallCount += 1 }
            if flippingCatalogCallCount == 0 {
                return AgentModels(models: [], defaultModel: nil)
            }
            return AgentModels(
                models: [SessionModelOption(id: "flipped-model", displayName: "Flipped Model")],
                defaultModel: "flipped-model"
            )
        }

        switch kind {
        case .claudeCode:
            return AgentModels(
                models: [SessionModelOption(id: "sonnet", displayName: "Sonnet")],
                defaultModel: "sonnet"
            )
        case .cursor:
            return AgentModels(models: [], defaultModel: nil)
        case .codex:
            return AgentModels(models: [], defaultModel: nil)
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

private actor NonEmptyCodexCatalogAPI: PhloxAPI {
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        switch kind {
        case .claudeCode:
            AgentModels(models: [], defaultModel: nil)
        case .cursor:
            AgentModels(models: [], defaultModel: nil)
        case .codex:
            AgentModels(
                models: [
                    SessionModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex"),
                    SessionModelOption(id: "gpt-5.2", displayName: "GPT-5.2"),
                ],
                defaultModel: "gpt-5.3-codex"
            )
        }
    }

    func spawn(_ request: SpawnRequest) async throws -> Session { fatalError("Not used") }
    func waitUntilReady(sessionID: String) async throws -> Bool { fatalError("Not used") }
    func send(_ request: SendRequest) async throws -> SendResult { fatalError("Not used") }
    func listSessions() async throws -> [Session] { [] }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
