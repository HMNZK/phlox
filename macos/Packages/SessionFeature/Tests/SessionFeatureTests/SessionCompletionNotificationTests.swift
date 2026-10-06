import Foundation
import Testing
import os
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
import TerminalUI
@testable import SessionFeature

// 「セッションが完了・待機しているのに通知が来ない」取りこぼし遷移を塞ぐ。
//   (1) 承認待ち・質問待ちの間に turnCompleted が届いても完了通知を出す
//   (2) pty 型はプロセス終了（completed/error）も完了通知の対象にする
//   (3) Codex のライブターン中の idle 報告は無視し、完了通知は turnCompleted からちょうど1回だけ出す（ADR 0064）
//   (4) 終了コード・承認カード・入力欄の送信保留など、プロセス終了まわりの表示と通知
// 既存の意図的な無通知（interrupt 由来 idle・復元リプレイ・連続 awaiting）は維持する。

// MARK: - ハーネス

private final class NotifyFakeAgentClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

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
private func makeViewModel(
    notifier: MockRemoteSessionNotifier
) -> (ChatSessionViewModel, NotifyFakeAgentClient) {
    let client = NotifyFakeAgentClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notify-gap-test"
    )
    vm.remoteSessionNotifier = notifier
    return (vm, client)
}

// MARK: - 取りこぼし遷移 (1): 待機中に届いた turnCompleted

@Test @MainActor
func turnCompletedWhileAwaitingApproval_firesSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve?")
    #expect(notifier.approvalPendingCalls.count == 1)

    // 承認待ちのまま turn が終わった（承認不要になった・turn 側で決着した）場合も
    // 「本物のターン完了」として完了通知を出すこと。
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "承認待ち経由の完了で通知が取りこぼされないこと")
}

@Test @MainActor
func turnCompletedWhileAwaitingUserQuestion_firesSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.userQuestionRequested(requestId: "req-1", questions: [
        ChatUserQuestion(question: "どちらにしますか?", header: "選択", options: [], multiSelect: false),
    ]))
    try await waitUntil { vm.status == .awaitingUserQuestion }

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "質問待ち経由の完了で通知が取りこぼされないこと")
}

// MARK: - 過剰通知の禁止（既存の意図的無通知の維持）

@Test @MainActor
func turnInterruptedAfterAwaitingApproval_doesNotFireSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve?")

    // ユーザー起点の中断（esc・拒否）で idle 化しても完了通知は出さないこと。
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty, "interrupt 由来の idle 遷移では鳴らさない（既存仕様の維持）")
}

@Test @MainActor
func duplicateTurnCompleted_firesSessionCompletedOnlyOnce() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "idle 中の重複 turnCompleted で多重通知しないこと")
}

// MARK: - 取りこぼし遷移 (2): pty 型のプロセス終了（純ポリシー）

@Suite("Completion notification policy")
struct CompletionNotificationPolicyTests {

    @Test("running からの実効的な停止（idle・プロセス終了・エラー終了）は通知対象")
    func runningToTerminalStatesNotify() {
        #expect(SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .idle))
        #expect(
            SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .completed(exitCode: 0)),
            "実行中のプロセス終了（completed）は完了として通知すること（現行の取りこぼし）"
        )
        #expect(
            SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .error(message: "boom")),
            "実行中の異常終了（error）も要対応の停止として通知すること（現行の取りこぼし）"
        )
    }

    @Test("実行を経ない遷移・状態の継続は通知しない")
    func nonRunningTransitionsStaySilent() {
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .starting, next: .idle))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .starting, next: .completed(exitCode: 0)))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .idle, next: .idle))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .idle, next: .running))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .running))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(
            previous: .running, next: .awaitingApproval(prompt: "p")
        ), "承認待ち入りは完了ではない（awaiting 系の通知は別経路）")
    }
}

// MARK: - Codex・pty・プロセス終了まわり

private enum CompletionNotificationFakeError: Error {
    case unsupported
}

private final class CompletionNotificationCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let resumesActiveThread: Bool

    init(resumesActiveThread: Bool = false) {
        self.resumesActiveThread = resumesActiveThread
        var capturedEvents: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { capturedEvents = $0 }
        eventContinuation = capturedEvents!

        var capturedThreadEvents: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { capturedThreadEvents = $0 }
        threadEventContinuation = capturedThreadEvents!
    }

    func yield(_ event: NormalizedChatEvent) { eventContinuation.yield(event) }
    func yield(_ event: ThreadEvent) { threadEventContinuation.yield(event) }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        eventContinuation.finish()
        threadEventContinuation.finish()
    }

    func activeThreadId() async -> String? { "t1" }
    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try decode(#"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#)
    }
    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try decode(#"{"thread":{"id":"t1","status":{"type":"idle"}}}"#)
    }
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        guard resumesActiveThread else { throw CompletionNotificationFakeError.unsupported }
        return try decode(#"{"thread":{"id":"t1","status":{"type":"active"}}}"#)
    }
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        guard resumesActiveThread else { throw CompletionNotificationFakeError.unsupported }
        return try decode(#"{"thread":{"id":"t1","status":{"type":"active"},"turns":[]}}"#)
    }
    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try decode(#"{"data":[]}"#)
    }
    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try decode(#"{"data":[]}"#)
    }
    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try decode(#"{"data":[]}"#)
    }
    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        ThreadSettingsUpdateResponse()
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

@MainActor
private func waitForCompletionNotification(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        elapsed += 5_000_000
    }
}

private final class CompletionNotificationPTYManager: PTYManagerProtocol, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var outputStreams: [SessionID: AsyncStream<Data>] = [:]
        var exitStreams: [SessionID: AsyncStream<Int32>] = [:]
        var exitContinuations: [SessionID: AsyncStream<Int32>.Continuation] = [:]
        var spawnedIDs: Set<SessionID> = []
    }

    var didSpawn: Bool { state.withLock { !$0.spawnedIDs.isEmpty } }

    func emitExit(_ code: Int32, for id: SessionID) {
        _ = state.withLock { $0.exitContinuations[id]?.yield(code) }
    }

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        let id = id ?? SessionID()
        let (outputStream, _) = AsyncStream<Data>.makeStream()
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        state.withLock {
            $0.outputStreams[id] = outputStream
            $0.exitStreams[id] = exitStream
            $0.exitContinuations[id] = exitContinuation
            $0.spawnedIDs.insert(id)
        }
        return id
    }

    func write(_ data: Data, to id: SessionID) async throws {}
    func kill(_ id: SessionID) async {}
    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {}
    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        state.withLock { $0.outputStreams[id] } ?? AsyncStream { $0.finish() }
    }
    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        state.withLock { $0.exitStreams[id] } ?? AsyncStream { $0.finish() }
    }
}

// ADR 0064: ライブターン進行中の非同期 idle 報告は無視し（インジケータ維持・誤通知禁止）、
// 完了通知は正である turnCompleted からちょうど1回だけ出る。
@Test @MainActor
func codexMidTurnIdleIsIgnored_turnCompletedFiresOnce() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = MockRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.turnStarted)
    try await waitForCompletionNotification { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .running)
    #expect(notifier.sessionCompletedCalls.isEmpty)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitForCompletionNotification { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func chatErrorWhileRunning_firesSessionCompleted() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = MockRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.turnStarted)
    try await waitForCompletionNotification { vm.status == .running }

    client.yield(.error(message: "boom"))
    try await waitForCompletionNotification {
        if case .error = vm.status { return true }
        return false
    }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func codexSystemErrorWhileRunning_firesSessionCompleted() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = MockRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.turnStarted)
    try await waitForCompletionNotification { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .systemError))
    try await waitForCompletionNotification {
        if case .error = vm.status { return true }
        return false
    }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func restoredActiveCodexThreadIdle_firesSessionCompleted() async throws {
    let client = CompletionNotificationCodexClient(resumesActiveThread: true)
    let notifier = MockRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    await vm.restore(
        threadId: "t1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )
    try await waitForCompletionNotification { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForCompletionNotification { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

// 復元推定ターン（ライブの turnStarted なし）の idle 終端は通知するが、その後の
// active/idle フラッピングで二重通知しない。
@Test @MainActor
func restoredThreadStatusFlapping_firesSessionCompletedOnlyOnce() async throws {
    let client = CompletionNotificationCodexClient(resumesActiveThread: true)
    let notifier = MockRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    await vm.restore(
        threadId: "t1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )
    try await waitForCompletionNotification { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForCompletionNotification { vm.status == .idle }
    client.yield(.threadStatusChanged(threadId: "t1", status: .active(flags: [])))
    try await waitForCompletionNotification { vm.status == .running }
    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForCompletionNotification { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func ptyProcessExit_firesSessionCompleted() async throws {
    let sessionID = SessionID()
    let ptyManager = CompletionNotificationPTYManager()
    let notifier = MockRemoteSessionNotifier()
    let (hooks, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: ptyManager,
        hookEvents: hooks,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: .init(
            command: "/usr/local/bin/claude",
            args: [],
            env: [:],
            workingDirectory: "/tmp/phlox-notification-gap"
        )
    )
    vm.remoteSessionNotifier = notifier

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitForCompletionNotification { ptyManager.didSpawn }
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitForCompletionNotification { vm.status == .running }

    ptyManager.emitExit(0, for: sessionID)
    try await waitForCompletionNotification { vm.status == .completed(exitCode: 0) }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

// C-60: ターミナル型のプロセスが 0 以外で終わったら、実行中でなくても終了コードを添えて知らせる。
@Test @MainActor
func ptyNonZeroExit_sendsTheExitCodeEvenWhenIdle() async throws {
    let sessionID = SessionID()
    let ptyManager = CompletionNotificationPTYManager()
    let notifier = KindRecordingRemoteSessionNotifier()
    let (hooks, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: sessionID,
        ptyManager: ptyManager,
        hookEvents: hooks,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: .init(
            command: "/usr/local/bin/claude",
            args: [],
            env: [:],
            workingDirectory: "/tmp/phlox-notification-gap"
        )
    )
    vm.remoteSessionNotifier = notifier

    await vm.start()
    vm.terminalCoordinator.onResize(80, 24)
    try await waitForCompletionNotification { ptyManager.didSpawn }

    ptyManager.emitExit(2, for: sessionID)
    try await waitForCompletionNotification { vm.status == .error(message: "exit code 2") }

    #expect(notifier.kinds == [.exited(code: 2)])
}

// 04 B3: チャットのプロセスが自分で終わったら、入力欄の代わりに出す終了コードを持ち、0 以外は「終了」を知らせる。
@Test @MainActor
func chatProcessNonZeroExit_marksEndedAndSendsTheExitCode() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = KindRecordingRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.processExit == nil)
    client.yield(.processExited(exitCode: 3))
    try await waitForCompletionNotification { notifier.kinds.contains(.exited(code: 3)) }

    #expect(vm.processExit == ChatProcessExit(exitCode: 3))
    #expect(vm.status == .error(message: "exit code 3"))
    #expect(notifier.kinds == [.exited(code: 3)])
}

@Test @MainActor
func chatProcessZeroExit_isCompletedWithoutAnExitNotification() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = KindRecordingRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.processExited(exitCode: 0))
    try await waitForCompletionNotification { vm.status == .completed(exitCode: 0) }

    #expect(vm.status == .completed(exitCode: 0))
    #expect(!notifier.kinds.contains(.exited(code: 0)))
}

// 死因のエラーが先に届いた（Claude の途中終了）なら、そのエラー表示を残し、「終了」を重ねて送らない。
@Test @MainActor
func chatProcessExitAfterError_keepsTheErrorAndDoesNotNotifyTwice() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = KindRecordingRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.turnStarted)
    try await waitForCompletionNotification { vm.status == .running }
    client.yield(.error(message: "process ended"))
    client.yield(.processExited(exitCode: 1))
    try await waitForCompletionNotification { vm.processExit != nil }

    #expect(vm.status == .error(message: "process ended"))
    #expect(!notifier.kinds.contains(.exited(code: 1)))
}

// 実行中でないときのエラーは通知されないので、その後の 0 以外の終了は終了コードつきで知らせる。
@Test @MainActor
func chatProcessExitAfterAnUnnotifiedError_sendsTheExitCode() async throws {
    let client = CompletionNotificationCodexClient()
    let notifier = KindRecordingRemoteSessionNotifier()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    vm.remoteSessionNotifier = notifier

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.error(message: "idle failure"))
    client.yield(.processExited(exitCode: 2))
    try await waitForCompletionNotification { notifier.kinds.contains(.exited(code: 2)) }

    #expect(vm.status == .error(message: "idle failure"))
    #expect(notifier.kinds == [.exited(code: 2)])
}

// 終了コードが取れないときは、成功（完了）とは表示しない。
@Test @MainActor
func chatProcessExitWithoutACode_isNotShownAsCompleted() async throws {
    let client = CompletionNotificationCodexClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notification-gap"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.processExited(exitCode: nil))
    try await waitForCompletionNotification { vm.status == .error(message: "process exited") }

    #expect(vm.status == .error(message: "process exited"))
}

// 承認を待っている間にプロセスが終わったら、答えられない承認カードを残さない。
@Test @MainActor
func chatProcessExitWhileAwaitingApproval_dropsTheApprovalCard() async throws {
    let client = CompletionNotificationCodexClient()
    let broker = ChatApprovalBroker()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    let json = """
    {"threadId":"t","turnId":"u","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}
    """
    let request = try JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data(json.utf8))
    let handler = broker.serverRequestHandler
    let wire = Task { try? await handler(.commandExecutionApproval(request)) }
    try await waitForCompletionNotification { !vm.replyApprovals.isEmpty }

    client.yield(.processExited(exitCode: 1))
    try await waitForCompletionNotification { vm.processExit != nil }

    let dropped = vm.replyApprovals.isEmpty
    #expect(dropped)
    // 残っていたら、下の待ちで止まらないようにテスト側で決着させる。
    if !dropped { await broker.respond(to: vm.pendingApprovals[0].id, decision: .accept) }
    // 待っていた承認は否認で決着する（ぶら下がったままにしない）。
    #expect(await wire.value?["decision"]?.stringValue == "decline")
}

// 承認のカードが出る前に終了が届いても、あとから承認のカードを出さない。
@Test @MainActor
func approvalQueuedBeforeTheExitIsNotShownAfterIt() async throws {
    let client = CompletionNotificationCodexClient()
    let broker = ChatApprovalBroker()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    let json = """
    {"threadId":"t","turnId":"u","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}
    """
    let request = try JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data(json.utf8))
    let handler = broker.serverRequestHandler
    // 承認は受け取りの列に積まれたが、画面の処理より先に終了が届く順にする。
    client.yield(.processExited(exitCode: 1))
    let wire = Task { try? await handler(.commandExecutionApproval(request)) }
    try await waitForCompletionNotification { vm.processExit != nil }
    let decision = await wire.value?["decision"]?.stringValue
    for _ in 0..<20 { await Task.yield() }

    #expect(decision == "decline")
    #expect(vm.replyApprovals.isEmpty)
}

// 05 R6: 承認を待っている間は入力できるが送らない。承認に答えたら送れる。
@Test @MainActor
func replyArea_sendIsHeldWhileAnApprovalIsPending() async throws {
    let client = CompletionNotificationCodexClient()
    let broker = ChatApprovalBroker()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-notification-gap"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    let json = """
    {"threadId":"t","turnId":"u","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}
    """
    let request = try JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data(json.utf8))
    let handler = broker.serverRequestHandler
    let wire = Task { try? await handler(.commandExecutionApproval(request)) }
    try await waitForCompletionNotification { !vm.replyApprovals.isEmpty }

    vm.draft = "次はテストも"
    #expect(vm.consumeDraftForSend() == nil)
    #expect(vm.draft == "次はテストも")

    await vm.respondToApproval(vm.pendingApprovals[0].id, decision: .accept)
    #expect(vm.consumeDraftForSend() == "次はテストも")
    _ = await wire.value
}
