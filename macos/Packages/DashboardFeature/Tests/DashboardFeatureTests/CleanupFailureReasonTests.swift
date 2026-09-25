import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

// C-52 / 09 D2: 後始末の警告に、残った場所と実際の失敗の理由を出す。
@MainActor
struct CleanupFailureReasonTests {
    @Test
    func gitFailureUsesTheFirstLineOfItsOutput() {
        let error = WorktreeIsolationGitError.commandFailed(
            arguments: ["worktree", "remove"],
            output: "\nfatal: '/tmp/w' contains modified or untracked files, use --force to delete it\nhint: x\n"
        )
        #expect(DashboardViewModel.cleanupFailureReason(error) == "fatal: '/tmp/w' contains modified or untracked files, use --force to delete it")
    }

    @Test
    func detailAppendsTheReasonOnlyWhenKnown() {
        let warning = WorkspaceCleanupWarning.branchRetained(branchName: "phlox/a3f9")
        #expect(CleanupWarningDialogText.detail(warning, reason: "Permission denied") == "phlox/a3f9（Permission denied）")
        #expect(CleanupWarningDialogText.detail(warning) == "phlox/a3f9")
    }
}

// 09 D2: worktree でない作業フォルダを消せなかったときも、消せなかったファイルと理由を警告に出す。
@Test @MainActor
func removeSession_warnsWithTheFileAndReasonWhenTheWorkspaceCannotBeRemoved() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    let locked = environment.sessionWorkspaceDirectory(for: sessionID).appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    let file = locked.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

    await dashboard.removeSession(sessionID)

    guard case .workspaceRetained(let path) = dashboard.workspaceCleanupWarning else {
        Issue.record("作業フォルダの警告が出ていない: \(String(describing: dashboard.workspaceCleanupWarning))")
        return
    }
    #expect(URL(fileURLWithPath: path).lastPathComponent == "hooks.json")
    #expect(dashboard.workspaceCleanupFailureReason == "Permission denied")
}
