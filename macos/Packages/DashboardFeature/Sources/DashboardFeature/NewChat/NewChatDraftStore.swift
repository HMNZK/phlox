import Foundation
import Observation
import AgentDomain
import DesignSystem
import SessionFeature

@MainActor @Observable
public final class NewChatDraftStore {
    private var drafts: [ProjectID?: NewChatDraft] = [:]
    private let lastUsedChatSettingsStore: LastUsedChatSettingsStore

    public init(lastUsedChatSettingsStore: LastUsedChatSettingsStore = LastUsedChatSettingsStore()) {
        self.lastUsedChatSettingsStore = lastUsedChatSettingsStore
    }

    public func draft(for projectID: ProjectID?) -> NewChatDraft {
        if let draft = drafts[projectID] { return draft }
        let draft = NewChatDraft(lastUsedChatSettingsStore: lastUsedChatSettingsStore)
        drafts[projectID] = draft
        return draft
    }

    public func discard(_ projectID: ProjectID) {
        drafts[projectID] = nil
    }

    public func hasDraft(for projectID: ProjectID) -> Bool {
        guard let draft = drafts[projectID] else { return false }
        return !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.attachments.isEmpty
    }
}

@MainActor @Observable
public final class NewChatDraft {
    public var text = ""
    public let attachments = ComposerAttachmentStore()
    public var usesWorktree = false
    public var agentRef: AgentRef
    public var settings: CodexAppServerSessionSettings

    private let lastUsedChatSettingsStore: LastUsedChatSettingsStore

    init(lastUsedChatSettingsStore: LastUsedChatSettingsStore) {
        self.lastUsedChatSettingsStore = lastUsedChatSettingsStore
        let kind = Self.initialKind(lastHarness: lastUsedChatSettingsStore.lastHarness)
        self.agentRef = .builtin(kind)
        self.settings = Self.initialSettings(for: kind, saved: lastUsedChatSettingsStore.lastUsed(agentID: kind.rawValue))
    }

    public func selectHarness(_ ref: AgentRef) {
        guard ref != agentRef else { return }
        let kind = ref.builtinKind
        agentRef = ref
        settings = Self.initialSettings(for: kind, saved: lastUsedChatSettingsStore.lastUsed(agentID: ref.id))
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

    func makeLaunchRequest(projectID: ProjectID, workingDirectoryOverride: String? = nil) -> NewChatLaunchRequest? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.attachments.isEmpty else { return nil }
        let request = NewChatLaunchRequest(
            projectID: projectID,
            agentRef: agentRef,
            settings: settings,
            usesWorktree: usesWorktree,
            text: text,
            attachments: attachments.attachments,
            workingDirectoryOverride: workingDirectoryOverride
        )
        text = ""
        attachments.clear()
        usesWorktree = false
        return request
    }

    func restoreLaunchDraft(from request: NewChatLaunchRequest) {
        if !request.text.isEmpty {
            text = text.isEmpty ? request.text : request.text + "\n\n" + text
        }
        var seen: Set<UUID> = []
        attachments.restore((request.attachments + attachments.attachments).filter { seen.insert($0.id).inserted })
        usesWorktree = request.usesWorktree
    }

    private static func initialKind(lastHarness: String?) -> AgentKind {
        guard let kind = lastHarness.flatMap(AgentKind.init(rawValue:)),
              AgentRegistry.descriptor(for: kind).supportsStructuredChat else { return .claudeCode }
        return kind
    }

    private static func initialSettings(for kind: AgentKind, saved: LastUsedChatSettings?) -> CodexAppServerSessionSettings {
        let model = saved?.model ?? AgentModelCatalog.defaultModel(for: kind)
        let modelOption = AgentModelCatalog.models(for: kind).first { $0.id == model }
        return CodexAppServerSessionSettings(
            selectedModel: model,
            selectedEffort: saved?.effort ?? modelOption?.defaultReasoningEffort ?? (kind == .claudeCode ? "high" : nil),
            selectedPermissionProfile: saved?.permission ?? (kind == .claudeCode ? "bypassPermissions" : nil),
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
