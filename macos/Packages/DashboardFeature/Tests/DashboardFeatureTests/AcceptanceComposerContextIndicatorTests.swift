// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-5.md — ComposerContextGauge.fraction の nil/クランプ規則と、
// GitBranchReader の SessionFeature への移設（挙動不変）。

import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

// MARK: - ComposerContextGauge.fraction

@Test func contextGauge_nilUsage_returnsNil() {
    #expect(ComposerContextGauge.fraction(for: nil) == nil)
}

@Test func contextGauge_explicitUsedAndWindow_returnsRatio() {
    let usage = TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == 0.25)
}

@Test func contextGauge_derivesUsedFromTokenFieldsWhenContextUsedNil() {
    // Claude 形: contextUsedTokens は nil、input + cacheRead + cacheCreation から導出する。
    let usage = TurnUsage(
        inputTokens: 10_000,
        cacheReadTokens: 80_000,
        cacheCreationTokens: 10_000,
        contextWindowTokens: 200_000
    )
    #expect(ComposerContextGauge.fraction(for: usage) == 0.5)
}

@Test func contextGauge_outputTokensAreNotCountedAsContextUse() {
    let usage = TurnUsage(
        inputTokens: 100_000,
        outputTokens: 50_000,
        contextWindowTokens: 200_000
    )
    #expect(ComposerContextGauge.fraction(for: usage) == 0.5)
}

@Test func contextGauge_missingWindow_returnsNil() {
    let usage = TurnUsage(inputTokens: 10_000)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_zeroWindow_returnsNil() {
    let usage = TurnUsage(contextUsedTokens: 10, contextWindowTokens: 0)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_missingUsed_returnsNil() {
    let usage = TurnUsage(costUSD: 1.0, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_overflow_isClampedToOne() {
    let usage = TurnUsage(contextUsedTokens: 300_000, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == 1.0)
}

// MARK: - GitBranchReader（SessionFeature へ移設・挙動不変）

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
