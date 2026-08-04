// GitWorkflowService / 部分コミットの白箱テスト（task-4）。
// 実 git プロセスは必要最小限にし、時間予算テストを枯渇させない。

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("GitWorkflow white-box (task-4)", .timeLimit(.minutes(1)))
struct GitWorkflowWhiteboxTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-gitworkflow-wb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ args: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(process.terminationStatus == 0, "git \(args.joined(separator: " ")) failed: \(text)")
        return text
    }

    private func write(_ content: String, to name: String, in root: URL) throws {
        try content.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func makeBaseRepo() throws -> URL {
        let root = try makeTempDir()
        try git(["init", "--initial-branch=main"], cwd: root)
        try git(["config", "user.name", "phlox-test"], cwd: root)
        try git(["config", "user.email", "test@phlox.local"], cwd: root)
        try git(["config", "commit.gpgsign", "false"], cwd: root)
        try git(["config", "core.hooksPath", "/dev/null"], cwd: root)
        try write("a1\n", to: "a.txt", in: root)
        try write("b1\n", to: "b.txt", in: root)
        try git(["add", "."], cwd: root)
        try git(["commit", "-m", "initial"], cwd: root)
        return root
    }

    private func configValue(_ key: String, in root: URL) throws -> String {
        try git(["config", "--get", key], cwd: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func 他パスのステージ済み変更を巻き込まず選択パスだけコミットする() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)
        try write("b2\n", to: "b.txt", in: root)
        try git(["add", "b.txt"], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["a.txt"], message: "a only")

        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("a only"))
        #expect(head.contains("a.txt"))
        #expect(!head.contains("b.txt"), "ステージ済み b.txt までコミットしてしまった: \(head)")

        let status = try git(["status", "--porcelain"], cwd: root)
        #expect(status.contains("b.txt"), "b.txt のステージが消えている: \(status)")
        #expect(!status.contains("a.txt"))
    }

    @Test func 失敗出力にpathspec不一致の原因文字列が入る() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GitWorkflowService(repositoryRoot: root)
        var captured: GitWorkflowError?
        do {
            _ = try await service.commit(paths: ["missing-file.txt"], message: "nope")
        } catch let error as GitWorkflowError {
            captured = error
        }
        guard case let .commandFailed(arguments, output) = captured else {
            Issue.record("expected commandFailed, got \(String(describing: captured))")
            return
        }
        #expect(arguments.contains("missing-file.txt") || arguments.contains(where: { $0.contains("missing-file") }))
        #expect(
            output.localizedCaseInsensitiveContains("pathspec")
                || output.localizedCaseInsensitiveContains("did not match"),
            "原因を示す文字列が無い: \(output)"
        )
        #expect(output.contains("missing-file.txt"))
    }

    @Test func スペースと日本語とダッシュ始まりのパスをコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("s1\n", to: "file with space.txt", in: root)
        try write("j1\n", to: "日本語.txt", in: root)
        try write("d1\n", to: "--dashed.txt", in: root)
        try git(["add", "--", "file with space.txt", "日本語.txt", "--dashed.txt"], cwd: root)
        try git(["commit", "-m", "add special"], cwd: root)

        try write("s2\n", to: "file with space.txt", in: root)
        try write("j2\n", to: "日本語.txt", in: root)
        try write("d2\n", to: "--dashed.txt", in: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(
            paths: ["file with space.txt", "日本語.txt", "--dashed.txt"],
            message: "special paths"
        )

        // `git show` は非 ASCII を C-quote するため、quotepath を切って名前を読む。
        let head = try git(
            ["-c", "core.quotepath=false", "show", "--name-only", "--format=%s", "HEAD"],
            cwd: root
        )
        #expect(head.contains("special paths"))
        #expect(head.contains("file with space.txt"))
        #expect(head.contains("日本語.txt"))
        #expect(head.contains("--dashed.txt"))
    }

    @Test func 削除済みファイルをパス指定でコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.txt"))

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["a.txt"], message: "remove a")

        let tracked = try git(["ls-files"], cwd: root)
        #expect(!tracked.split(whereSeparator: \.isNewline).map(String.init).contains("a.txt"))
        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("remove a"))
        #expect(head.contains("a.txt"))
    }

    @Test func ステージ済み削除のパスをコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["rm", "-q", "a.txt"], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["a.txt"], message: "remove staged")

        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("remove staged"))
        #expect(head.contains("a.txt"))
        let status = try git(["status", "--porcelain"], cwd: root)
        #expect(!status.contains("a.txt"), "削除が残っている: \(status)")
    }

    @Test func サブディレクトリをrepositoryRootにしてもトップレベル相対パスでコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write("a2\n", to: "a.txt", in: root)

        let service = GitWorkflowService(repositoryRoot: sub)
        _ = try await service.commit(paths: ["a.txt"], message: "from subdir")

        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("from subdir"))
        #expect(head.contains("a.txt"))
    }

    @Test func 製品コードはgit_identity設定を上書きしない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let beforeName = try configValue("user.name", in: root)
        let beforeEmail = try configValue("user.email", in: root)
        let beforeSign = try configValue("commit.gpgsign", in: root)
        let beforeHooks = try configValue("core.hooksPath", in: root)

        try write("a2\n", to: "a.txt", in: root)
        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["a.txt"], message: "touch")

        #expect(try configValue("user.name", in: root) == beforeName)
        #expect(try configValue("user.email", in: root) == beforeEmail)
        #expect(try configValue("commit.gpgsign", in: root) == beforeSign)
        #expect(try configValue("core.hooksPath", in: root) == beforeHooks)
    }

    @Test func グロブメタ文字を含むパスは同名グロブに一致する他ファイルを巻き込まない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x1\n", to: "test1.txt", in: root)
        try write("y1\n", to: "test[1].txt", in: root)
        try git(["add", "--", "test1.txt", ":(literal)test[1].txt"], cwd: root)
        try git(["commit", "-m", "add glob-ish"], cwd: root)

        try write("x2\n", to: "test1.txt", in: root) // 選択しない
        try write("y2\n", to: "test[1].txt", in: root) // これだけ選ぶ

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["test[1].txt"], message: "only bracket")

        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("only bracket"))
        #expect(head.contains("test[1].txt"))
        #expect(!head.contains("\ntest1.txt"), "選択していない test1.txt を巻き込んだ: \(head)")
        let status = try git(["status", "--porcelain"], cwd: root)
        #expect(status.contains("test1.txt"), "test1.txt の変更がツリーに残っていない: \(status)")
        #expect(!status.contains("test[1].txt"))
    }

    @Test func コロン始まりのパスもコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("c\n", to: ":colon.txt", in: root)
        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: [":colon.txt"], message: "colon")
        let tracked = try git(["ls-files"], cwd: root)
        #expect(tracked.contains(":colon.txt"))
    }

    @Test func コミットが失敗しても選択パスのステージ状態を元に戻す() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        // makeBaseRepo は hooksPath=/dev/null。実際の hooks を効かせる。
        try git(["config", "--unset", "core.hooksPath"], cwd: root)
        try write("a2\n", to: "a.txt", in: root)
        try write("b2\n", to: "b.txt", in: root)
        let before = try git(["status", "--porcelain"], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: (any Error).self) {
            _ = try await service.commit(paths: ["a.txt"], message: "rejected")
        }
        let after = try git(["status", "--porcelain"], cwd: root)
        #expect(after == before, "失敗後に index が変わっている: before=\(before) after=\(after)")
    }

    @Test func 未追跡パスのコミット失敗後は未追跡のまま戻る() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try git(["config", "--unset", "core.hooksPath"], cwd: root)
        try write("new\n", to: "new.txt", in: root)
        let before = try git(["status", "--porcelain"], cwd: root)
        #expect(before.contains("?? new.txt"))

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: (any Error).self) {
            _ = try await service.commit(paths: ["new.txt"], message: "rejected new")
        }
        let after = try git(["status", "--porcelain"], cwd: root)
        #expect(after == before, "未追跡の add が残っている: before=\(before) after=\(after)")
        #expect(after.contains("?? new.txt"))
    }

    @Test func 空文字列のパスは全ファイルコミットに化けない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)
        try write("b2\n", to: "b.txt", in: root)
        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.noPathsSelected) {
            _ = try await service.commit(paths: [""], message: "empty pathspec")
        }
        await #expect(throws: GitWorkflowError.noPathsSelected) {
            _ = try await service.commit(paths: ["  "], message: "whitespace pathspec")
        }
        let status = try git(["status", "--porcelain"], cwd: root)
        #expect(status.contains("a.txt") && status.contains("b.txt"), "全ファイルを巻き込んだ: \(status)")
        let head = try git(["log", "-1", "--format=%s"], cwd: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(head == "initial", "空パスでコミットが作られた: \(head)")
    }

    @Test func 壊れたsymlinkもコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("link").path,
            withDestinationPath: "/nonexistent/target"
        )

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["link"], message: "add symlink")

        let head = try git(["show", "--name-only", "--format=%s", "HEAD"], cwd: root)
        #expect(head.contains("add symlink"))
        #expect(head.contains("link"))
    }

    /// 「実在しない（ENOENT）」と「実在するか判定できない（権限不足・親が非ディレクトリ等）」を
    /// 区別する。後者を握りつぶすと、原因が git の pathspec 不一致に化けてユーザーに伝わらない。
    /// `a.txt` は通常ファイルなので `a.txt/child.txt` の stat は ENOTDIR で失敗する
    /// （実測: CocoaError 256 = fileReadUnknown。ENOENT の 260 とは別）。
    @Test func 実在を判定できないパスは握りつぶさず失敗理由を伝える() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GitWorkflowService(repositoryRoot: root)
        var thrown: Error?
        do {
            _ = try await service.commit(paths: ["a.txt/child.txt"], message: "should not commit")
        } catch {
            thrown = error
        }

        let error = try #require(thrown, "実在を判定できないパスなのにコミットが成功した")
        #expect(
            error is CocoaError,
            "実在判定の失敗理由が握りつぶされ、別の失敗に化けている: \(error)"
        )
    }

    @Test func remoteNames失敗時は失敗理由を保持し未設定と区別できる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitWorkflowService(repositoryRoot: root)

        let emptyRemotes = await service.remoteNames()
        #expect(emptyRemotes.isEmpty)
        #expect(await service.remoteLookupFailureReason() == nil)

        // workingTreeRoot をキャッシュさせたあと .git を壊し、git remote 自体を失敗させる。
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        let failed = await service.remoteNames()
        #expect(failed.isEmpty)
        let reason = await service.remoteLookupFailureReason()
        #expect(reason != nil)
        #expect(reason?.contains("失敗") == true)
    }
}

@Suite("EditorPanel git commit UI white-box (task-4)")
@MainActor
struct EditorPanelGitCommitUIWhiteboxTests {
    @Test func リモート未設定とgh不在の理由がVMに出る() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-git-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--initial-branch=main"]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()

        let workflow = GitWorkflowService(
            repositoryRoot: root,
            gitHubCLIPath: "/nonexistent/bin/gh-\(UUID().uuidString)"
        )
        let viewModel = EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: workflow
        )
        await viewModel.refresh()

        #expect(viewModel.pushAvailabilityReason != nil)
        #expect(viewModel.pushAvailabilityReason?.contains("リモート") == true)
        #expect(!viewModel.canPush)
        #expect(viewModel.pullRequestAvailabilityReason != nil)
        #expect(viewModel.pullRequestAvailabilityReason?.contains("gh") == true)
        #expect(!viewModel.canCreatePullRequest)
    }

    @Test func commit成功後のCreatePRは直近コミットsubjectをタイトルにする() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-pr-title-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = root
            var env = ProcessInfo.processInfo.environment
            env["GIT_CONFIG_NOSYSTEM"] = "1"
            process.environment = env
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
        }

        try git(["init", "--initial-branch=main"])
        try git(["config", "user.name", "phlox-test"])
        try git(["config", "user.email", "test@phlox.local"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["config", "core.hooksPath", "/dev/null"])
        try "a1\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "a.txt"])
        try git(["commit", "-m", "initial"])

        let fakeGh = root.appendingPathComponent("fake-gh")
        try """
        #!/bin/sh
        while [ $# -gt 0 ]; do
          if [ "$1" = "--title" ]; then
            shift
            printf '%s' "$1" > "$(dirname "$0")/gh-title.txt"
          else
            shift
          fi
        done
        echo "https://example.com/pr/1"
        """.write(to: fakeGh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGh.path)

        try "a2\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let workflow = GitWorkflowService(repositoryRoot: root, gitHubCLIPath: fakeGh.path)
        let viewModel = EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: workflow
        )
        await viewModel.refresh()
        viewModel.toggleCommitSelection(for: "a.txt")
        viewModel.commitMessage = "feat: only-this-title"
        await viewModel.commitSelectedPaths()
        #expect(viewModel.commitMessage.isEmpty)
        #expect(viewModel.workflowStatusIsError == false)
        #expect(viewModel.canCreatePullRequest)

        await viewModel.createPullRequest()
        let titlePath = root.appendingPathComponent("gh-title.txt")
        let title = try String(contentsOf: titlePath, encoding: .utf8)
        #expect(title == "feat: only-this-title")
        #expect(title != "Update")
    }

    /// `GitCommitPanel` の実測固有高が stacked 予算内に収まることを固定する。
    @Test func stackedのコミットパネルは予算内に収まる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let withoutStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        viewModel.presentWorkflowError("git commit failed: hook rejected")
        let withStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        #expect(
            withStatus >= withoutStatus + 40,
            "状態表示ブロックが無い／潰れている: without=\(withoutStatus) with=\(withStatus)"
        )
        #expect(
            withStatus <= EditorPanelLayout.stackedCommitPanelBudget,
            "パネル実測 \(withStatus) が予算 \(EditorPanelLayout.stackedCommitPanelBudget) を超える"
        )
    }

    /// 26 行の git 失敗出力でも、有界化によりパネル固有高が stacked 予算を超えない（回帰止め）。
    @Test func 長いgit失敗出力でもコミットパネルはstacked予算を超えない() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let withoutStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        let longOutput = (1...26).map { "hook: lint failed on file_\($0).swift" }.joined(separator: "\n")
        viewModel.presentWorkflowError("git commit -m x -- a.txt failed:\n\(longOutput)")

        let measured = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        let budget = EditorPanelLayout.stackedCommitPanelBudget
        #expect(
            measured >= withoutStatus + 40,
            "長い失敗出力でも状態表示ブロックが無い: without=\(withoutStatus) with=\(measured)"
        )
        #expect(
            measured <= budget,
            "失敗表示でパネルが stacked 予算を超え、ボタンが押し出される: \(measured) > \(budget)"
        )
        #expect(viewModel.workflowStatusMessage != nil)

        viewModel.dismissWorkflowStatus()
        #expect(viewModel.workflowStatusMessage == nil)
        #expect(viewModel.workflowStatusIsError == false)
    }

    /// 狭い split 列幅では ViewThatFits が縦積みへ落ち、高さが広幅より有意に増える。
    @Test func 狭い列幅でもコミットパネルのアクションは収まる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let narrow = measureCommitPanelSize(viewModel: viewModel, width: 180)
        let wide = measureCommitPanelSize(viewModel: viewModel, width: 388)
        #expect(
            narrow.height > wide.height + 30,
            "狭い列で ViewThatFits が縦積みへ落ちていない: narrow=\(narrow.height) wide=\(wide.height)"
        )
    }

    @MainActor
    private func measureCommitPanelHeight(viewModel: EditorPanelViewModel, width: CGFloat) -> CGFloat {
        measureCommitPanelSize(viewModel: viewModel, width: width).height
    }

    @MainActor
    private func measureCommitPanelSize(
        viewModel: EditorPanelViewModel,
        width: CGFloat
    ) -> CGSize {
        let root = GitCommitPanel(viewModel: viewModel)
            .frame(width: width)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 4000)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
}
