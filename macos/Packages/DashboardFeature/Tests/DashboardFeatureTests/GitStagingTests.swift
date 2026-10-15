import Foundation
import Testing
@testable import DashboardFeature

@Suite("GitStaging", .timeLimit(.minutes(2)))
struct GitStagingTests {
    private func repository(unborn: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-staging-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "--initial-branch=main"], root)
        try git(["config", "user.name", "Phlox Test"], root)
        try git(["config", "user.email", "test@phlox.local"], root)
        try git(["config", "commit.gpgsign", "false"], root)
        try git(["config", "core.hooksPath", "/dev/null"], root)
        if !unborn {
            try write("original\n", "a.txt", root)
            try write("original\n", "b.txt", root)
            try git(["add", "."], root)
            try git(["commit", "-m", "initial"], root)
        }
        return root
    }

    private func write(_ content: String, _ path: String, _ root: URL) throws {
        try content.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func git(_ args: [String], _ root: URL, input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }
        try process.run()
        if let input {
            try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try stdin.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        try #require(process.terminationStatus == 0, "git \(args): \(output)")
        return output
    }

    @Test @MainActor func 競合は通常変更から分離し一括ステージでも解決済みにしない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let oid = try git(["rev-parse", "HEAD:a.txt"], root).trimmingCharacters(in: .whitespacesAndNewlines)
        let states = [("DD", [1]), ("AU", [2]), ("UD", [1, 2]), ("UA", [3]), ("DU", [1, 3]), ("AA", [2, 3]), ("UU", [1, 2, 3])]
        for (xy, stages) in states {
            let path = xy + ".txt"
            try write("<<<<<<< ours\n=======\n>>>>>>> theirs\n", path, root)
            try git(["update-index", "--index-info"], root,
                    input: stages.map { "100644 \(oid) \($0)\t\(path)\n" }.joined())
        }
        let reader = WorkingTreeService(repositoryRoot: root)
        let model = EditorPanelViewModel(service: reader)
        await model.refresh()
        model.commitMessage = "競合を含めない"
        #expect(model.conflictedPaths == states.map { $0.0 + ".txt" }.sorted())
        #expect(model.stagedChanges.isEmpty)
        #expect(model.unstagedChanges.isEmpty)
        #expect(!model.canCommit)
        let before = try git(["ls-files", "--unmerged", "-z"], root)
        await model.stageAll()
        #expect(try git(["ls-files", "--unmerged", "-z"], root) == before)
        try write("normal change\n", "b.txt", root)
        await model.refresh()
        await model.stageAll()
        #expect(model.stagedChanges.map(\.path) == ["b.txt"])
        #expect(!model.canCommit)
        #expect(try git(["ls-files", "--unmerged", "-z"], root) == before)
        let workflow = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.unmergedChanges) { try await workflow.stage(paths: ["UU.txt"]) }
        await #expect(throws: GitWorkflowError.unmergedChanges) { try await workflow.unstage(paths: ["UU.txt"]) }
        await #expect(throws: GitWorkflowError.unmergedChanges) { try await workflow.commit(message: "競合") }
        #expect(try git(["ls-files", "--unmerged", "-z"], root) == before)
    }

    @Test(arguments: [false, true]) func GTWRegression_同名ディレクトリへの置換を一括ステージする(逆順: Bool) async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        let paths = ["a.txt", "a.txt/child.txt"]
        try await GitWorkflowService(repositoryRoot: root).stage(paths: 逆順 ? paths.reversed() : paths)
        #expect(Set(try git(["diff", "--cached", "--name-only"], root).split(whereSeparator: \.isNewline).map(String.init)) == Set(paths))
        #expect(try git(["show", ":a.txt/child.txt"], root) == "child\n")
    }

    @Test(arguments: [false, true]) func GTWRegression_同名ディレクトリへの置換を一括解除する(逆順: Bool) async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        try git(["add", "-A"], root)
        let paths = ["a.txt", "a.txt/child.txt"]
        try await GitWorkflowService(repositoryRoot: root).unstage(paths: 逆順 ? paths.reversed() : paths)
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt/child.txt"), encoding: .utf8) == "child\n")
    }

    @Test @MainActor func GTWRegression_ディレクトリをファイルに置換しても一括操作できる() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        try git(["add", "-A"], root)
        try git(["commit", "-m", "directory"], root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try write("replacement\n", "a.txt", root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        await model.stageAll()
        #expect(!model.workflowStatusIsError)
        #expect(model.unstagedChanges.isEmpty)
        #expect(try git(["show", ":a.txt"], root) == "replacement\n")
        await model.unstageAll()
        #expect(!model.workflowStatusIsError)
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "replacement\n")
    }

    @Test @MainActor func GTWRegression_一部解除後に失敗しても一覧を実際のindexへ更新する() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        try write("changed\n", "b.txt", root)
        try git(["add", "-A"], root)
        let reader = WorkingTreeService(repositoryRoot: root)
        let model = EditorPanelViewModel(service: reader)
        await model.refresh()
        await model.unstage(paths: ["b.txt", "a.txt"])
        #expect(model.workflowStatusIsError)
        #expect(model.workflowStatusMessage?.contains("update-index") == true)
        #expect(try git(["diff", "--cached", "--name-only", "--", "b.txt"], root).isEmpty)
        #expect(model.stagedChanges == (try await reader.snapshot()).stagedChanges)
        #expect(model.unstagedChanges == (try await reader.snapshot()).unstagedChanges)
        #expect(try git(["show", ":a.txt/child.txt"], root) == "child\n")
    }

    @Test @MainActor func GTWRegression_ステージ失敗時も外部で変わったindexを読み直す() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", "b.txt", root)
        let reader = WorkingTreeService(repositoryRoot: root)
        let model = EditorPanelViewModel(service: reader)
        await model.refresh()
        try git(["add", "b.txt"], root)
        await model.stage(paths: ["missing.txt"])
        #expect(model.workflowStatusIsError)
        #expect(model.workflowStatusMessage?.contains("missing.txt") == true)
        #expect(model.stagedChanges == (try await reader.snapshot()).stagedChanges)
        #expect(model.unstagedChanges == (try await reader.snapshot()).unstagedChanges)
    }

    @Test func 削除行のステージと解除は同名ディレクトリの子を含めない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        let reader = WorkingTreeService(repositoryRoot: root)
        try await workflow.stage(paths: ["a.txt"])
        #expect(try await reader.snapshot().stagedChanges.map(\.path) == ["a.txt"])
        try await workflow.unstage(paths: ["a.txt"])
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt/child.txt"), encoding: .utf8) == "child\n")
    }

    @Test func 削除の解除が子のステージと衝突したら子を外さず失敗を返す() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        try await workflow.stage(paths: ["a.txt"])
        try await workflow.stage(paths: ["a.txt/child.txt"])
        let before = try git(["ls-files", "--stage", "-z"], root)
        do {
            try await workflow.unstage(paths: ["a.txt"])
            Issue.record("同名の子がindexにあるのにファイルを復元した")
        } catch let error as GitWorkflowError {
            guard case .commandFailed(_, let output) = error else { Issue.record("Gitの失敗理由がない"); return }
            #expect(!output.isEmpty)
        }
        #expect(try git(["ls-files", "--stage", "-z"], root) == before)
    }

    @Test func 改名元が同名ディレクトリでもステージと解除は子を含めない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.moveItem(at: root.appendingPathComponent("a.txt"), to: root.appendingPathComponent("renamed.txt"))
        try git(["add", "-N", "renamed.txt"], root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a.txt"), withIntermediateDirectories: false)
        try write("child\n", "a.txt/child.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        let reader = WorkingTreeService(repositoryRoot: root)
        #expect(try await reader.snapshot().unstagedChanges.contains { $0.path == "renamed.txt" && $0.kind == .renamed })
        try await workflow.stage(paths: ["renamed.txt"])
        #expect(try await reader.snapshot().stagedChanges.map(\.path) == ["renamed.txt"])
        try await workflow.unstage(paths: ["renamed.txt"])
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt/child.txt"), encoding: .utf8) == "child\n")
    }

    @Test @MainActor func 削除後の同名再作成でも削除を隠さない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["rm", "--", "a.txt"], root)
        try write("rebuilt\n", "a.txt", root)
        try write("changed\n", "b.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        try await workflow.stage(paths: ["b.txt"])
        let reader = WorkingTreeService(repositoryRoot: root)
        let model = EditorPanelViewModel(service: reader)
        await model.refresh()
        #expect(Set(model.stagedChanges.map(\.path)) == ["a.txt", "b.txt"])
        #expect(model.stagedChanges.first { $0.path == "a.txt" }?.kind == .deleted)
        #expect(model.unstagedChanges.map(\.path) == ["a.txt"])
        #expect(try await reader.detail(for: "a.txt", source: .worktree) == .untrackedContent("rebuilt\n"))
        guard case .diff(let deletion) = try await reader.detail(for: "a.txt", source: .staged) else {
            Issue.record("ステージ済み削除の差分がない")
            return
        }
        #expect(deletion.contains("-original"))
        await model.unstageAll()
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "rebuilt\n")
    }

    @Test func 改名元の再作成と改名先の削除も出どころごとに残る() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["mv", "a.txt", "renamed.txt"], root)
        try write("rebuilt\n", "a.txt", root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("renamed.txt"))
        let reader = WorkingTreeService(repositoryRoot: root)
        let snapshot = try await reader.snapshot()
        #expect(snapshot.stagedChanges == [.init(path: "renamed.txt", kind: .renamed, isBinary: false)])
        #expect(snapshot.unstagedChanges.map(\.path) == ["a.txt", "renamed.txt"])
        #expect(snapshot.unstagedChanges.map(\.kind) == [.untracked, .deleted])
        #expect(try await reader.detail(for: "a.txt", source: .worktree) == .untrackedContent("rebuilt\n"))
        guard case .diff(let rename) = try await reader.detail(for: "renamed.txt", source: .staged) else {
            Issue.record("改名差分がない"); return
        }
        #expect(rename.contains("rename from a.txt"))
        try await GitWorkflowService(repositoryRoot: root).unstage(paths: ["renamed.txt"])
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
    }

    @Test func 型変更をステージした後の通常ファイルへの変更も両側に残る() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "b.txt")
        let workflow = GitWorkflowService(repositoryRoot: root)
        try await workflow.stage(paths: ["a.txt"])
        try FileManager.default.removeItem(at: file)
        try write("rebuilt\n", "a.txt", root)
        let reader = WorkingTreeService(repositoryRoot: root)
        let snapshot = try await reader.snapshot()
        #expect(snapshot.stagedChanges.map(\.path) == ["a.txt"])
        #expect(snapshot.unstagedChanges.map(\.path) == ["a.txt"])
        guard case .diff(let staged) = try await reader.detail(for: "a.txt", source: .staged),
              case .diff(let worktree) = try await reader.detail(for: "a.txt", source: .worktree) else {
            Issue.record("型変更の差分がない"); return
        }
        #expect(snapshot.stagedLineCounts["a.txt"] == .init(added: 1, deleted: 1))
        #expect(snapshot.unstagedLineCounts["a.txt"] == .init(added: 1, deleted: 1))
        #expect(staged.contains("120000"))
        #expect(worktree.contains("+rebuilt"))
        try await workflow.unstage(paths: ["a.txt"])
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
    }

    @Test @MainActor func 閉じた区画のキー操作は選択もindexも変えない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", "a.txt", root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        await model.select("a.txt")
        let before = try git(["ls-files", "--stage"], root)
        await model.moveGitSelection(by: 1, changesExpanded: false)
        await model.toggleSelectedStaging(changesExpanded: false)
        #expect(model.visibleGitRows(changesExpanded: false).isEmpty)
        #expect(model.gitSelection == .init(path: "a.txt", source: .worktree))
        #expect(try git(["ls-files", "--stage"], root) == before)
        await model.toggleSelectedStaging(changesExpanded: true)
        #expect(model.stagedChanges.map(\.path) == ["a.txt"])
    }

    @Test @MainActor func プッシュは初回前とdetachedでは無効で追跡先なしでは有効() async throws {
        let root = try repository(unborn: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["remote", "add", "origin", root.path + "/remote.git"], root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        #expect(!model.canPush)
        #expect(model.pushAvailabilityReason?.contains("初回") == true)
        try write("first\n", "a.txt", root)
        try git(["add", "."], root)
        try git(["commit", "-m", "initial"], root)
        await model.refresh()
        #expect(model.canPush)
        #expect(!model.hasUpstream)
        try git(["checkout", "--detach"], root)
        await model.refresh()
        #expect(!model.canPush)
        #expect(model.pushAvailabilityReason?.contains("detached HEAD") == true)
    }

    @Test func 部分ステージは両グループに現れ差分と行数を分離しindexだけコミットする() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        let reader = WorkingTreeService(repositoryRoot: root)
        try write("original\nstaged\n", "a.txt", root)
        try await workflow.stage(paths: ["a.txt"])
        try write("original\nstaged\nunstaged\n", "a.txt", root)
        let before = try git(["status", "--porcelain"], root)
        let snapshot = try await reader.snapshot()
        #expect(snapshot.stagedChanges.map(\.path) == ["a.txt"])
        #expect(snapshot.unstagedChanges.map(\.path) == ["a.txt"])
        #expect(snapshot.stagedLineCounts["a.txt"] == .init(added: 1, deleted: 0))
        #expect(snapshot.unstagedLineCounts["a.txt"] == .init(added: 1, deleted: 0))
        let staged = try await reader.detail(for: "a.txt", source: .staged)
        let unstaged = try await reader.detail(for: "a.txt", source: .worktree)
        guard case .diff(let stagedText) = staged, case .diff(let unstagedText) = unstaged else {
            Issue.record("比較元ごとの差分を取得できない")
            return
        }
        #expect(stagedText.contains("+staged"))
        #expect(!stagedText.contains("unstaged"))
        #expect(try await reader.fileContents("a.txt", source: .staged) == "original\nstaged\n")
        #expect(unstagedText.contains("+unstaged"))
        #expect(!unstagedText.contains("+staged"))
        #expect(try git(["status", "--porcelain"], root) == before)
        _ = try await workflow.commit(message: "index only")
        #expect(try git(["show", "HEAD:a.txt"], root) == "original\nstaged\n")
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "original\nstaged\nunstaged\n")
    }

    @Test func 特殊名のステージと解除は隣の名前を巻き込まない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        let names = ["test[1].txt", ":colon.txt", "--dash.txt", "日本語 space.txt", "line\nbreak.txt"]
        for name in names + ["test1.txt"] { try write("new\n", name, root) }
        try await workflow.stage(paths: names)
        let staged = try git(["diff", "--cached", "--name-only", "-z"], root).split(separator: "\0").map(String.init)
        #expect(Set(staged) == Set(names))
        try await workflow.unstage(paths: names)
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        for name in names { #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)) }
    }

    @Test func 削除と改名の解除はindexを戻し作業ツリーを維持する() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))
        try await workflow.stage(paths: ["a.txt"])
        try await workflow.unstage(paths: ["a.txt"])
        #expect(try git(["status", "--porcelain"], root).contains(" D a.txt"))
        try git(["mv", "b.txt", "renamed.txt"], root)
        try await workflow.unstage(paths: ["renamed.txt"])
        #expect(try git(["diff", "--cached", "--name-only"], root).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.txt").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path))
    }

    @Test func 初回コミット前でもステージを外せて内容は残る() async throws {
        let root = try repository(unborn: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        try write("first\n", "first.txt", root)
        try await workflow.stage(paths: ["first.txt"])
        let reader = WorkingTreeService(repositoryRoot: root)
        #expect(try await reader.snapshot().stagedChanges.map(\.path) == ["first.txt"])
        try await workflow.unstage(paths: ["first.txt"])
        #expect(try git(["status", "--porcelain"], root).contains("?? first.txt"))
        #expect(try String(contentsOf: root.appendingPathComponent("first.txt"), encoding: .utf8) == "first\n")
    }

    @Test func 初回コミット前の部分ステージ解除をgitが拒否したら理由とindexを保持する() async throws {
        let root = try repository(unborn: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        try write("staged\n", "first.txt", root)
        try await workflow.stage(paths: ["first.txt"])
        try write("changed after staging\n", "first.txt", root)
        do {
            try await workflow.unstage(paths: ["first.txt"])
            Issue.record("git rm --cached が部分ステージの保護を行わなかった")
        } catch let error as GitWorkflowError {
            guard case .commandFailed(let arguments, let output) = error else {
                Issue.record("解除失敗の理由が保存されていない: \(error)")
                return
            }
            #expect(arguments == ["rm", "--cached", "--quiet", "--", ":(literal)first.txt"])
            #expect(output.contains("first.txt"))
            #expect(!output.isEmpty)
        }
        #expect(try git(["show", ":first.txt"], root) == "staged\n")
        #expect(try String(contentsOf: root.appendingPathComponent("first.txt"), encoding: .utf8) == "changed after staging\n")
    }

    @Test @MainActor func 入力先は同グループの次行へ進み最後は未選択になる() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", "a.txt", root)
        try write("changed\n", "b.txt", root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        #expect(model.selectedPath == nil)
        #expect(model.gitSelection == nil)
        #expect(model.detail == .none)
        await model.select("a.txt")
        model.presentWorkflowError("前の失敗")
        await model.toggleSelectedStaging()
        #expect(model.workflowStatusMessage == nil)
        #expect(model.gitSelection == .init(path: "b.txt", source: .worktree))
        await model.toggleSelectedStaging()
        #expect(model.gitSelection == nil)
        #expect(model.detail == .none)
        await model.select("a.txt", source: .staged)
        #expect(model.selectedSource == .staged)
        #expect(model.draft == "changed\n")
        #expect(model.isReadOnly)
        await model.refresh()
        #expect(model.gitSelection == .init(path: "a.txt", source: .staged))
        await model.toggleSelectedStaging()
        #expect(model.gitSelection == .init(path: "b.txt", source: .staged))
    }

    @Test @MainActor func 別の選択行があっても操作した行の次へ入力先が進む() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", "a.txt", root)
        try write("changed\n", "b.txt", root)
        try write("new\n", "c.txt", root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        await model.select("a.txt")
        await model.stage(paths: ["b.txt"])
        #expect(model.gitSelection == .init(path: "c.txt", source: .worktree))
        #expect(model.stagedChanges.map(\.path) == ["b.txt"])
    }

    @Test @MainActor func 外部のステージと解除の後も更新で同じパスを選択し続ける() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", "a.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        let model = EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root))
        await model.refresh()
        await model.select("a.txt", source: .worktree)
        try await workflow.stage(paths: ["a.txt"])
        await model.refresh()
        #expect(model.gitSelection == .init(path: "a.txt", source: .staged))
        try await workflow.unstage(paths: ["a.txt"])
        await model.refresh()
        #expect(model.gitSelection == .init(path: "a.txt", source: .worktree))
    }

    @Test func ステージ失敗は引数とgitの理由を返しindexを変更しない() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let workflow = GitWorkflowService(repositoryRoot: root)
        let before = try git(["ls-files", "--stage"], root)
        do {
            try await workflow.stage(paths: ["missing.txt"])
            Issue.record("存在しないパスのステージが成功した")
        } catch let error as GitWorkflowError {
            guard case .commandFailed(let arguments, let output) = error else {
                Issue.record("失敗理由が保存されていない: \(error)")
                return
            }
            #expect(arguments == ["add", "-A", "--", ":(literal)missing.txt"])
            #expect(output.contains("missing.txt"))
            #expect(output.contains("pathspec"))
        }
        #expect(try git(["ls-files", "--stage"], root) == before)
    }

    @Test func 未ステージの改名は旧パスの削除も一緒にステージする() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.moveItem(at: root.appendingPathComponent("a.txt"),
                                         to: root.appendingPathComponent("renamed.txt"))
        // intent-to-add の新パスと旧パスの削除は、status が未ステージ改名として返す。
        try git(["add", "-N", "renamed.txt"], root)
        let reader = WorkingTreeService(repositoryRoot: root)
        let snapshot = try await reader.snapshot()
        #expect(snapshot.unstagedChanges.contains { $0.path == "renamed.txt" && $0.kind == .renamed })
        let workflow = GitWorkflowService(repositoryRoot: root)
        try await workflow.stage(paths: ["renamed.txt"])
        _ = try await workflow.commit(message: "rename")
        let paths = try git(["ls-tree", "-r", "--name-only", "HEAD"], root)
        #expect(paths.contains("renamed.txt"))
        #expect(!paths.contains("a.txt"))
        #expect(try git(["status", "--porcelain"], root).isEmpty)
    }

    @Test func バイナリ判定もステージと作業ツリーを分離する() async throws {
        let root = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("original\nstaged\n", "a.txt", root)
        let workflow = GitWorkflowService(repositoryRoot: root)
        try await workflow.stage(paths: ["a.txt"])
        try Data([0, 1, 2, 3]).write(to: root.appendingPathComponent("a.txt"))
        let reader = WorkingTreeService(repositoryRoot: root)
        let snapshot = try await reader.snapshot()
        #expect(snapshot.stagedChanges.first?.isBinary == false)
        #expect(snapshot.unstagedChanges.first?.isBinary == true)
        #expect(try await reader.detail(for: "a.txt", source: .worktree) == .binary)
        guard case .diff = try await reader.detail(for: "a.txt", source: .staged) else {
            Issue.record("ステージのテキスト差分が作業ツリーのバイナリで隠された")
            return
        }
    }
}
