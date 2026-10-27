import Foundation
import Observation
import PhloxCore

@MainActor @Observable
final class MobileSkillSuggestions {
    enum Context: Equatable, Hashable {
        case session(String, AgentKind)
        case agent(AgentKind, projectID: String?, workspace: String?)
    }

    private(set) var skills: [AgentSkill] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var selected: (skill: AgentSkill, context: Context)?
    private var generation = 0

    func load(api: PhloxAPI, context: Context?) async {
        guard let context else { return }
        generation += 1
        let requestGeneration = generation
        skills = []
        errorMessage = nil
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let result: [AgentSkill]?
            switch context {
            case .session(let id, _): result = try await api.sessionSkills(sessionID: id)
            case .agent(let kind, let projectID, let workspace):
                result = try await api.agentSkills(kind: kind, projectID: projectID, workspace: workspace)
            }
            guard !Task.isCancelled, generation == requestGeneration else { return }
            skills = result ?? []
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            errorMessage = "スキル候補を取得できませんでした。/ を入力し直すと再試行できます"
        }
    }

    func select(_ skill: AgentSkill, context: Context) { selected = (skill, context) }

    func reconcile(text: String, context: Context) {
        if selected?.context != context || (selected != nil && codexSelection(text: text, context: context) == nil) {
            selected = nil
        }
    }

    func selection(text: String, context: Context) -> AgentSkillSelection? {
        switch context {
        case .session(_, .codex), .agent(.codex, _, _):
            return codexSelection(text: text, context: context)
        default: return nil
        }
    }

    static func refreshed(_ selection: AgentSkillSelection?, api: PhloxAPI, sessionID: String) async throws -> AgentSkillSelection? {
        guard let selection else { return nil }
        let skills = try await api.sessionSkills(sessionID: sessionID) ?? []
        guard let skill = skills.first(where: { $0.name == selection.name && $0.path == selection.path }),
              selection.runtimeFingerprint == nil || selection.runtimeFingerprint == skill.runtimeFingerprint else {
            throw PhloxError.server(status: 409, message: "スキルが変更されました。候補から選び直してください")
        }
        return AgentSkillSelection(name: skill.name, path: skill.path, runtimeFingerprint: skill.runtimeFingerprint)
    }

    private func codexSelection(text: String, context: Context) -> AgentSkillSelection? {
        guard let selected, selected.context == context,
              text.split(whereSeparator: \.isWhitespace).contains(Substring("$" + selected.skill.name))
        else { return nil }
        return AgentSkillSelection(name: selected.skill.name, path: selected.skill.path, runtimeFingerprint: selected.skill.runtimeFingerprint)
    }
}
