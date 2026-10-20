import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

@Suite("New chat drafts", .serialized) @MainActor
struct NewChatDraftStoreTests {
    @Test func selectedCodexSkillSurvivesLaunchFailureAndClearsWithToken() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft
        draft.selectHarness(.builtin(.codex))
        let skill = SkillIdentity(name: "pstack-codex:poteto-mode", path: "/skills/poteto-mode/SKILL.md")
        draft.text = "$pstack-codex:poteto-mode fix this"
        draft.selectedSkill = skill
        let request = try #require(draft.makeLaunchRequest(projectID: ProjectID()))
        #expect(request.selectedSkill == skill)
        #expect(draft.selectedSkill == nil)
        draft.restoreLaunchDraft(from: request)
        #expect(draft.selectedSkill == skill)
        draft.text = "fix this"
        #expect(draft.selectedSkill == nil)
    }

    @Test func worktreeStartPointsBelongToProjectsAndSurviveSendAndRestore() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let a = ProjectID(), b = ProjectID()
        let draft = store.draft
        #expect(draft.worktreeStartPoint(projectID: a, directory: nil) == .head)
        draft.selectWorktreeStartPoint(.localBranch("topic"), projectID: a, directory: nil)
        draft.selectWorktreeStartPoint(.tag("v1"), projectID: b, directory: nil)
        #expect(draft.worktreeStartPoint(projectID: a, directory: nil) == .localBranch("topic"))
        #expect(draft.worktreeStartPoint(projectID: b, directory: nil) == .tag("v1"))
        draft.text = "hello"
        draft.usesWorktree = true
        let request = try #require(draft.makeLaunchRequest(projectID: a))
        #expect(request.worktreeStartPoint == .localBranch("topic"))
        #expect(draft.worktreeStartPoint(projectID: a, directory: nil) == .localBranch("topic"))
        draft.restoreLaunchDraft(from: request)
        #expect(draft.usesWorktree)
        #expect(draft.text == "hello")
        #expect(draft.worktreeStartPoint(projectID: b, directory: nil) == .tag("v1"))
        draft.selectWorktreeStartPoint(.commit("abcdef"), projectID: nil, directory: "/tmp/project/./")
        #expect(draft.worktreeStartPoint(projectID: nil, directory: "/tmp/project") == .commit("abcdef"))
        #expect(draft.worktreeStartPoint(projectID: nil, directory: nil) == .head)
    }
    @Test func failedLaunchRenumbersCollidingImagesAndRemovingChipKeepsOtherReference() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft
        let first = ComposerAttachment(data: Data([1]), mediaType: "image/png")
        let next = ComposerAttachment(data: Data([2]), mediaType: "image/png")
        draft.text = "first [Image #1]"
        draft.attachments.restore([first])
        let request = try #require(draft.makeLaunchRequest(projectID: project))
        draft.text = "next [Image #1]"
        draft.attachments.restore([next])
        draft.restoreLaunchDraft(from: request)
        #expect(draft.text == "first [Image #1]\n\nnext [Image #2]")
        #expect(draft.attachments.attachments.map(\.number) == [1, 2])
        let restoredNext = try #require(draft.attachments.attachments.first { $0.id == next.id })
        draft.attachments.remove(id: restoredNext.id)
        draft.text = ComposerImagePlaceholder.removing(number: restoredNext.number, from: draft.text)
        #expect(draft.text == "first [Image #1]\n\nnext")
        #expect(draft.attachments.attachments == [first])
    }
    private func makeStore() throws -> (NewChatDraftStore, LastUsedChatSettingsStore, String) {
        let suite = "phlox-new-chat-drafts-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = LastUsedChatSettingsStore(defaults: defaults)
        return (NewChatDraftStore(lastUsedChatSettingsStore: settings), settings, suite)
    }

    @Test func AC5e_draftIsOneAndSurvivesChoosingOrSwitchingProjects() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let router = AppRouter()
        let projectA = ProjectID()
        let projectB = ProjectID()

        router.showNewChat(projectID: nil)
        store.draft.text = "プロジェクトを選ぶ前の書きかけ"
        router.newChatProjectID = projectA
        router.showNewChat(projectID: projectB)

        #expect(store.draft.text == "プロジェクトを選ぶ前の書きかけ")
        #expect(router.newChatProjectID == projectB)
        #expect(router.selectedProjectID == projectB)
        #expect(!router.tabs.layout(for: projectA).items.contains(.newChat))
        #expect(!router.tabs.layout(for: projectB).items.contains(.newChat))
    }

    @Test func AC5f_deletingTheDestinationProjectClearsItAndKeepsTheText() async throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let router = AppRouter()
        let project = ProjectID()
        router.showNewChat(projectID: project)
        store.draft.text = "keep me"

        await router.forgetProject(project, terminals: nil, simulatorHub: nil)

        #expect(router.newChatProjectID == nil)
        #expect(store.draft.text == "keep me")
        #expect(!store.draft.canSend(projectExists: false, harnessDetected: true, modelAcceptsImages: true))
    }

    @Test func initialDraftUsesLastHarnessAndItsSavedSettings() throws {
        let (_, settings, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        settings.record(agentID: "codex", model: "gpt-6-sol", effort: "high", permission: ":workspace", isPlanMode: true)
        settings.recordLastHarness("codex")

        let draft = NewChatDraftStore(lastUsedChatSettingsStore: settings).draft

        #expect(draft.agentRef == .builtin(.codex))
        #expect(draft.settings.selectedModel == "gpt-6-sol")
        #expect(draft.settings.selectedEffort == "high")
        #expect(draft.settings.selectedPermissionProfile == ":workspace")
        #expect(draft.settings.isPlanMode == true)
    }

    @Test func claudePermissionWithoutSavedValueFollowsFullAccessSetting() throws {
        let suite = "phlox.new-chat-full-access.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LastUsedChatSettingsStore(defaults: defaults)

        let restricted = NewChatDraft(lastUsedChatSettingsStore: settings, isFullAccessEnabled: { _ in false })
        let full = NewChatDraft(lastUsedChatSettingsStore: settings, isFullAccessEnabled: { _ in true })

        #expect(restricted.agentRef == .builtin(.claudeCode))
        #expect(restricted.settings.selectedPermissionProfile == "auto")
        #expect(full.settings.selectedPermissionProfile == "bypassPermissions")
    }

    @Test func AC2a_requestCapturesAndClearsTheDraftBeforeLaunch() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft
        let image = ComposerAttachment(data: Data([1, 2]), mediaType: "image/png")
        draft.agentRef = .builtin(.codex)
        draft.settings = CodexAppServerSessionSettings(selectedModel: "gpt-6-sol", selectedEffort: "high")
        draft.usesWorktree = true
        draft.text = "first message"
        draft.attachments.restore([image])

        let request = try #require(draft.makeLaunchRequest(projectID: project))

        #expect(request.text == "first message")
        #expect(request.attachments == [image])
        #expect(request.agentRef == .builtin(.codex))
        #expect(request.settings.selectedModel == "gpt-6-sol")
        #expect(request.usesWorktree)
        #expect(draft.text.isEmpty)
        #expect(draft.attachments.attachments.isEmpty)
        #expect(!draft.usesWorktree)
    }

    @Test func AC5d_failedLaunchRestoresTextAndAttachmentsToTheSameDraft() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft
        let image = ComposerAttachment(data: Data([3]), mediaType: "image/jpeg")
        draft.text = "keep this"
        draft.attachments.restore([image])
        let request = try #require(draft.makeLaunchRequest(projectID: project))

        draft.restoreLaunchDraft(from: request)

        #expect(draft.text == "keep this")
        #expect(draft.attachments.attachments == [image])
    }

    @Test func failedLaunchPreservesNextInputAndRestoresWorktreeSelection() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft
        let first = ComposerAttachment(data: Data([1]), mediaType: "image/png")
        let next = ComposerAttachment(data: Data([2]), mediaType: "image/png")
        draft.text = "first"
        draft.usesWorktree = true
        draft.attachments.restore([first])
        let request = try #require(draft.makeLaunchRequest(projectID: project))
        draft.text = "next"
        draft.usesWorktree = false
        draft.attachments.restore([next, first])

        draft.restoreLaunchDraft(from: request)

        #expect(draft.text == "first\n\nnext")
        #expect(draft.attachments.attachments == [first, ComposerAttachment(id: next.id, number: 2,
            data: next.data, mediaType: next.mediaType, filename: next.filename)])
        #expect(draft.usesWorktree)
    }

    @Test func AC5g_cursorImageBlocksSendWithoutDroppingTheAttachment() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft
        let image = ComposerAttachment(data: Data([1]), mediaType: "image/png")
        draft.agentRef = .builtin(.cursor)
        draft.text = "look at this"
        draft.attachments.restore([image])

        #expect(!draft.canSend(projectExists: true, harnessDetected: true, modelAcceptsImages: false))
        #expect(draft.sendUnavailableReason(projectExists: true, harnessDetected: true, modelAcceptsImages: false)
            == "Cursor は画像を送れません。画像を外すか、画像を送れるハーネスを選んでください")
        #expect(draft.attachments.attachments == [image])
    }

    @Test func emptyDraftHasNoReasonAndMissingProjectExplainsHowToContinue() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft

        #expect(draft.sendUnavailableReason(projectExists: false, harnessDetected: false, modelAcceptsImages: false) == nil)
        draft.text = "work"
        #expect(draft.sendUnavailableReason(projectExists: false, harnessDetected: true, modelAcceptsImages: true) == "プロジェクトを選んでください")
    }

    @Test func contentCannotSendWhenTheSelectedHarnessIsNotDetected() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft
        draft.text = "work"

        #expect(!draft.canSend(projectExists: true, harnessDetected: false, modelAcceptsImages: true))
        #expect(draft.sendUnavailableReason(projectExists: true, harnessDetected: false, modelAcceptsImages: true)
            == "\(AgentRegistry.descriptor(for: .claudeCode).displayName) が見つかりません。インストールするか、別のハーネスを選んでください")
    }

    @Test func AC8_suggestionAppendsTextWithoutSending() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft
        draft.text = "背景"

        draft.appendSuggestion("未コミットの変更をレビューして、問題点を重要度順に挙げてください。")

        #expect(draft.text == "背景\n未コミットの変更をレビューして、問題点を重要度順に挙げてください。")
        #expect(draft.attachments.attachments.isEmpty)
    }

    @Test func modelMenuHasAllBuiltInChatHarnessesAndMarksEachDefault() {
        let groups = NewChatModelMenuSection.make(availableHarnessIDs: [AgentRef.builtin(.claudeCode).id])

        #expect(groups.map(\.kind) == [.claudeCode, .codex, .cursor])
        #expect(groups.map(\.isDetected) == [true, false, false])
        #expect(groups.allSatisfy { group in group.models.contains { $0.id == group.defaultModel } })
    }

    @Test func AC9a_suggestionDirectoryTracksProjectAndUsesProjectRootForWorktrees() {
        #expect(NewChatSuggestionDirectory.path(projectDirectory: "/work/a", usesWorktree: false) == "/work/a")
        #expect(NewChatSuggestionDirectory.path(projectDirectory: "/work/a", usesWorktree: true) == "/work/a")
        #expect(NewChatSuggestionDirectory.path(projectDirectory: "/work/b", usesWorktree: false) == "/work/b")
    }

    @Test func completingNewChatOpensTheCreatedChatAsTheProjectTab() {
        let router = AppRouter()
        let projectID = ProjectID()
        let sessionID = SessionID()
        router.showNewChat(projectID: projectID)

        #expect(router.tabs.layout(for: projectID).items.isEmpty)
        router.completeNewChat(sessionID: sessionID, projectID: projectID)

        #expect(router.selectedProjectID == projectID)

        #expect(router.tabs.layout(for: projectID).selected == .chat(sessionID))
        #expect(!router.tabs.layout(for: projectID).items.contains(.newChat))
        #expect(router.selectedSession == sessionID)
    }
}
