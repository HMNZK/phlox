// GitBranchReader: .git/HEAD から現在のブランチ名を読む（通常 HEAD・detached HEAD・worktree の .git ファイル・非リポジトリ）。

import Foundation
import Testing
@testable import SessionFeature

private func makeBranchTempDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "phlox-branch-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func gitBranchReader_refHead_returnsBranchName() throws {
    let root = try makeBranchTempDirectory()
    let gitDir = root.appending(path: ".git")
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try "ref: refs/heads/feature/context-donut\n".write(
        to: gitDir.appending(path: "HEAD"), atomically: true, encoding: .utf8
    )

    #expect(GitBranchReader.currentBranch(at: root.path) == "feature/context-donut")
}

@Test func gitBranchReader_detachedHead_returnsShortSHA() throws {
    let root = try makeBranchTempDirectory()
    let gitDir = root.appending(path: ".git")
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try "0123456789abcdef0123456789abcdef01234567\n".write(
        to: gitDir.appending(path: "HEAD"), atomically: true, encoding: .utf8
    )

    #expect(GitBranchReader.currentBranch(at: root.path) == "0123456")
}

@Test func gitBranchReader_worktreeGitFile_resolvesIndirectHead() throws {
    let root = try makeBranchTempDirectory()
    let externalGitDir = try makeBranchTempDirectory()
    try "ref: refs/heads/task/task-5\n".write(
        to: externalGitDir.appending(path: "HEAD"), atomically: true, encoding: .utf8
    )
    try "gitdir: \(externalGitDir.path)\n".write(
        to: root.appending(path: ".git"), atomically: true, encoding: .utf8
    )

    #expect(GitBranchReader.currentBranch(at: root.path) == "task/task-5")
}

@Test func gitBranchReader_nonRepository_returnsNil() throws {
    let root = try makeBranchTempDirectory()
    #expect(GitBranchReader.currentBranch(at: root.path) == nil)
}
