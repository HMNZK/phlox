import Foundation
import Testing
import AgentDomain
import PhloxCore
@testable import Features

@MainActor
@Suite("NewChatViewModel", .serialized)
struct NewChatViewModelTests {
    private let project = ProjectSummary(id: "project-1", name: "Phlox")

    @Test("見出しは Mac の 10 種で固定できる")
    func greetingCatalogAndFixedValue() {
        #expect(NewChatViewModel.greetings.count == 10)
        #expect(NewChatViewModel.greeting(fixed: "今日は何を進めますか？") == "今日は何を進めますか？")
        #expect(Set(NewChatViewModel.greetings).count == 10)
    }

    @Test("提案チップは Mac の文面を末尾へ追加し、カーソルとフォーカスを末尾へ移す")
    func suggestionAppendAndFocus() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        let beforeFocus = viewModel.focusRequest

        viewModel.inputText = "既存の依頼"
        viewModel.appendSuggestion(1)

        #expect(NewChatViewModel.suggestions.map(\.title) == ["コードレビュー", "バグ修正", "テスト追加", "コードの説明", "リファクタ"])
        #expect(viewModel.inputText == "既存の依頼\n次の不具合を調べて、根本原因を直してください: ")
        #expect(viewModel.inputCursorUTF16 == viewModel.inputText.utf16.count)
        #expect(viewModel.focusRequest == beforeFocus + 1)
    }

    @Test("下部入口は前回使ったプロジェクトを初期選択する")
    func bottomEntryRestoresLastProject() async {
        let store = makeStore()
        store.record(kind: .claudeCode, model: "sonnet", effort: "high", permission: "auto", planMode: false, projectKey: project.id)
        let (viewModel, _) = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.selectedProject?.id == project.id)
        #expect(viewModel.lastUsedProjectID == project.id)
    }

    @Test("プロジェクト見出しの＋入口はそのプロジェクトを選ぶ")
    func plusEntrySelectsItsProject() async {
        let (viewModel, _) = makeViewModel(entry: SessionComposeDraft(project: "Gardenia", projectID: "gardenia-id"))

        await viewModel.load()

        #expect(viewModel.selectedProject?.name == "Gardenia")
        #expect(viewModel.selectedProject?.projectID == "gardenia-id")
    }

    @Test("前回のプロジェクトが一覧から消えたら未選択にする")
    func missingLastProjectStartsUnselected() async {
        let store = makeStore()
        store.record(kind: .claudeCode, model: nil, effort: nil, permission: nil, planMode: false, projectKey: "deleted")
        let (viewModel, _) = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.selectedProjectID == nil)
    }

    @Test("プロジェクト 0 件なら未選択で、送信しても spawn しない")
    func emptyProjectsRequireSelection() async {
        let (viewModel, api) = makeViewModel(projects: [])
        await viewModel.load()
        viewModel.inputText = "依頼"

        await viewModel.send { _, _ in Issue.record("プロジェクト未選択では遷移しない") }

        #expect(viewModel.projects.isEmpty)
        #expect(viewModel.projectValidationMessage == "プロジェクトを選んでください")
        #expect(await api.lastSpawnRequest == nil)
    }

    @Test("古い Mac の nil project 一覧はセッションから作り、名前を projectID として送らない")
    func legacyProjectFallbackDoesNotSendNameAsID() async throws {
        let legacySession = Session(
            id: "legacy-session",
            name: "Gardenia task",
            agent: .claudeCode,
            status: .idle,
            subtitle: "Gardenia",
            projectName: "Gardenia",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let (viewModel, api) = makeViewModel(
            entry: SessionComposeDraft(project: "Gardenia"),
            projects: nil,
            sessions: [legacySession]
        )
        await viewModel.load()
        viewModel.inputText = "依頼"

        await viewModel.send { _, _ in }

        let request = try #require(await api.lastSpawnRequest)
        #expect(viewModel.selectedProject?.name == "Gardenia")
        #expect(request.workspace == "Gardenia")
        #expect(request.projectID == nil)
    }

    @Test("前回使ったエージェントと設定を Mac と同じキーで復元する")
    func restoresLastUsedAgentModelAndSettings() async {
        let store = makeStore()
        store.record(kind: .codex, model: "gpt-5-codex", effort: "medium", permission: ":workspace", planMode: true, projectKey: project.id)
        let (viewModel, _) = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.selectedAgent == .codex)
        #expect(viewModel.selectedModelID == "gpt-5-codex")
        #expect(viewModel.selectedEffort == "medium")
        #expect(viewModel.selectedPermission == ":workspace")
        #expect(viewModel.planMode)
    }

    @Test("保存値が無いときは Mac から届いた既定を使う")
    func firstRunDefaultsMatchMac() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load()

        #expect(viewModel.selectedAgent == .claudeCode)
        #expect(viewModel.selectedModelID == "sonnet")
        #expect(viewModel.selectedEffort == "high")
        #expect(viewModel.selectedPermission == "auto")
        #expect(!viewModel.planMode)
    }

    @Test("Mac が Bypass を既定として返したときはその値を使う")
    func usesMacReportedBypassDefault() async {
        var settings = Self.settings
        settings[.claudeCode] = AgentSettings(
            availableEfforts: settings[.claudeCode]!.availableEfforts,
            availablePermissions: settings[.claudeCode]!.availablePermissions,
            planModeAvailable: true,
            defaultEfforts: ["sonnet": "high", "opus": "medium"],
            defaultPermission: "bypassPermissions"
        )
        let (viewModel, _) = makeViewModel(settings: settings)

        await viewModel.load()

        #expect(viewModel.selectedPermission == "bypassPermissions")
    }

    @Test("古い Mac が既定キーを返さないときは推論強度と権限を送らない")
    func missingMacDefaultsStayUnspecifiedThroughSpawn() async throws {
        let legacySettings = Self.settings.mapValues { settings in
            AgentSettings(
                availableEfforts: settings.availableEfforts,
                availablePermissions: settings.availablePermissions,
                planModeAvailable: settings.planModeAvailable
            )
        }
        let (viewModel, api) = makeViewModel(settings: legacySettings)
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "指示"

        #expect(viewModel.selectedEffort == nil)
        #expect(viewModel.selectedPermission == nil)
        await viewModel.send { _, _ in }

        let request = try #require(await api.lastSpawnRequest)
        #expect(request.effort == nil)
        #expect(request.permission == nil)
    }

    @Test("保存された権限が現在の選択肢に無ければ Mac の既定へ戻す")
    func invalidSavedPermissionFallsBackToMacDefault() async {
        let store = makeStore()
        store.record(kind: .claudeCode, model: "sonnet", effort: "high", permission: "ask", planMode: false, projectKey: project.id)
        let (viewModel, _) = makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.selectedPermission == "auto")
    }

    @Test("同じエージェントのモデル変更は推論だけ既定へ戻し権限と Plan を保つ")
    func sameAgentModelChangePreservesPermissionAndPlan() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        viewModel.selectPermission("manual")
        viewModel.selectPlanMode(true)

        viewModel.selectModel(entryID: "claudeCode::opus")

        #expect(viewModel.selectedAgent == .claudeCode)
        #expect(viewModel.selectedEffort == "medium")
        #expect(viewModel.selectedPermission == "manual")
        #expect(viewModel.planMode)
    }

    @Test("エージェント変更時は選んだモデルの強度と前回設定へ戻す")
    func modelSelectionChangesAgentAndRestoresItsSavedSettings() async {
        let defaults = UserDefaults(suiteName: "NewChatViewModelTests.\(UUID().uuidString)")!
        let store = NewChatSettingsStore(defaults: defaults)
        store.record(kind: .codex, model: "gpt-5-codex", effort: "medium", permission: ":workspace", planMode: true, projectKey: project.id)
        defaults.set(AgentKind.claudeCode.rawValue, forKey: "phlox.newChat.lastHarness")
        let (viewModel, _) = makeViewModel(store: store)
        await viewModel.load()
        viewModel.selectPermission("bypassPermissions")
        viewModel.selectPlanMode(true)

        viewModel.selectModel(entryID: "codex::gpt-5-codex")

        #expect(viewModel.selectedAgent == .codex)
        #expect(viewModel.selectedModelID == "gpt-5-codex")
        #expect(viewModel.selectedEffort == "medium")
        #expect(viewModel.selectedPermission == ":workspace")
        #expect(viewModel.planMode)
    }

    @Test("Codex のカタログ行を選ぶと選択したモデルを spawn に渡す")
    func selectedCodexModelReachesSpawnRequest() async throws {
        let (viewModel, api) = makeViewModel()
        await viewModel.load()
        viewModel.selectModel(entryID: "codex::gpt-5-codex")
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "Codex で始める"

        await viewModel.send { _, _ in }

        let request = try #require(await api.lastSpawnRequest)
        #expect(request.agent == .codex)
        #expect(request.model == "gpt-5-codex")
    }

    @Test("モデル一覧取得失敗のエージェントも欄を残し、選択できない状態にする")
    func unavailableAgentRemainsInPicker() async {
        let (viewModel, _) = makeViewModel(unavailableKinds: [.cursor])

        await viewModel.load()

        #expect(viewModel.modelSections.map(\.kind) == [.claudeCode, .codex, .cursor])
        #expect(viewModel.modelSections.last?.isUnavailable == true)
        #expect(viewModel.modelEntries.allSatisfy { $0.kind != .cursor })
    }

    @Test("spawn → 準備待ち → 送信を順に行い、指定された全項目を spawn に渡す")
    func spawnWaitAndSendInOrder() async throws {
        let (viewModel, api) = makeViewModel()
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "最初の指示"
        viewModel.selectPermission("auto")
        viewModel.selectPlanMode(true)
        var completion: (Session, SessionDetailRecovery?)?

        await viewModel.send { completion = ($0, $1) }

        let request = try #require(await api.lastSpawnRequest)
        #expect(request.agent == .claudeCode)
        #expect(request.workspace == "Phlox")
        #expect(request.projectID == "project-1")
        #expect(request.prompt == nil)
        #expect(request.model == "sonnet")
        #expect(request.effort == "high")
        #expect(request.permission == "auto")
        #expect(request.planMode == true)
        #expect(await api.events == ["spawn", "ready:new-session", "send:new-session"])
        #expect(viewModel.progressHistory == [.idle, .creating, .waiting, .sending, .idle])
        #expect(completion?.0.id == "new-session")
        #expect(completion?.1 == nil)
        #expect(viewModel.inputText.isEmpty)
    }

    @Test("作成応答待ちから発言と進捗を表示し、送信本文を凍結する")
    func pendingSpawnShowsFrozenSubmission() async throws {
        let (viewModel, api) = makeViewModel()
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "  最初の指示\n"
        #expect(viewModel.canEditDraft)
        await api.pauseNextSpawn()
        var completed = false

        let sending = Task { @MainActor in
            await viewModel.send { _, _ in completed = true }
        }
        await api.waitForPausedSpawn()

        #expect(viewModel.progressStage == .creating)
        #expect(viewModel.showsSubmittedConversation)
        #expect(viewModel.isSending)
        #expect(!viewModel.canEditDraft)
        #expect(!viewModel.hasCreatedSession)
        #expect(viewModel.submittedText == "  最初の指示\n")
        #expect(!completed)
        viewModel.inputText = "後から変更した指示"
        viewModel.inputCursorUTF16 = viewModel.inputText.utf16.count
        #expect(viewModel.submittedText == "  最初の指示\n")
        await viewModel.send { _, _ in Issue.record("作成待ちの二重送信では遷移しない") }
        #expect(await api.events == ["spawn"])

        await api.resumeSpawn()
        await sending.value

        let request = try #require(await api.lastSendRequest)
        #expect(request.text == "最初の指示")
        #expect(completed)
        #expect(viewModel.hasCreatedSession)
        #expect(viewModel.progressStage == .idle)
        #expect(!viewModel.canEditDraft)
        #expect(viewModel.inputText == "後から変更した指示")
        #expect(viewModel.inputCursorUTF16 == "後から変更した指示".utf16.count)
    }

    @Test("作成待ちで失敗したら発言表示を閉じ、下書きと添付を再送できる")
    func pendingSpawnFailurePreservesDraftForRetry() async throws {
        let (viewModel, api) = makeViewModel()
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        await viewModel.addAttachments([Self.pngAttachment])
        viewModel.inputText += "元の指示"
        let original = viewModel.inputText
        let originalItems = viewModel.attachmentItems
        await api.pauseNextSpawn()

        let sending = Task { @MainActor in
            await viewModel.send { _, _ in Issue.record("作成失敗では遷移しない") }
        }
        await api.waitForPausedSpawn()
        #expect(viewModel.showsSubmittedConversation)
        #expect(!viewModel.canEditDraft)
        #expect(viewModel.submittedText == original)
        await api.resumeSpawn(with: .failure(.spawnRejected(reason: "workspace is locked")))
        await sending.value

        #expect(viewModel.progressStage == .idle)
        #expect(!viewModel.showsSubmittedConversation)
        #expect(!viewModel.hasCreatedSession)
        #expect(viewModel.canEditDraft)
        #expect(viewModel.submittedText == nil)
        #expect(viewModel.inputText == original)
        #expect(viewModel.attachmentItems.map(\.id) == originalItems.map(\.id))
        #expect(viewModel.creationErrorPresentation?.technicalDetail == "workspace is locked")
        #expect(await api.events == ["spawn"])

        viewModel.inputText += "を再送"
        let retriedText = viewModel.inputText
        var completed = false
        await viewModel.send { _, recovery in
            #expect(recovery == nil)
            completed = true
        }

        let request = try #require(await api.lastSendRequest)
        #expect(completed)
        #expect(viewModel.submittedText == retriedText)
        #expect(viewModel.creationErrorPresentation == nil)
        #expect(request.text == retriedText.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(request.images.count == 1)
        #expect(await api.events == ["spawn", "spawn", "ready:new-session", "send:new-session"])
    }

    @Test("nil の設定は SpawnRequest でも nil のまま")
    func spawnKeepsUnavailableOptionalSettingsNil() async throws {
        let (viewModel, api) = makeViewModel(settings: [:])
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "指示"

        await viewModel.send { _, _ in }

        let request = try #require(await api.lastSpawnRequest)
        #expect(request.effort == nil)
        #expect(request.permission == nil)
        #expect(request.planMode == false)
    }

    @Test("作成失敗は Mac の理由を表示し、本文を残して準備待ちへ進まない")
    func spawnFailureKeepsTextAndReason() async throws {
        let (viewModel, api) = makeViewModel(spawn: .failure(.spawnRejected(reason: "workspace is locked")))
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "元の指示"

        await viewModel.send { _, _ in Issue.record("作成失敗では遷移しない") }

        #expect(viewModel.inputText == "元の指示")
        let presentation = try #require(viewModel.creationErrorPresentation)
        #expect(presentation.title == "セッションを作れませんでした")
        #expect(presentation.cause == "Mac がこの作成を受け付けませんでした。Mac にセッションは作られていません。")
        #expect(presentation.nextStep == "理由を確かめてから、もう一度送信してください。指示は入力欄に戻してあります。")
        #expect(presentation.technicalDetail == "workspace is locked")
        #expect(await api.events == ["spawn"])
    }

    @Test("読めない画像は受理時に A5 を出し、本文を保持し、セッションを作らない")
    func unreadableImageUsesCatalogCopyAtIntake() async {
        let (viewModel, api) = makeViewModel()
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        viewModel.inputText = "この画像を見て"
        await viewModel.addAttachments([SendAttachment(mediaType: "image/png", data: Data([0x00]))])

        #expect(viewModel.attachmentError == "画像を読み込めませんでした")
        #expect(viewModel.attachmentItems.isEmpty)
        #expect(viewModel.inputText == "この画像を見て")
        #expect(await api.events.isEmpty)
    }

    @Test("準備待ちが間に合わなければ作成済みセッションへ本文と添付を戻す")
    func readyTimeoutRecoversTextAndAttachments() async throws {
        let (viewModel, api) = makeViewModel(ready: .success(false))
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        await viewModel.addAttachments([Self.pngAttachment])
        viewModel.inputText += "テストしてください"
        var recovery: SessionDetailRecovery?

        await viewModel.send { _, draft in recovery = draft }

        let restored = try #require(recovery)
        #expect(restored.text == viewModel.submittedText)
        #expect(restored.attachments.map(\.number) == [1])
        #expect(restored.errorMessage == "送信に失敗しました · Mac に接続できません")
        #expect(await api.events == ["spawn", "ready:new-session"])
    }

    @Test("送信失敗でも同じセッションへ本文と添付を戻す")
    func sendFailureRecoversTextAndAttachments() async throws {
        let (viewModel, api) = makeViewModel(send: .failure(.unreachable))
        await viewModel.load()
        viewModel.selectProject(id: project.id)
        await viewModel.addAttachments([Self.pngAttachment])
        viewModel.inputText += "確認してください"
        let original = viewModel.inputText
        var createdSession: Session?
        var recovery: SessionDetailRecovery?

        await viewModel.send { createdSession = $0; recovery = $1 }

        let restored = try #require(recovery)
        #expect(createdSession?.id == "new-session")
        #expect(restored.text == original)
        #expect(restored.attachments.map(\.number) == [1])
        #expect(await api.events == ["spawn", "ready:new-session", "send:new-session"])

        viewModel.inputText = original
        await viewModel.send { _, _ in Issue.record("作成済みセッションを二重作成しない") }
        #expect(await api.events == ["spawn", "ready:new-session", "send:new-session"])
    }

    private static let pngAttachment = SendAttachment(
        mediaType: "image/png",
        data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
    )

    private func makeStore() -> NewChatSettingsStore {
        let suite = "NewChatViewModelTests.\(UUID().uuidString)"
        return NewChatSettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeViewModel(
        entry: SessionComposeDraft = SessionComposeDraft(project: ""),
        projects: [ProjectSummary]?? = .some([ProjectSummary(id: "project-1", name: "Phlox"), ProjectSummary(id: "gardenia-id", name: "Gardenia")]),
        sessions: [Session] = [],
        store: NewChatSettingsStore? = nil,
        unavailableKinds: Set<AgentKind> = [],
        catalogs: [AgentKind: AgentModels]? = nil,
        settings: [AgentKind: AgentSettings]? = nil,
        spawn: Result<Session, PhloxError> = .success(.init(
            id: "new-session", name: "New Session", agent: .claudeCode,
            status: .starting, subtitle: "Phlox", projectId: "project-1", projectName: "Phlox",
            updatedAt: Date(timeIntervalSince1970: 2)
        )),
        ready: Result<Bool, PhloxError> = .success(true),
        send: Result<SendResult, PhloxError> = .success(SendResult(accepted: true))
    ) -> (NewChatViewModel, NewChatTestAPI) {
        var resolvedCatalogs = catalogs ?? Self.catalogs
        for kind in unavailableKinds { resolvedCatalogs.removeValue(forKey: kind) }
        let api = NewChatTestAPI(
            projects: projects ?? nil,
            hasProjectResponse: projects != nil,
            sessions: sessions,
            catalogs: resolvedCatalogs,
            settings: settings ?? Self.settings,
            spawn: spawn,
            ready: ready,
            send: send
        )
        return (
            NewChatViewModel(api: api, entryProject: entry, settingsStore: store ?? makeStore()),
            api
        )
    }

    private static let catalogs: [AgentKind: AgentModels] = [
        .claudeCode: AgentModels(models: [
            SessionModelOption(id: "sonnet", displayName: "Sonnet 5"),
            SessionModelOption(id: "opus", displayName: "Opus 5"),
        ], defaultModel: "sonnet"),
        .codex: AgentModels(models: [
            SessionModelOption(id: "gpt-5-codex", displayName: "GPT-5 Codex"),
        ], defaultModel: "gpt-5-codex"),
        .cursor: AgentModels(models: [
            SessionModelOption(id: "composer-2.5", displayName: "Composer 2.5"),
        ], defaultModel: "composer-2.5"),
    ]

    private static let settings: [AgentKind: AgentSettings] = [
        .claudeCode: AgentSettings(
            availableEfforts: [
                "sonnet": [AgentSettingOption(value: "high", displayName: "高")],
                "opus": [AgentSettingOption(value: "medium", displayName: "中")],
            ],
            availablePermissions: [
                AgentSettingOption(value: "auto", displayName: "Auto"),
                AgentSettingOption(value: "manual", displayName: "Manual"),
                AgentSettingOption(value: "bypassPermissions", displayName: "Bypass Permissions"),
            ],
            planModeAvailable: true,
            defaultEfforts: ["sonnet": "high", "opus": "medium"],
            defaultPermission: "auto"
        ),
        .codex: AgentSettings(
            availableEfforts: ["gpt-5-codex": [AgentSettingOption(value: "medium", displayName: "中")]],
            availablePermissions: [
                AgentSettingOption(value: ":read-only", displayName: "Read Only"),
                AgentSettingOption(value: ":workspace", displayName: "Default"),
                AgentSettingOption(value: ":danger-full-access", displayName: "Full Access"),
            ],
            planModeAvailable: true,
            defaultEfforts: ["gpt-5-codex": "medium"]
        ),
        .cursor: AgentSettings(
            availableEfforts: ["composer-2.5": [AgentSettingOption(value: "medium", displayName: "中")]],
            availablePermissions: [
                AgentSettingOption(value: nil, displayName: "既定"),
                AgentSettingOption(value: "ask", displayName: "Ask"),
            ],
            planModeAvailable: true,
            defaultEfforts: ["composer-2.5": "medium"]
        ),
    ]
}

private actor NewChatTestAPI: PhloxAPI {
    private let projectResponse: [ProjectSummary]?
    private let hasProjectResponse: Bool
    private let sessions: [Session]
    private let catalogs: [AgentKind: AgentModels]
    private let settings: [AgentKind: AgentSettings]
    private let spawnOutcome: Result<Session, PhloxError>
    private let readyOutcome: Result<Bool, PhloxError>
    private let sendOutcome: Result<SendResult, PhloxError>
    private(set) var events: [String] = []
    private(set) var lastSpawnRequest: SpawnRequest?
    private(set) var lastSendRequest: SendRequest?
    private var pausesNextSpawn = false
    private var spawnContinuation: CheckedContinuation<Void, Never>?
    private var pausedSpawnObserver: CheckedContinuation<Void, Never>?
    private var resumedSpawnOutcome: Result<Session, PhloxError>?

    func pauseNextSpawn() {
        pausesNextSpawn = true
    }

    func waitForPausedSpawn() async {
        guard spawnContinuation == nil else { return }
        await withCheckedContinuation { pausedSpawnObserver = $0 }
    }

    func resumeSpawn(with outcome: Result<Session, PhloxError>? = nil) {
        resumedSpawnOutcome = outcome
        spawnContinuation?.resume()
        spawnContinuation = nil
    }

    init(
        projects: [ProjectSummary]?,
        hasProjectResponse: Bool,
        sessions: [Session],
        catalogs: [AgentKind: AgentModels],
        settings: [AgentKind: AgentSettings],
        spawn: Result<Session, PhloxError>,
        ready: Result<Bool, PhloxError>,
        send: Result<SendResult, PhloxError>
    ) {
        self.projectResponse = projects
        self.hasProjectResponse = hasProjectResponse
        self.sessions = sessions
        self.catalogs = catalogs
        self.settings = settings
        self.spawnOutcome = spawn
        self.readyOutcome = ready
        self.sendOutcome = send
    }

    func listSessions() async throws -> [Session] { sessions }
    func projects() async throws -> [ProjectSummary]? { hasProjectResponse ? projectResponse : nil }
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        guard let catalog = catalogs[kind] else { throw PhloxError.notFound }
        return catalog
    }
    func agentSettings(kind: AgentKind) async throws -> AgentSettings? { settings[kind] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        events.append("spawn")
        lastSpawnRequest = request
        if pausesNextSpawn {
            pausesNextSpawn = false
            await withCheckedContinuation { continuation in
                spawnContinuation = continuation
                pausedSpawnObserver?.resume()
                pausedSpawnObserver = nil
            }
            if let outcome = resumedSpawnOutcome {
                resumedSpawnOutcome = nil
                return try outcome.get()
            }
        }
        return try spawnOutcome.get()
    }
    func waitUntilReady(sessionID: String) async throws -> Bool {
        events.append("ready:\(sessionID)")
        return try readyOutcome.get()
    }
    func send(_ request: SendRequest) async throws -> SendResult {
        events.append("send:\(request.sessionID)")
        lastSendRequest = request
        return try sendOutcome.get()
    }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func rename(sessionID: String, name: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
