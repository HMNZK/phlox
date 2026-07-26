import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite(.serialized)
struct DraftSelectionStabilityWhiteboxTests {
    @Test("カタログから行が消えても選択した kind で spawn し、ピッカーは未選択になる")
    func selectedKindSurvivesWhenItsPickerRowDisappears() async throws {
        let api = CursorCatalogLossAPI()
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
        let cursor = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .cursor && $0.modelID == "composer-2.5"
        })
        viewModel.selectDraftModel(entryID: cursor.id)

        await viewModel.prepareDraft(draft)

        #expect(viewModel.modelPickerEntries.allSatisfy { $0.kind != .cursor })
        #expect(viewModel.selectedModelPickerEntryID == nil)

        viewModel.inputText = "Cursor で開始"
        await viewModel.sendMessage()

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .cursor)
        #expect(request.model == nil)
    }
}

private actor CursorCatalogLossAPI: PhloxAPI {
    private var fetchedKinds: Set<AgentKind> = []
    private(set) var spawnRequest: SpawnRequest?

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        let isSubsequentFetch = fetchedKinds.contains(kind)
        fetchedKinds.insert(kind)
        if kind == .cursor, isSubsequentFetch {
            return AgentModels(models: [], defaultModel: nil)
        }
        switch kind {
        case .claudeCode:
            return AgentModels(
                models: [SessionModelOption(id: "opus", displayName: "Opus")],
                defaultModel: "opus"
            )
        case .cursor:
            return AgentModels(
                models: [SessionModelOption(id: "composer-2.5", displayName: "Composer 2.5")],
                defaultModel: "composer-2.5"
            )
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
