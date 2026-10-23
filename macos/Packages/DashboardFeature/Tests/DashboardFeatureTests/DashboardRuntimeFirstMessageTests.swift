import AgentDomain
import CursorAgentKit
import Foundation
import Observation
import SessionFeature
import StructuredChatKit
import Testing
@testable import DashboardFeature

private actor ControlledRuntimeCursorRunner: OneShotProcessRunning {
    nonisolated let entered: AsyncStream<Void>
    nonisolated let finished: AsyncStream<Bool>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let finishedContinuation: AsyncStream<Bool>.Continuation
    private var pending: CheckedContinuation<OneShotProcessResult, Error>?
    private(set) var completed = false

    init() {
        (entered, enteredContinuation) = AsyncStream.makeStream()
        (finished, finishedContinuation) = AsyncStream.makeStream()
    }

    func run(command: String, arguments: [String], environment: [String: String], workingDirectory: URL?) async throws -> OneShotProcessResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    completed = true
                    finishedContinuation.yield(true)
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending = continuation
                    enteredContinuation.yield(())
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func fail() {
        guard let pending else { return }
        self.pending = nil
        completed = true
        finishedContinuation.yield(false)
        pending.resume(returning: .init(exitCode: 1, outputLines: [], errorLines: [Data("controlled first turn failure".utf8)]))
    }

    func abort() {
        fail()
        enteredContinuation.finish()
        finishedContinuation.finish()
    }

    private func cancel() {
        guard let pending else { return }
        self.pending = nil
        completed = true
        pending.resume(throwing: CancellationError())
        finishedContinuation.yield(true)
    }
}

@Suite @MainActor struct DashboardRuntimeFirstMessageTests {
    @Test func acceptedCursorFirstMessageCanBeInterruptedBehindAnOrdinaryCommand() async throws {
        let fixture = try RuntimeFirstMessageFixture()
        defer { fixture.remove() }
        let runner = ControlledRuntimeCursorRunner()
        let owned = fixture.dashboard(runner: runner)
        let request = fixture.request(in: owned)
        let launch = Task { try await owned.performRuntimeCommand(.launchNewChat(request)) }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await runner.abort()
        }
        defer { watchdog.cancel() }
        var entered = runner.entered.makeAsyncIterator()
        let enteredEvent = await entered.next()
        try #require(enteredEvent != nil)
        let reply = try await launch.value
        let id: SessionID
        switch reply {
        case .acceptedSession(let accepted): id = accepted
        default:
            Issue.record("初回送信は処理成功ではなく受理として応答する必要があります")
            await runner.fail()
            for node in owned.sessionNodes { await owned.removeSession(node.id) }
            return
        }
        #expect(await runner.completed == false, "runner完了より先にセッションIDを返す必要があります")
        watchdog.cancel()

        let renameEntered = AsyncStream<Void>.makeStream()
        let renameRelease = AsyncStream<Void>.makeStream()
        let gui = try DashboardViewModel(projection: owned.makeRuntimeSnapshot()) { command in
            if case .renameSession = command {
                renameEntered.continuation.yield(())
                for await _ in renameRelease.stream { break }
            }
            return try await owned.performRuntimeCommand(command)
        }
        gui.renameSession(id, to: "after acceptance")
        var renaming = renameEntered.stream.makeAsyncIterator()
        await renaming.next()
        let session = try #require(gui.sessionNode(id: id)?.appServer)
        let stopWatchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            renameRelease.continuation.yield(())
            await runner.fail()
        }
        defer { stopWatchdog.cancel() }
        let interrupt = Task { await session.turnInterrupt() }
        var finished = runner.finished.makeAsyncIterator()
        let cancelled = await finished.next()
        await interrupt.value
        #expect(cancelled == true, "通常操作を保留していても中断をrunnerへ届ける必要があります")
        #expect(await runner.completed)
        renameRelease.continuation.yield(())
        _ = try await gui.addProjectFromRuntime(name: "barrier", directoryPath: fixture.directory.path)
        renameEntered.continuation.finish()
        renameRelease.continuation.finish()
        await owned.removeSession(id)
    }

    @Test func acceptedCursorFailurePublishesLaunchErrorAndRestoredDraft() async throws {
        let fixture = try RuntimeFirstMessageFixture()
        defer { fixture.remove() }
        let runner = ControlledRuntimeCursorRunner()
        let owned = fixture.dashboard(runner: runner)
        let request = fixture.request(in: owned)
        let launch = Task { try await owned.performRuntimeCommand(.launchNewChat(request)) }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await runner.abort()
        }
        defer { watchdog.cancel() }
        var entered = runner.entered.makeAsyncIterator()
        let enteredEvent = await entered.next()
        try #require(enteredEvent != nil)
        let reply = try await launch.value
        guard case .acceptedSession(let id) = reply else {
            Issue.record("runner処理を待たず受理IDを返す必要があります")
            await runner.fail()
            for node in owned.sessionNodes { await owned.removeSession(node.id) }
            return
        }
        let vm = try #require(owned.sessionNode(id: id)?.appServer)
        let failure = AsyncStream<Void>.makeStream()
        let failureWatchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            failure.continuation.finish()
        }
        defer { failureWatchdog.cancel() }
        withObservationTracking { _ = vm.launchFailure } onChange: { failure.continuation.yield(()) }
        await runner.fail()
        var failed = failure.stream.makeAsyncIterator()
        if vm.launchFailure == nil { await failed.next() }
        let snapshot = vm.makeRuntimeSnapshot()
        #expect(snapshot.launchFailure != nil)
        try #require(snapshot.draftRecoveryID != nil)
        #expect(vm.draft == request.text)
        #expect(vm.transcript.contains { if case .error = $0 { true } else { false } })
        let recovery = AsyncStream<Void>.makeStream()
        let recoveryWatchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            recovery.continuation.finish()
        }
        defer { recoveryWatchdog.cancel() }
        let gui = try DashboardViewModel(projection: owned.makeRuntimeSnapshot()) { command in
            let reply = try await owned.performRuntimeCommand(command)
            if case .session(_, _, .acknowledgeRecoveredDraft) = command { recovery.continuation.yield(()) }
            return reply
        }
        var recovered = recovery.stream.makeAsyncIterator()
        let recoveredEvent = await recovered.next()
        #expect(recoveredEvent != nil)
        #expect(gui.sessionNode(id: id)?.appServer?.draft == request.text)
        #expect(gui.sessionNode(id: id)?.appServer?.launchFailure != nil)
        recovery.continuation.finish()
        failure.continuation.finish()
        await owned.removeSession(id)
    }
}

@MainActor private struct RuntimeFirstMessageFixture {
    let directory: URL
    let defaultsSuite = "phlox-runtime-firstsend-\(UUID())"

    init() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        directory = root.appendingPathComponent(".verification/independent-session-runtime/runtime-firstsend-tests/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "Dashboard runtime first-message tests. Cursor execution uses a controlled runner. Isolated defaults domain \(defaultsSuite).\n"
            .write(to: directory.appendingPathComponent("ownership.txt"), atomically: true, encoding: .utf8)
    }

    func remove() {
        UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("検証用ディレクトリを削除できませんでした: \(error)") }
    }

    func dashboard(runner: ControlledRuntimeCursorRunner) -> DashboardViewModel {
        let client = CursorChatClient(command: "/bin/echo", runMode: .runEverything, runner: runner)
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() },
            workspaceDirectory: directory.appendingPathComponent("workspaces"),
            codexHome: directory.appendingPathComponent("codex"), agentBinaryPaths: [.cursor: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, _ in client }), paneLayoutStore: nil)
        dashboard.lastUsedChatSettingsStoreForTesting = .init(defaults: UserDefaults(suiteName: defaultsSuite)!)
        dashboard.addProject(name: "Runtime", directoryPath: directory.path)
        return dashboard
    }

    func request(in dashboard: DashboardViewModel) -> NewChatLaunchRequest {
        .init(projectID: dashboard.projects[0].id, agentRef: .builtin(.cursor),
              settings: .init(selectedModel: "auto", selectedPermissionProfile: "ask"),
              usesWorktree: false, text: "controlled first message", attachments: [])
    }
}
