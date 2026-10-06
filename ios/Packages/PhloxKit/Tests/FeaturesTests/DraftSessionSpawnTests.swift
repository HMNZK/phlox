import Foundation
import Testing
import PhloxCore
@testable import Features

/// 下書きからの初回送信（spawn → ready 待ち → send）とモデル選択の spawn への反映。
@MainActor
@Suite("Draft session spawn", .serialized)
struct DraftSessionSpawnTests {
    private let draft = SessionComposeDraft(project: "phlox")

    @Test func firstDraftSendSpawnsWaitsUntilReadyThenSends() async throws {
        let api = DraftFlowAPI()
        let viewModel = makeViewModel(api: api)
        viewModel.inputText = "最初の指示"

        // View の `.task` より先に送信されても placeholder へ send しない。
        await viewModel.sendMessage(composeDraft: draft)

        #expect(await api.flow == ["spawn", "ready:real-session", "send:real-session"])
        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .claudeCode)
        #expect(request.workspace == "phlox")
        #expect(request.model == "sonnet")
        #expect(viewModel.session.id == "real-session")
    }

    @Test func selectedCatalogRowResolvesKindWithoutModelIDCollision() async throws {
        let api = DraftFlowAPI()
        let viewModel = makeViewModel(api: api)
        await viewModel.prepareDraft(draft)
        let cursorCollision = try #require(viewModel.modelPickerEntries.first {
            $0.kind == .cursor && $0.modelID == "shared"
        })
        viewModel.selectDraftModel(entryID: cursorCollision.id)
        viewModel.inputText = "Cursor で開始"

        await viewModel.sendMessage()

        let request = try #require(await api.spawnRequest)
        #expect(request.agent == .cursor)
        #expect(request.model == "shared")
    }

    @Test func draftPollingEntryOnlyPreparesComposeAndDoesNotPollPlaceholder() async {
        let api = DraftFlowAPI()
        let viewModel = makeViewModel(api: api)

        await viewModel.startPolling(composeDraft: draft, interval: .milliseconds(1))

        #expect(await api.pollingReadCount == 0)
        #expect(viewModel.isAwaitingInitialSpawn)
    }

    private func makeViewModel(api: DraftFlowAPI) -> SessionDetailViewModel {
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

private actor DraftFlowAPI: PhloxAPI {
    private(set) var flow: [String] = []
    private(set) var spawnRequest: SpawnRequest?
    private(set) var pollingReadCount = 0

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        switch kind {
        case .claudeCode:
            AgentModels(
                models: [
                    SessionModelOption(id: "sonnet", displayName: "Sonnet"),
                    SessionModelOption(id: "shared", displayName: "Shared Claude"),
                ],
                defaultModel: "sonnet"
            )
        case .cursor:
            AgentModels(
                models: [SessionModelOption(id: "shared", displayName: "Shared Cursor")],
                defaultModel: "shared"
            )
        case .codex:
            AgentModels(models: [], defaultModel: nil)
        }
    }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        flow.append("spawn")
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

    func waitUntilReady(sessionID: String) async throws -> Bool {
        flow.append("ready:\(sessionID)")
        return true
    }

    func send(_ request: SendRequest) async throws -> SendResult {
        flow.append("send:\(request.sessionID)")
        return SendResult(accepted: true)
    }

    func listSessions() async throws -> [Session] {
        pollingReadCount += 1
        return []
    }

    func output(sessionID: String) async throws -> String {
        pollingReadCount += 1
        return ""
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        pollingReadCount += 1
        return []
    }

    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
