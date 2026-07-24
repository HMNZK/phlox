import Foundation
import Testing
import os
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
import TerminalUI
@testable import SessionFeature

private enum NotificationGapFakeError: Error {
    case unsupported
}

private final class NotificationGapCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
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
        guard resumesActiveThread else { throw NotificationGapFakeError.unsupported }
        return try decode(#"{"thread":{"id":"t1","status":{"type":"active"}}}"#)
    }
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        guard resumesActiveThread else { throw NotificationGapFakeError.unsupported }
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
private func waitForNotificationGap(
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

private final class NotificationGapPTYManager: PTYManagerProtocol, @unchecked Sendable {
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
func notificationGap_codexMidTurnIdleIsIgnored_turnCompletedFiresOnce() async throws {
    let client = NotificationGapCodexClient()
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
    try await waitForNotificationGap { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(vm.status == .running)
    #expect(notifier.sessionCompletedCalls.isEmpty)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitForNotificationGap { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func notificationGap_chatErrorWhileRunning_firesSessionCompleted() async throws {
    let client = NotificationGapCodexClient()
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
    try await waitForNotificationGap { vm.status == .running }

    client.yield(.error(message: "boom"))
    try await waitForNotificationGap {
        if case .error = vm.status { return true }
        return false
    }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func notificationGap_codexSystemErrorWhileRunning_firesSessionCompleted() async throws {
    let client = NotificationGapCodexClient()
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
    try await waitForNotificationGap { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .systemError))
    try await waitForNotificationGap {
        if case .error = vm.status { return true }
        return false
    }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func notificationGap_restoredActiveCodexThreadIdle_firesSessionCompleted() async throws {
    let client = NotificationGapCodexClient(resumesActiveThread: true)
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
    try await waitForNotificationGap { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForNotificationGap { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

// 復元推定ターン（ライブの turnStarted なし）の idle 終端は通知するが、その後の
// active/idle フラッピングで二重通知しない。
@Test @MainActor
func notificationGap_restoredThreadStatusFlapping_firesSessionCompletedOnlyOnce() async throws {
    let client = NotificationGapCodexClient(resumesActiveThread: true)
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
    try await waitForNotificationGap { vm.status == .running }

    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForNotificationGap { vm.status == .idle }
    client.yield(.threadStatusChanged(threadId: "t1", status: .active(flags: [])))
    try await waitForNotificationGap { vm.status == .running }
    client.yield(.threadStatusChanged(threadId: "t1", status: .idle))
    try await waitForNotificationGap { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1)
}

@Test @MainActor
func notificationGap_ptyProcessExit_firesSessionCompleted() async throws {
    let sessionID = SessionID()
    let ptyManager = NotificationGapPTYManager()
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
    try await waitForNotificationGap { ptyManager.didSpawn }
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitForNotificationGap { vm.status == .running }

    ptyManager.emitExit(0, for: sessionID)
    try await waitForNotificationGap { vm.status == .completed(exitCode: 0) }

    #expect(notifier.sessionCompletedCalls.count == 1)
}
