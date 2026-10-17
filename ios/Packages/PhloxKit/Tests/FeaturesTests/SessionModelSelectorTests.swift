import Foundation
import Testing
import PhloxCore
import PhloxNetworking
@testable import Features

/// モデル選択チップの表示条件と API 配線（選択で setModel を叩き、チップ表示が更新される）。
@MainActor
@Suite("Session model selector") struct SessionModelSelectorTests {
    private func makeSession() -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func shouldShowChipFalseWhenSettingsNil() {
        #expect(SessionDetailViewModel.shouldShowModelSelectorChip(for: nil) == false)
    }

    @Test func shouldShowChipFalseWhenAvailableModelsEmpty() {
        let settings = SessionModelSettings(selectedModel: nil, availableModels: [])
        #expect(SessionDetailViewModel.shouldShowModelSelectorChip(for: settings) == false)
    }

    @Test func shouldShowChipTrueWhenAvailableModelsNonempty() {
        let settings = SessionModelSettings(
            selectedModel: "m1",
            availableModels: [SessionModelOption(id: "m1", displayName: "Model 1")]
        )
        #expect(SessionDetailViewModel.shouldShowModelSelectorChip(for: settings) == true)
    }

    @Test func loadModelSettingsHidesChipOnFailure() async {
        let api = ModelSelectorMockAPI(settingsOutcome: .failure(.notFound))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.loadModelSettings()

        #expect(vm.showsModelSelectorChip == false)
        #expect(vm.modelSettings == nil)
    }

    @Test func loadModelSettingsShowsChipWhenModelsAvailable() async {
        let settings = SessionModelSettings(
            selectedModel: "m1",
            availableModels: [
                SessionModelOption(id: "m1", displayName: "Sonnet"),
                SessionModelOption(id: "m2", displayName: "Opus"),
            ]
        )
        let api = ModelSelectorMockAPI(settingsOutcome: .success(settings))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.loadModelSettings()

        #expect(vm.showsModelSelectorChip)
        #expect(vm.selectedModelDisplayName == "Sonnet")
    }

    @Test func selectModelCallsSetModelAndUpdatesChip() async {
        let settings = SessionModelSettings(
            selectedModel: "m1",
            availableModels: [
                SessionModelOption(id: "m1", displayName: "Sonnet"),
                SessionModelOption(id: "m2", displayName: "Opus"),
            ]
        )
        let api = ModelSelectorMockAPI(settingsOutcome: .success(settings))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectModel("m2")

        let log = await api.setModelLog
        #expect(log.count == 1)
        #expect(log[0].0 == "s1")
        #expect(log[0].1 == "m2")
        #expect(vm.modelSettings?.selectedModel == "m2")
        #expect(vm.selectedModelDisplayName == "Opus")
    }

    @Test func nilSelectedModelUsesMacDefaultModelForChipAndSheetMarker() async {
        let settings = SessionModelSettings(
            selectedModel: nil,
            availableModels: [
                SessionModelOption(id: "m1", displayName: "Sonnet"),
                SessionModelOption(id: "m2", displayName: "Opus"),
            ]
        )
        let api = ModelSelectorMockAPI(settingsOutcome: .success(settings), defaultModelID: "m2")
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        await vm.loadModelSettings()

        #expect(vm.selectedModelDisplayName == "Opus")
        #expect(vm.defaultModelPickerEntryID == vm.modelPickerEntries.first(where: { $0.modelID == "m2" })?.id)
        #expect(vm.selectedModelPickerEntryID == vm.defaultModelPickerEntryID)
    }
}

private actor ModelSelectorMockAPI: PhloxAPI, SessionModelSelecting {
    let settingsOutcome: Result<SessionModelSettings, PhloxError>
    private let defaultModelID: String?
    private var currentSettings: SessionModelSettings?
    private(set) var setModelLog: [(String, String)] = []

    init(settingsOutcome: Result<SessionModelSettings, PhloxError>, defaultModelID: String? = nil) {
        self.settingsOutcome = settingsOutcome
        self.defaultModelID = defaultModelID
        self.currentSettings = try? settingsOutcome.get()
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "x", name: "x", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: .init())
    }
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        let settings = try currentSettings ?? settingsOutcome.get()
        return AgentModels(models: settings.availableModels, defaultModel: defaultModelID)
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        try currentSettings ?? settingsOutcome.get()
    }

    func setModel(sessionID: String, model: String) async throws {
        setModelLog.append((sessionID, model))
        if let settings = currentSettings {
            currentSettings = SessionModelSettings(
                selectedModel: model,
                availableModels: settings.availableModels,
                selectedEffort: settings.selectedEffort,
                availableEfforts: settings.availableEfforts,
                selectedPermission: settings.selectedPermission,
                availablePermissions: settings.availablePermissions,
                planMode: settings.planMode,
                planModeAvailable: settings.planModeAvailable
            )
        }
    }
}
