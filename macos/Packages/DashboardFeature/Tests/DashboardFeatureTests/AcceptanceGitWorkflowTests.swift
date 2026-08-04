// 契約の正本: tasks/task-4.md — commit / push / PR 作成。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// ゲート①決定: ADR 0150 は stage/commit/push をスコープ外としていたが、これを覆す新 ADR を
// 起こしたうえで実装する（decision-log.md 参照）。merge と衝突解消 UI はスコープ外のまま。
//
// 凍結する公開面:
// - GitWorkflowService(repositoryRoot:gitHubCLIPath:)
// - commit(paths:message:) -> String（SHA） / remoteNames() / push()
//   / isGitHubCLIAvailable() / createPullRequest(title:body:) -> String
// - GitWorkflowError { notARepository, noPathsSelected, emptyCommitMessage,
//                      noRemoteConfigured, gitHubCLIUnavailable, commandFailed(arguments:output:) }

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: git ワークフロー（task-4）", .timeLimit(.minutes(2)))
struct AcceptanceGitWorkflowTests {

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

    @Test func 新規ファイルもパス指定でコミットできる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("new\n", to: "c.txt", in: root)

        let service = GitWorkflowService(repositoryRoot: root)
        _ = try await service.commit(paths: ["c.txt"], message: "c を追加")

        let tracked = try git(["ls-files"], cwd: root)
        #expect(tracked.contains("c.txt"))
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

    // MARK: - 失敗出力を握りつぶさない

    @Test func 失敗したgitコマンドの出力がエラーに含まれる() async throws {
        let root = try makeBaseRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GitWorkflowService(repositoryRoot: root)
        var captured: GitWorkflowError?
        do {
            _ = try await service.commit(paths: ["does-not-exist.txt"], message: "存在しないパス")
        } catch let error as GitWorkflowError {
            captured = error
        }
        guard case let .commandFailed(arguments, output) = captured else {
            Issue.record("期待は .commandFailed だが \(String(describing: captured)) だった")
            return
        }
        #expect(!arguments.isEmpty, "実行した git 引数が保持されていない")
        #expect(!output.isEmpty, "git の失敗出力が握りつぶされている")
        #expect(output.contains("does-not-exist.txt"), "失敗出力が原因を含まない: \(output)")
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
}
