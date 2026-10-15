import Foundation
import Testing
import AppKit
import SwiftUI
@testable import DashboardFeature

@Suite("GitHistoryWorkflow", .serialized, .timeLimit(.minutes(3)))
struct GitHistoryWorkflowTests {
    @Test @MainActor func モデル交換後も開いた区画を新モデルへ同期する() async throws {
        _ = NSApplication.shared
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var settings = original
        for section in GitHistorySection.allCases { settings[section.storageKey] = true }
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let first = fixture.model()
        let second = fixture.model()
        await first.refresh()
        await second.refresh()
        let holder = GitHistoryModelHolder(model: first)
        let host = NSHostingView(rootView: GitHistoryModelHost(holder: holder))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<200 where first.loadedHistorySections.count < 5 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(first.loadedHistorySections == Set(GitHistorySection.allCases))
        holder.model = second
        for _ in 0..<200 where second.loadedHistorySections.count < 5 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(second.loadedHistorySections == Set(GitHistorySection.allCases))
        #expect(second.historyCommits.count == 1 && second.graphRows.count == 1)
    }

    @Test func 本文のBinaryFilesという語はコミットもスタッシュもテキストのまま() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.write("Binary files are explained here\n")
        try fixture.git(["add", "a.txt"])
        try fixture.git(["commit", "-m", "text"])
        let commit = try #require(try await fixture.reader.history().first)
        guard case .diff(let diff) = try await fixture.reader.detail(for: "a.txt", source: .commit(commit.id)) else {
            Issue.record("コミットのテキストをバイナリと誤判定"); return
        }
        #expect(diff.contains("+Binary files are explained here"))
        try fixture.write("Binary files are explained here too\n")
        try fixture.write("Binary files untracked\n", path: "new.txt")
        try Data([0, 1, 2]).write(to: fixture.root.appendingPathComponent("binary.dat"))
        try await fixture.workflow.perform(.stash("text and binary"))
        let stash = try #require(try await fixture.reader.stashes().first)
        for path in ["a.txt", "new.txt"] {
            guard case .diff(let text) = try await fixture.reader.detail(for: path, source: stash.source) else {
                Issue.record("スタッシュのテキストをバイナリと誤判定"); continue
            }
            #expect(text.contains("+Binary files "))
        }
        #expect(try await fixture.reader.detail(for: "binary.dat", source: stash.source) == .binary)
    }

    @Test func 古い先端へ切り替えると利用順の先頭に来る() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.git(["branch", "old"])
        try fixture.git(["commit", "--allow-empty", "-m", "newer"], environment: ["GIT_COMMITTER_DATE": "2030-01-01T00:00:00+00:00"])
        try fixture.git(["branch", "never-used-new"])
        try fixture.git(["branch", "never-used-old", "HEAD~1"])
        try fixture.git(["switch", "old"])
        #expect(try await fixture.reader.branches().map(\.name).first == "old")
        try fixture.git(["switch", "main"])
        try fixture.git(["switch", "old"])
        let names = try await fixture.reader.branches().map(\.name)
        #expect(Array(names.prefix(2)) == ["old", "main"])
        #expect(Array(names.suffix(2)) == ["never-used-new", "never-used-old"])
        #expect(names.count == 4)
    }

    @Test(arguments: [false, true]) func GTWRegression_改名後も現在と過去のブランチの利用順を引き継ぐ(現在を改名: Bool) async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.git(["branch", "topic"])
        try fixture.git(["switch", "topic"])
        try fixture.git(["switch", "main"])
        try fixture.git(["commit", "--allow-empty", "-m", "newer"], environment: ["GIT_COMMITTER_DATE": "2030-01-01T00:00:00+00:00"])
        try fixture.git(["branch", "unused"])
        try await fixture.workflow.perform(.renameBranch(old: 現在を改名 ? "main" : "topic", new: "renamed"))
        let branches = try await fixture.reader.branches()
        #expect(branches.map(\.name) == (現在を改名 ? ["renamed", "topic", "unused"] : ["main", "renamed", "unused"]))
        #expect(branches.first?.current == true)
    }

    @Test func GTWRegression_改名前の名前を再利用しても利用順を混同しない() async throws {
        let f = try GitHistoryFixture()
        defer { f.remove() }
        try f.git(["branch", "topic"])
        try f.git(["switch", "topic"])
        try f.git(["switch", "main"])
        try f.git(["commit", "--allow-empty", "-m", "newer"],
                  environment: ["GIT_COMMITTER_DATE": "2030-01-01T00:00:00+00:00"])
        try f.git(["branch", "unused"])
        try f.git(["branch", "-m", "topic", "old-topic"],
                  environment: ["GIT_COMMITTER_DATE": "2031-01-01T00:00:00+00:00"])
        try f.git(["branch", "topic"])
        try f.git(["switch", "topic"])
        try f.git(["switch", "main"])
        try f.git(["branch", "-m", "topic", "new-topic"],
                  environment: ["GIT_COMMITTER_DATE": "2032-01-01T00:00:00+00:00"])

        let names = try await f.reader.branches().map(\.name)
        // 既知の制限（ADR 0209）: reflog だけでは同じ名前を使った別のブランチを確実に見分けられない。
        withKnownIssue("旧名を再利用したブランチの利用順を区別できない（ADR 0209）") {
            #expect(names == ["main", "new-topic", "old-topic", "unused"])
        }
    }

    @Test func GTWRegression_連続改名でも利用順を引き継ぐ() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.git(["branch", "topic"])
        try fixture.git(["switch", "topic"])
        try fixture.git(["switch", "main"])
        try fixture.git(["commit", "--allow-empty", "-m", "newer"], environment: ["GIT_COMMITTER_DATE": "2030-01-01T00:00:00+00:00"])
        try fixture.git(["branch", "unused"])
        try await fixture.workflow.perform(.renameBranch(old: "topic", new: "renamed"))
        try await fixture.workflow.perform(.renameBranch(old: "renamed", new: "twice"))
        #expect(try await fixture.reader.branches().map(\.name) == ["main", "twice", "unused"])
    }

    @Test @MainActor func GTWRegression_ページ間に外部コミットが増えてもグラフを重複させない() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        for i in 1...204 { try fixture.git(["commit", "--allow-empty", "-m", "commit \(i)"]) }
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.graph, expanded: true)
        #expect(model.graphRows.count == 200 && model.hasMoreGraph)
        try fixture.git(["commit", "--allow-empty", "-m", "external"])
        await model.loadMoreGraph()
        let ids = model.graphRows.map(\.commit.id)
        #expect(ids.count == Set(ids).count)
        #expect(ids.count == 206 && !model.hasMoreGraph)
        #expect(model.graphRows.first?.commit.summary == "external")
        #expect(model.graphRows.last?.commit.summary == "initial")
        await model.refresh()
        #expect(model.graphRows.count == 206 && !model.hasMoreGraph)
    }

    @Test @MainActor func グラフは200件から追加して末尾の初回コミットに届く() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        for i in 1...204 { try fixture.git(["commit", "--allow-empty", "-m", "commit \(i)"]) }
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.graph, expanded: true)
        #expect(model.graphRows.count == 200 && model.hasMoreGraph)
        await model.loadMoreGraph()
        #expect(model.graphRows.count == 205 && !model.hasMoreGraph)
        #expect(model.graphRows.last?.commit.summary == "initial")
        #expect(Set(model.graphRows.map(\.commit.id)).count == 205)
        await model.refresh()
        #expect(model.graphRows.count == 205 && !model.hasMoreGraph)
    }

    @Test @MainActor func 履歴と初回コミットとページと参照を読み取り専用で取得する() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        let reader = fixture.reader
        let initial = try #require(try await reader.history().first)
        #expect(initial.summary == "initial" && initial.parents.isEmpty)
        #expect(try await reader.historyFiles(source: .commit(initial.id)).map(\.path) == ["a.txt"])
        for i in 1...52 { try fixture.git(["commit", "--allow-empty", "-m", "commit \(i)"]) }
        try fixture.git(["tag", "v1"])
        try fixture.git(["branch", "other"])
        let index = fixture.root.appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        let modified = try index.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let page = try await reader.history()
        let next = try await reader.history(skip: 50)
        #expect(page.count == 50 && next.count == 3)
        #expect(Set(page.map(\.id)).isDisjoint(with: next.map(\.id)))
        #expect(page.first?.summary == "commit 52")
        #expect(try await reader.branches().contains { $0.name == "main" && $0.current })
        #expect(try await reader.history(all: true).first?.refs.contains("tag: refs/tags/v1") == true)
        #expect(await reader.worktreeStartPoints().contains { $0.point == .localBranch("other") })
        #expect(try Data(contentsOf: index) == before)
        #expect(try index.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.commits, expanded: true)
        #expect(model.historyCommits.count == 50 && model.hasMoreCommits)
        await model.loadMoreCommits()
        #expect(model.historyCommits.count == 53 && !model.hasMoreCommits)
        #expect(Set(model.historyCommits.map(\.id)).count == 53)
    }

    @Test func 新しいリポジトリの空状態() async throws {
        let fixture = try GitHistoryFixture(unborn: true)
        defer { fixture.remove() }
        #expect(try await fixture.reader.history().isEmpty)
        #expect(try await fixture.reader.history(all: true).isEmpty)
        #expect(try await fixture.reader.stashes().isEmpty)
        #expect(try await fixture.reader.branches() == [.init(name: "main", current: true)])
        #expect(try await fixture.reader.branches(remote: true).isEmpty)
        try await fixture.workflow.perform(.createBranch(name: "new-unborn", start: "HEAD", switchTo: true))
        #expect(await fixture.reader.branchLabel() == "new-unborn")
    }

    @Test func 改名と削除とバイナリの履歴を現在の作業ツリーと混ぜない() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.write("delete me\n", path: "deleted.txt")
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "base files"])
        try fixture.git(["mv", "a.txt", "日本語 [x].txt"])
        try fixture.git(["rm", "deleted.txt"])
        try Data([0, 1, 2, 3]).write(to: fixture.root.appendingPathComponent("binary.dat"))
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "rename delete binary"])
        let commit = try #require(try await fixture.reader.history().first)
        let source = WorkingTreeSource.commit(commit.id)
        let files = try await fixture.reader.historyFiles(source: source)
        #expect(files.first { $0.path == "日本語 [x].txt" }?.originalPath == "a.txt")
        #expect(files.first { $0.path == "deleted.txt" }?.kind == .deleted)
        guard case .diff(let rename) = try await fixture.reader.detail(for: "日本語 [x].txt", source: source),
              case .diff(let deleted) = try await fixture.reader.detail(for: "deleted.txt", source: source) else {
            Issue.record("履歴の差分がない"); return
        }
        #expect(rename.contains("rename from a.txt"))
        #expect(deleted.contains("-delete me"))
        #expect(try await fixture.reader.detail(for: "binary.dat", source: source) == .binary)
        try fixture.write("working copy\n", path: "日本語 [x].txt")
        #expect(try await fixture.reader.fileContents("日本語 [x].txt", source: source) == "initial\n")
        await #expect(throws: (any Error).self) { try await fixture.reader.detail(for: "../a.txt", source: source) }
    }

    @Test func スタッシュ内の削除は未追跡ツリーと取り違えない() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.git(["rm", "a.txt"])
        try fixture.write("new\n", path: "new.txt")
        try await fixture.workflow.perform(.stash("delete and untracked"))
        let stash = try #require(try await fixture.reader.stashes().first)
        guard case .diff(let diff) = try await fixture.reader.detail(for: "a.txt", source: stash.source) else {
            Issue.record("スタッシュ内の削除差分がない"); return
        }
        #expect(diff.contains("-initial"))
    }

    @Test func ブランチ作成と切り替えと改名と削除() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        let workflow = fixture.workflow
        let initial = try fixture.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await workflow.perform(.createBranch(name: "from-head", start: "HEAD", switchTo: false))
        #expect(await fixture.reader.branchLabel() == "main")
        try await workflow.perform(.switchBranch("from-head"))
        try await workflow.perform(.renameBranch(old: "from-head", new: "renamed"))
        #expect(await fixture.reader.branchLabel() == "renamed")
        try await workflow.perform(.switchBranch("main"))
        #expect(try await fixture.reader.isBranchMerged("renamed"))
        try await workflow.perform(.deleteBranch("renamed", force: false))
        try await workflow.perform(.createBranch(name: "from-commit", start: initial, switchTo: true))
        #expect(await fixture.reader.branchLabel() == "from-commit")
        try fixture.write("unmerged\n")
        try fixture.git(["add", "a.txt"])
        try fixture.git(["commit", "-m", "unmerged"])
        try await workflow.perform(.switchBranch("main"))
        #expect(try await fixture.reader.isBranchMerged("from-commit") == false)
        await #expect(throws: GitWorkflowError.self) { try await workflow.perform(.deleteBranch("from-commit", force: false)) }
        #expect(try await fixture.reader.branches().contains { $0.name == "from-commit" })
        try await workflow.perform(.deleteBranch("from-commit", force: true))
        #expect(try await fixture.reader.branches().contains { $0.name == "from-commit" } == false)
        await #expect(throws: GitWorkflowError.self) { try await workflow.perform(.createBranch(name: "bad name", start: "HEAD", switchTo: true)) }
        await #expect(throws: GitWorkflowError.self) { try await workflow.perform(.createBranch(name: "-unsafe", start: "HEAD", switchTo: true)) }
        await #expect(throws: GitWorkflowError.self) { try await workflow.perform(.createBranch(name: "main", start: "HEAD", switchTo: true)) }
    }

    @Test @MainActor func 切り替え失敗の理由と作業中の内容を保持する() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try await fixture.workflow.perform(.createBranch(name: "other", start: "HEAD", switchTo: true))
        try fixture.write("other branch\n")
        try fixture.git(["add", "a.txt"])
        try fixture.git(["commit", "-m", "other"])
        try await fixture.workflow.perform(.switchBranch("main"))
        try fixture.write("unsaved\n")
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.branches, expanded: true)
        await model.performRepositoryAction(.switchBranch("other"))
        #expect(model.workflowStatusIsError)
        #expect(model.workflowStatusMessage?.contains("would be overwritten") == true)
        #expect(model.branchLabel == "main" && !model.isWorkflowBusy)
        #expect(try fixture.content() == "unsaved\n")
        #expect(try await fixture.reader.stashes().isEmpty)
    }

    @Test func リモート一覧は別名を除き追跡付きチェックアウトと取得ができる() async throws {
        let fixture = try GitHistoryFixture()
        let remote = try GitHistoryFixture()
        defer { fixture.remove(); remote.remove() }
        try remote.git(["branch", "topic/one"])
        try fixture.git(["remote", "add", "origin", remote.root.path])
        #expect(try await fixture.reader.lastFetchDate() == nil)
        try await fixture.workflow.perform(.fetch)
        #expect(try await fixture.reader.lastFetchDate() != nil)
        try fixture.git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"])
        let branches = try await fixture.reader.branches(remote: true)
        #expect(Set(branches.map(\.name)) == ["origin/main", "origin/topic/one"])
        try await fixture.workflow.perform(.checkoutRemote("origin/topic/one"))
        #expect(await fixture.reader.branchLabel() == "topic/one")
        #expect(try await fixture.reader.branches(remote: true).first { $0.name == "origin/topic/one" }?.tracked == true)
        #expect(try await fixture.reader.branches(remote: true).first { $0.name == "origin/main" }?.tracked == false)
        #expect(try fixture.git(["rev-parse", "--abbrev-ref", "@{upstream}"]).trimmingCharacters(in: .whitespacesAndNewlines) == "origin/topic/one")
        try await fixture.workflow.perform(.switchBranch("main"))
        try await fixture.workflow.perform(.checkoutRemote("origin/topic/one"))
        #expect(await fixture.reader.branchLabel() == "topic/one")
        try remote.git(["branch", "later"])
        try await fixture.workflow.perform(.fetch)
        #expect(try await fixture.reader.branches(remote: true).contains { $0.name == "origin/later" })
    }

    @Test @MainActor func 未追跡を含むスタッシュの一覧と差分と内容と適用と取り出しと削除() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.write("stashed\n")
        try fixture.write("new file\n", path: "日本語 [x].txt")
        try await fixture.workflow.perform(.stash("saved message"))
        #expect(try await fixture.reader.changes().isEmpty)
        let stash = try #require(try await fixture.reader.stashes().first)
        #expect(stash.message.contains("saved message") && stash.name == "stash@{0}")
        let graph = try await fixture.reader.history(limit: 200, all: true)
        #expect(!graph.contains { $0.id == stash.id })
        #expect(graph.count == 1 && graph.first?.summary == "initial")
        #expect(Set(try await fixture.reader.historyFiles(source: stash.source).map(\.path)) == ["a.txt", "日本語 [x].txt"])
        guard case .diff(let tracked) = try await fixture.reader.detail(for: "a.txt", source: stash.source),
              case .diff(let untracked) = try await fixture.reader.detail(for: "日本語 [x].txt", source: stash.source) else {
            Issue.record("スタッシュ差分がない"); return
        }
        #expect(tracked.contains("+stashed") && untracked.contains("+new file"))
        #expect(try await fixture.reader.fileContents("日本語 [x].txt", source: stash.source) == "new file\n")
        let model = fixture.model()
        await model.refresh()
        await model.select("a.txt", source: stash.source)
        #expect(model.isReadOnly && model.selectedSource == stash.source && model.canViewContent)
        try await fixture.workflow.perform(.applyStash(stash.id))
        #expect(try fixture.content() == "stashed\n")
        #expect(try await fixture.reader.stashes().count == 1)
        try await fixture.workflow.perform(.stash(""))
        let newest = try #require(try await fixture.reader.stashes().first)
        // ID を使うので、古い番号が変わってもそのスタッシュだけを削除する。
        try await fixture.workflow.perform(.dropStash(stash.id))
        #expect(try await fixture.reader.stashes().map(\.id) == [newest.id])
        try await fixture.workflow.perform(.popStash(newest.id))
        #expect(try await fixture.reader.stashes().isEmpty)
        #expect(try fixture.content() == "stashed\n")
        #expect(try fixture.content(path: "日本語 [x].txt") == "new file\n")
    }

    @Test @MainActor func スタッシュの衝突でもスタッシュを残して一覧と失敗を更新する() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        try fixture.write("stash version\n")
        try await fixture.workflow.perform(.stash("conflict"))
        let stash = try #require(try await fixture.reader.stashes().first)
        try fixture.write("committed version\n")
        try fixture.git(["add", "a.txt"])
        try fixture.git(["commit", "-m", "conflicting change"])
        let model = fixture.model()
        await model.refresh()
        await model.setHistorySection(.stashes, expanded: true)
        await model.performRepositoryAction(.popStash(stash.id))
        #expect(model.workflowStatusIsError)
        #expect(model.workflowStatusMessage?.contains("CONFLICT") == true)
        #expect(model.gitStashes.map(\.id) == [stash.id])
        // 再レビュー要件: 衝突は通常の変更へ混ぜず、専用一覧で保持する。
        #expect(model.conflictedPaths == ["a.txt"])
        #expect(!model.unstagedChanges.contains { $0.path == "a.txt" })
        #expect(!model.stagedChanges.contains { $0.path == "a.txt" })
        model.commitMessage = "競合をコミットしない"
        #expect(!model.canCommit)
        #expect(try fixture.content().contains("<<<<<<<"))
    }

    @Test @MainActor func 開いた区画だけ更新し閉じた区画は次に開いたとき読む() async throws {
        let fixture = try GitHistoryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.refresh()
        #expect(model.loadedHistorySections.isEmpty)
        await model.setHistorySection(.commits, expanded: true)
        #expect(model.historyCommits.count == 1)
        await model.setHistorySection(.commits, expanded: false)
        await model.performRepositoryAction(.createBranch(name: "new", start: "HEAD", switchTo: false))
        #expect(!model.loadedHistorySections.contains(.commits))
        try fixture.git(["commit", "--allow-empty", "-m", "new commit"])
        await model.setHistorySection(.commits, expanded: true)
        #expect(model.historyCommits.count == 2)
        await model.setHistorySection(.branches, expanded: true)
        #expect(model.localBranches.contains { $0.name == "new" })
        model.activeGitRow = .branch("new")
        await model.refresh()
        #expect(model.activeGitRow == .branch("new"))
        model.setSnapshotNotRepository()
        #expect(model.historyCommits.isEmpty && model.localBranches.isEmpty && model.loadedHistorySections.isEmpty)
    }
}

struct GitHistoryFixture {
    let root: URL
    var reader: WorkingTreeService { WorkingTreeService(repositoryRoot: root) }
    var workflow: GitWorkflowService { GitWorkflowService(repositoryRoot: root, gitHubCLIPath: "/nonexistent/phlox-test-gh") }

    init(unborn: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "--initial-branch=main"])
        try git(["config", "user.name", "Phlox Test"])
        try git(["config", "user.email", "test@phlox.local"])
        try git(["config", "commit.gpgsign", "false"])
        if !unborn {
            try write("initial\n")
            try git(["add", "a.txt"])
            try git(["commit", "-m", "initial"])
        }
    }

    @MainActor func model() -> EditorPanelViewModel { EditorPanelViewModel(service: reader, workflowService: workflow) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func write(_ text: String, path: String = "a.txt") throws { try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
    func content(path: String = "a.txt") throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    @discardableResult func git(_ arguments: [String], environment overrides: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["LC_ALL"] = "C"
        environment.merge(overrides) { _, value in value }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        try #require(process.terminationStatus == 0, "git \(arguments): \(text)")
        return text
    }
}

@MainActor @Observable private final class GitHistoryModelHolder {
    var model: EditorPanelViewModel
    init(model: EditorPanelViewModel) { self.model = model }
}

@MainActor private struct GitHistoryModelHost: View {
    let holder: GitHistoryModelHolder
    var body: some View {
        GitInspectorView(model: holder.model, workingDirectory: "", openChanges: { _, _, _ in }, openFile: { _ in })
    }
}
