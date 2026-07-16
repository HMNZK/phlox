// task-8 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-8.md — ドーナツのホバー即時ポップアップ文言（Cursor 準拠3行）と、
// ブランチ一覧・checkout 切替の実行系（GitBranchSwitcher・実 git）。
// アサーションは変更禁止。ハーネス欠陥を発見した場合は PM に報告し承認を得たうえで
// ハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - ポップアップ文言（純関数）

@Test
func popoverText_formatsCursorStyleLines() {
    let lines = ComposerContextPopoverText.lines(usedTokens: 27_400, windowTokens: 353_000)
    #expect(lines == [
        "Context window:",
        "8% used (92% left)",
        "27k / 353k tokens used",
    ])
}

@Test
func popoverText_percentRoundsToNearest() {
    // 84.6% → 85% used (15% left)
    let lines = ComposerContextPopoverText.lines(usedTokens: 84_600, windowTokens: 100_000)
    #expect(lines[1] == "85% used (15% left)")
}

@Test
func popoverText_tokenTextBoundaries() {
    #expect(ComposerContextPopoverText.tokenText(540) == "540")
    #expect(ComposerContextPopoverText.tokenText(999) == "999")
    #expect(ComposerContextPopoverText.tokenText(1_000) == "1k")
    #expect(ComposerContextPopoverText.tokenText(27_400) == "27k")
    #expect(ComposerContextPopoverText.tokenText(353_000) == "353k")
}

// MARK: - GitBranchSwitcher（実 git・一時リポジトリ）

private struct TempGitRepo {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "branch-switcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run("init", "--initial-branch=main")
        try run("config", "user.email", "test@example.com")
        try run("config", "user.name", "Test")
        try run("config", "commit.gpgsign", "false")
    }

    func write(_ name: String, _ contents: String) throws {
        try contents.write(to: url.appending(path: name), atomically: true, encoding: .utf8)
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "TempGitRepo", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

@Test
func branchSwitcher_listsLocalBranchesNewestFirst() throws {
    let repo = try TempGitRepo()
    defer { repo.cleanup() }
    try repo.write("a.txt", "1")
    try repo.run("add", ".")
    try repo.run("commit", "-m", "first")
    try repo.run("checkout", "-b", "feature/newer")
    try repo.write("b.txt", "2")
    try repo.run("add", ".")
    try repo.run("commit", "-m", "second")

    let branches = try GitBranchSwitcher.localBranches(at: repo.url.path)

    #expect(branches.contains("main"))
    #expect(branches.contains("feature/newer"))
    // committerdate 降順: 直近コミットを持つ feature/newer が main より前。
    let newerIndex = try #require(branches.firstIndex(of: "feature/newer"))
    let mainIndex = try #require(branches.firstIndex(of: "main"))
    #expect(newerIndex < mainIndex)
}

@Test
func branchSwitcher_checkoutSwitchesHEAD() throws {
    let repo = try TempGitRepo()
    defer { repo.cleanup() }
    try repo.write("a.txt", "1")
    try repo.run("add", ".")
    try repo.run("commit", "-m", "first")
    try repo.run("branch", "feature/target")
    #expect(GitBranchReader.currentBranch(at: repo.url.path) == "main")

    try GitBranchSwitcher.checkout(branch: "feature/target", at: repo.url.path)

    #expect(GitBranchReader.currentBranch(at: repo.url.path) == "feature/target")
}

@Test
func branchSwitcher_conflictingDirtyCheckoutThrowsAndKeepsBranch() throws {
    let repo = try TempGitRepo()
    defer { repo.cleanup() }
    // main と feature/other で同一ファイルを異なる内容でコミットし、
    // main 側に未コミット変更を残して checkout を衝突させる。
    try repo.write("shared.txt", "main-content")
    try repo.run("add", ".")
    try repo.run("commit", "-m", "main version")
    try repo.run("checkout", "-b", "feature/other")
    try repo.write("shared.txt", "other-content")
    try repo.run("add", ".")
    try repo.run("commit", "-m", "other version")
    try repo.run("checkout", "main")
    try repo.write("shared.txt", "dirty-uncommitted")

    #expect(throws: (any Error).self) {
        try GitBranchSwitcher.checkout(branch: "feature/other", at: repo.url.path)
    }
    // 失敗時はブランチが変わらない（force・stash の自動実行をしていない証拠）。
    #expect(GitBranchReader.currentBranch(at: repo.url.path) == "main")
}
