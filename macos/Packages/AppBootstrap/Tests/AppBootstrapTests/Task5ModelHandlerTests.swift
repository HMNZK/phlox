import AgentDomain
import AppBootstrap
import ControlServer
import DashboardFeature
import Foundation
import SessionFeature
import StructuredChatKit
import Testing

private final class Task5NonControllingSpawnClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent> = AsyncStream { _ in }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}

private struct Task5AppliedSpawnSettings: Equatable {
    let model: String?
    let permissionOrMode: String?
    let effort: String?
}

private final class Task5ControllingSpawnClient: StructuredAgentClient, SpawnAgentSettingsControlling, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent> = AsyncStream { _ in }
    private let lock = NSLock()
    private var recordedSettings: [Task5AppliedSpawnSettings] = []

    var appliedSettings: [Task5AppliedSpawnSettings] {
        lock.withLock { recordedSettings }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}

    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        lock.withLock {
            recordedSettings.append(Task5AppliedSpawnSettings(
                model: model,
                permissionOrMode: permissionOrMode,
                effort: effort
            ))
        }
    }
}

@MainActor
@Suite struct Task5ModelHandlerTests {
    @MainActor
    private final class DashboardStub: ControlActionDashboard {
        var settingsByID: [SessionID: ControlSessionModelSettings] = [:]
        var modelResults: [SessionID: Bool] = [:]
        private(set) var appliedModels: [(SessionID, String)] = []

        var controlSessionSummaries: [ControlSessionSummary] = []
        func sendMessage(to: Recipient, text: String, submit: Bool, from: SessionID?, inReplyTo: UUID?, images: [ControlImageAttachment]) async -> DashboardViewModel.SendOutcome { .sent }
        func spawnSession(ref: AgentRef, from: SessionID?, backend: SessionBackend, workingDirectory: String?) async throws -> SessionID { SessionID() }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(for id: SessionID, timeout: Duration, sentinel: String?) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { false }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }

        func sessionModelSettings(for id: SessionID) -> ControlSessionModelSettings? {
            settingsByID[id]
        }

        func setSessionModel(_ model: String, for id: SessionID) async -> Bool {
            appliedModels.append((id, model))
            return modelResults[id] ?? false
        }
    }

    @Test func settingsReturnsSelectedAndAvailableModels() async throws {
        let id = SessionID()
        let dashboard = DashboardStub()
        dashboard.settingsByID[id] = ControlSessionModelSettings(
            selectedModel: "sonnet",
            availableModels: [
                ControlModelOption(id: "opus", displayName: "Opus 4.8"),
                ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
            ]
        )
        let response = await makeHandler(dashboard).handle(request(.sessionSettings(id: id)))

        #expect(response.statusCode == 200)
        let body = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(body[ControlModelWireContract.selectedModelKey] as? String == "sonnet")
        let available = try #require(body[ControlModelWireContract.availableModelsKey] as? [[String: Any]])
        #expect(available.map { $0[ControlModelWireContract.modelIDKey] as? String } == ["opus", "sonnet"])
        #expect(available.map { $0[ControlModelWireContract.modelDisplayNameKey] as? String } == ["Opus 4.8", "Sonnet 5"])
    }

    @Test func settingsForUnsupportedSessionReturnsEmptySettings() async throws {
        let id = SessionID()
        let dashboard = DashboardStub()
        dashboard.controlSessionSummaries = [
            ControlSessionSummary(
                id: id,
                name: "codex",
                agentID: "codex",
                status: .idle,
                workspaceName: "workspace"
            )
        ]

        let response = await makeHandler(dashboard).handle(request(.sessionSettings(id: id)))

        #expect(response.statusCode == 200)
        let body = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(body[ControlModelWireContract.selectedModelKey] is NSNull)
        let available = try #require(body[ControlModelWireContract.availableModelsKey] as? [[String: Any]])
        #expect(available.isEmpty)
    }

    @Test func settingsForUnknownSessionReturns404() async {
        let dashboard = DashboardStub()
        let response = await makeHandler(dashboard).handle(request(.sessionSettings(id: SessionID())))
        #expect(response.statusCode == 404)
    }

    @Test func modelApplicationForwardsToDashboard() async {
        let id = SessionID()
        let dashboard = DashboardStub()
        dashboard.modelResults[id] = true

        let response = await makeHandler(dashboard).handle(request(.setModel(id: id, model: "fable")))

        #expect(response.statusCode == 200)
        #expect(dashboard.appliedModels.count == 1)
        #expect(dashboard.appliedModels.first?.0 == id)
        #expect(dashboard.appliedModels.first?.1 == "fable")
    }

    @Test func modelApplicationForUnknownOrUnsupportedSessionReturns404() async {
        let dashboard = DashboardStub()
        let response = await makeHandler(dashboard).handle(request(.setModel(id: SessionID(), model: "opus")))
        #expect(response.statusCode == 404)
    }

    @Test func spawnModelCapabilityRequiresSettingsControllerAndRejectsLocalOnlyMutation() async throws {
        let client = Task5NonControllingSpawnClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/task-5"
        )
        try await viewModel.startNew(
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )

        #expect(!viewModel.availableSpawnAgentModels.isEmpty)
        #expect(viewModel.canApplySpawnAgentSettings == false)
        let selectedBeforeAttempt = viewModel.selectedModel

        await viewModel.setSpawnAgentModel("sonnet")

        #expect(viewModel.selectedModel == selectedBeforeAttempt)
    }

    @Test func spawnModelCapabilityAcceptsControllerAndPreservesFullSettingsSnapshot() async throws {
        let client = Task5ControllingSpawnClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/task-5"
        )
        try await viewModel.startNew(
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )

        #expect(viewModel.canApplySpawnAgentSettings == true)
        await viewModel.setSpawnAgentModel("sonnet")

        #expect(viewModel.selectedModel == "sonnet")
        #expect(client.appliedSettings.last == Task5AppliedSpawnSettings(
            model: "sonnet",
            permissionOrMode: "bypassPermissions",
            effort: "high"
        ))
    }

    private func makeHandler(_ dashboard: DashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func request(_ action: ControlRequest.Action) -> ControlRequest {
        ControlRequest(requester: nil, action: action)
    }
}
