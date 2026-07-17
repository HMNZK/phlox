import Foundation
import Testing
import AgentDomain
import PTYKit
import TerminalUI
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Helpers

@MainActor
private func makeSpawnRequest(
    kind: AgentKind = .claudeCode,
    postSpawnReset: PostSpawnReset? = nil
) -> SessionViewModel.SpawnRequest {
    SessionViewModel.SpawnRequest(
        command: "/usr/local/bin/claude",
        args: ["--settings", "/tmp/test-settings.json"],
        env: ["TERM": "xterm-256color"],
        workingDirectory: "/tmp/workspace",
        kind: kind,
        statusBootstrap: kind == .claudeCode ? .viaHook : .idleOnSpawnComplete,
        postSpawnReset: postSpawnReset
    )
}

@MainActor
private func makeSessionViewModel(
    sessionID: SessionID = SessionID(),
    ptyManager: MockPTYManager = MockPTYManager(),
    kind: AgentKind = .claudeCode
) -> (SessionViewModel, MockPTYManager, AsyncStream<(SessionID, HookEvent)>.Continuation, SessionViewModel.SpawnRequest) {
    let spawnRequest = makeSpawnRequest(kind: kind)
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
func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

private let codexQuestionPrompt = """
Question from Codex
unanswered
enter to submit answer
"""

private func isAwaitingApproval(_ status: SessionStatus) -> Bool {
    if case .awaitingApproval = status {
        true
    } else {
        false
    }
}

@MainActor
final class CapturedLines {
    private(set) var lines: [String] = []
    var count: Int { lines.count }
    func append(_ line: String) { lines.append(line) }
}

// MARK: - Tests

@Test @MainActor
func start_appliesHookEventForMatchingSession() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))

    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
}

@Test @MainActor
func start_claudeCodeSessionStartHookTransitionsToIdle() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()

    hookContinuation.yield((sessionID, .sessionStart))

    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
}

@Test @MainActor
func start_stopHookTransitionsToIdle() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .idle)
}

@Test @MainActor
func start_runningToIdleMarksCompletionUnseen() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }
    #expect(vm.hasUnseenCompletion == false)

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { vm.hasUnseenCompletion }

    #expect(vm.status == .idle)
    #expect(vm.hasUnseenCompletion)

    vm.markCompletionSeen()
    #expect(vm.hasUnseenCompletion == false)
}

@Test @MainActor
func nonHookCLI_inputSubmitAndOutputSilenceMarksCompletionUnseen() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    vm.markInputSubmitted()
    #expect(vm.status == .running)

    ptyManager.emitOutput(for: sessionID, data: Data("done\n".utf8))

    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        vm.status == .idle && vm.hasUnseenCompletion
    }
    #expect(vm.status == .idle)
    #expect(vm.hasUnseenCompletion)
}

/// codex への submit 後、submitTurnStartTimeout 内に処理開始(turn 開始)を一度も観測しなければ
/// 「submit 滞留の疑い」を診断 sink に 1 件記録する(observe-only)。再発が稀な submit 滞留バグ
/// (ADR 0002 §8.5/§8.6)を次の再発で捕捉するための計装。status/completedTurnSeq は変えない。
@Test @MainActor
func sendText_codexSubmitWithoutObservedProcessing_emitsDiagnostic() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    vm.submitKeyDelay = .zero
    vm.submitTurnStartTimeout = .milliseconds(40)
    let captured = CapturedLines()
    vm.submitDiagnosticSink = { captured.append($0) }

    // mock PTY は出力を返さない＝処理開始は観測されない → タイムアウトで診断が記録される。
    try await vm.sendText("hello world body", submit: true)

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) { captured.count >= 1 }
    #expect(captured.lines.first?.contains("submit-no-processing") == true)
    #expect(captured.lines.first?.contains("kind=codex") == true)
    #expect(captured.lines.first?.contains("bytes=16") == true)  // "hello world body" = 16 bytes
}

@Test @MainActor
func nonHookCLI_idleFallbackAdvancesCompletedTurnSeq() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }
    #expect(vm.completedTurnSeq == 0)

    vm.markInputSubmitted()
    #expect(vm.status == .running)

    ptyManager.emitOutput(for: sessionID, data: Data("done\n".utf8))

    // settle(400ms) 経過後の running→idle 確定で turn 完了として記録される。
    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        vm.completedTurnSeq == 1
    }
    #expect(vm.completedTurnSeq == 1)
    #expect(vm.lastTurnCompletedAt != nil)
    #expect(vm.status == .idle)
}

@Test @MainActor
func shiftEnterNewlineDoesNotSubmit() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    // Shift+Enter は LF(\n) を送る＝改行。送信(CR)ではないので running にならない。
    await vm.sendInput(Data("\n".utf8))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .idle)

    // 対照: Enter は CR(\r)＝送信。codex は楽観的に running になる。
    await vm.sendInput(Data("\r".utf8))
    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
}

@Test @MainActor
func escapeWhileRunningResetsClaudeToIdle() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // userPromptSubmit フックで running に。
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    // Claude は esc 中断で stop フックを出さないため、Escape 単体を検知して idle へ整合する。
    await vm.sendInput(Data([0x1b]))
    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
    // キャンセルであり完了ではないため完了通知は立たない。
    #expect(vm.hasUnseenCompletion == false)
}

@Test @MainActor
func start_startingToIdleDoesNotMarkCompletionUnseen() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()

    hookContinuation.yield((sessionID, .sessionStart))
    try await waitUntil { vm.status == .idle }

    #expect(vm.hasUnseenCompletion == false)
}

@Test @MainActor
func start_stopHookRecordsTurnCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .stop(turnId: nil)))

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.completedTurnSeq == 1)
    #expect(vm.lastTurnCompletedAt != nil)
}

@Test @MainActor
func start_stopHookWhileAwaitingApprovalDoesNotRecordTurnCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .notification(message: "Do you want to allow this?")))
    try await waitUntil {
        if case .awaitingApproval = vm.status {
            true
        } else {
            false
        }
    }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(vm.completedTurnSeq == 0)
    #expect(vm.lastTurnCompletedAt == nil)
}

@Test @MainActor
func start_matchingTurnIdStopRecordsTurnCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T2")))
    try await waitUntil { vm.activeTurnId == "T2" }

    hookContinuation.yield((sessionID, .stop(turnId: "T2")))
    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.completedTurnSeq == 1)
}

@Test @MainActor
func start_staleTurnIdStopDoesNotRecordTurnCompletion() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T2")))
    try await waitUntil { vm.activeTurnId == "T2" }

    hookContinuation.yield((sessionID, .stop(turnId: "T1")))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(vm.completedTurnSeq == 0)
    #expect(vm.lastTurnCompletedAt == nil)
}

@Test @MainActor
func markAwaitingNewTurn_clearsActiveTurnId() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T1")))
    try await waitUntil { vm.activeTurnId == "T1" }

    vm.markAwaitingNewTurn()
    #expect(vm.activeTurnId == nil)
}

// 送信直後(activeTurnId=nil)の隙間に来た前ターンの遅延 Stop は無視され、
// その後始まった新ターンの Stop で正しく完了する（クロスターン汚染防止＋回復）。
@Test @MainActor
func start_staleStopDuringAwaitingNewTurnIsIgnoredThenNextTurnCompletes() async throws {
    let sessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    // ターン1が active
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T1")))
    try await waitUntil { vm.activeTurnId == "T1" }

    // 送信2相当: 次ターンの userPromptSubmit 待ちへリセット
    vm.markAwaitingNewTurn()
    #expect(vm.activeTurnId == nil)

    // 送信2の userPromptSubmit より前に、ターン1の遅延 Stop が到着 → 無視されるべき
    hookContinuation.yield((sessionID, .stop(turnId: "T1")))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.completedTurnSeq == 0)
    #expect(vm.lastTurnCompletedAt == nil)

    // ターン2が始まり、その Stop で完了する（回復）
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T2")))
    try await waitUntil { vm.activeTurnId == "T2" }
    hookContinuation.yield((sessionID, .stop(turnId: "T2")))
    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.completedTurnSeq == 1)
}

@Test @MainActor
func start_appliesExitCodeZeroAsCompleted() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    ptyManager.emitExit(for: sessionID, code: 0)

    try await waitUntil { vm.status == .completed(exitCode: 0) }
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func start_appliesNonZeroExitCodeAsError() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    ptyManager.emitExit(for: sessionID, code: 137)

    try await waitUntil {
        if case .error(let message) = vm.status {
            return message.contains("exit code 137")
        }
        return false
    }
    if case .error(let message) = vm.status {
        #expect(message.contains("exit code 137"))
    } else {
        Issue.record("Expected error status, got \(vm.status)")
    }
}

@Test @MainActor
func start_onInputForwardsToPTYWrite() async throws {
    let sessionID = SessionID()
    let ptyManager = MockPTYManager()
    let (vm, _, _, _) = makeSessionViewModel(sessionID: sessionID, ptyManager: ptyManager)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let input = Data([0x61])
    vm.terminalCoordinator.onInput(input)

    try await waitUntil {
        ptyManager.writtenCalls.contains { $0 == (input, sessionID) }
    }

    let calls = ptyManager.writtenCalls
    #expect(calls.contains { $0 == (input, sessionID) })
}

@Test @MainActor
func start_ignoresHookEventsForOtherSessions() async throws {
    let sessionID = SessionID()
    let otherSessionID = SessionID()
    let (vm, _, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()

    hookContinuation.yield((otherSessionID, .stop(turnId: nil)))

    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .starting)
}

@Test @MainActor
func firstSizeChanged_triggersSpawn() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    #expect(ptyManager.spawnCalls.isEmpty)

    vm.terminalCoordinator.onResize(100, 30)

    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.id == sessionID)
    #expect(call.initialSize == PTYInitialSize(cols: 100, rows: 30))
}

@Test @MainActor
func secondSizeChanged_triggersResizeNotSpawn() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(100, 30)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    vm.terminalCoordinator.onResize(120, 35)
    try await waitUntil { ptyManager.resizeCalls.count == 1 }

    #expect(ptyManager.spawnCalls.count == 1)
    let resize = try #require(ptyManager.resizeCalls.first)
    #expect(resize.id == sessionID)
    #expect(resize.cols == 120)
    #expect(resize.rows == 35)
}

@Test @MainActor
func spawnIfNeeded_nonHookCLI_transitionsToIdleAfterSpawn() async throws {
    // Codex/Cursor は起動時 hooks を持たないため、spawn 完了をもって starting → idle へ遷移する。
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    #expect(vm.status == .starting)

    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
    #expect(vm.agentKind == .codex)
}

@Test @MainActor
func spawnIfNeeded_cursor_transitionsToIdleAfterSpawn() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, spawnRequest) = makeSessionViewModel(sessionID: sessionID, kind: .cursor)

    await vm.start()
    #expect(vm.status == .starting)
    #expect(vm.agentKind == .cursor)
    #expect(spawnRequest.statusBootstrap == .idleOnSpawnComplete)

    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }
    #expect(vm.status == .idle)
}

@Test @MainActor
func spawnIfNeeded_cursor_doesNotTriggerPostSpawnReset() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .cursor)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(ptyManager.resizeCalls.isEmpty)
}

@Test @MainActor
func spawnIfNeeded_claudeCode_doesNotTriggerPostSpawnReset() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    try await Task.sleep(nanoseconds: 300_000_000)

    #expect(ptyManager.resizeCalls.isEmpty)
}

@Test @MainActor
func isReadyForInput_idleOnSpawnComplete_requiresOutputAndSettle() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    #expect(vm.isReadyForInput == false)

    ptyManager.emitOutput(for: sessionID, data: Data("banner\n".utf8))
    try await waitUntil { vm.hasProducedOutput }

    #expect(vm.isReadyForInput == false)

    try await Task.sleep(for: .milliseconds(500))
    #expect(vm.isReadyForInput == true)
}

@Test @MainActor
func codexSession_autoAnswersDirectoryTrustPrompt() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // codex のディレクトリ信頼プロンプトを模した出力を流す。
    ptyManager.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n1. Yes, continue\r\n2. No, quit\r\n".utf8)
    )

    // outputTask が feed → autoAnswer が visibleText を見て Enter(\r) を1回書く。
    try await waitUntil {
        ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" }
    }
    let enterWrites = ptyManager.writtenCalls.filter { String(decoding: $0.0, as: UTF8.self) == "\r" }
    #expect(enterWrites.count == 1)
}

@Test @MainActor
func codexQuestion_visibleWhileRunning_entersAwaitingApproval() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    vm.markInputSubmitted()
    #expect(vm.status == .running)

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))

    try await waitUntil { isAwaitingApproval(vm.status) }
    #expect(isAwaitingApproval(vm.status))
}

@Test @MainActor
func codexQuestion_visibleWhileIdle_entersAwaitingApproval() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))

    try await waitUntil { isAwaitingApproval(vm.status) }
    #expect(isAwaitingApproval(vm.status))
}

@Test @MainActor
func codexQuestion_visiblePromptSurvivesHookEvents() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))
    try await waitUntil { isAwaitingApproval(vm.status) }

    hookContinuation.yield((sessionID, .postToolUse(toolName: "shell")))
    try await Task.sleep(for: .milliseconds(50))
    #expect(isAwaitingApproval(vm.status))

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "turn-1")))
    try await Task.sleep(for: .milliseconds(50))
    #expect(isAwaitingApproval(vm.status))
}

@Test @MainActor
func codexQuestion_stopWhileAwaitingDoesNotCountCompletion() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))
    try await waitUntil { isAwaitingApproval(vm.status) }

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await Task.sleep(for: .milliseconds(50))

    #expect(isAwaitingApproval(vm.status))
    #expect(vm.completedTurnSeq == 0)
    #expect(vm.lastTurnCompletedAt == nil)
    // ターン完了(completedTurnSeq)は立たないが、承認待ちは「未確認の停止（要対応）」として
    // ラッチする（本機能で idle 完了に加え承認待ち・エラーへ拡張）。
    #expect(vm.hasUnseenCompletion)
}

@Test @MainActor
func codexQuestion_exitsOnlyAfterSubmitAndMarkerDisappears() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    try await waitUntil { vm.status == .idle }

    ptyManager.emitOutput(for: sessionID, data: Data(codexQuestionPrompt.utf8))
    try await waitUntil { isAwaitingApproval(vm.status) }

    vm.terminalCoordinator.resetBuffer()
    ptyManager.emitOutput(for: sessionID, data: Data("plain output without a visible question\n".utf8))
    try await Task.sleep(for: .milliseconds(50))
    #expect(isAwaitingApproval(vm.status))

    // 実 Enter は CR(\r)。LF(\n) は Shift+Enter による改行で送信ではない。
    await vm.sendInput(Data("\r".utf8))
    vm.terminalCoordinator.resetBuffer()
    ptyManager.emitOutput(for: sessionID, data: Data("answer accepted\n".utf8))

    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
}

// P2: codex 固有評価(信頼プロンプト自動応答・質問検知)は出力チャンク毎ではなく、
// 最後の出力から debounce 間隔静止後に 1 回だけ visibleText() を構築して行う。
@Test @MainActor
func codexOutputEvaluation_deferredUntilOutputSettles() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)
    vm.codexOutputDebounceInterval = .milliseconds(300)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    ptyManager.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n1. Yes, continue\r\n".utf8)
    )
    try await waitUntil { vm.hasProducedOutput }

    // debounce 静止待ちの間は評価されず、自動応答の Enter は送られない。
    try await Task.sleep(for: .milliseconds(50))
    #expect(!ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" })

    // 静止後に 1 回だけ評価され、Enter が 1 回送られる。
    try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
        ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" }
    }
    let enterWrites = ptyManager.writtenCalls.filter { String(decoding: $0.0, as: UTF8.self) == "\r" }
    #expect(enterWrites.count == 1)
}

@Test @MainActor
func codexOutputEvaluation_debounceResetsWhileOutputKeepsStreaming() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .codex)
    vm.codexOutputDebounceInterval = .milliseconds(500)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    ptyManager.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n".utf8)
    )
    try await waitUntil { vm.hasProducedOutput }

    // 1 チャンク目の debounce(500ms) が満了する前に 2 チャンク目が到着するとタイマーが
    // リセットされ、最初のチャンクから 500ms 経過時点でもまだ評価されない。
    try await Task.sleep(for: .milliseconds(200))
    ptyManager.emitOutput(for: sessionID, data: Data("1. Yes, continue\r\n".utf8))
    try await Task.sleep(for: .milliseconds(200))
    #expect(!ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" })

    // 出力が静止すると最終チャンク基準の 500ms 後に 1 回だけ評価される。
    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" }
    }
    let enterWrites = ptyManager.writtenCalls.filter { String(decoding: $0.0, as: UTF8.self) == "\r" }
    #expect(enterWrites.count == 1)
}

@Test @MainActor
func claudeSession_doesNotAutoAnswerTrustPrompt() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // Claude には信頼プロンプト処理を適用しない（agentKind ガード）。同じ文言が出ても Enter は送らない。
    ptyManager.emitOutput(
        for: sessionID,
        data: Data("Do you trust the contents of this directory?\r\n".utf8)
    )
    try await waitUntil { vm.hasProducedOutput }
    try await Task.sleep(for: .milliseconds(100))

    #expect(!ptyManager.writtenCalls.contains { String(decoding: $0.0, as: UTF8.self) == "\r" })
}

@Test @MainActor
func isReadyForInput_viaHook_requiresHookAndSettledOutput() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    hookContinuation.yield((sessionID, .sessionStart))
    try await waitUntil { vm.status == .idle }

    // フック受信済みでも出力ゼロでは ready にならない。
    #expect(vm.isReadyForInput == false)

    ptyManager.emitOutput(for: sessionID, data: Data("banner\n".utf8))
    try await waitUntil { vm.hasProducedOutput }

    // 出力直後はまだ settle していない。
    #expect(vm.isReadyForInput == false)

    try await Task.sleep(for: .milliseconds(500))
    #expect(vm.isReadyForInput == true)
}

@Test @MainActor
func isReadyForInput_viaHook_outputAloneWithoutSessionStartIsNotReady() async throws {
    // バグ回帰: 起動バナー（初回出力）だけで ready 扱いになり、TUI 起動完了前の
    // send が破棄されていた。SessionStart フック未受信なら settle 後も ready にしない。
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    ptyManager.emitOutput(for: sessionID, data: Data("banner\n".utf8))
    try await waitUntil { vm.hasProducedOutput }

    try await Task.sleep(for: .milliseconds(500))
    #expect(vm.status == .starting)
    #expect(vm.isReadyForInput == false)
}

@Test @MainActor
func spawnIfNeeded_claudeCode_staysStartingUntilHook() async throws {
    // Claude Code は hooks 駆動。spawn だけでは running にならず starting のまま。
    let sessionID = SessionID()
    let (vm, ptyManager, _, spawnRequest) = makeSessionViewModel(sessionID: sessionID, kind: .claudeCode)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // spawn 後しばらく待っても hooks が来ない限り starting を維持する。
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .starting)
    #expect(spawnRequest.statusBootstrap == .viaHook)
}

// MARK: - restart

@Test @MainActor
func restart_respawnsWithNewWorkingDirectory() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)

    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    let secondCall = try #require(ptyManager.spawnCalls.last)
    #expect(secondCall.workingDirectory == "/new/dir")
    #expect(secondCall.id == sessionID)
}

@Test @MainActor
func workspaceName_returnsBasenameAndUpdatesAfterRestart() async throws {
    let (vm, ptyManager, _, _) = makeSessionViewModel()

    // 初期 workingDirectory "/tmp/workspace" の末尾ディレクトリ名とフルパス。
    #expect(vm.workspaceName == "workspace")
    #expect(vm.workspacePath == "/tmp/workspace")

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // restart で workingDirectory が差し替わると表示も追従する（spawnRequest 経由の @Observable 更新）。
    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/Users/example/Projects/koi-mentor", hookEvents: newStream)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    #expect(vm.workspaceName == "koi-mentor")
    #expect(vm.workspacePath == "/Users/example/Projects/koi-mentor")
}

@Test @MainActor
func restart_killsOldProcessBeforeRespawn() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)

    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    #expect(ptyManager.killedIDs == [sessionID])
    #expect(ptyManager.spawnCalls.count == 2)
}

@Test @MainActor
func restart_keepsSameCoordinator() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let coordinatorBefore = vm.terminalCoordinator
    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)

    #expect(vm.terminalCoordinator === coordinatorBefore)
}

@Test @MainActor
func restart_resetsStatusToStarting() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, hookContinuation, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // 初回は running に遷移させてから、restart が starting へ戻すことを確認する。
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }

    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)

    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    #expect(vm.status == .starting)
}

@Test @MainActor
func restart_exitTaskBoundToNewStreamAfterRespawn() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)

    // 再 spawn 完了を待ってから emitExit する（MockPTYManager は spawn 毎に exit stream を
    // 登録し、emitExit(for:code:) は最新世代の continuation へ発火するため、最新 stream へ
    // 届けるには 2 回目の spawn 完了を待つ必要がある）。
    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    ptyManager.emitExit(for: sessionID, code: 0)

    try await waitUntil { vm.status == .completed(exitCode: 0) }
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func restart_staleExitFromOldGenerationDoesNotCorruptNewSession() async throws {
    let sessionID = SessionID()
    let (vm, ptyManager, _, _) = makeSessionViewModel(sessionID: sessionID)

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let (newStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    await vm.restart(workingDirectory: "/new/dir", hookEvents: newStream)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    // 実機で旧プロセスが SIGTERM 後に遅れて exit したのと同じく、初回 spawn 世代(=0) の
    // exit continuation へ非ゼロ code を発火する。旧 exitTask は restart の kill() で
    // cancel 済みのため、この旧世代 exit は孤児 stream に届くだけで再起動後の status を汚染しない。
    ptyManager.emitExit(for: sessionID, spawnGeneration: 0, code: 137)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .starting)  // .error(exit code 137) に汚染されていない

    // 一方、新世代(=1) の exit は最新 exitTask が購読しており、completed へ正しく遷移する
    // （旧世代を流したことで新世代の購読が壊れていないことも併せて担保する）。
    ptyManager.emitExit(for: sessionID, spawnGeneration: 1, code: 0)
    try await waitUntil { vm.status == .completed(exitCode: 0) }
    #expect(vm.status == .completed(exitCode: 0))
}

@Test @MainActor
func displayName_emptyName_fallsBackToShortID() {
    let sessionID = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)
    let (vm, _, _, _) = makeSessionViewModel(sessionID: sessionID)

    #expect(vm.displayName == "#F83921")
}

@Test @MainActor
func displayName_withName_returnsName() {
    let sessionID = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)
    let (vm, _, _, _) = makeSessionViewModel(sessionID: sessionID)

    vm.name = "My Session"

    #expect(vm.displayName == "My Session")
}

@Test @MainActor
func displayName_whitespaceOnlyName_fallsBackToShortID() {
    let sessionID = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)
    let (vm, _, _, _) = makeSessionViewModel(sessionID: sessionID)

    vm.name = "   "

    #expect(vm.displayName == "#F83921")
}

@Test @MainActor
func shortID_returnsHashPrefixedUUIDPrefix() {
    let sessionID = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)

    #expect(SessionViewModel.shortID(for: sessionID) == "#F83921")
}

@Test @MainActor
func outputTask_capturesRawBytesWhenDebugDumpEnabled() async throws {
    let sessionID = SessionID(rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!)
    let sessionLabel = String(sessionID.rawValue.uuidString.prefix(6))
    let captureURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Phlox", isDirectory: true)
        .appendingPathComponent("cursor-raw-\(sessionLabel).bin")
    defer { try? FileManager.default.removeItem(at: captureURL) }

    let ptyManager = MockPTYManager()
    let spawnRequest = SessionViewModel.SpawnRequest(
        command: "/usr/local/bin/agent",
        args: [],
        env: ["TERM": "xterm-256color"],
        workingDirectory: "/tmp/workspace",
        kind: .cursor,
        statusBootstrap: .idleOnSpawnComplete,
        debugDump: true
    )
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: ptyManager,
        hookEvents: hookStream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: spawnRequest
    )

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let payload = Data([0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68, 0x48, 0x65, 0x6C, 0x6C, 0x6F])
    ptyManager.emitOutput(for: sessionID, data: payload)

    try await waitUntil {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: captureURL.path),
              let size = attrs[.size] as? Int else { return false }
        return size >= 6
    }

    let captured = try Data(contentsOf: captureURL)
    #expect(captured.prefix(6) == payload.prefix(6))
}
