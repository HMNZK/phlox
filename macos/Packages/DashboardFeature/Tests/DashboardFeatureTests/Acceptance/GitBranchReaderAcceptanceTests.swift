// task-15 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-15.md — 現在のブランチを読む純関数（セッション情報パネルは ADR 0192 で廃止）。

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
