import AgentDomain
import Foundation
import DesignSystem
import Testing
@testable import DashboardFeature

// 09 確認ダイアログとアラート: 見出しに対象の名前・件数、本文に消えるもの・消えないもの、原因ごとの次の手。

@Suite("Dialog redesign (09)")
struct DialogRedesignTests {
    private let ja = Locale(identifier: "ja")

    @Test func spawnFailure_namesTheAgent_andOffersAgentConsoleOnlyForMissingBinaries() {
        #expect(SpawnFailureDialogText.title(agentName: "Codex", locale: ja) == "Codex を起動できませんでした")
        #expect(SpawnFailureDialogText.agentName(for: .builtin(.codex)) == AgentKind.codex.displayName)
        #expect(SpawnFailureDialogText.agentName(for: .custom("aider")) == "aider")
        #expect(SpawnFailureDialogText.opensAgentConsole(for: AgentSpawnError.binaryNotFound(.codex)))
        #expect(SpawnFailureDialogText.opensAgentConsole(for: AgentSpawnError.customBinaryNotFound("aider")))
        #expect(!SpawnFailureDialogText.opensAgentConsole(for: AgentSpawnError.depthLimitExceeded))
        #expect(!SpawnFailureDialogText.opensAgentConsole(for: AgentSpawnError.spawnRateLimited))
    }

    @Test func cleanupWarning_saysTheSessionEnded_andShowsWhatIsLeft() {
        let worktree = WorkspaceCleanupWarning.worktreeRetained(path: "/tmp/w")
        #expect(CleanupWarningDialogText.message(worktree, locale: ja).hasPrefix("セッションは終了しています。"))
        #expect(CleanupWarningDialogText.detail(worktree) == "/tmp/w")
        #expect(CleanupWarningDialogText.revealPath(worktree) == "/tmp/w")
        let branch = WorkspaceCleanupWarning.branchRetained(branchName: "phlox/a3f9")
        #expect(CleanupWarningDialogText.title(branch, locale: ja) == "ブランチを片付けられませんでした")
        #expect(CleanupWarningDialogText.title(worktree, locale: ja) == "worktree を片付けられませんでした")
        #expect(CleanupWarningDialogText.detail(branch) == "phlox/a3f9")
        #expect(CleanupWarningDialogText.revealPath(branch) == nil)
    }

    @Test func sessionDeletion_namesTheSession_andCountsChildren() {
        #expect(SessionDeletionDialogText.title(sessionName: "準備", childCount: 0, locale: ja) == "「準備」を削除しますか?")
        #expect(SessionDeletionDialogText.title(sessionName: "準備", childCount: 3, locale: ja) == "「準備」と子セッション 3 件を削除しますか?")
    }

    @Test func sessionDeletion_listsChildren_keepsFolder_andEndsWithIrreversibility() {
        #expect(SessionDeletionDialogText.message(locale: ja).hasSuffix("元に戻せません。"))
        #expect(SessionDeletionDialogText.note(dirtyFiles: [], locale: ja) == "プロジェクトのフォルダとファイルは削除されません。")

        let children = (1...8).map { (name: "子\($0)", meta: "Cx · 実行中") }
        let rows = SessionDeletionDialogText.rows(children: children, locale: ja)
        #expect(rows.count == SessionDeletionDialogText.listLimit + 1)
        #expect(rows.first == DSDialogList.Row(id: 0, title: "子1", meta: "Cx · 実行中"))
        #expect(rows[SessionDeletionDialogText.listLimit - 1].title == "子\(SessionDeletionDialogText.listLimit)")
        #expect(rows.last?.title == "ほか \(children.count - SessionDeletionDialogText.listLimit) 件")
        #expect(SessionDeletionDialogText.rows(children: [], locale: ja).isEmpty)

        let note = SessionDeletionDialogText.note(dirtyFiles: ["a.swift", "b.swift"], locale: ja)
        #expect(note.hasPrefix("保存していないファイル（a.swift、b.swift）の変更も失われます。"))
        #expect(note.hasSuffix("プロジェクトのフォルダとファイルは削除されません。"))
    }

    /// 表示言語に合わせて引く版が、テストで固定された日本語と一字一句同じであること。
    @Test func projectDeletion_localizedTextMatchesFrozenJapanese() {
        #expect(ProjectDeletionDialogText.title(projectName: "phlox-core", locale: ja) == ProjectDeletionDialogText.title(projectName: "phlox-core"))
        for (sessions, children, others) in [(0, 0, 0), (3, 0, 0), (6, 2, 0), (4, 1, 2), (1, 0, 3)] {
            #expect(
                ProjectDeletionDialogText.message(sessionCount: sessions, childCount: children, otherProjectChildCount: others, locale: ja)
                    == ProjectDeletionDialogText.message(sessionCount: sessions, childCount: children, otherProjectChildCount: others)
            )
        }
        #expect(ProjectDeletionDialogText.note(folderPath: "~/dev/phlox", locale: ja) == ProjectDeletionDialogText.note(folderPath: "~/dev/phlox"))
    }
}
