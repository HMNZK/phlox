import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

@Suite("New chat drafts", .serialized) @MainActor
struct NewChatDraftStoreTests {
    @Test func failedLaunchRenumbersCollidingImagesAndRemovingChipKeepsOtherReference() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft(for: project)
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

    @Test func AC5e_draftsAreSharedByProjectAndSeparatedBetweenProjects() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let projectA = ProjectID()
        let projectB = ProjectID()

        let draftA = store.draft(for: projectA)
        draftA.text = "A の書きかけ"
        let draftB = store.draft(for: projectB)
        draftB.text = "B の書きかけ"

        #expect(store.draft(for: projectA) === draftA)
        #expect(store.draft(for: projectA).text == "A の書きかけ")
        #expect(store.draft(for: projectB).text == "B の書きかけ")
        #expect(store.draft(for: nil) !== draftA)
    }

    @Test func AC5f_discardRemovesTheDeletedProjectsDraftAndItCannotBeSent() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        store.draft(for: project).text = "discard me"

        store.discard(project)

        #expect(store.draft(for: project).text.isEmpty)
        #expect(!store.draft(for: project).canSend(projectExists: false, harnessDetected: true, modelAcceptsImages: true))
    }

    @Test func initialDraftUsesLastHarnessAndItsSavedSettings() throws {
        let (store, settings, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        settings.record(agentID: "codex", model: "gpt-6-sol", effort: "high", permission: ":workspace", isPlanMode: true)
        settings.recordLastHarness("codex")

        let draft = store.draft(for: nil)

        #expect(draft.agentRef == .builtin(.codex))
        #expect(draft.settings.selectedModel == "gpt-6-sol")
        #expect(draft.settings.selectedEffort == "high")
        #expect(draft.settings.selectedPermissionProfile == ":workspace")
        #expect(draft.settings.isPlanMode == true)
    }

    @Test func AC2a_requestCapturesAndClearsTheDraftBeforeLaunch() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let draft = store.draft(for: project)
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
        let draft = store.draft(for: project)
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
        let draft = store.draft(for: project)
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
        let draft = store.draft(for: ProjectID())
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
        let draft = store.draft(for: nil)

        #expect(draft.sendUnavailableReason(projectExists: false, harnessDetected: false, modelAcceptsImages: false) == nil)
        draft.text = "work"
        #expect(draft.sendUnavailableReason(projectExists: false, harnessDetected: true, modelAcceptsImages: true) == "プロジェクトを選んでください")
    }

    @Test func contentCannotSendWhenTheSelectedHarnessIsNotDetected() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft(for: ProjectID())
        draft.text = "work"

        #expect(!draft.canSend(projectExists: true, harnessDetected: false, modelAcceptsImages: true))
        #expect(draft.sendUnavailableReason(projectExists: true, harnessDetected: false, modelAcceptsImages: true)
            == "\(AgentRegistry.descriptor(for: .claudeCode).displayName) が見つかりません。インストールするか、別のハーネスを選んでください")
    }

    @Test func AC8_suggestionAppendsTextWithoutSending() throws {
        let (store, _, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let draft = store.draft(for: ProjectID())
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

    @Test func completingNewChatReplacesItsProjectTabWithTheCreatedChat() {
        let router = AppRouter()
        let projectID = ProjectID()
        let sessionID = SessionID()
        router.showNewChat(projectID: projectID)

        #expect(router.tabs.layout(for: projectID).selected == .newChat)
        router.completeNewChat(sessionID: sessionID, projectID: projectID)

        #expect(router.tabs.layout(for: projectID).selected == .chat(sessionID))
        #expect(!router.tabs.layout(for: projectID).items.contains(.newChat))
        #expect(router.selectedSession == sessionID)
    }
}
