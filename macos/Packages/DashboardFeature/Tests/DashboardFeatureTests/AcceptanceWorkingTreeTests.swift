// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — git ワーキングツリーの読み書きサービス。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面:
// - WorkingTreeChange { path, kind(modified/added/deleted/untracked/renamed), isBinary }
// - WorkingTreeDetail { diff(String), untrackedContent(String), binary }
// - WorkingTreeSaveOutcome { saved, conflict }
// - WorkingTreeService(repositoryRoot:) / isGitRepository() / changes() / detail(for:)
//   / fileContents(_:) / save(path:content:expectedDiskContent:)
//
// ゲート①決定: 変更一覧は staged / 未ステージを区別せず「HEAD からの変更」に一本化する。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Working tree acceptance (task-2)", .timeLimit(.minutes(1)))
struct AcceptanceWorkingTreeTests {

    // MARK: - fixture harness

    /// 一時ディレクトリに fixture リポジトリを作る。git はシステムの /usr/bin/git を使う。
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-worktree-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ args: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // ユーザー設定・システム設定に依存しない決定的な実行。
        process.arguments = ["-c", "user.name=phlox-test", "-c", "user.email=test@phlox.local",
                             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        try #require(process.terminationStatus == 0, "git \(args.joined(separator: " ")) failed: \(text)")
        return text
    }

    private func write(_ content: String, to name: String, in root: URL) throws {
        try content.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// 基本 fixture: 初回コミットに a.txt / b.txt / d.txt を含むリポジトリ。
    private func makeBaseRepo() throws -> URL {
        let root = try makeTempDir()
        try git(["init", "-q"], cwd: root)
        try write("old-a\n", to: "a.txt", in: root)
        try write("old-b\n", to: "b.txt", in: root)
        try write("old-d\n", to: "d.txt", in: root)
        try git(["add", "."], cwd: root)
        try git(["commit", "-q", "-m", "base"], cwd: root)
        return root
    }

    /// 標準の変更セットを適用する:
    /// a.txt=未ステージ変更 / b.txt=ステージ済み変更 / c.txt=未追跡 /
    /// d.txt=削除 / f.txt=ステージ済み新規 / bin.dat=未追跡バイナリ
    private func applyStandardChanges(to root: URL) throws {
        try write("new-a\n", to: "a.txt", in: root)
        try write("new-b\n", to: "b.txt", in: root)
        try git(["add", "b.txt"], cwd: root)
        try write("hello-c\n", to: "c.txt", in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("d.txt"))
        try write("new-f\n", to: "f.txt", in: root)
        try git(["add", "f.txt"], cwd: root)
        let binary = Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x10])
        try binary.write(to: root.appendingPathComponent("bin.dat"))
    }

    // MARK: - acceptance

    @Test("git リポジトリの判定")
    func detectsRepository() async throws {
        let repo = try makeBaseRepo()
        let plain = try makeTempDir()
        #expect(await WorkingTreeService(repositoryRoot: repo).isGitRepository() == true)
        #expect(await WorkingTreeService(repositoryRoot: plain).isGitRepository() == false)
    }

    @Test("非リポジトリで changes() は throw する")
    func changesThrowsOutsideRepository() async throws {
        let plain = try makeTempDir()
        let service = WorkingTreeService(repositoryRoot: plain)
        await #expect(throws: (any Error).self) {
            _ = try await service.changes()
        }
    }

    @Test("changes(): staged / 未ステージを区別せず HEAD からの変更＋未追跡を昇順で返す")
    func changesMergesStagedAndUnstaged() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()
        let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) })

        #expect(changes.map(\.path) == changes.map(\.path).sorted())
        #expect(byPath["a.txt"]?.kind == .modified)          // 未ステージ変更
        #expect(byPath["b.txt"]?.kind == .modified)          // ステージ済み変更（区別しない）
        #expect(byPath["c.txt"]?.kind == .untracked)
        #expect(byPath["d.txt"]?.kind == .deleted)
        #expect(byPath["f.txt"]?.kind == .added)             // ステージ済み新規
        #expect(byPath["bin.dat"]?.kind == .untracked)
        #expect(byPath["bin.dat"]?.isBinary == true)
        #expect(byPath["c.txt"]?.isBinary == false)
        #expect(changes.count == 6)
    }

    @Test("detail: 追跡ファイルは HEAD からの unified diff")
    func detailForTrackedFileIsDiff() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)

        let detail = try await WorkingTreeService(repositoryRoot: root).detail(for: "a.txt")
        guard case .diff(let text) = detail else {
            Issue.record("a.txt の detail は .diff であるべきだが \(detail) だった")
            return
        }
        #expect(text.contains("-old-a"))
        #expect(text.contains("+new-a"))
    }

    @Test("detail: ステージ済み変更も HEAD からの diff として見える")
    func detailForStagedFileIsDiffAgainstHEAD() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)

        let detail = try await WorkingTreeService(repositoryRoot: root).detail(for: "b.txt")
        guard case .diff(let text) = detail else {
            Issue.record("b.txt の detail は .diff であるべきだが \(detail) だった")
            return
        }
        #expect(text.contains("-old-b"))
        #expect(text.contains("+new-b"))
    }

    @Test("detail: 未追跡テキストは全文、未追跡バイナリは .binary")
    func detailForUntrackedFiles() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)
        let service = WorkingTreeService(repositoryRoot: root)

        let text = try await service.detail(for: "c.txt")
        #expect(text == .untrackedContent("hello-c\n"))

        let binary = try await service.detail(for: "bin.dat")
        #expect(binary == .binary)
    }

    @Test("save: ディスク内容が期待どおりなら書き込む")
    func saveWritesWhenExpectationMatches() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)
        let service = WorkingTreeService(repositoryRoot: root)

        let current = try await service.fileContents("a.txt")
        #expect(current == "new-a\n")

        let outcome = try await service.save(
            path: "a.txt", content: "edited-a\n", expectedDiskContent: "new-a\n")
        #expect(outcome == .saved)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(onDisk == "edited-a\n")
    }

    @Test("save: ディスクが外部に変えられていたら書き込まず .conflict を返す")
    func saveDetectsConflictAndDoesNotWrite() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)
        let service = WorkingTreeService(repositoryRoot: root)

        let outcome = try await service.save(
            path: "a.txt", content: "mine\n", expectedDiskContent: "stale-snapshot\n")
        #expect(outcome == .conflict)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(onDisk == "new-a\n")
    }

    @Test("save: expectedDiskContent が nil なら無条件で上書きする")
    func saveWithNilExpectationForcesOverwrite() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)
        let service = WorkingTreeService(repositoryRoot: root)

        let outcome = try await service.save(
            path: "a.txt", content: "forced\n", expectedDiskContent: nil)
        #expect(outcome == .saved)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(onDisk == "forced\n")
    }

    @Test("読み取り操作は index / ワーキングツリーを変更しない")
    func readOperationsDoNotMutateRepository() async throws {
        let root = try makeBaseRepo()
        try applyStandardChanges(to: root)
        let before = try git(["status", "--porcelain"], cwd: root)

        let service = WorkingTreeService(repositoryRoot: root)
        _ = try await service.changes()
        _ = try await service.detail(for: "a.txt")
        _ = try await service.detail(for: "c.txt")
        _ = try await service.fileContents("a.txt")

        let after = try git(["status", "--porcelain"], cwd: root)
        #expect(before == after)
    }

    @Test("HEAD の無い空リポジトリでも未追跡ファイルを列挙できる")
    func emptyRepositoryListsUntracked() async throws {
        let root = try makeTempDir()
        try git(["init", "-q"], cwd: root)
        try write("first\n", to: "new.txt", in: root)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()
        #expect(changes.count == 1)
        #expect(changes.first?.path == "new.txt")
        #expect(changes.first?.kind == .untracked)
    }
}
