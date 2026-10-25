import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite(.serialized)
struct NewChatParityAcceptanceTests {
    private let project = ProjectSummary(id: "project-1", name: "Phlox")
    private let startPoint = NewChatStartPoint(kind: .localBranch, value: "dev", title: "dev", summary: nil)
    private let history = NewChatHistoryEntry(id: "earlier-session", title: "Earlier task",
                                             updatedAt: Date(timeIntervalSince1970: 1), branch: "dev", workingDirectory: "/repo")

    @Test("空本文でも履歴を再開し、初回メッセージを送らない")
    func resumeDoesNotSendAnInitialMessage() async throws {
        let (model, api, suite) = model()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        await model.load()
        model.selectProject(id: project.id)
        await model.loadLaunchOptions()
        let selectedHistory: NewChatHistoryEntry = try #require(model.historyEntries.first)
        model.selectHistory(selectedHistory)
        var openedSession: Session?

        await model.send { session, _ in openedSession = session }

        #expect(openedSession?.id == "created")
        #expect(await api.lastSpawnRequest?.resumeHistoryID == history.id)
        #expect(await api.sendCount == 0)
        #expect(await api.spawnCount == 1)
    }

    @Test("通常のworktree起動は選んだ開始ブランチと依頼を一度だけ送る")
    func worktreeLaunchKeepsNormalInitialSend() async throws {
        let (model, api, suite) = model()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        await model.load()
        model.selectProject(id: project.id)
        await model.loadLaunchOptions()
        model.usesWorktree = true
        model.selectStartPoint(try #require(model.startPoints.first))
        model.inputText = "Fix the bug"

        await model.send { _, _ in }

        let request = try #require(await api.lastSpawnRequest)
        #expect(request.projectID == project.id)
        #expect(request.usesWorktree == true)
        #expect(request.startPoint?.kind == .localBranch)
        #expect(request.startPoint?.value == "dev")
        #expect(request.resumeHistoryID == nil)
        #expect(await api.sendCount == 1)
        #expect(await api.lastSentRequest?.text == "Fix the bug")
    }

    @Test("プロジェクトを変えたら以前の履歴選択を起動要求へ混ぜない")
    func changingProjectClearsHistorySelection() async throws {
        let (model, api, suite) = model()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        await model.load()
        model.selectProject(id: project.id)
        await model.loadLaunchOptions()
        let selectedHistory: NewChatHistoryEntry = try #require(model.historyEntries.first)
        model.selectHistory(selectedHistory)

        model.selectProject(id: "project-2")
        model.inputText = "New task"
        await model.send { _, _ in }

        #expect(model.selectedHistoryID == nil)
        #expect(await api.lastSpawnRequest?.projectID == "project-2")
        #expect(await api.lastSpawnRequest?.resumeHistoryID == nil)
        #expect(await api.sendCount == 1)
    }

    @Test("エージェントを変えたら別エージェントの履歴選択を持ち越さない")
    func changingAgentClearsHistorySelection() async throws {
        let (model, api, suite) = model()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        await model.load()
        model.selectProject(id: project.id)
        await model.loadLaunchOptions()
        let selectedHistory: NewChatHistoryEntry = try #require(model.historyEntries.first)
        model.selectHistory(selectedHistory)
        let entry = try #require(model.modelEntries.first(where: { $0.kind == .codex }))

        model.selectModel(entryID: entry.id)
        model.inputText = "New task"
        await model.send { _, _ in }

        #expect(model.selectedHistoryID == nil)
        #expect(await api.lastSpawnRequest?.agent == .codex)
        #expect(await api.lastSpawnRequest?.resumeHistoryID == nil)
    }

    private func model() -> (NewChatViewModel, ParityNewChatAPI, String) {
        let suite = "NewChatParityAcceptanceTests.\(UUID().uuidString)"
        let api = ParityNewChatAPI(projects: [project, ProjectSummary(id: "project-2", name: "Gardenia")],
                                   startPoints: [startPoint], history: [history])
        return (NewChatViewModel(api: api, entryProject: SessionComposeDraft(project: ""),
                                 settingsStore: NewChatSettingsStore(defaults: UserDefaults(suiteName: suite)!)), api, suite)
    }
}

private actor ParityNewChatAPI: PhloxAPI {
    private let projectValues: [ProjectSummary]
    private let pointValues: [NewChatStartPoint]
    private let historyValues: [NewChatHistoryEntry]
    private(set) var spawnCount = 0
    private(set) var sendCount = 0
    private(set) var lastSpawnRequest: SpawnRequest?
    private(set) var lastSentRequest: SendRequest?

    init(projects: [ProjectSummary], startPoints: [NewChatStartPoint], history: [NewChatHistoryEntry]) {
        projectValues = projects
        pointValues = startPoints
        historyValues = history
    }

    func projects() async throws -> [ProjectSummary]? { projectValues }
    func projectStartPoints(projectID: String, commit: String?) async throws -> [NewChatStartPoint] { pointValues }
    func projectHistory(projectID: String, kind: AgentKind) async throws -> [NewChatHistoryEntry] { historyValues }
    func listSessions() async throws -> [Session] { [] }
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        AgentModels(models: [SessionModelOption(id: "model", displayName: "Model")], defaultModel: "model")
    }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        spawnCount += 1
        lastSpawnRequest = request
        return Session(id: "created", name: "Created", agent: request.agent, status: .starting,
                       subtitle: request.workspace, updatedAt: Date(timeIntervalSince1970: 2))
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult {
        sendCount += 1
        lastSentRequest = request
        return SendResult(accepted: true)
    }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
