import Foundation
import Testing
import os
import AgentDomain
import PTYKit
import TerminalUI
@testable import SessionFeature

// MARK: - Mock RemoteSessionNotifier

final class MockRemoteSessionNotifier: RemoteSessionNotifier, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var sessionCompletedCalls: [(sessionId: String, sessionName: String)] = []
        var approvalPendingCalls: [(sessionId: String, sessionName: String)] = []
    }

    var sessionCompletedCalls: [(sessionId: String, sessionName: String)] {
        state.withLock { $0.sessionCompletedCalls }
    }

    var approvalPendingCalls: [(sessionId: String, sessionName: String)] {
        state.withLock { $0.approvalPendingCalls }
    }

    func sessionCompleted(sessionId: String, sessionName: String) {
        state.withLock { $0.sessionCompletedCalls.append((sessionId, sessionName)) }
    }

    func approvalPending(sessionId: String, sessionName: String) {
        state.withLock { $0.approvalPendingCalls.append((sessionId, sessionName)) }
    }
}

// MARK: - Minimal MockPTYManager (SessionFeature テスト専用)

struct TestSpawnCall: Sendable, Equatable {
    let id: SessionID?
}

final class TestMockPTYManager: PTYManagerProtocol, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var outputStreams: [SessionID: AsyncStream<Data>] = [:]
        var outputContinuations: [SessionID: AsyncStream<Data>.Continuation] = [:]
        var pendingOutput: [SessionID: [Data]] = [:]
        var exitStreams: [SessionID: AsyncStream<Int32>] = [:]
        var spawnCalls: [TestSpawnCall] = []
    }

    var spawnCalls: [TestSpawnCall] {
        state.withLock { $0.spawnCalls }
    }

    func emitOutput(for id: SessionID, data: Data) {
        state.withLock { state in
            if let continuation = state.outputContinuations[id] {
                continuation.yield(data)
            } else {
                state.pendingOutput[id, default: []].append(data)
            }
        }
    }

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        let resolvedID = id ?? SessionID()
        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()
        let (exitStream, _) = AsyncStream<Int32>.makeStream()
        state.withLock { state in
            state.spawnCalls.append(TestSpawnCall(id: resolvedID))
            state.outputStreams[resolvedID] = outputStream
            state.outputContinuations[resolvedID] = outputContinuation
            state.exitStreams[resolvedID] = exitStream
        }
        return resolvedID
    }

    func write(_ data: Data, to id: SessionID) async throws {}

    func kill(_ id: SessionID) async {}

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {}

    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        state.withLock { state -> AsyncStream<Data> in
            if let continuation = state.outputContinuations[id] {
                for data in state.pendingOutput.removeValue(forKey: id) ?? [] {
                    continuation.yield(data)
                }
            }
            return state.outputStreams[id] ?? AsyncStream { $0.finish() }
        }
    }

    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        state.withLock { $0.exitStreams[id] } ?? AsyncStream { $0.finish() }
    }
}

// MARK: - Helpers

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeSessionViewModel(
    sessionID: SessionID = SessionID(),
    kind: AgentKind = .claudeCode,
    remoteSessionNotifier: (any RemoteSessionNotifier)? = nil
) -> (SessionViewModel, TestMockPTYManager, AsyncStream<(SessionID, HookEvent)>.Continuation) {
    let ptyManager = TestMockPTYManager()
    let spawnRequest = SessionViewModel.SpawnRequest(
        command: "/usr/local/bin/claude",
        args: [],
        env: ["TERM": "xterm-256color"],
        workingDirectory: "/tmp/workspace",
        kind: kind,
        statusBootstrap: kind == .claudeCode ? .viaHook : .idleOnSpawnComplete
    )
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: ptyManager,
        hookEvents: hookStream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: spawnRequest
    )
    vm.remoteSessionNotifier = remoteSessionNotifier
    return (vm, ptyManager, hookContinuation)
}

private let codexQuestionPrompt = """
Question from Codex
unanswered
enter to submit answer
"""

// MARK: - Tests

@Test @MainActor
func remoteSessionNotifier_runningToIdle_firesSessionCompletedOnce() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, _, hookContinuation) = makeSessionViewModel(
        sessionID: sessionID,
        remoteSessionNotifier: notifier
    )
    vm.name = "Test Session"

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
    #expect(notifier.sessionCompletedCalls[0].sessionId == sessionID.description)
    #expect(notifier.sessionCompletedCalls[0].sessionName == "Test Session")
    #expect(notifier.approvalPendingCalls.isEmpty)
}

@Test @MainActor
func remoteSessionNotifier_startingToIdle_doesNotFireSessionCompleted() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, _, hookContinuation) = makeSessionViewModel(
        sessionID: sessionID,
        remoteSessionNotifier: notifier
    )

    await vm.start()

    hookContinuation.yield((sessionID, .sessionStart))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func remoteSessionNotifier_escapeWhileRunning_doesNotFireSessionCompleted() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, ptyManager, hookContinuation) = makeSessionViewModel(
        sessionID: sessionID,
        remoteSessionNotifier: notifier
    )

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    await vm.sendInput(Data([0x1b]))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func remoteSessionNotifier_codexQuestionWhileRunning_firesApprovalPending() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, ptyManager, _) = makeSessionViewModel(
        sessionID: sessionID,
        kind: .codex,
        remoteSessionNotifier: notifier
    )
    vm.name = "Codex Session"

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    vm.markInputSubmitted()
    #expect(vm.status == .running)

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))
    try await waitUntil { notifier.approvalPendingCalls.count == 1 }

    #expect(notifier.approvalPendingCalls[0].sessionId == sessionID.description)
    #expect(notifier.approvalPendingCalls[0].sessionName == "Codex Session")
    #expect(notifier.sessionCompletedCalls.isEmpty)
}

@Test @MainActor
func remoteSessionNotifier_codexQuestionWhileIdle_doesNotFireApprovalPending() async throws {
    let sessionID = SessionID()
    let notifier = MockRemoteSessionNotifier()
    let (vm, ptyManager, _) = makeSessionViewModel(
        sessionID: sessionID,
        kind: .codex,
        remoteSessionNotifier: notifier
    )

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))
    try await waitUntil {
        if case .awaitingApproval = vm.status { true } else { false }
    }

    #expect(notifier.approvalPendingCalls.isEmpty)
}

@Test @MainActor
func remoteSessionNotifier_nilNotifier_runningToIdleStillMarksCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation) = makeSessionViewModel(sessionID: sessionID, remoteSessionNotifier: nil)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { vm.hasUnseenCompletion }

    #expect(vm.status == .idle)
    #expect(vm.hasUnseenCompletion)
}
