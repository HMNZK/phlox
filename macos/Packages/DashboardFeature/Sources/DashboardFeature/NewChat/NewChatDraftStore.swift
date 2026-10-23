import Foundation
import Observation
import AgentDomain
import DesignSystem
import SessionFeature

@MainActor @Observable
public final class NewChatDraftStore {
    /// 新規チャットの下書きはアプリに 1 つ（ADR 0188）。送信先のプロジェクトは `AppRouter.newChatProjectID`。
    public let draft: NewChatDraft

    public init(lastUsedChatSettingsStore: LastUsedChatSettingsStore = LastUsedChatSettingsStore()) {
        draft = NewChatDraft(lastUsedChatSettingsStore: lastUsedChatSettingsStore)
    }
}

@MainActor @Observable
public final class NewChatDraft {
    public var text = "" {
        didSet {
            if let selectedSkill,
               !text.split(whereSeparator: \.isWhitespace).contains(where: { $0 == "$\(selectedSkill.name)" }) {
                self.selectedSkill = nil
            }
        }
    }
    public var selectedSkill: SkillIdentity?
    public let attachments = ComposerAttachmentStore()
    public var usesWorktree = false
    private var worktreeStartPoints: [ProjectID: WorktreeStartPoint] = [:]
    private var folderStartPoints: [String: WorktreeStartPoint] = [:]

    func worktreeStartPoint(projectID: ProjectID?, directory: String?) -> WorktreeStartPoint {
        if let projectID { return worktreeStartPoints[projectID] ?? .head }
        guard let directory else { return .head }
        return folderStartPoints[URL(fileURLWithPath: directory).standardizedFileURL.path] ?? .head
    }

    func selectWorktreeStartPoint(_ point: WorktreeStartPoint, projectID: ProjectID?, directory: String?) {
        if let projectID { worktreeStartPoints[projectID] = point }
        else if let directory { folderStartPoints[URL(fileURLWithPath: directory).standardizedFileURL.path] = point }
    }
    /// プロジェクトにまだしていない送信先のフォルダ。送信したときにプロジェクトを作る（要件 FR-3）。
    public var pendingFolderPath: String?
    public var agentRef: AgentRef
    public var settings: CodexAppServerSessionSettings

    private let lastUsedChatSettingsStore: LastUsedChatSettingsStore
    private let isFullAccessEnabled: (AgentKind) -> Bool

    init(
        lastUsedChatSettingsStore: LastUsedChatSettingsStore,
        isFullAccessEnabled: @escaping (AgentKind) -> Bool = { BypassSettings.isEnabled(for: $0) }
    ) {
        self.lastUsedChatSettingsStore = lastUsedChatSettingsStore
        self.isFullAccessEnabled = isFullAccessEnabled
        let kind = Self.initialKind(lastHarness: lastUsedChatSettingsStore.lastHarness)
        self.agentRef = .builtin(kind)
        self.settings = Self.initialSettings(
            for: kind,
            saved: lastUsedChatSettingsStore.lastUsed(agentID: kind.rawValue),
            fullAccess: isFullAccessEnabled(kind)
        )
    }

    public func selectHarness(_ ref: AgentRef) {
        guard ref != agentRef else { return }
        let kind = ref.builtinKind
        agentRef = ref
        selectedSkill = nil
        settings = Self.initialSettings(
            for: kind,
            saved: lastUsedChatSettingsStore.lastUsed(agentID: ref.id),
            fullAccess: isFullAccessEnabled(kind)
        )
    }

    public func appendSuggestion(_ suggestion: String) {
        text = text.isEmpty ? suggestion : text + "\n" + suggestion
    }

    public func sendUnavailableReason(
        projectExists: Bool,
        harnessDetected: Bool,
        modelAcceptsImages: Bool,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> String? {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.attachments.isEmpty
        guard hasContent else { return nil }
        guard projectExists else { return AppLocalizedString.string("プロジェクトを選んでください", locale: locale, bundle: bundle) }
        guard harnessDetected else {
            let name = AgentRegistry.descriptor(for: agentRef.builtinKind).displayName
            return String(format: AppLocalizedString.string("%@ が見つかりません。インストールするか、別のハーネスを選んでください", locale: locale, bundle: bundle), name)
        }
        if !attachments.attachments.isEmpty, !modelAcceptsImages {
            let prefix = agentRef.builtinKind == .cursor
                ? AppLocalizedString.string("Cursor", locale: locale, bundle: bundle)
                : AppLocalizedString.string("このモデル", locale: locale, bundle: bundle)
            return String(format: AppLocalizedString.string("%@ は画像を送れません。画像を外すか、画像を送れるハーネスを選んでください", locale: locale, bundle: bundle), prefix)
        }
        return nil
    }

    public func canSend(projectExists: Bool, harnessDetected: Bool, modelAcceptsImages: Bool) -> Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.attachments.isEmpty
        return hasContent && sendUnavailableReason(
            projectExists: projectExists,
            harnessDetected: harnessDetected,
            modelAcceptsImages: modelAcceptsImages
        ) == nil
    }

    /// 送信先のプロジェクト。フォルダだけを選んでいれば、ここで初めてプロジェクトにする（要件 FR-3）。
    func projectIDForSend(selected: ProjectID?, in dashboard: DashboardViewModel) -> ProjectID? {
        if let selected, dashboard.projects.contains(where: { $0.id == selected }) { return selected }
        guard let path = pendingFolderPath,
              let id = dashboard.addProject(name: URL(fileURLWithPath: path).lastPathComponent, directoryPath: path) else { return nil }
        worktreeStartPoints[id] = worktreeStartPoint(projectID: nil, directory: path)
        pendingFolderPath = nil
        return id
    }

    func projectIDForSendFromRuntime(selected: ProjectID?, in dashboard: DashboardViewModel) async throws -> ProjectID? {
        if let selected, dashboard.projects.contains(where: { $0.id == selected }) { return selected }
        guard let path = pendingFolderPath,
              let id = try await dashboard.addProjectFromRuntime(name: URL(fileURLWithPath: path).lastPathComponent,
                                                               directoryPath: path) else { return nil }
        worktreeStartPoints[id] = worktreeStartPoint(projectID: nil, directory: path)
        pendingFolderPath = nil
        return id
    }

    func makeLaunchRequest(projectID: ProjectID, workingDirectoryOverride: String? = nil) -> NewChatLaunchRequest? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.attachments.isEmpty else { return nil }
        let request = NewChatLaunchRequest(
            projectID: projectID,
            agentRef: agentRef,
            settings: settings,
            usesWorktree: usesWorktree,
            text: text,
            selectedSkill: selectedSkill,
            attachments: attachments.attachments,
            workingDirectoryOverride: workingDirectoryOverride,
            worktreeStartPoint: worktreeStartPoint(projectID: projectID, directory: nil)
        )
        text = ""
        selectedSkill = nil
        attachments.clear()
        usesWorktree = false
        return request
    }

    func restoreLaunchDraft(from request: NewChatLaunchRequest) {
        let merged = ComposerAttachmentStore.mergingDrafts(text: request.text, attachments: request.attachments,
            nextText: text, nextAttachments: attachments.attachments)
        text = merged.text
        selectedSkill = request.selectedSkill
        attachments.restore(merged.attachments)
        usesWorktree = request.usesWorktree
        worktreeStartPoints[request.projectID] = request.worktreeStartPoint
    }

    private static func initialKind(lastHarness: String?) -> AgentKind {
        guard let kind = lastHarness.flatMap(AgentKind.init(rawValue:)),
              AgentRegistry.descriptor(for: kind).supportsStructuredChat else { return .claudeCode }
        return kind
    }

    /// 保存値が無いときの Claude の権限は、設定のフルアクセス（`BypassSettings`）に従う。
    private static func initialSettings(
        for kind: AgentKind,
        saved: LastUsedChatSettings?,
        fullAccess: Bool
    ) -> CodexAppServerSessionSettings {
        let defaults = newChatDefaultSettings(for: kind, modelID: saved?.model, fullAccess: fullAccess)
        return CodexAppServerSessionSettings(
            selectedModel: saved?.model ?? defaults.selectedModel,
            selectedEffort: saved?.effort ?? defaults.selectedEffort,
            selectedPermissionProfile: saved?.permission ?? defaults.selectedPermissionProfile,
            isPlanMode: saved?.isPlanMode ?? false
        )
    }
}

struct NewChatModelMenuSection: Identifiable {
    let kind: AgentKind
    let name: String
    let isDetected: Bool
    let models: [ControlModelOption]
    let defaultModel: String?

    var id: AgentKind { kind }

    static func make(availableHarnessIDs: Set<String>) -> [Self] {
        [AgentKind.claudeCode, .codex, .cursor].map { kind in
            Self(
                kind: kind,
                name: AgentRegistry.descriptor(for: kind).displayName,
                isDetected: availableHarnessIDs.contains(AgentRef.builtin(kind).id),
                models: AgentModelCatalog.models(for: kind),
                defaultModel: AgentModelCatalog.defaultModel(for: kind)
            )
        }
    }
}

enum NewChatSuggestionDirectory {
    static func path(projectDirectory: String, usesWorktree: Bool) -> String {
        // A worktree does not exist while typing, so file suggestions use the project root.
        projectDirectory
    }
}
