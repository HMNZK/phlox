import Foundation
import Testing
import PhloxCore
import PhloxNetworking
@testable import Features

@MainActor
@Suite("Session input settings")
struct SessionSettingsSelectionTests {
    @Test("Haiku のように努力の選択肢が空ならチップを隠し、古い Mac の空設定も隠す")
    func chipVisibilityUsesDeliveredOptions() {
        let haiku = settings(
            efforts: [],
            permissions: [AgentSettingOption(value: "ask", displayName: "Ask")]
        )
        let oldMac = settings(efforts: [], permissions: [])

        #expect(!SessionDetailViewModel.shouldShowEffortSelectorChip(for: haiku))
        #expect(SessionDetailViewModel.shouldShowPermissionSelectorChip(for: haiku))
        #expect(!SessionDetailViewModel.shouldShowEffortSelectorChip(for: oldMac))
        #expect(!SessionDetailViewModel.shouldShowPermissionSelectorChip(for: oldMac))
    }

    @Test("思考の強さは PATCH 後に settings を取り直す")
    func effortSelectionPatchesAndReloadsSettings() async {
        let initial = settings(selectedEffort: "medium")
        let api = SessionSettingsMockAPI(settings: initial)
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectEffort("high")

        let updates = await api.settingsUpdates
        #expect(updates == [SessionSettingsUpdate(effort: "high")])
        #expect(await api.settingsReadCount == 2)
        #expect(vm.modelSettings?.selectedEffort == "high")
        #expect(vm.settingsChangeError == nil)
    }

    @Test("権限の既定は permission null を送り、Plan は独立したキーで送る")
    func permissionDefaultAndPlanUseSeparatePatchFields() async {
        let initial = settings(
            selectedPermission: "ask",
            permissions: [
                AgentSettingOption(value: nil, displayName: "既定"),
                AgentSettingOption(value: "ask", displayName: "確認"),
            ],
            planModeAvailable: true
        )
        let api = SessionSettingsMockAPI(settings: initial)
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectPermission(nil)
        await vm.selectPlanMode(true)

        let updates = await api.settingsUpdates
        #expect(updates.count == 2)
        #expect(updates[0] == SessionSettingsUpdate(permission: .some(nil)))
        #expect(updates[1] == SessionSettingsUpdate(planMode: true))
        #expect(await api.settingsReadCount == 3)
        #expect(vm.modelSettings?.selectedPermission == nil)
        #expect(vm.modelSettings?.planMode == true)
    }

    @Test("権限を変えると Plan が解除される")
    func permissionSelectionExitsPlanMode() async {
        let initial = settings(
            selectedPermission: "ask",
            permissions: [AgentSettingOption(value: "manual", displayName: "手動")],
            planMode: true
        )
        let api = SessionSettingsMockAPI(settings: initial)
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectPermission("manual")

        let updates = await api.settingsUpdates
        #expect(updates == [SessionSettingsUpdate(permission: .some("manual"))])
        #expect(vm.modelSettings?.selectedPermission == "manual")
        #expect(vm.modelSettings?.planMode == false)
    }

    @Test("409 設定変更中は現在値を保ち、権限の失敗文言を出す")
    func conflictKeepsCurrentValueAndShowsFailureCopy() async {
        let initial = settings(
            selectedPermission: "ask",
            permissions: [
                AgentSettingOption(value: "ask", displayName: "確認"),
                AgentSettingOption(value: "manual", displayName: "手動"),
            ]
        )
        let api = SessionSettingsMockAPI(
            settings: initial,
            updateError: .server(status: 409, message: "settings update in progress")
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectPermission("manual")

        #expect(vm.modelSettings?.selectedPermission == "ask")
        #expect(vm.settingsChangeError == "権限を変更できませんでした。今の権限（確認）のままです。もう一度選んでください")
        #expect(await api.settingsUpdates.count == 1)
        #expect(await api.readyWaitCount == 0)
    }

    @Test("425 準備前は ready を待って一度だけ再送する")
    func tooEarlyWaitsUntilReadyAndRetriesOnce() async {
        let api = SessionSettingsMockAPI(
            settings: settings(selectedEffort: "medium"),
            firstUpdateError: .server(status: 425, message: "session not ready")
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        await vm.loadModelSettings()

        await vm.selectEffort("high")

        #expect(await api.settingsUpdates.count == 2)
        #expect(await api.readyWaitCount == 1)
        #expect(vm.modelSettings?.selectedEffort == "high")
        #expect(vm.settingsChangeError == nil)
    }

    private func makeSession() -> Session {
        Session(
            id: "settings-session",
            name: "Settings",
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func settings(
        selectedEffort: String? = nil,
        efforts: [AgentSettingOption] = [
            AgentSettingOption(value: "low", displayName: "低"),
            AgentSettingOption(value: "medium", displayName: "中"),
            AgentSettingOption(value: "high", displayName: "高"),
        ],
        selectedPermission: String? = nil,
        permissions: [AgentSettingOption] = [
            AgentSettingOption(value: "manual", displayName: "手動"),
            AgentSettingOption(value: "ask", displayName: "確認"),
        ],
        planMode: Bool = false,
        planModeAvailable: Bool = false
    ) -> SessionModelSettings {
        SessionModelSettings(
            selectedModel: "sonnet",
            availableModels: [SessionModelOption(id: "sonnet", displayName: "Sonnet")],
            selectedEffort: selectedEffort,
            availableEfforts: efforts,
            selectedPermission: selectedPermission,
            availablePermissions: permissions,
            planMode: planMode,
            planModeAvailable: planModeAvailable
        )
    }
}

private actor SessionSettingsMockAPI: PhloxAPI, SessionModelSelecting {
    private var settings: SessionModelSettings
    private let updateError: PhloxError?
    private var firstUpdateError: PhloxError?
    private(set) var settingsUpdates: [SessionSettingsUpdate] = []
    private(set) var settingsReadCount = 0
    private(set) var readyWaitCount = 0

    init(
        settings: SessionModelSettings,
        updateError: PhloxError? = nil,
        firstUpdateError: PhloxError? = nil
    ) {
        self.settings = settings
        self.updateError = updateError
        self.firstUpdateError = firstUpdateError
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "spawned", name: "Spawned", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: .init())
    }
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        AgentModels(models: settings.availableModels, defaultModel: "sonnet")
    }
    func waitUntilReady(sessionID: String) async throws -> Bool {
        readyWaitCount += 1
        return true
    }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        settingsReadCount += 1
        return settings
    }

    func setModel(sessionID: String, model: String) async throws {}

    func updateSessionSettings(sessionID: String, update: SessionSettingsUpdate) async throws {
        settingsUpdates.append(update)
        if let firstUpdateError {
            self.firstUpdateError = nil
            throw firstUpdateError
        }
        if let updateError { throw updateError }

        var selectedPermission = settings.selectedPermission
        var planMode = settings.planMode
        if let permission = update.permission {
            selectedPermission = permission
            planMode = false
        }
        if let requestedPlanMode = update.planMode { planMode = requestedPlanMode }
        settings = SessionModelSettings(
            selectedModel: settings.selectedModel,
            availableModels: settings.availableModels,
            selectedEffort: update.effort ?? settings.selectedEffort,
            availableEfforts: settings.availableEfforts,
            selectedPermission: selectedPermission,
            availablePermissions: settings.availablePermissions,
            planMode: planMode,
            planModeAvailable: settings.planModeAvailable
        )
    }
}
