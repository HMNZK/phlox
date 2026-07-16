// SessionViewModel 特性化テスト（Run 3 / task-19）
// 871 行の SessionViewModel を後続タスクで分解する前に、観測可能な振る舞いを固定する。
// 公開インターフェース経由のみ。既存 SessionViewModelTests は変更しない。

import AgentDomain
import Foundation
import PTYKit
import TerminalUI
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Test doubles

private final class FailingSpawnPTYManager: PTYManagerProtocol, @unchecked Sendable {
    private let inner = MockPTYManager()

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        throw PTYError.spawnFailed(errno: 1)
    }

    func write(_ data: Data, to id: SessionID) async throws {
        try await inner.write(data, to: id)
    }

    func kill(_ id: SessionID) async {
        await inner.kill(id)
    }

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        try await inner.resize(id, cols: cols, rows: rows)
    }

    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        inner.outputStream(for: id)
    }

    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        inner.exitStream(for: id)
    }
}

@MainActor
private final class CharacterizationDiagnosticCapture {
    private(set) var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

// MARK: - Helpers

private let characterizationFixedSessionID = SessionID(
    rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!
)

private let codexQuestionPrompt = """
Question from Codex
unanswered
enter to submit answer
"""

@MainActor
private func characterizationSpawnRequest(
    kind: AgentKind = .claudeCode
) -> SessionViewModel.SpawnRequest {
    SessionViewModel.SpawnRequest(
        command: "/usr/local/bin/agent",
        args: ["--settings", "/tmp/char-settings.json"],
        env: ["TERM": "xterm-256color"],
        workingDirectory: "/tmp/char-workspace",
        kind: kind,
        statusBootstrap: kind == .claudeCode ? .viaHook : .idleOnSpawnComplete
    )
}

@MainActor
private func sessionVM_characterizationVM(
    sessionID: SessionID = SessionID(),
    ptyManager: any PTYManagerProtocol = MockPTYManager(),
    kind: AgentKind = .claudeCode
) -> (
    SessionViewModel,
    any PTYManagerProtocol,
    AsyncStream<(SessionID, HookEvent)>.Continuation,
    SessionViewModel.SpawnRequest
) {
    let spawnRequest = characterizationSpawnRequest(kind: kind)
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: ptyManager,
        hookEvents: hookStream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: spawnRequest
    )
    return (vm, ptyManager, hookContinuation, spawnRequest)
}

@MainActor
private func characterizationSpawnCodex(
    _ vm: SessionViewModel,
    ptyManager: any PTYManagerProtocol,
    cols: UInt16 = 80,
    rows: UInt16 = 24
) async throws {
    vm.terminalCoordinator.onResize(cols, rows)
    let mock = ptyManager as? MockPTYManager
    try await waitUntil { mock?.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }
}

private func isAwaitingApproval(_ status: SessionStatus) -> Bool {
    if case .awaitingApproval = status {
        true
    } else {
        false
    }
}

// MARK: - Init & display

@Test @MainActor
func sessionVM_characterization_init_exposesStartingSessionDefaults() {
    let (vm, _, _, spawnRequest) = sessionVM_characterizationVM(sessionID: characterizationFixedSessionID)

    #expect(vm.id == characterizationFixedSessionID)
    #expect(vm.status == .starting)
    #expect(vm.hasProducedOutput == false)
    #expect(vm.lastOutputAt == nil)
    #expect(vm.completedTurnSeq == 0)
    #expect(vm.activeTurnId == nil)
    #expect(vm.isRestored == false)
    #expect(vm.hasUnseenCompletion == false)
    #expect(vm.agentKind == .claudeCode)
    #expect(spawnRequest.statusBootstrap == .viaHook)
}

@Test @MainActor
func sessionVM_characterization_displayName_fallsBackToShortIDLiteral() {
    let (vm, _, _, _) = sessionVM_characterizationVM(sessionID: characterizationFixedSessionID)

    #expect(vm.displayName == "#F83921")
    #expect(SessionViewModel.shortID(for: characterizationFixedSessionID) == "#F83921")
}

// MARK: - PTY lifecycle

@Test @MainActor
func sessionVM_characterization_spawnEager_bootstrapsPTYWithoutResize() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    await vm.spawnEager()

    try await waitUntil { mock.spawnCalls.count == 1 }
    let call = try #require(mock.spawnCalls.first)
    #expect(call.id == sessionID)
    #expect(call.command == "/usr/local/bin/agent")
    #expect(call.workingDirectory == "/tmp/char-workspace")
}

@Test @MainActor
func sessionVM_characterization_spawnIfNeeded_recordsGridSizeFromResize() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    vm.terminalCoordinator.onResize(100, 30)

    try await waitUntil { mock.spawnCalls.count == 1 }
    let call = try #require(mock.spawnCalls.first)
    #expect(call.initialSize == PTYInitialSize(cols: 100, rows: 30))
}

@Test @MainActor
func sessionVM_characterization_spawnFailure_transitionsToErrorLiteral() async throws {
    let sessionID = SessionID()
    let failingPTY = FailingSpawnPTYManager()
    let spawnRequest = characterizationSpawnRequest(kind: .codex)
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: failingPTY,
        hookEvents: hookStream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: spawnRequest
    )

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil {
        if case .error(let message) = vm.status {
            return message.contains("spawn failed:")
        }
        return false
    }
    if case .error(let message) = vm.status {
        #expect(message.contains("spawn failed:"))
    } else {
        Issue.record("Expected error status, got \(vm.status)")
    }
}

@Test @MainActor
func sessionVM_characterization_exitZero_transitionsToCompletedLiteral() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { mock.spawnCalls.count == 1 }

    mock.emitExit(for: sessionID, code: 0)
    try await waitUntil { vm.status == .completed(exitCode: 0) }
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func sessionVM_characterization_exitNonZero_transitionsToErrorWithExitCodeLiteral() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { mock.spawnCalls.count == 1 }

    mock.emitExit(for: sessionID, code: 137)
    try await waitUntil {
        if case .error(let message) = vm.status {
            return message == "exit code 137"
        }
        return false
    }
    if case .error(let message) = vm.status {
        #expect(message == "exit code 137")
    } else {
        Issue.record("Expected error status, got \(vm.status)")
    }
}

@Test @MainActor
func sessionVM_characterization_terminate_killsSpawnedPTY() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { mock.spawnCalls.count == 1 }

    await vm.terminate()
    #expect(mock.killedIDs == [sessionID])
}

@Test @MainActor
func sessionVM_characterization_sendText_beforeSpawnThrowsNotSpawned() async throws {
    let (vm, _, _, _) = sessionVM_characterizationVM(kind: .codex)

    await vm.start()

    await #expect(throws: ControllableSessionError.notSpawned) {
        try await vm.sendText("hello", submit: true)
    }
}

// MARK: - Hook state machine

@Test @MainActor
func sessionVM_characterization_hookSessionStart_transitionsToIdle() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((sessionID, .sessionStart))

    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
}

@Test @MainActor
func sessionVM_characterization_hookUserPromptSubmit_transitionsToRunning() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "turn-1")))

    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
    #expect(vm.activeTurnId == "turn-1")
}

@Test @MainActor
func sessionVM_characterization_hookStop_transitionsToIdle() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
}

@Test @MainActor
func sessionVM_characterization_hookNotification_approvalRequest_entersAwaiting() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)
    let prompt = "Do you want to allow this?"

    await vm.start()
    hookContinuation.yield((sessionID, .notification(message: prompt)))

    try await waitUntil { vm.status == .awaitingApproval(prompt: prompt) }
    #expect(vm.status == .awaitingApproval(prompt: prompt))
}

@Test @MainActor
func sessionVM_characterization_hookPreToolUse_exitPlanMode_entersAwaiting() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((sessionID, .preToolUse(toolName: "ExitPlanMode")))

    try await waitUntil { vm.status == .awaitingApproval(prompt: "Plan approval requested") }
    #expect(vm.status == .awaitingApproval(prompt: "Plan approval requested"))
}

@Test @MainActor
func sessionVM_characterization_hookIgnoresEventsForOtherSessions() async throws {
    let sessionID = SessionID()
    let otherSessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((otherSessionID, .sessionStart))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(vm.status == .starting)
}

@Test @MainActor
func sessionVM_characterization_hookRunningToIdle_marksUnseenCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)

    await vm.start()
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }
    #expect(vm.hasUnseenCompletion == false)

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { vm.hasUnseenCompletion }
    #expect(vm.hasUnseenCompletion == true)

    vm.markCompletionSeen()
    #expect(vm.hasUnseenCompletion == false)
}

// MARK: - Non-hook idle fallback

@Test @MainActor
func sessionVM_characterization_nonHook_spawnBootstrapsToIdle() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, spawnRequest) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)

    await vm.start()
    #expect(vm.status == .starting)
    #expect(spawnRequest.statusBootstrap == .idleOnSpawnComplete)

    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)
    #expect(vm.status == .idle)
    #expect(vm.agentKind == .codex)
}

@Test @MainActor
func sessionVM_characterization_nonHook_submitTransitionsToRunning() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.markInputSubmitted()
    #expect(vm.status == .running)
}

@Test @MainActor
func sessionVM_characterization_nonHook_outputSettleReturnsIdleAndAdvancesTurnSeq() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)
    #expect(vm.completedTurnSeq == 0)

    vm.markInputSubmitted()
    mock.emitOutput(for: sessionID, data: Data("done\n".utf8))

    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        vm.status == .idle && vm.completedTurnSeq == 1
    }
    #expect(vm.completedTurnSeq == 1)
    #expect(vm.lastTurnCompletedAt != nil)
}

@Test @MainActor
func sessionVM_characterization_nonHook_runningToIdle_marksUnseenCompletion() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.markInputSubmitted()
    mock.emitOutput(for: sessionID, data: Data("done\n".utf8))

    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        vm.status == .idle && vm.hasUnseenCompletion
    }
    #expect(vm.hasUnseenCompletion == true)
}

// MARK: - Codex evaluation

@Test @MainActor
func sessionVM_characterization_codex_trustPrompt_autoAnswersEnterOnce() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)
    vm.codexOutputDebounceInterval = .milliseconds(50)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    mock.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n1. Yes, continue\r\n".utf8)
    )

    try await waitUntil {
        mock.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" }
    }
    let enterWrites = mock.writtenCalls.filter { String(decoding: $0.0, as: UTF8.self) == "\r" }
    #expect(enterWrites.count == 1)
}

@Test @MainActor
func sessionVM_characterization_codex_questionVisible_entersAwaitingApproval() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)
    vm.codexOutputDebounceInterval = .milliseconds(50)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    mock.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))

    try await waitUntil { isAwaitingApproval(vm.status) }
    if case .awaitingApproval(let prompt) = vm.status {
        #expect(prompt == "Codex is asking a question")
    } else {
        Issue.record("Expected awaitingApproval, got \(vm.status)")
    }
}

@Test @MainActor
func sessionVM_characterization_codex_outputEvaluation_deferredUntilDebounceSettles() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)
    vm.codexOutputDebounceInterval = .milliseconds(300)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    mock.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n1. Yes, continue\r\n".utf8)
    )
    try await waitUntil { vm.hasProducedOutput }

    try await Task.sleep(for: .milliseconds(50))
    #expect(!mock.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" })

    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        mock.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" }
    }
}

// MARK: - Submit diagnostic

@Test @MainActor
func sessionVM_characterization_sendText_codex_noProcessingObserved_emitsDiagnosticLine() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let capture = CharacterizationDiagnosticCapture()

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.submitKeyDelay = .zero
    vm.submitTurnStartTimeout = .milliseconds(40)
    vm.submitDiagnosticSink = { capture.append($0) }

    try await vm.sendText("hello world body", submit: true)

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) { capture.lines.count >= 1 }
    #expect(capture.lines.first?.contains("submit-no-processing") == true)
    #expect(capture.lines.first?.contains("kind=codex") == true)
    #expect(capture.lines.first?.contains("bytes=16") == true)
    // 特性化: 送信後も codex セッションは running のまま（no-processing 診断は status を idle にしない）
    #expect(vm.status == .running)
    #expect(vm.completedTurnSeq == 0)
}

@Test @MainActor
func sessionVM_characterization_sendText_codex_processingObserved_suppressesDiagnostic() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)
    let capture = CharacterizationDiagnosticCapture()
    vm.codexOutputDebounceInterval = .milliseconds(20)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.submitKeyDelay = .zero
    vm.submitTurnStartTimeout = .milliseconds(80)
    vm.submitDiagnosticSink = { capture.append($0) }

    try await vm.sendText("task", submit: true)
    mock.emitOutput(
        for: sessionID,
        data: Data("Starting MCP servers (1/2) (0s • esc to interrupt)\n".utf8)
    )

    // 「処理中の観測」を固定 sleep でなく確定的に待つ（実時計・スケジューラ負荷から独立）。
    // observedProcessing は再 arm まで単調なので、true 確認後は flush が診断を発火しない。
    let observedProcessing = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        vm.hasObservedSubmitProcessingForTesting
    }
    #expect(observedProcessing)
    #expect(capture.lines.isEmpty)
    #expect(vm.completedTurnSeq == 0)
}

@Test @MainActor
func sessionVM_characterization_sendText_submitTrue_setsSubmitBaselineTurnSeq() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.submitKeyDelay = .zero
    try await vm.sendText("baseline", submit: true)

    #expect(vm.submitBaselineTurnSeq == 0)
}

// MARK: - Public API surface

@Test @MainActor
func sessionVM_characterization_markRestoreFailed_setsRestoredAndErrorLiteral() {
    let (vm, _, _, _) = sessionVM_characterizationVM()
    let message = "restore token expired"

    vm.markRestoreFailed(message)

    #expect(vm.isRestored == true)
    #expect(vm.status == .error(message: message))
}

@Test @MainActor
func sessionVM_characterization_eventSink_emitsOnStatusTransition() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = sessionVM_characterizationVM(sessionID: sessionID)
    var observed: [SessionStatus] = []
    vm.eventSink = { _, status, _ in observed.append(status) }

    await vm.start()
    hookContinuation.yield((sessionID, .sessionStart))
    try await waitUntil { vm.status == .idle }

    #expect(observed == [.idle])
}

@Test @MainActor
func sessionVM_characterization_readText_returnsCoordinatorVisibleText() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)
    let mock = try #require(ptyManager as? MockPTYManager)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    mock.emitOutput(for: sessionID, data: Data("line-one\nline-two\n".utf8))
    try await waitUntil { vm.hasProducedOutput }

    let tail = vm.readText(lines: 1)
    #expect(tail.contains("line-two"))
}

@Test @MainActor
func sessionVM_characterization_consumeSubmitBaseline_clearsBaselineTurnSeq() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = sessionVM_characterizationVM(sessionID: sessionID, kind: .codex)

    await vm.start()
    try await characterizationSpawnCodex(vm, ptyManager: ptyManager)

    vm.submitKeyDelay = .zero
    try await vm.sendText("baseline", submit: true)
    #expect(vm.submitBaselineTurnSeq == 0)

    vm.consumeSubmitBaseline()
    #expect(vm.submitBaselineTurnSeq == nil)
}
