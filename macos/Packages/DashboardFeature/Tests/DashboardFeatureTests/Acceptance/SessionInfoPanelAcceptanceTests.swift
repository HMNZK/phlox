// task-15 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-15.md — セッション情報パネル（経過時間・ブランチ）の純関数群。

import Foundation
import Testing
@testable import DashboardFeature

// MARK: - GitBranchReader

private func makeTempRepoDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("git-branch-reader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func gitBranchReader_readsBranchFromRefHead() throws {
    let repo = try makeTempRepoDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try "ref: refs/heads/feature/chat-ux-batch\n".write(
        to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

    #expect(GitBranchReader.currentBranch(at: repo.path) == "feature/chat-ux-batch")
}

@Test func gitBranchReader_detachedHeadReturnsShortSHA() throws {
    let repo = try makeTempRepoDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try "0123456789abcdef0123456789abcdef01234567\n".write(
        to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

    #expect(GitBranchReader.currentBranch(at: repo.path) == "0123456")
}

@Test func gitBranchReader_resolvesWorktreeGitFileIndirection() throws {
    let root = try makeTempRepoDir()
    defer { try? FileManager.default.removeItem(at: root) }
    // 実リポジトリの worktree 構造を模す: <wt>/.git はファイルで gitdir を指す
    let gitdirTarget = root.appendingPathComponent("main/.git/worktrees/wt1", isDirectory: true)
    try FileManager.default.createDirectory(at: gitdirTarget, withIntermediateDirectories: true)
    try "ref: refs/heads/dev\n".write(
        to: gitdirTarget.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
    let worktree = root.appendingPathComponent("wt1", isDirectory: true)
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try "gitdir: \(gitdirTarget.path)\n".write(
        to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

    #expect(GitBranchReader.currentBranch(at: worktree.path) == "dev")
}

@Test func gitBranchReader_nonRepoReturnsNil() throws {
    let dir = try makeTempRepoDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(GitBranchReader.currentBranch(at: dir.path) == nil)
}

// MARK: - SessionElapsedFormat

@Test func sessionInfoPanel_elapsedFormatBoundaries() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func label(_ seconds: TimeInterval) -> String {
        SessionElapsedFormat.label(from: base, to: base.addingTimeInterval(seconds))
    }
    #expect(label(0) == "00:00")
    #expect(label(59) == "00:59")
    #expect(label(60) == "01:00")
    #expect(label(3599) == "59:59")
    #expect(label(3600) == "1:00:00")
    #expect(label(3661) == "1:01:01")
    #expect(label(-5) == "00:00")
}
