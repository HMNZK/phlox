import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor struct MobileSkillSuggestionsTests {
    let skill = AgentSkill(name: "poteto-mode", description: "説明", path: "/skills/poteto-mode/SKILL.md", runtimeFingerprint: "old")

    @Test func loadsAndReportsFailuresAndLegacyServers() async {
        let api = MockAPI()
        let model = MobileSkillSuggestions()
        let context = MobileSkillSuggestions.Context.session("s1", .codex)
        await api.setSkillsOutcome(.success([skill]))
        await model.load(api: api, context: context)
        #expect(model.skills == [skill])
        #expect(!model.isLoading)
        await api.setSkillsOutcome(.failure(.server(status: 500, message: "failure")))
        await model.load(api: api, context: context)
        #expect(model.skills.isEmpty)
        #expect(model.errorMessage != nil)
        await api.setSkillsOutcome(.success(nil))
        await model.load(api: api, context: context)
        #expect(model.skills.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func selectionCannotLeakToOtherProjectOrAgentOrRemovedToken() {
        let model = MobileSkillSuggestions()
        let context = MobileSkillSuggestions.Context.agent(.codex, projectID: "p1", workspace: "repo")
        model.select(skill, context: context)
        #expect(model.selection(text: "$poteto-mode 実装", context: context)?.path == skill.path)
        #expect(model.selection(text: "$poteto-mode-extra", context: context) == nil)
        #expect(model.selection(text: "実装", context: context) == nil)
        #expect(model.selection(text: "$poteto-mode", context: .agent(.codex, projectID: "p2", workspace: "other")) == nil)
        #expect(model.selection(text: "$poteto-mode", context: .session("s1", .claudeCode)) == nil)
    }

    @Test func refreshesCodexIdentityAndRejectsMissingSkill() async throws {
        let api = MockAPI()
        let selection = AgentSkillSelection(name: skill.name, path: skill.path)
        let fresh = AgentSkill(name: skill.name, description: "", path: skill.path, runtimeFingerprint: "new")
        await api.setSkillsOutcome(.success([fresh]))
        let result = try await MobileSkillSuggestions.refreshed(selection, api: api, sessionID: "spawned")
        #expect(result?.runtimeFingerprint == "new")
        let stale = AgentSkillSelection(name: skill.name, path: skill.path, runtimeFingerprint: "old")
        await #expect(throws: PhloxError.self) {
            try await MobileSkillSuggestions.refreshed(stale, api: api, sessionID: "spawned")
        }
        await api.setSkillsOutcome(.success([]))
        await #expect(throws: PhloxError.self) {
            try await MobileSkillSuggestions.refreshed(selection, api: api, sessionID: "spawned")
        }
    }

    @Test func existingChatSendCarriesNativeSkill() async throws {
        let api = MockAPI()
        await api.setSkillsOutcome(.success([skill]))
        let session = Session(id: "s1", name: "Codex", agent: .codex, status: .idle, updatedAt: Date())
        let model = SessionDetailViewModel(session: session, api: api)
        model.inputText = "$poteto-mode 実装"
        model.skillSuggestions.select(skill, context: model.skillContext)
        await model.sendMessage()
        #expect(await api.lastSentRequest?.skill?.name == skill.name)
        #expect(await api.lastSentRequest?.text == "$poteto-mode 実装")
    }

    @Test func newChatSendAndFailureRecoveryKeepSkill() async throws {
        let suite = "MobileSkillSuggestionsTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NewChatSettingsStore(defaults: defaults)
        store.record(kind: .codex, model: nil, effort: nil, permission: nil, planMode: false, projectKey: "p1")
        let session = Session(id: "spawned", name: "Codex", agent: .codex, status: .idle, updatedAt: Date())
        let api = MockAPI(spawnOutcome: .success(session), sendOutcome: .failure(.server(status: 500, message: "send failed")))
        await api.setProjectsOutcome(.success([ProjectSummary(id: "p1", name: "repo")]))
        await api.setSkillsOutcome(.success([skill]))
        let model = NewChatViewModel(api: api, entryProject: SessionComposeDraft(project: "repo", projectID: "p1"), settingsStore: store)
        await model.load()
        model.inputText = "$poteto-mode 実装"
        model.skillSuggestions.select(skill, context: model.skillContext)
        var recovery: SessionDetailRecovery?
        await model.send { _, value in recovery = value }
        #expect(await api.lastSentRequest?.skill?.name == skill.name)
        #expect(recovery?.skill?.path == skill.path)
        let recoveredDraft = try #require(recovery)
        let recovered = SessionDetailViewModel(session: session, api: api, recovery: recoveredDraft)
        #expect(recovered.skillSuggestions.selection(text: recovered.inputText, context: recovered.skillContext)?.name == skill.name)
    }
}
