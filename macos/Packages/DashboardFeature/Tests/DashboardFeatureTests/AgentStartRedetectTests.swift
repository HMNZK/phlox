import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// 08 S3・S4: 起動カードの 2 行目（版）と「再検出」、4 列 / 2 列の切替。

@Test func cliVersionProbe_readsFirstVersionNumber() {
    #expect(CLIVersionProbe.parse("2.1.220 (Claude Code)\n") == "2.1.220")
    #expect(CLIVersionProbe.parse("codex-cli 0.144.6") == "0.144.6")
    #expect(CLIVersionProbe.parse("cursor-agent 2026.09.01-abc123") == "2026.09.01-abc123")
    #expect(CLIVersionProbe.parse("unknown option") == nil)
}

@Test func agentStartCards_fourColumnsFrom900PointsWide() {
    let inset = AgentStartCardsView.outerHorizontalInset * 2
    #expect(AgentStartCardsView.columnCount(availableWidth: 900 - inset, cardCount: 4) == 4)
    #expect(AgentStartCardsView.columnCount(availableWidth: 899 - inset, cardCount: 4) == 2)
    #expect(AgentStartCardsView.columnCount(availableWidth: 1200, cardCount: 3) == 3)
    #expect(AgentStartCardsView.columnCount(availableWidth: 600, cardCount: 1) == 1)
}

@Test @MainActor
func redetect_findsCLIInstalledAfterLaunch_inEveryCopyOfTheEnvironment() throws {
    let bin = FileManager.default.temporaryDirectory.appendingPathComponent("redetect-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bin) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream, pathEnvironment: bin.path)
    let copy = environment
    #expect(environment.binaryPath(for: .codex) == nil)
    #expect(environment.redetectBinaries() == false)

    let codex = bin.appendingPathComponent(AgentKind.codex.binaryName)
    try Data("#!/bin/sh\n".utf8).write(to: codex)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

    #expect(environment.redetectBinaries() == true)
    // 環境は値型でサービスへ写されるので、写しからも新しい場所が見える。
    #expect(copy.binaryPath(for: .codex) == codex.path)
}

@Test func cliVersionProbe_readsOutputAndGivesUpOnCLIsThatIgnoreTermination() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func script(_ name: String, _ body: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    let ok = try script("ok", "echo 'codex-cli 0.156.1'")
    #expect(await CLIVersionProbe.version(executable: ok, pathEnvironment: "/usr/bin:/bin") == "0.156.1")

    // 終了信号を無視し、孫プロセスが標準出力を握ったままでも 5 秒で打ち切る。
    let stuck = try script("stuck", "trap '' TERM\nsleep 30 &\nsleep 30")
    let started = Date()
    #expect(await CLIVersionProbe.version(executable: stuck, pathEnvironment: "/usr/bin:/bin") == nil)
    #expect(Date().timeIntervalSince(started) < 8)
}
