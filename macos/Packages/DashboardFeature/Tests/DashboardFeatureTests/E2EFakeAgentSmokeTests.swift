import Foundation
import Testing
import AgentDomain
import PTYKit
import TerminalUI
@testable import DashboardFeature
@testable import SessionFeature

@Suite("E2E FakeAgent")
struct E2EFakeAgentSmokeTests {

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func fakeAgent_inputEchoThenSilenceReachesIdleCompletion() async {
        let sessionID = SessionID()
        let pty = PTYManager()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/bash",
            args: [fakeAgentPath()],
            env: childEnvironment(),
            workingDirectory: makeTempWorkingDirectory(),
            kind: .cursor,
            statusBootstrap: .idleOnSpawnComplete
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: pty,
            hookEvents: AsyncStream { _ in },
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )

        await vm.start()
        vm.terminalCoordinator.onResize(80, 24)

        let ready = await waitUntil(timeoutNanoseconds: 10_000_000_000) { vm.status == .idle }
        #expect(ready, "fake-agent 起動後に ready(.idle) へ到達しなかった")

        vm.markInputSubmitted()
        #expect(vm.status == .running)
        #expect(vm.completedTurnSeq == 0)
        await vm.sendInput(Data("hello\n".utf8))

        let completed = await waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.status == .idle && vm.hasUnseenCompletion
        }
        #expect(completed, "出力沈黙後に idle 完了検知が発火しなかった")
        #expect(vm.terminalCoordinator.visibleText().contains("ECHO: hello"))
        // 非フック CLI の idle フォールバックが turn 完了として記録されること
        // （wait API の完了条件）。実 PTY の settle タイミングで検証する。
        #expect(vm.completedTurnSeq == 1, "idle フォールバックで completedTurnSeq が進まなかった")
        #expect(vm.lastTurnCompletedAt != nil)

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }

    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func fakeAgent_exitAfterZeroCompletesWithoutStuckRunning() async {
        let sessionID = SessionID()
        let pty = PTYManager()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/bash",
            args: [fakeAgentPath(), "--exit-after", "0"],
            env: childEnvironment(),
            workingDirectory: makeTempWorkingDirectory(),
            kind: .cursor,
            statusBootstrap: .idleOnSpawnComplete
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: pty,
            hookEvents: AsyncStream { _ in },
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )

        await vm.start()
        vm.terminalCoordinator.onResize(80, 24)

        let completed = await waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.status == .completed(exitCode: 0)
        }
        #expect(completed, "fake-agent --exit-after 0 後に .completed(exitCode: 0) へ到達しなかった")
        #expect(vm.status != .running, "プロセス終了後も .running のまま残った")

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }
}
