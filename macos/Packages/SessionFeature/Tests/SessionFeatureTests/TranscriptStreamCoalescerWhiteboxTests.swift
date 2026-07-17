import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private actor InterruptGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class InterruptGateClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let interruptGate = InterruptGate()

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func waitUntilInterruptEntered() async {
        await interruptGate.waitUntilEntered()
    }

    func releaseInterrupt() async {
        await interruptGate.release()
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws { await interruptGate.enterAndWait() }
    func close() async { continuation.finish() }
}

private struct InterruptFailure: Error {}

/// interrupt() がゲート解放後に throw するクライアント（interrupt 失敗経路の順序検証用）。
private final class FailingInterruptClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let interruptGate = InterruptGate()

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func waitUntilInterruptEntered() async {
        await interruptGate.waitUntilEntered()
    }

    func releaseInterrupt() async {
        await interruptGate.release()
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {
        await interruptGate.enterAndWait()
        throw InterruptFailure()
    }
    func close() async { continuation.finish() }
}

private enum DualStreamFakeError: Error {
    case unsupported
}

private final class DualStreamCodexFake: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation

    init() {
        var capturedEvent: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { capturedEvent = $0 }
        eventContinuation = capturedEvent!

        var capturedThreadEvent: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { capturedThreadEvent = $0 }
        threadEventContinuation = capturedThreadEvent!
    }

    func yieldNormalized(_ event: NormalizedChatEvent) {
        eventContinuation.yield(event)
    }

    func yieldThread(_ event: ThreadEvent) {
        threadEventContinuation.yield(event)
    }

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
        throw DualStreamFakeError.unsupported
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        throw DualStreamFakeError.unsupported
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
private func makeViewModel(client: any StructuredAgentClient, agentRef: AgentRef = .builtin(.claudeCode)) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: agentRef,
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollIntervalNanoseconds: UInt64 = 5_000_000,
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

@MainActor
private func agentMessageText(_ vm: ChatSessionViewModel, id: String) -> String? {
    for item in vm.transcript {
        if case .agentMessage(let itemId, let text, _) = item, itemId == id {
            return text
        }
    }
    return nil
}

@MainActor
@Test
func streamCoalescer_barrierFlushesInOrderAndInvalidatesScheduledFlush() {
    var now = Date(timeIntervalSince1970: 10)
    var scheduled: [(TimeInterval, UInt64)] = []
    let coalescer = TranscriptStreamCoalescer(
        flushInterval: 0.05,
        now: { now },
        schedule: { delay, token in scheduled.append((delay, token)) }
    )

    coalescer.enqueue(itemId: "a", kind: .agent, delta: "one", rawEvent: "first")
    now = Date(timeIntervalSince1970: 11)
    coalescer.enqueue(itemId: "r", kind: .reasoning, delta: "two", rawEvent: "second")

    #expect(scheduled.count == 1)
    #expect(scheduled[0].0 == 0.05)
    let batch = coalescer.flushBarrier()
    #expect(batch?.deltas.map(\.itemId) == ["a", "r"])
    #expect(batch?.rawEvents == ["first", "second"])
    #expect(coalescer.flushScheduled(token: scheduled[0].1) == nil)
}

@MainActor
@Test
func streamCoalescer_latestEventTimeChangesOnlyAtFlushCadence() {
    var now = Date(timeIntervalSince1970: 20)
    var scheduledTokens: [UInt64] = []
    let coalescer = TranscriptStreamCoalescer(
        flushInterval: 0.08,
        now: { now },
        schedule: { _, token in scheduledTokens.append(token) }
    )

    coalescer.enqueue(itemId: "a", kind: .agent, delta: "1", rawEvent: "1")
    now = Date(timeIntervalSince1970: 21)
    coalescer.enqueue(itemId: "a", kind: .agent, delta: "2", rawEvent: "2")
    now = Date(timeIntervalSince1970: 22)
    coalescer.enqueue(itemId: "a", kind: .agent, delta: "3", rawEvent: "3")

    #expect(scheduledTokens.count == 1)
    let batch = coalescer.flushScheduled(token: scheduledTokens[0])
    #expect(batch?.latestEventAt == now)
    #expect(batch?.deltas.count == 3)
}

@MainActor
@Test
func streamCoalescer_invalidateDropsPendingDataAndRejectsStaleFlush() {
    var scheduledToken: UInt64?
    let coalescer = TranscriptStreamCoalescer(
        now: { Date(timeIntervalSince1970: 30) },
        schedule: { _, token in scheduledToken = token }
    )

    coalescer.enqueue(itemId: "a", kind: .agent, delta: "stale", rawEvent: "stale")
    let token = scheduledToken
    coalescer.invalidate()

    #expect(token != nil)
    #expect(coalescer.flushScheduled(token: token!) == nil)
    #expect(coalescer.flushBarrier() == nil)
}

@Test @MainActor
func interrupt_deltaArrivingDuringAwait_doesNotMutateAfterIdle() async throws {
    let client = InterruptGateClient()
    let vm = makeViewModel(client: client)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    let interrupt = Task { await vm.turnInterrupt() }
    await client.waitUntilInterruptEntered()

    client.yield(.agentMessageDelta(itemId: "late", "stale"))
    try await Task.sleep(nanoseconds: 10_000_000)
    await client.releaseInterrupt()

    await interrupt.value
    #expect(vm.status == .idle)
    let revisionAtIdle = vm.transcriptRevision

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(vm.transcriptRevision == revisionAtIdle)
}

/// interrupt 失敗時、await 中に先着していた delta がエラー項目より前に確定すること
/// （エラー追加前の barrier flush。stage2 差し戻し#1 の HIGH 指摘の回帰ガード）。
@Test @MainActor
func interruptFailure_errorItemIsOrderedAfterDeltasThatArrivedFirst() async throws {
    let client = FailingInterruptClient()
    let vm = makeViewModel(client: client)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    let interrupt = Task { await vm.turnInterrupt() }
    await client.waitUntilInterruptEntered()

    client.yield(.agentMessageDelta(itemId: "late", "先着"))
    // delta がイベント Task で coalescer へ enqueue される（未適用のまま保留される）猶予。
    try await Task.sleep(nanoseconds: 20_000_000)
    await client.releaseInterrupt()
    await interrupt.value

    let lateIndex = vm.transcript.firstIndex { $0.id == "late" }
    let errorIndex = vm.transcript.firstIndex {
        if case .error = $0 { return true } else { return false }
    }
    let late = try #require(lateIndex)
    let err = try #require(errorIndex)
    #expect(late < err, "先着 delta がエラー項目の後ろへ挿入された（順序逆転）")
}

@Test @MainActor
func codex_itemCompletedDoesNotDuplicatePendingDelta() async throws {
    let client = DualStreamCodexFake()
    let vm = makeViewModel(client: client, agentRef: .builtin(.codex))
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yieldNormalized(.agentMessageDelta(itemId: "a1", "Hello"))
    try await Task.sleep(nanoseconds: 10_000_000)

    let item = try JSONDecoder().decode(
        ThreadItem.self,
        from: Data(#"{"id":"a1","type":"agentMessage","text":"Hello"}"#.utf8)
    )
    client.yieldThread(.itemCompleted(threadId: "t1", turnId: "turn1", item: item))

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(agentMessageText(vm, id: "a1") == "Hello")
}
