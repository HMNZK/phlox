import Foundation
import Observation
import AgentDomain
import ImageAttachmentKit
import PhloxCore

public struct NewChatProject: Identifiable, Equatable, Sendable {
    /// API project id, or a local stable key for projects reconstructed from legacy sessions.
    public let id: String
    public let name: String
    public let projectID: String?

    public init(id: String, name: String, projectID: String?) {
        self.id = id
        self.name = name
        self.projectID = projectID
    }
}

public struct NewChatSuggestion: Identifiable, Equatable, Sendable {
    public let title: String
    public let text: String
    public let symbol: String

    public var id: String { title }

    public init(title: String, text: String, symbol: String) {
        self.title = title
        self.text = text
        self.symbol = symbol
    }
}

public struct NewChatModelEntry: Identifiable, Equatable, Sendable {
    public let kind: AgentKind
    public let model: SessionModelOption

    public var id: String { "\(kind.rawValue)::\(model.id)" }
}

public struct NewChatAgentModelSection: Identifiable, Equatable, Sendable {
    public let kind: AgentKind
    public let models: [SessionModelOption]?
    public let defaultModel: String?

    public var id: AgentKind { kind }
    public var isUnavailable: Bool { models == nil }
}

/// 新規チャットで最後に使ったエージェントと設定を端末に保存する。
@MainActor
public struct NewChatSettingsStore {
    private let defaults: UserDefaults
    private static let prefix = "phlox.lastUsedChatSettings"
    private static let lastAgentKey = "phlox.newChat.lastHarness"
    private static let lastProjectKey = "phlox.newChat.lastProject"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastAgent: AgentKind? {
        defaults.string(forKey: Self.lastAgentKey).flatMap(AgentKind.init(rawValue:))
    }

    public var lastProjectKey: String? {
        defaults.string(forKey: Self.lastProjectKey)
    }

    public func lastSettings(for kind: AgentKind) -> LastUsedSettings? {
        let base = "\(Self.prefix).\(kind.rawValue)"
        let model = defaults.string(forKey: "\(base).model")
        let effort = defaults.string(forKey: "\(base).effort")
        let permission = defaults.string(forKey: "\(base).permission")
        let planMode = defaults.object(forKey: "\(base).planMode") as? Bool
        guard model != nil || effort != nil || permission != nil || planMode != nil else { return nil }
        return LastUsedSettings(model: model, effort: effort, permission: permission, planMode: planMode)
    }

    public func record(
        kind: AgentKind,
        model: String?,
        effort: String?,
        permission: String?,
        planMode: Bool,
        projectKey: String
    ) {
        let base = "\(Self.prefix).\(kind.rawValue)"
        Self.set(model, forKey: "\(base).model", in: defaults)
        Self.set(effort, forKey: "\(base).effort", in: defaults)
        Self.set(permission, forKey: "\(base).permission", in: defaults)
        defaults.set(planMode, forKey: "\(base).planMode")
        defaults.set(kind.rawValue, forKey: Self.lastAgentKey)
        defaults.set(projectKey, forKey: Self.lastProjectKey)
    }

    private static func set(_ value: String?, forKey key: String, in defaults: UserDefaults) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

public struct LastUsedSettings: Equatable, Sendable {
    public let model: String?
    public let effort: String?
    public let permission: String?
    public let planMode: Bool?
}

public enum NewChatProgressStage: Equatable, Sendable {
    case idle
    case creating
    case waiting
    case sending
}

/// 新規チャット画面の選択・添付・作成と初回送信をまとめる。
@MainActor
@Observable
public final class NewChatViewModel {
    public static let greetings = [
        "何から始めますか？", "今日は何を進めますか？", "さあ、始めましょう", "次は何を作りますか？",
        "どこから手をつけますか？", "アイデアを形にしましょう", "今日の課題を教えてください",
        "どんな変更を加えますか？", "続きを進めましょう", "何をお手伝いしましょうか？",
    ]

    public static func greeting(fixed: String? = nil) -> String {
        fixed ?? greetings.randomElement() ?? greetings[0]
    }

    public static let suggestions = [
        NewChatSuggestion(title: "コードレビュー", text: "未コミットの変更をレビューして、問題点を重要度順に挙げてください。", symbol: "magnifyingglass"),
        NewChatSuggestion(title: "バグ修正", text: "次の不具合を調べて、根本原因を直してください: ", symbol: "ladybug"),
        NewChatSuggestion(title: "テスト追加", text: "次の機能にテストを追加してください: ", symbol: "checkmark.circle"),
        NewChatSuggestion(title: "コードの説明", text: "このプロジェクトの構成と主な処理の流れを説明してください。", symbol: "book"),
        NewChatSuggestion(title: "リファクタ", text: "次のコードを、振る舞いを変えずに読みやすく整理してください: ", symbol: "arrow.triangle.2.circlepath"),
    ]

    private let api: PhloxAPI
    private let settingsStore: NewChatSettingsStore
    private let entryProject: SessionComposeDraft
    private var didLoad = false

    public private(set) var projects: [NewChatProject] = []
    public private(set) var modelSections: [NewChatAgentModelSection] = []
    public private(set) var settingsByAgent: [AgentKind: AgentSettings] = [:]
    public private(set) var selectedProjectID: String?
    public private(set) var selectedAgent: AgentKind
    public private(set) var selectedModelID: String?
    public private(set) var selectedEffort: String?
    public private(set) var selectedPermission: String?
    public private(set) var planMode = false
    public private(set) var projectValidationMessage: String?
    public private(set) var creationErrorPresentation: ErrorPresentation?
    public private(set) var attachmentError: String?
    public private(set) var progressStage: NewChatProgressStage = .idle
    public private(set) var progressHistory: [NewChatProgressStage] = [.idle]
    public private(set) var hasCreatedSession = false
    public private(set) var submittedText: String?
    public private(set) var readyWaitSeconds = 0
    public private(set) var attachmentItems: [SessionDetailViewModel.SessionAttachmentItem] = []
    public var inputText = "" {
        didSet { skillSuggestions.reconcile(text: inputText, context: skillContext) }
    }
    public var inputCursorUTF16 = 0
    let skillSuggestions = MobileSkillSuggestions()
    var skillContext: MobileSkillSuggestions.Context {
        .agent(selectedAgent, projectID: selectedProject?.projectID, workspace: selectedProject?.name)
    }
    var skillRequestContext: MobileSkillSuggestions.Context? {
        SkillSuggestionQuery.detect(text: inputText, cursorUTF16: inputCursorUTF16) == nil ? nil : skillContext
    }
    func loadSkillSuggestions() async { await skillSuggestions.load(api: api, context: skillRequestContext) }
    public private(set) var focusRequest = 0
    public var isModelPickerPresented = false
    public var usesWorktree = false
    public private(set) var startPoints: [NewChatStartPoint] = []
    public private(set) var historyEntries: [NewChatHistoryEntry] = []
    public private(set) var selectedStartPoint = NewChatStartPoint(kind: .head, title: "今の位置（HEAD）")
    public private(set) var selectedHistoryID: String?
    public private(set) var launchOptionsError: String?
    public private(set) var isLoadingLaunchOptions = false
    private var launchOptionsGeneration = 0

    public var isSending: Bool { progressStage != .idle }
    public var canEditDraft: Bool { !isSending && !hasCreatedSession }
    public var showsSubmittedConversation: Bool { isSending || hasCreatedSession }

    public var selectedProject: NewChatProject? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    public var lastUsedProjectID: String? { settingsStore.lastProjectKey }

    public var selectedModelDisplayName: String {
        guard let section = modelSections.first(where: { $0.kind == selectedAgent }),
              let models = section.models
        else { return "取得できません" }
        guard let selectedModelID else { return "既定" }
        return models.first(where: { $0.id == selectedModelID })?.displayName ?? "既定"
    }

    public var selectedEffortOptions: [AgentSettingOption] {
        guard let settings = settingsByAgent[selectedAgent] else { return [] }
        return settings.availableEfforts[selectedModelID ?? ""] ?? []
    }

    public var selectedPermissionOptions: [AgentSettingOption] {
        settingsByAgent[selectedAgent]?.availablePermissions ?? []
    }

    public var planModeAvailable: Bool {
        settingsByAgent[selectedAgent]?.planModeAvailable ?? false
    }

    public var selectedEntryID: String? {
        guard let selectedModelID else { return nil }
        return "\(selectedAgent.rawValue)::\(selectedModelID)"
    }

    public var modelEntries: [NewChatModelEntry] {
        modelSections.flatMap { section in
            (section.models ?? []).map { NewChatModelEntry(kind: section.kind, model: $0) }
        }
    }

    public var defaultEntryIDs: Set<String> {
        Set(modelSections.compactMap { section in
            section.defaultModel.map { "\(section.kind.rawValue)::\($0)" }
        })
    }

    public init(
        api: PhloxAPI,
        entryProject: SessionComposeDraft,
        settingsStore: NewChatSettingsStore = NewChatSettingsStore()
    ) {
        self.api = api
        self.entryProject = entryProject
        self.settingsStore = settingsStore
        self.selectedAgent = settingsStore.lastAgent ?? .claudeCode
    }

    public func load() async {
        guard !didLoad else { return }
        didLoad = true

        enum LoadResult {
            case projects([ProjectSummary]?)
            case sessions([Session]?)
            case models(AgentKind, AgentModels?)
            case settings(AgentKind, AgentSettings?)
        }

        let kinds: [AgentKind] = [.claudeCode, .codex, .cursor]
        let apiClient = api
        let results = await withTaskGroup(of: LoadResult.self, returning: [LoadResult].self) { group in
            group.addTask {
                do { return .projects(try await apiClient.projects()) }
                catch { return .projects(nil) }
            }
            group.addTask {
                do { return .sessions(try await apiClient.listSessions()) }
                catch { return .sessions(nil) }
            }
            for kind in kinds {
                group.addTask {
                    do { return .models(kind, try await apiClient.agentModels(kind: kind)) }
                    catch { return .models(kind, nil) }
                }
                group.addTask {
                    do { return .settings(kind, try await apiClient.agentSettings(kind: kind)) }
                    catch { return .settings(kind, nil) }
                }
            }
            var values: [LoadResult] = []
            for await result in group { values.append(result) }
            return values
        }

        var projectResponse: [ProjectSummary]?
        var sessionFallback: [Session]?
        var catalogs: [AgentKind: AgentModels] = [:]
        var loadedSettings: [AgentKind: AgentSettings] = [:]
        for result in results {
            switch result {
            case .projects(let projects): projectResponse = projects
            case .sessions(let sessions): sessionFallback = sessions
            case .models(let kind, let models): if let models { catalogs[kind] = models }
            case .settings(let kind, let settings): if let settings { loadedSettings[kind] = settings }
            }
        }

        settingsByAgent = loadedSettings
        modelSections = kinds.map { kind in
            let catalog = catalogs[kind]
            return NewChatAgentModelSection(kind: kind, models: catalog?.models, defaultModel: catalog?.defaultModel)
        }
        projects = projectResponse.map(Self.projects(from:)) ?? Self.legacyProjects(from: sessionFallback ?? [])

        if !kinds.contains(selectedAgent) { selectedAgent = .claudeCode }
        let saved = settingsStore.lastSettings(for: selectedAgent)
        let section = modelSections.first(where: { $0.kind == selectedAgent })
        let availableModels = section?.models ?? []
        let savedModel = saved?.model.flatMap { value in availableModels.first(where: { $0.id == value })?.id }
        selectedModelID = savedModel ?? section?.defaultModel.flatMap { value in
            availableModels.first(where: { $0.id == value })?.id
        } ?? availableModels.first?.id
        selectedEffort = valid(saved?.effort, among: effortOptions(for: selectedAgent, modelID: selectedModelID))
            ?? defaultEffort(for: selectedAgent, modelID: selectedModelID)
        selectedPermission = validPermission(saved?.permission, kind: selectedAgent)
            ?? defaultPermission(for: selectedAgent)
        planMode = saved?.planMode == true && (settingsByAgent[selectedAgent]?.planModeAvailable ?? false)

        if entryProject.projectID != nil || !entryProject.project.isEmpty {
            selectedProjectID = projects.first(where: { project in
                if let projectID = entryProject.projectID { return project.projectID == projectID }
                return project.name == entryProject.project
            })?.id
        } else if let lastProject = settingsStore.lastProjectKey,
                  projects.contains(where: { $0.id == lastProject }) {
            selectedProjectID = lastProject
        } else {
            selectedProjectID = nil
        }
    }

    public func selectProject(id: String?) {
        guard id == nil || projects.contains(where: { $0.id == id }) else { return }
        if selectedProjectID != id { resetLaunchOptions() }
        selectedProjectID = id
        projectValidationMessage = nil
    }

    public func appendSuggestion(_ index: Int) {
        guard Self.suggestions.indices.contains(index) else { return }
        let suggestion = Self.suggestions[index].text
        inputText = inputText.isEmpty ? suggestion : inputText + "\n" + suggestion
        inputCursorUTF16 = inputText.utf16.count
        focusRequest &+= 1
    }

    public func selectModel(entryID: String) {
        guard let entry = modelEntries.first(where: { $0.id == entryID }) else { return }
        let agentChanged = entry.kind != selectedAgent
        let saved = agentChanged ? settingsStore.lastSettings(for: entry.kind) : nil
        selectedAgent = entry.kind
        selectedModelID = entry.model.id
        selectedEffort = defaultEffort(for: entry.kind, modelID: entry.model.id)
        if agentChanged {
            resetLaunchOptions()
            selectedPermission = validPermission(saved?.permission, kind: entry.kind)
                ?? defaultPermission(for: entry.kind)
            planMode = saved?.planMode == true && (settingsByAgent[entry.kind]?.planModeAvailable ?? false)
        }
        isModelPickerPresented = false
    }

    private func resetLaunchOptions() {
        launchOptionsGeneration &+= 1
        startPoints = []
        historyEntries = []
        selectedHistoryID = nil
        selectedStartPoint = NewChatStartPoint(kind: .head, title: "今の位置（HEAD）")
        usesWorktree = false
        launchOptionsError = nil
        isLoadingLaunchOptions = false
    }

    public func loadLaunchOptions(commit: String? = nil) async {
        guard let projectID = selectedProject?.projectID else { return }
        launchOptionsGeneration &+= 1
        let generation = launchOptionsGeneration
        let kind = selectedAgent
        isLoadingLaunchOptions = true
        launchOptionsError = nil
        defer { if generation == launchOptionsGeneration { isLoadingLaunchOptions = false } }
        do {
            let points = try await api.projectStartPoints(projectID: projectID, commit: commit)
            guard generation == launchOptionsGeneration else { return }
            startPoints = points
        } catch {
            guard generation == launchOptionsGeneration else { return }
            launchOptionsError = "起点を取得できませんでした。Macを更新するか、再試行してください。"
        }
        guard generation == launchOptionsGeneration else { return }
        if kind == .claudeCode || kind == .codex {
            do {
                let entries = try await api.projectHistory(projectID: projectID, kind: kind)
                guard generation == launchOptionsGeneration else { return }
                historyEntries = entries
                if let selectedHistoryID, !entries.contains(where: { $0.id == selectedHistoryID }) {
                    self.selectedHistoryID = nil
                }
            } catch {
                guard generation == launchOptionsGeneration else { return }
                launchOptionsError = "履歴を取得できませんでした。Macを更新するか、再試行してください。"
            }
        } else {
            historyEntries = []
            selectedHistoryID = nil
        }
    }

    public func selectStartPoint(_ point: NewChatStartPoint) {
        guard startPoints.contains(where: { $0.id == point.id }) else { return }
        selectedStartPoint = point
    }

    public func selectHistory(_ entry: NewChatHistoryEntry?) {
        guard entry == nil || historyEntries.contains(where: { $0.id == entry?.id }) else { return }
        selectedHistoryID = entry?.id
    }

    public func selectEffort(_ value: String?) {
        guard value == nil || selectedEffortOptions.contains(where: { $0.value == value }) else { return }
        selectedEffort = value
    }

    public func selectPermission(_ value: String?) {
        guard value == nil || selectedPermissionOptions.contains(where: { $0.value == value }) else { return }
        selectedPermission = value
        planMode = false
    }

    public func selectPlanMode(_ value: Bool) {
        planMode = value && planModeAvailable
    }

    public func attachmentLimitReached() {
        attachmentError = ImageAttachmentLimits.countMessage
    }

    public func addAttachments(_ candidates: [SendAttachment]) async {
        await addAttachmentLoadResults(candidates.map { .success($0) })
    }

    public func addAttachmentLoadResults(_ candidates: [Result<SendAttachment, Error>]) async {
        guard !candidates.isEmpty else { return }
        let previews = await Task.detached(priority: .userInitiated) {
            candidates.map { candidate in
                Result { try ImageAttachmentPreparer.validatedPreview(try candidate.get().data) }
            }
        }.value
        attachmentError = nil
        var total = attachmentItems.reduce(0) { $0 + $1.send.data.count }
        var numbers = attachmentItems.map(\.number)
        for (index, result) in candidates.enumerated() {
            guard case .success(let candidate) = result else {
                attachmentError = attachmentError ?? "画像を読み込めませんでした"
                continue
            }
            guard attachmentItems.count < ImageAttachmentLimits.maxCount else {
                attachmentError = attachmentError ?? ImageAttachmentLimits.countMessage
                continue
            }
            guard candidate.data.count <= ImageAttachmentLimits.maxInputBytes else {
                attachmentError = attachmentError ?? ImageAttachmentLimits.inputSizeMessage
                continue
            }
            guard total + candidate.data.count <= ImageAttachmentLimits.maxTotalInputBytes else {
                attachmentError = attachmentError ?? ImageAttachmentLimits.inputTotalMessage
                continue
            }
            let preview: Data
            switch previews[index] {
            case .success(let data): preview = data
            case .failure(let error):
                attachmentError = attachmentError ?? Self.attachmentFailureMessage(error)
                continue
            }
            total += candidate.data.count
            let number = ComposerImagePlaceholder.nextNumber(after: numbers)
            numbers.append(number)
            let mediaType = Self.normalizedMediaType(candidate)
            attachmentItems.append(.init(
                number: number,
                send: SendAttachment(mediaType: mediaType, data: candidate.data),
                previewData: preview
            ))
            let inserted = ComposerImagePlaceholder.inserting(
                number: number,
                into: inputText,
                cursorUTF16: inputCursorUTF16
            )
            inputText = inserted.text
            inputCursorUTF16 = inserted.cursorUTF16
        }
    }

    public func removeAttachment(at index: Int) {
        guard attachmentItems.indices.contains(index) else { return }
        let removed = attachmentItems.remove(at: index)
        inputText = ComposerImagePlaceholder.removing(number: removed.number, from: inputText)
        inputCursorUTF16 = min(inputCursorUTF16, inputText.utf16.count)
        attachmentError = nil
    }

    public func syncAttachmentsWithTextEdit(oldText: String, newText: String) {
        guard oldText != newText, !attachmentItems.isEmpty else { return }
        let removed = ComposerImagePlaceholder.numbersRemoved(
            from: oldText,
            to: newText,
            among: attachmentItems.map(\.number)
        )
        guard !removed.isEmpty else { return }
        let surviving = attachmentItems.map(\.number).filter { !removed.contains($0) }
        var repaired = newText
        var repairedCursor: Int?
        for number in removed {
            guard let result = ComposerImagePlaceholder.repairingBrokenPlaceholder(
                number: number,
                oldText: oldText,
                newText: repaired,
                preserving: surviving
            ) else { continue }
            repaired = result.text
            repairedCursor = result.cursorUTF16
        }
        let removedAfterRepair = Set(ComposerImagePlaceholder.numbersRemoved(
            from: oldText,
            to: repaired,
            among: attachmentItems.map(\.number)
        ))
        attachmentItems.removeAll { removedAfterRepair.contains($0.number) }
        if repaired != newText {
            inputText = repaired
            inputCursorUTF16 = min(repairedCursor ?? inputCursorUTF16, repaired.utf16.count)
        }
    }

    public func send(onCreated: @escaping (Session, SessionDetailRecovery?) -> Void) async {
        guard !isSending, !hasCreatedSession else { return }
        guard let project = selectedProject else {
            projectValidationMessage = "プロジェクトを選んでください"
            focusRequest &+= 1
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resumeHistoryID = selectedHistoryID
        guard !text.isEmpty || resumeHistoryID != nil else { return }
        guard !usesWorktree || !startPoints.isEmpty else {
            launchOptionsError = "起点を取得してから、もう一度開始してください。"
            return
        }
        projectValidationMessage = nil
        creationErrorPresentation = nil
        attachmentError = nil
        let backupText = inputText
        let backupSkill = skillSuggestions.selection(text: text, context: skillContext)
        let backupItems = attachmentItems
        submittedText = resumeHistoryID == nil ? backupText : nil
        readyWaitSeconds = 0
        transition(to: .creating)

        let prepared: [PreparedImageAttachment]
        do {
            prepared = try await ImageAttachmentPreparer.prepare(resumeHistoryID == nil ? backupItems.map { $0.send.data } : [])
        } catch {
            attachmentError = Self.attachmentFailureMessage(error)
            transition(to: .idle)
            return
        }

        let request = SpawnRequest(
            agent: selectedAgent,
            workspace: project.name,
            projectID: project.projectID,
            prompt: nil,
            model: selectedModelID,
            effort: selectedEffort,
            permission: selectedPermission,
            planMode: planMode,
            usesWorktree: startPoints.isEmpty ? nil : usesWorktree,
            startPoint: usesWorktree ? selectedStartPoint : nil,
            resumeHistoryID: resumeHistoryID
        )
        let session: Session
        do {
            session = try await api.spawn(request)
        } catch let error as PhloxError {
            creationErrorPresentation = error.presentation
            transition(to: .idle)
            focusRequest &+= 1
            return
        } catch {
            creationErrorPresentation = Self.unknownSpawnFailurePresentation(
                technicalDetail: Self.spawnFailureReason(error)
            )
            transition(to: .idle)
            focusRequest &+= 1
            return
        }

        hasCreatedSession = true
        settingsStore.record(
            kind: selectedAgent,
            model: selectedModelID,
            effort: selectedEffort,
            permission: selectedPermission,
            planMode: planMode,
            projectKey: project.id
        )
        if resumeHistoryID != nil {
            transition(to: .idle)
            onCreated(session, nil)
            return
        }
        if inputText == backupText, attachmentItems.map(\.id) == backupItems.map(\.id) {
            inputText = ""
            inputCursorUTF16 = 0
            attachmentItems = []
        }
        transition(to: .waiting)
        readyWaitSeconds = 0
        let timer = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                readyWaitSeconds += 1
            }
        }
        let isReady: Bool
        do {
            isReady = try await api.waitUntilReady(sessionID: session.id)
        } catch {
            timer.cancel()
            transition(to: .idle)
            onCreated(session, recovery(text: backupText, attachments: backupItems, skill: backupSkill))
            return
        }
        timer.cancel()
        guard isReady else {
            transition(to: .idle)
            onCreated(session, recovery(text: backupText, attachments: backupItems, skill: backupSkill))
            return
        }

        transition(to: .sending)
        do {
            let skill = try await MobileSkillSuggestions.refreshed(backupSkill, api: api, sessionID: session.id)
            let result = try await api.send(SendRequest(
                sessionID: session.id,
                text: text,
                images: prepared.map { SendAttachment(mediaType: $0.mediaType, data: $0.data) },
                skill: skill
            ))
            guard result.accepted else {
                transition(to: .idle)
                onCreated(session, recovery(text: backupText, attachments: backupItems, skill: backupSkill))
                return
            }
            transition(to: .idle)
            onCreated(session, nil)
        } catch {
            transition(to: .idle)
            onCreated(session, recovery(text: backupText, attachments: backupItems, skill: backupSkill))
        }
    }

    func seedProgressForSnapshot(
        text: String,
        waitSeconds: Int = 4,
        stage: NewChatProgressStage = .waiting
    ) {
        submittedText = text
        inputText = ""
        inputCursorUTF16 = 0
        hasCreatedSession = stage != .creating
        transition(to: stage)
        readyWaitSeconds = waitSeconds
    }

    func seedSpawnFailureForSnapshot(reason: String, text: String) {
        creationErrorPresentation = PhloxError.spawnRejected(reason: reason).presentation
        inputText = text
        inputCursorUTF16 = text.utf16.count
        focusRequest &+= 1
    }

    private func recovery(
        text: String,
        attachments: [SessionDetailViewModel.SessionAttachmentItem],
        skill: AgentSkillSelection?
    ) -> SessionDetailRecovery {
        SessionDetailRecovery(
            text: text,
            attachments: attachments,
            errorMessage: "送信に失敗しました · Mac に接続できません",
            skill: skill
        )
    }

    private func transition(to stage: NewChatProgressStage) {
        progressStage = stage
        progressHistory.append(stage)
        if stage == .idle, !hasCreatedSession {
            submittedText = nil
        }
    }

    private func effortOptions(for kind: AgentKind, modelID: String?) -> [AgentSettingOption] {
        settingsByAgent[kind]?.availableEfforts[modelID ?? ""] ?? []
    }

    private func defaultEffort(for kind: AgentKind, modelID: String?) -> String? {
        guard let modelID,
              let value = settingsByAgent[kind]?.defaultEfforts?[modelID],
              effortOptions(for: kind, modelID: modelID).contains(where: { $0.value == value })
        else { return nil }
        return value
    }

    private func defaultPermission(for kind: AgentKind) -> String? {
        guard let settings = settingsByAgent[kind],
              let value = settings.defaultPermission,
              settings.availablePermissions.contains(where: { $0.value == value })
        else { return nil }
        return value
    }

    private func validPermission(_ value: String?, kind: AgentKind) -> String? {
        guard let settings = settingsByAgent[kind] else { return nil }
        guard let value else { return defaultPermission(for: kind) }
        return settings.availablePermissions.contains(where: { $0.value == value })
            ? value
            : defaultPermission(for: kind)
    }

    private func valid(_ value: String?, among options: [AgentSettingOption]) -> String? {
        guard let value else { return nil }
        return options.contains(where: { $0.value == value }) ? value : nil
    }

    private static func projects(from items: [ProjectSummary]) -> [NewChatProject] {
        items.map { NewChatProject(id: $0.id, name: $0.name, projectID: $0.id) }
    }

    private static func legacyProjects(from sessions: [Session]) -> [NewChatProject] {
        var seen: Set<String> = []
        return sessions.compactMap { session in
            let name = session.projectName ?? session.subtitle
            guard !name.isEmpty else { return nil }
            let key = session.projectId ?? "legacy:\(name)"
            guard seen.insert(key).inserted else { return nil }
            return NewChatProject(id: key, name: name, projectID: session.projectId)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func normalizedMediaType(_ candidate: SendAttachment) -> String {
        let data = candidate.data
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        return candidate.mediaType
    }

    private static func attachmentFailureMessage(_ error: Error) -> String {
        (error as? ImageAttachmentPreparationError)?.errorDescription ?? "画像を読み込めませんでした"
    }

    private static func spawnFailureReason(_ error: Error) -> String {
        if case let PhloxError.spawnRejected(reason) = error { return reason }
        if let error = error as? PhloxError { return error.presentation.message }
        return String(describing: error)
    }

    private static func unknownSpawnFailurePresentation(technicalDetail: String) -> ErrorPresentation {
        ErrorPresentation(
            title: "セッションの作成結果を確認できませんでした",
            message: "Mac から作成の結果を受け取れませんでした。",
            recoveryAction: "送信",
            nextStep: "一覧を更新して、セッションが作成されていないことを確かめてください。",
            technicalDetail: technicalDetail
        )
    }
}
