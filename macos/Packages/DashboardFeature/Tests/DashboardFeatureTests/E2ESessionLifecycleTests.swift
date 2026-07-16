import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
import TerminalUI
@testable import DashboardFeature
@testable import SessionFeature
@testable import PTYKit

// MARK: - WP-E2 専用ヘルパ（共有ファイルは編集しない）

private func lifecycle_isE2EEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PHLOX_E2E"] == "1"
}

private func lifecycle_childEnvironment(extra: [String: String] = [:]) -> [String: String] {
    let basePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var env: [String: String] = [
        "PATH": inherited.isEmpty ? basePath : "\(basePath):\(inherited)",
        "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
        "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
        "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
        "TERM": "xterm-256color",
    ]
    for (k, v) in extra { env[k] = v }
    return env
}

private func lifecycle_makeTempWorkingDirectory() -> String {
    let dir = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("phlox-e2e-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

private func lifecycle_fakeAgentPath() -> String {
    let fixturesDir = (#filePath as NSString).deletingLastPathComponent + "/Fixtures"
    return (fixturesDir as NSString).appendingPathComponent("fake-agent.sh")
}

@MainActor
private func lifecycle_waitUntil(
    timeoutNanoseconds: UInt64,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else { return false }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
    return true
}

@Suite("E2E SessionLifecycle")
struct E2ESessionLifecycleTests {

    @Test(.enabled(if: lifecycle_isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func sessionLifecycle_hookDrivenSendAndStopCompletion() async throws {
        let hookServer = HookServer()
        let port = try await hookServer.start(preferredPort: 0)
        guard let hookURL = URL(string: "http://127.0.0.1:\(port)/hook") else {
            Issue.record("HookServer URL の組み立てに失敗")
            return
        }

        let sessionID = SessionID()
        let pty = PTYManager()
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let hookMultiplexTask = Task { @MainActor in
            for await delivery in hookServer.deliveries {
                hookContinuation.yield((delivery.sessionID, delivery.event))
            }
        }

        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/bash",
            args: [lifecycle_fakeAgentPath()],
            env: lifecycle_childEnvironment(extra: [
                "FAKE_AGENT_HOOK_URL": hookURL.absoluteString,
                "PHLOX_SESSION_ID": sessionID.rawValue.uuidString,
            ]),
            workingDirectory: lifecycle_makeTempWorkingDirectory(),
            kind: .claudeCode,
            statusBootstrap: .viaHook
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: pty,
            hookEvents: hookStream,
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )

        await vm.start()
        vm.terminalCoordinator.onResize(80, 24)

        let ready = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) { vm.status == .idle }
        #expect(ready, "sessionStart フック経由で ready(.idle) へ到達しなかった")

        vm.markInputSubmitted()
        hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
        let running = await lifecycle_waitUntil(timeoutNanoseconds: 2_000_000_000) { vm.status == .running }
        #expect(running, "送信後に .running へ遷移しなかった")
        await vm.sendInput(Data("hello\n".utf8))

        let completed = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.status == .idle && vm.hasUnseenCompletion
        }
        #expect(completed, "stop フック受信後に idle 完了検知が発火しなかった")
        #expect(vm.terminalCoordinator.visibleText().contains("ECHO: hello"))

        hookMultiplexTask.cancel()
        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }

    @Test(.enabled(if: lifecycle_isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func sessionLifecycle_exitAfterOneRoundTripThenCompletes() async {
        let sessionID = SessionID()
        let pty = PTYManager()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/bash",
            args: [lifecycle_fakeAgentPath(), "--exit-after", "1"],
            env: lifecycle_childEnvironment(),
            workingDirectory: lifecycle_makeTempWorkingDirectory(),
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

        let ready = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) { vm.status == .idle }
        #expect(ready, "fake-agent 起動後に ready(.idle) へ到達しなかった")

        vm.markInputSubmitted()
        await vm.sendInput(Data("hello\n".utf8))

        let echoed = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.terminalCoordinator.visibleText().contains("ECHO: hello")
        }
        #expect(echoed, "1 往復のエコー出力が確認できなかった")

        let completed = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) {
            if case .completed(exitCode: 0) = vm.status { return true }
            return false
        }
        #expect(completed, "--exit-after 1 によるプロセス終了後に .completed(exitCode: 0) へ到達しなかった")
        #expect(vm.status != .running, "プロセス終了後も .running のまま残った")

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }

    @Test(.enabled(if: lifecycle_isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func sessionLifecycle_killTerminatesChildProcess() async {
        let sessionID = SessionID()
        let pty = PTYManager()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/bash",
            args: [lifecycle_fakeAgentPath(), "--exit-after", "9999"],
            env: lifecycle_childEnvironment(),
            workingDirectory: lifecycle_makeTempWorkingDirectory(),
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

        let ready = await lifecycle_waitUntil(timeoutNanoseconds: 10_000_000_000) { vm.status == .idle }
        #expect(ready, "fake-agent 起動後に ready(.idle) へ到達しなかった")

        let pid = await pty.pid(for: sessionID)
        #expect(pid != nil, "子プロセス PID を取得できなかった")

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))

        let stillAlive = pid.map { Darwin.kill($0, 0) == 0 } ?? true
        #expect(!stillAlive, "kill 後も子プロセスが生存している")
    }
}
