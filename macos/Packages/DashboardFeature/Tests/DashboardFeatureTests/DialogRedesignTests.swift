import AgentDomain
import Foundation
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
        #expect(CleanupWarningDialogText.title(branch, locale: ja) == branch.title)
        #expect(CleanupWarningDialogText.detail(branch) == "phlox/a3f9")
        #expect(CleanupWarningDialogText.revealPath(branch) == nil)
    }

    @Test func sessionDeletion_namesTheSession_andCountsChildren() {
        #expect(SessionDeletionDialogText.title(sessionName: "準備", childCount: 0, locale: ja) == "「準備」を削除しますか?")
        #expect(SessionDeletionDialogText.title(sessionName: "準備", childCount: 3, locale: ja) == "「準備」と子セッション 3 件を削除しますか?")
    }

    @Test func sessionDeletion_listsChildren_keepsFolder_andEndsWithIrreversibility() {
        let plain = SessionDeletionDialogText.message(children: [], dirtyFiles: [], locale: ja)
        #expect(plain.contains("元に戻せません"))
        #expect(plain.hasSuffix("プロジェクトのフォルダとファイルは削除されません。"))

        let children = (1...8).map { "子\($0) · 実行中" }
        let full = SessionDeletionDialogText.message(children: children, dirtyFiles: ["a.swift", "b.swift"], locale: ja)
        #expect(full.contains("・子1 · 実行中"))
        #expect(full.contains("・子\(SessionDeletionDialogText.listLimit) · 実行中"))
        #expect(!full.contains("・子\(SessionDeletionDialogText.listLimit + 1) "))
        #expect(full.contains("ほか \(children.count - SessionDeletionDialogText.listLimit) 件"))
        #expect(full.contains("保存していないファイル（a.swift、b.swift）の変更も失われます。"))
    }

    /// 表示言語に合わせて引く版が、テストで固定された日本語と一字一句同じであること。
    @Test func projectDeletion_localizedTextMatchesFrozenJapanese() {
        for count in 0...3 {
            #expect(ProjectDeletionDialogText.title(descendantCount: count, locale: ja) == ProjectDeletionDialogText.title(descendantCount: count))
            #expect(ProjectDeletionDialogText.message(descendantCount: count, locale: ja) == ProjectDeletionDialogText.message(descendantCount: count))
        }
        #expect(ProjectDeletionDialogText.irreversibleNote(sessionCount: 6, locale: ja) == "セッション 6 件の会話とターミナルの内容は元に戻せません。")
    }
}
