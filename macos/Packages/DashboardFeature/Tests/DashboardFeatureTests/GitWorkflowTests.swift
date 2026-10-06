// GitWorkflowService: commit（選択パスだけの部分コミット）/ push / PR 作成。
// 実 git プロセスは必要最小限にし、時間予算テストを枯渇させない。
//
// 公開面: commit(paths:message:) -> String（SHA） / remoteNames() / push() / isGitHubCLIAvailable() /
// createPullRequest(title:body:) -> String。
// GitWorkflowError { notARepository, noPathsSelected, emptyCommitMessage, noRemoteConfigured,
//                    gitHubCLIUnavailable, commandFailed(arguments:output:) }

import Foundation
import Testing
@testable import DashboardFeature

@Suite("GitWorkflow", .timeLimit(.minutes(2)))
struct GitWorkflowTests {

    // MARK: - fixture harness

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-gitworkflow-\(UUID().uuidString)", isDirectory: true)
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

    /// a.txt / b.txt を含む初回コミット済みリポジトリ。リモートは設定しない。
    /// 署名・hooks・identity をリポジトリローカルで固定し、実行者の global config に依存させない。
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

    private func headSHA(_ root: URL) throws -> String {
        try git(["rev-parse", "HEAD"], cwd: root).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func porcelainStatus(_ root: URL) throws -> String {
        try git(["status", "--porcelain"], cwd: root)
    }


    private func configValue(_ key: String, in root: URL) throws -> String {
        try git(["config", "--get", key], cwd: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - commit の入力検証

    @Test func 空のコミットメッセージは拒否されコミットは作られない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)
        let before = try headSHA(root)

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.emptyCommitMessage) {
            _ = try await service.commit(paths: ["a.txt"], message: "")
        }
        #expect(try headSHA(root) == before)
    }

    @Test func 空白だけのコミットメッセージも拒否される() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.emptyCommitMessage) {
            _ = try await service.commit(paths: ["a.txt"], message: "   \n\t ")
        }
    }

    @Test func パス未選択は拒否されコミットは作られない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)
        let before = try headSHA(root)

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.noPathsSelected) {
            _ = try await service.commit(paths: [], message: "変更")
        }
        #expect(try headSHA(root) == before)
    }

    @Test func gitリポジトリでなければnotARepositoryを返す() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x\n", to: "a.txt", in: root)

        let service = GitWorkflowService(repositoryRoot: root)
        await #expect(throws: GitWorkflowError.notARepository) {
            _ = try await service.commit(paths: ["a.txt"], message: "変更")
        }
    }

    // MARK: - commit の正常系（部分コミット）

    @Test func 選択したファイルだけがコミットされ他の変更はツリーに残る() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a2\n", to: "a.txt", in: root)
        try write("b2\n", to: "b.txt", in: root)
        let before = try headSHA(root)

        let service = GitWorkflowService(repositoryRoot: root)
        let sha = try await service.commit(paths: ["a.txt"], message: "a だけ変更")

        #expect(!sha.isEmpty)
        #expect(try headSHA(root) != before)
        #expect(try headSHA(root).hasPrefix(sha) || sha.hasPrefix(headSHA(root)))

        // a.txt はコミット済み、b.txt は未コミットのまま残る。
        let status = try porcelainStatus(root)
        #expect(!status.contains("a.txt"), "a.txt がコミットされていない: \(status)")
        #expect(status.contains("b.txt"), "b.txt までコミットしてしまっている: \(status)")

        let logged = try git(["show", "--stat", "--format=%s", "HEAD"], cwd: root)
        #expect(logged.contains("a だけ変更"))
        #expect(logged.contains("a.txt"))
        #expect(!logged.contains("b.txt"))
    }

    /// ユーザーが外部（ターミナル）で `git mv` した状態＝ステージにリネームが載っている。
    /// 変更一覧はこれを新パス 1 件（kind=renamed）としてしか返さないため、新パスだけを
    /// pathspec にすると旧パスの削除が取り残され、HEAD にファイルが二重に残る。
    @Test func ステージ済みリネームを選んでコミットすると旧パスが残らない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["mv", "a.txt", "renamed.txt"], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["renamed.txt"], message: "a.txt を renamed.txt へ改名")

        let tree = try git(["ls-tree", "-r", "--name-only", "HEAD"], cwd: root)
        #expect(tree.contains("renamed.txt"), "新パスがコミットされていない: \(tree)")
        #expect(!tree.contains("a.txt"), "旧パスが HEAD に残り二重になっている: \(tree)")

        let status = try porcelainStatus(root)
        #expect(!status.contains("a.txt"), "旧パスの削除がステージに取り残されている: \(status)")

        // 選択していない b.txt には触れない。
        #expect(tree.contains("b.txt"), "無関係な b.txt が失われている: \(tree)")
    }

    /// 既定の `git status --porcelain` はパスに空白・非 ASCII があると引用と C エスケープが掛かる。
    /// 旧パスの解決がそれを考慮していないと、ASCII 名だけ直って特殊文字名で二重に残る。
    @Test func 空白と日本語を含むステージ済みリネームでも旧パスが残らない() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("s\n", to: "sp ace.txt", in: root)
        try write("j\n", to: "日本語.txt", in: root)
        try git(["add", "--", "sp ace.txt", "日本語.txt"], cwd: root)
        try git(["commit", "-m", "add special"], cwd: root)
        try git(["mv", "sp ace.txt", "sp ace2.txt"], cwd: root)
        try git(["mv", "日本語.txt", "日本語2.txt"], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["sp ace2.txt", "日本語2.txt"], message: "特殊文字の改名")

        // ls-tree は既定でパスを引用するので -z で生パスを取る（比較を引用規則に依存させない）。
        let treeRaw = try git(["ls-tree", "-r", "--name-only", "-z", "HEAD"], cwd: root)
        let tracked = Set(treeRaw.split(separator: "\0").map(String.init))
        #expect(tracked.contains("sp ace2.txt"), "空白入りの新パスがコミットされていない: \(tracked)")
        #expect(tracked.contains("日本語2.txt"), "日本語の新パスがコミットされていない: \(tracked)")
        #expect(!tracked.contains("sp ace.txt"), "空白入りの旧パスが HEAD に残っている: \(tracked)")
        #expect(!tracked.contains("日本語.txt"), "日本語の旧パスが HEAD に残っている: \(tracked)")

        let status = try porcelainStatus(root)
        #expect(status.isEmpty, "旧パスの削除がステージに取り残されている: \(status)")
    }

    // MARK: - push

    @Test func リモート未設定ならpushはnoRemoteConfiguredを返す() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GitWorkflowService(repositoryRoot: root)
        #expect(await service.remoteNames().isEmpty)
        await #expect(throws: GitWorkflowError.noRemoteConfigured) {
            try await service.push()
        }
    }

    @Test func リモートを設定すると一覧に現れる() async throws {
        let root = try makeBaseRepo()
        let remote = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: remote)
        }
        try git(["init", "--bare"], cwd: remote)
        try git(["remote", "add", "origin", remote.path], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        #expect(await service.remoteNames() == ["origin"])
    }

    @Test func リモートがあればpushが成功しリモートにコミットが載る() async throws {
        let root = try makeBaseRepo()
        let remote = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: remote)
        }
        try git(["init", "--bare"], cwd: remote)
        try git(["remote", "add", "origin", remote.path], cwd: root)

        let service = GitWorkflowService(repositoryRoot: root)
        try await service.push()

        let remoteLog = try git(["log", "--format=%s", "-1", "main"], cwd: remote)
        #expect(remoteLog.contains("initial"))
    }

    // MARK: - PR 作成（gh 不在時は明示エラー）

    @Test func gh不在ならPR作成はgitHubCLIUnavailableを返す() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        // 存在しないパスを注入して「gh が無い」状態を決定的に再現する。
        let service = GitWorkflowService(
            repositoryRoot: root,
            gitHubCLIPath: "/nonexistent/bin/gh-\(UUID().uuidString)"
        )
        #expect(await service.isGitHubCLIAvailable() == false)
        await #expect(throws: GitWorkflowError.gitHubCLIUnavailable) {
            _ = try await service.createPullRequest(title: "t", body: "b")
        }
    }

    // MARK: - commit の特殊パス・失敗時の後始末・他ステージの保全

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

    // 失敗した git コマンドの出力を握りつぶさず、実行引数と原因（pathspec 不一致）をエラーに含める。
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
