import Foundation
import Testing
import AgentDomain
import DesignSystem
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

@Suite("AC-17 新規チャットの読み上げ")
@MainActor
struct NewChatAccessibilityTests {
    @Test func controlsExposeSeparateRolesAndValues() async throws {
        let suite = "phlox.new-chat-accessibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let project = Project(name: "読み上げ確認", directoryPath: "/tmp", createdAt: Date(), isManagedDirectory: false)
        let projects = InMemoryProjectStore()
        try await projects.save([project])
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }, projects: projects
        ))
        await dashboard.start()

        let draftStore = NewChatDraftStore(lastUsedChatSettingsStore: LastUsedChatSettingsStore(defaults: defaults))
        let draft = draftStore.draft(for: project.id)
        let model = try #require(AgentModelCatalog.models(for: .claudeCode).first { $0.id == "sonnet" })
        draft.settings = CodexAppServerSessionSettings(
            selectedModel: model.id,
            selectedEffort: "high",
            selectedPermissionProfile: "acceptEdits"
        )
        draft.usesWorktree = true
        let view = NewChatView(
            viewModel: dashboard,
            router: AppRouter(),
            draftStore: draftStore,
            draft: draft,
            project: project,
            onLaunchFailure: { _, _ in }
        )

        #expect(view.harnessAccessibility == NewChatAccessibilityCopy(role: "ハーネスとモデル", value: "Claude Code \(model.displayName)"))
        #expect(view.effortAccessibility == NewChatAccessibilityCopy(role: "推論の深さ", value: "高"))
        #expect(view.permissionAccessibility == NewChatAccessibilityCopy(
            role: "権限",
            value: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits", languageCode: "ja").title
        ))
        #expect(view.projectAccessibility == NewChatAccessibilityCopy(role: "プロジェクト", value: project.name))
        #expect(view.workspaceAccessibility == NewChatAccessibilityCopy(role: "作業場所", value: "新しい worktree"))
    }

    @Test func messageInputAnnouncesItsRoleAndCurrentText() {
        let text = "差分の危険な箇所を調べてください"
        let input = ComposerDraftInput(
            text: .constant(text), attachmentStore: ComposerAttachmentStore(),
            workingDirectory: "/tmp", placeholder: "入力", onSubmit: {}
        )
        #expect(input.accessibilityRole == "メッセージ")
        #expect(input.accessibilityValue == text)
    }

    @Test func launchAnnouncementsCoverStartingSuccessAndFailure() {
        let cases: [(NewChatLaunchAnnouncement.Phase, Bool, String)] = [
            (.starting, false, "起動しています。終わったら最初のメッセージを送ります"),
            (.succeeded, false, "起動しました。最初のメッセージを送りました"),
            (.failed, false, "起動できませんでした。本文を入力欄に戻しました"),
            (.starting, true, "会話を再開しています"),
            (.succeeded, true, "会話を再開しました"),
            (.failed, true, "会話を再開できませんでした"),
        ]
        for (phase, resumesHistory, expected) in cases {
            #expect(NewChatLaunchAnnouncement.text(
                phase: phase, resumesHistory: resumesHistory, locale: Locale(identifier: "ja")
            ) == expected)
        }
    }
}
