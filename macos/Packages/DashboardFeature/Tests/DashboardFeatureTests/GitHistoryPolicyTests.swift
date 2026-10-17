import Foundation
import AgentDomain
import Testing
@testable import DashboardFeature

@Suite("GitHistoryPolicy", .serialized)
struct GitHistoryPolicyTests {
    @Test @MainActor func 操作別の確認文言とスタッシュの対象件数() {
        let cases: [(GitRepositoryAction, String, String, String?)] = [
            (.deleteBranch("topic", force: false), "ブランチを削除しますか？", "削除", "現在の HEAD にマージ済みです。コミットは残ります。"),
            (.deleteBranch("topic", force: true), "マージされていないブランチを削除しますか？", "強制削除", "マージされていないコミットがブランチからたどれなくなります。強制削除します。"),
            (.dropStash("id"), "スタッシュを削除しますか？", "削除", "スタッシュの中の変更は戻せません。"),
            (.popStash("id"), "スタッシュを取り出しますか？", "取り出す", "変更を作業ツリーに戻してスタッシュを削除します。衝突した場合はスタッシュを残します。"),
            (.stash(""), "今の変更をスタッシュしますか？", "スタッシュ", "変更 9 件（未追跡 2 件を含む）をしまい、作業ツリーを HEAD に戻します。"),
            (.switchBranch("main"), "作業ツリーを変更しますか？", "実行", nil),
            (.checkoutRemote("origin/main"), "作業ツリーを変更しますか？", "実行", nil),
        ]
        for (action, title, button, message) in cases {
            let view = GitActionConfirmation(action: action, runningSessions: [], changeCount: 9, untrackedCount: 2, cancel: {}, perform: {})
            #expect(view.title == title)
            #expect(view.button == button)
            #expect(view.message == message)
        }
    }

    @Test @MainActor func リモートはoriginだけ既定で開く() {
        let model = EditorPanelViewModel(service: nil)
        model.remoteBranches = [.init(name: "origin/main", current: false), .init(name: "upstream/main", current: false)]
        let view = GitInspectorView(model: model, workingDirectory: "", openChanges: { _, _, _ in }, openFile: { _ in })
        #expect(view.remoteIsExpanded("origin"))
        #expect(!view.remoteIsExpanded("upstream"))
    }

    private func commit(_ id: String, _ parents: [String] = []) -> GitHistoryCommit {
        .init(id: id, parents: parents, summary: id, author: "Test", date: .distantPast)
    }

    @Test func 分岐と合流の線は親のレーンへ接続する() {
        let rows = GitGraphRow.make([commit("merge", ["left", "right"]), commit("left", ["base"]),
                                     commit("right", ["base"]), commit("base")])
        #expect(rows.count == 4)
        #expect(rows[0].lane == 0 && rows[0].outgoing == [.init(from: 0, to: 0, color: 0), .init(from: 0, to: 1, color: 1)])
        #expect(rows[1].lane == 0 && rows[1].width == 2)
        #expect(rows[2].lane == 1 && rows[2].outgoing.contains(.init(from: 1, to: 0, color: 0)))
        #expect(rows[3].incoming == [.init(from: 0, to: 0, color: 0)])
        #expect(rows[3].outgoing.isEmpty)
    }

    @Test func 独立したブランチと三つの親と表示外の親() {
        let rows = GitGraphRow.make([commit("tip1", ["p"]), commit("tip2", ["q"]),
                                     commit("p", ["q", "r", "s"]), commit("q", ["root"]), commit("r", ["root"])])
        #expect(rows[1].lane == 1)
        // q は既存レーンを共用し、残りの2親だけ追加する。
        #expect(rows[2].outgoing.filter { $0.from == rows[2].lane }.map(\.to) == [0, 1, 2])
        #expect(rows[2].width == 3)
        // 未表示の親も末尾から下へ線を残す。200件の境界で偽のルートにしない。
        #expect(!rows.last!.outgoing.isEmpty)
        #expect(GitGraphRow.make([]).isEmpty)
    }

    @Test func 確認は削除と取り出しと実行中の作業ツリー変更で必要() {
        let writes: [GitRepositoryAction] = [.switchBranch("main"), .checkoutRemote("origin/main"), .stash(""),
            .applyStash("id"), .createBranch(name: "new", start: "HEAD", switchTo: true)]
        for action in writes {
            #expect(!action.needsConfirmation(runningSession: false))
            #expect(action.needsConfirmation(runningSession: true))
        }
        for action in [GitRepositoryAction.deleteBranch("old", force: false), .deleteBranch("old", force: true), .dropStash("id"), .popStash("id")] {
            #expect(action.needsConfirmation(runningSession: false))
            #expect(action.needsConfirmation(runningSession: true))
        }
        for action in [GitRepositoryAction.fetch, .renameBranch(old: "a", new: "b"), .createBranch(name: "new", start: "HEAD", switchTo: false)] {
            #expect(!action.needsConfirmation(runningSession: true))
        }
    }

    @Test func グラフの札は追跡先を束ねてタグとリモート専用を分ける() {
        let badges = GitGraphBadge.make(refs: ["HEAD -> refs/heads/feature/long-name", "refs/remotes/origin/feature/long-name",
            "tag: refs/tags/v1", "refs/remotes/upstream/remote-only", "refs/remotes/origin/HEAD"])
        #expect(badges.count == 3)
        #expect(badges[0].title == "…/long-name" && badges[0].cloud && badges[0].current && !badges[0].remoteOnly)
        #expect(badges[0].fullName == "feature/long-name · origin/feature/long-name")
        #expect(badges[1].title == "v1" && badges[1].tag)
        #expect(badges[2].title == "remote-only" && badges[2].remoteOnly)
    }

    @Test func 実行中だけを対象にしてワークツリーと他のフォルダを除く() {
        #expect(GitTabPolicy.runningInProject(status: .running, workspacePath: "/project/./", projectPath: "/project"))
        #expect(!GitTabPolicy.runningInProject(status: .running, workspacePath: "/project/worktrees/a", projectPath: "/project"))
        #expect(!GitTabPolicy.runningInProject(status: .running, workspacePath: "/project-other", projectPath: "/project"))
        for status in [SessionStatus.idle, .starting, .awaitingApproval(prompt: ""), .awaitingUserQuestion, .completed(exitCode: 0), .error(message: "")] {
            #expect(!GitTabPolicy.runningInProject(status: status, workspacePath: "/project", projectPath: "/project"))
        }
    }

    @Test @MainActor func キー操作の対象は開いた区画と開いた履歴行のファイルだけ() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        let suiteName = "GitHistoryPolicyTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for section in GitHistorySection.allCases { defaults.set(false, forKey: section.storageKey) }
        defaults.set(false, forKey: "phlox.inspector.git.changesExpanded")
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.commits, expanded: true)
        await model.setHistorySection(.branches, expanded: true)
        let commit = try #require(model.historyCommits.first)
        var opened: [GitChangeSelection] = []
        let view = GitInspectorView(model: model, workingDirectory: fixture.root.path,
            openChanges: { path, source, _ in if let path { opened.append(.init(path: path, source: source)) } }, openFile: { _ in },
            defaults: defaults)
        #expect(view.visibleRows.isEmpty)
        view.activateHistoryRow(.commit(commit.id, graph: false))
        #expect(model.expandedHistoryRows.isEmpty)
        view.commitsExpanded = true
        #expect(view.visibleRows == [.commit(commit.id, graph: false)])
        await model.toggleHistoryRow(.commit(commit.id))
        let file = GitChangeSelection(path: "a.txt", source: .commit(commit.id))
        #expect(view.visibleRows == [.commit(commit.id, graph: false), .file(file, graph: false)])
        view.activateHistoryRow(.file(file, graph: false))
        #expect(opened == [file])
        view.commitsExpanded = false
        view.activateHistoryRow(.file(file, graph: false))
        view.activateHistoryRow(.branch("main"))
        #expect(opened == [file] && view.visibleRows.isEmpty)
        view.branchesExpanded = true
        #expect(view.visibleRows == [.branch("main")])
    }
}
