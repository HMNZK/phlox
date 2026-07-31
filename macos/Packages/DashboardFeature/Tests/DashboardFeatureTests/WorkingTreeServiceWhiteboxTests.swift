import Foundation
import Testing
@testable import DashboardFeature

@Suite("WorkingTreeService white-box (task-2)")
struct WorkingTreeServiceWhiteboxTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-working-tree-whitebox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=phlox-test", "-c", "user.email=test@phlox.local"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        try #require(process.terminationStatus == 0)
        return data
    }

    private func repository() throws -> URL {
        let root = try temporaryDirectory()
        try git(["init", "-q"], in: root)
        try "before\n".write(to: root.appendingPathComponent("before.txt"), atomically: true, encoding: .utf8)
        try git(["add", "before.txt"], in: root)
        try git(["commit", "-q", "-m", "base"], in: root)
        return root
    }

    @Test("-z porcelain のリネームは新しいパス1件として扱う")
    func changesUsesDestinationPathForRename() async throws {
        let root = try repository()
        try git(["mv", "before.txt", "after name 日本語.txt"], in: root)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()

        #expect(changes == [
            WorkingTreeChange(path: "after name 日本語.txt", kind: .renamed, isBinary: false),
        ])
    }

    @Test("非ASCIIとスペースを含む未追跡パスを壊さず扱う")
    func changesPreservesSpecialUntrackedPath() async throws {
        let root = try repository()
        try "contents\n".write(
            to: root.appendingPathComponent("space 日本語.txt"), atomically: true, encoding: .utf8)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()

        #expect(changes == [
            WorkingTreeChange(path: "space 日本語.txt", kind: .untracked, isBinary: false),
        ])
    }

    @Test("追跡済みバイナリ変更を一覧と詳細の両方でバイナリとして扱う")
    func detectsTrackedBinaryChanges() async throws {
        let root = try repository()
        try Data([0, 1, 2, 255]).write(to: root.appendingPathComponent("before.txt"))
        let service = WorkingTreeService(repositoryRoot: root)

        let changes = try await service.changes()
        let detail = try await service.detail(for: "before.txt")

        #expect(changes == [
            WorkingTreeChange(path: "before.txt", kind: .modified, isBinary: true),
        ])
        #expect(detail == .binary)
    }

    @Test("変更されていない追跡済みバイナリも detail でバイナリとして扱う")
    func detailForUnchangedTrackedBinaryIsBinary() async throws {
        let root = try repository()
        try Data([0, 1, 2, 255]).write(to: root.appendingPathComponent("binary.dat"))
        try git(["add", "binary.dat"], in: root)
        try git(["commit", "-q", "-m", "add binary fixture"], in: root)

        let detail = try await WorkingTreeService(repositoryRoot: root).detail(for: "binary.dat")

        #expect(detail == .binary)
    }

    @Test("ネストした git リポジトリのディレクトリは一覧から除外する")
    func changesExcludesNestedRepositoryDirectory() async throws {
        let root = try repository()
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try git(["init", "-q"], in: nested)
        try "x\n".write(to: nested.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()

        #expect(!changes.contains { $0.path == "nested/" })
        for change in changes {
            _ = try await WorkingTreeService(repositoryRoot: root).detail(for: change.path)
        }
    }

    @Test("git rm --cached 後のパスは未追跡として1件だけ出る")
    func changesDeduplicatesPathsAfterRemoveCached() async throws {
        let root = try repository()
        try git(["rm", "-q", "--cached", "before.txt"], in: root)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()

        #expect(changes == [
            WorkingTreeChange(path: "before.txt", kind: .untracked, isBinary: false),
        ])
    }

    @Test("git rm --cached 後の未追跡ファイルは実内容を detail で返す")
    func detailForRemoveCachedFileReturnsUntrackedContent() async throws {
        let root = try repository()
        try git(["rm", "-q", "--cached", "before.txt"], in: root)
        let service = WorkingTreeService(repositoryRoot: root)

        #expect(try await service.changes() == [
            WorkingTreeChange(path: "before.txt", kind: .untracked, isBinary: false),
        ])
        #expect(try await service.detail(for: "before.txt") == .untrackedContent("before\n"))
    }

    @Test("読み取り操作は git の意味論的状態を変えない")
    func readOperationsPreserveSemanticGitState() async throws {
        let root = try repository()
        try "after\n".write(to: root.appendingPathComponent("before.txt"), atomically: true, encoding: .utf8)
        let statusArguments = ["status", "--porcelain=v1"]
        let statusBefore = try git(statusArguments, in: root)
        let treeBefore = try git(["write-tree"], in: root)
        let service = WorkingTreeService(repositoryRoot: root)

        for _ in 0..<3 {
            _ = try await service.changes()
            _ = try await service.detail(for: "before.txt")
        }

        #expect(try git(statusArguments, in: root) == statusBefore)
        #expect(try git(["write-tree"], in: root) == treeBefore)
    }

    @Test("save はシンボリックリンクを置き換えずリンク先を更新する")
    func savePreservesSymbolicLink() async throws {
        let root = try repository()
        let target = root.appendingPathComponent("target.txt")
        let link = root.appendingPathComponent("link.txt")
        try "before\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        let outcome = try await WorkingTreeService(repositoryRoot: root)
            .save(path: "link.txt", content: "after\n", expectedDiskContent: "before\n")

        #expect(outcome == .saved)
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "after\n")
    }

    @Test("git の warning が混ざっても変更一覧を壊さない")
    func changesIgnoresGitWarnings() async throws {
        let root = try repository()
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try "x\n".write(to: blocked.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path)
        }
        try "z\n".write(to: root.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)

        let changes = try await WorkingTreeService(repositoryRoot: root).changes()

        #expect(changes.contains { $0.path == "z.txt" && $0.kind == .untracked })
        #expect(changes.allSatisfy { !$0.path.contains("warning:") })
    }

    @Test("大量の git stderr があっても changes は完了する", .timeLimit(.minutes(1)))
    func changesSurvivesHugeStderr() async throws {
        let root = try repository()
        let deep = root.appendingPathComponent("deep", isDirectory: true)

        for index in 0..<1_500 {
            let directory = deep.appendingPathComponent("d\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "x\n".write(
                to: directory.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        }
        defer {
            for index in 0..<1_500 {
                let path = deep.appendingPathComponent("d\(index)").path
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }

        _ = try await WorkingTreeService(repositoryRoot: root).changes()
    }

    @Test("git rm で staged 削除されたファイルの detail は diff として取れる")
    func detailForStagedDeletion() async throws {
        let root = try repository()
        try git(["rm", "-q", "before.txt"], in: root)
        let service = WorkingTreeService(repositoryRoot: root)

        #expect(try await service.changes() == [
            WorkingTreeChange(path: "before.txt", kind: .deleted, isBinary: false),
        ])
        guard case .diff(let text) = try await service.detail(for: "before.txt") else {
            Issue.record("staged 削除の detail は .diff であるべき")
            return
        }
        #expect(text.contains("-before"))
    }

    @Test("リポジトリのサブディレクトリを基点にしてもルート相対パスで扱う")
    func supportsRepositorySubdirectory() async throws {
        let root = try repository()
        let subdirectory = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try "before-sub\n".write(to: subdirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "sub/a.txt"], in: root)
        try git(["commit", "-q", "-m", "add subdirectory fixture"], in: root)
        try "after-sub\n".write(to: subdirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let service = WorkingTreeService(repositoryRoot: subdirectory)
        let changes = try await service.changes()
        let detail = try await service.detail(for: "sub/a.txt")

        #expect(changes == [
            WorkingTreeChange(path: "sub/a.txt", kind: .modified, isBinary: false),
        ])
        guard case .diff(let text) = detail else {
            Issue.record("サブディレクトリ基点の追跡ファイルは .diff であるべき")
            return
        }
        #expect(text.contains("-before-sub"))
        #expect(text.contains("+after-sub"))
    }

    @Test("外部で削除されたファイルへの save は throw せず .conflict")
    func saveReturnsConflictWhenFileVanished() async throws {
        let root = try repository()
        try FileManager.default.removeItem(at: root.appendingPathComponent("before.txt"))

        let outcome = try await WorkingTreeService(repositoryRoot: root)
            .save(path: "before.txt", content: "mine\n", expectedDiskContent: "before\n")

        #expect(outcome == .conflict)
    }
}
