// Whitebox: task-4 の正しさハザード（leading-edge スロットル・終了レース相当の await 完了・FIFO）。
// 受け入れテスト AcceptanceMidTurnPersistenceTests は編集禁止。こちらは内部経路を符号化する。

import Foundation
import os
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// MARK: - Doubles

private final class MidTurnFakeClient: StructuredAgentClient, @unchecked Sendable {
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

private final class TrackingTranscriptStore: TranscriptStore, @unchecked Sendable {
    private struct State {
        var items: [SessionID: [ChatItem]] = [:]
        var operations: [String] = []
        var upsertCount = 0
        var holdEnabled = false
        var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        var releaseWaiter: CheckedContinuation<Void, Never>?
        var insideHeldUpsert = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        state.withLock { $0.items[sessionID] ?? [] }
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        let shouldHold = state.withLock { $0.holdEnabled }
        if shouldHold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                state.withLock { state in
                    state.releaseWaiter = continuation
                    state.insideHeldUpsert = true
                    let waiters = state.enteredWaiters
                    state.enteredWaiters.removeAll()
                    waiters.forEach { $0.resume() }
                }
            }
            state.withLock { $0.insideHeldUpsert = false }
        }

        state.withLock { state in
            state.operations.append("upsert")
            state.upsertCount += 1
            var current = state.items[sessionID] ?? []
            for item in items {
                if let index = current.firstIndex(where: { $0.id == item.id }) {
                    current[index] = item
                } else {
                    current.append(item)
                }
            }
            state.items[sessionID] = current
        }
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        state.withLock { state in
            state.operations.append("replace")
            state.items[sessionID] = items
        }
    }

    func persistedItems(for sessionID: SessionID) -> [ChatItem] {
        state.withLock { $0.items[sessionID] ?? [] }
    }

    func upsertCount() -> Int {
        state.withLock { $0.upsertCount }
    }

    func operations() -> [String] {
        state.withLock { $0.operations }
    }

    func enableUpsertHold() {
        state.withLock { $0.holdEnabled = true }
    }

    func waitUntilUpsertEntered() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { state in
                if state.insideHeldUpsert {
                    continuation.resume()
                } else {
                    state.enteredWaiters.append(continuation)
                }
            }
        }
    }

    func releaseUpsert() {
        state.withLock { state in
            // One-shot hold: subsequent upserts must not block the drain path.
            state.holdEnabled = false
            state.releaseWaiter?.resume()
            state.releaseWaiter = nil
        }
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 5_000_000,
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
    store: TrackingTranscriptStore
) -> (ChatSessionViewModel, MidTurnFakeClient, SessionID) {
    let client = MidTurnFakeClient()
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-midturn-whitebox",
        transcriptStore: store
    )
    return (vm, client, sessionID)
}

// MARK: - Gate unit tests

@Suite("MidTurnPersistenceWhitebox: Gate")
@MainActor
struct MidTurnPersistenceWhiteboxGateTests {
    @Test
    func 先頭イベントは遅延なくflush判定になる() {
        let now = Date(timeIntervalSince1970: 100)
        var scheduled: [(TimeInterval, UInt64)] = []
        let gate = MidTurnPersistenceGate(
            interval: 1.0,
            eventThreshold: 10,
            now: { now },
            schedule: { delay, token in scheduled.append((delay, token)) }
        )

        #expect(gate.requestFlush() == true)
        #expect(scheduled.isEmpty)
    }

    @Test
    func 間隔内の後続はtrailingスケジュールになり即時flushしない() {
        var now = Date(timeIntervalSince1970: 100)
        var scheduled: [(TimeInterval, UInt64)] = []
        let gate = MidTurnPersistenceGate(
            interval: 1.0,
            eventThreshold: 10,
            now: { now },
            schedule: { delay, token in scheduled.append((delay, token)) }
        )

        #expect(gate.requestFlush() == true)
        now = Date(timeIntervalSince1970: 100.2)
        #expect(gate.requestFlush() == false)
        #expect(scheduled.count == 1)
        #expect(abs(scheduled[0].0 - 0.8) < 0.000_1)
    }

    @Test
    func 件数閾値で間隔内でも即時flushする() {
        var now = Date(timeIntervalSince1970: 100)
        let gate = MidTurnPersistenceGate(
            interval: 10.0,
            eventThreshold: 3,
            now: { now },
            schedule: { _, _ in }
        )

        #expect(gate.requestFlush() == true) // leading; counter resets
        now = Date(timeIntervalSince1970: 100.1)
        #expect(gate.requestFlush() == false) // eventsSinceFlush == 1
        #expect(gate.requestFlush() == false) // eventsSinceFlush == 2
        #expect(gate.requestFlush() == true)  // eventsSinceFlush == 3 → threshold
    }

    @Test
    func スケジュールtoken発火でtrailingflushが有効になる() {
        var now = Date(timeIntervalSince1970: 100)
        var scheduledToken: UInt64?
        let gate = MidTurnPersistenceGate(
            interval: 1.0,
            eventThreshold: 100,
            now: { now },
            schedule: { _, token in scheduledToken = token }
        )

        #expect(gate.requestFlush() == true)
        now = Date(timeIntervalSince1970: 100.1)
        #expect(gate.requestFlush() == false)
        let token = try! #require(scheduledToken)
        now = Date(timeIntervalSince1970: 101.0)
        #expect(gate.fireScheduled(token: token) == true)
        #expect(gate.fireScheduled(token: token) == false)
    }
}

// MARK: - Queue FIFO / await drain

@Suite("MidTurnPersistenceWhitebox: TranscriptPersistenceQueue FIFO")
@MainActor
struct MidTurnPersistenceWhiteboxQueueFIFOTests {
    @Test
    func upsertの後のreplaceはFIFO順を保つ() async throws {
        let store = TrackingTranscriptStore()
        store.enableUpsertHold()
        let sessionID = SessionID()
        let queue = TranscriptPersistenceQueue(sessionID: sessionID, store: store)

        queue.enqueueUpsert([
            .commandExecution(id: "a", command: "echo", output: "1", timestamp: Date())
        ])
        await store.waitUntilUpsertEntered()

        queue.enqueueReplace([
            .userMessage(id: "u", text: "kept", timestamp: Date())
        ])
        store.releaseUpsert()
        await queue.waitForPendingWrites()

        #expect(store.operations() == ["upsert", "replace"])
        let items = store.persistedItems(for: sessionID)
        #expect(items.count == 1)
        #expect(items.first?.id == "u")
    }

    @Test
    func waitForPendingWritesは待機中に追加された書き込みも排水する() async throws {
        let store = TrackingTranscriptStore()
        store.enableUpsertHold()
        let sessionID = SessionID()
        let queue = TranscriptPersistenceQueue(sessionID: sessionID, store: store)

        queue.enqueueUpsert([
            .agentMessage(id: "m1", text: "one", timestamp: Date())
        ])
        await store.waitUntilUpsertEntered()

        let waitTask = Task { @MainActor in
            await queue.waitForPendingWrites()
        }
        queue.enqueueUpsert([
            .agentMessage(id: "m2", text: "two", timestamp: Date())
        ])
        store.releaseUpsert()
        await waitTask.value

        #expect(store.upsertCount() == 2)
        let ids = store.persistedItems(for: sessionID).map(\.id)
        #expect(ids.contains("m1"))
        #expect(ids.contains("m2"))
    }
}

// MARK: - ViewModel integration

@Suite("MidTurnPersistenceWhitebox: ChatSessionViewModel")
@MainActor
struct MidTurnPersistenceWhiteboxViewModelTests {
    @Test
    func leadingEdgeで最初のバリアイベントは即時永続化される() async throws {
        let store = TrackingTranscriptStore()
        let (vm, client, sessionID) = makeViewModel(store: store)

        let now = Date(timeIntervalSince1970: 1_000)
        var scheduled: [(TimeInterval, UInt64)] = []
        vm.installMidTurnPersistenceForTesting(
            interval: 5.0,
            eventThreshold: 100,
            now: { now },
            schedule: { delay, token in scheduled.append((delay, token)) }
        )

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.commandExecution(itemId: "cmd-1", command: "swift build", outputDelta: "ok\n"))
        try await waitUntil {
            store.persistedItems(for: sessionID).contains { $0.id == "cmd-1" }
        }
        #expect(store.upsertCount() >= 1)
        #expect(scheduled.isEmpty)
    }

    @Test
    func スロットル中の後続バリアはtrailing発火まで追加upsertしない() async throws {
        let store = TrackingTranscriptStore()
        let (vm, client, sessionID) = makeViewModel(store: store)

        var now = Date(timeIntervalSince1970: 1_000)
        var scheduledToken: UInt64?
        vm.installMidTurnPersistenceForTesting(
            interval: 2.0,
            eventThreshold: 100,
            now: { now },
            schedule: { _, token in scheduledToken = token }
        )

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.commandExecution(itemId: "cmd-1", command: "a", outputDelta: "1\n"))
        try await waitUntil {
            store.persistedItems(for: sessionID).contains { $0.id == "cmd-1" }
        }
        let afterFirst = store.upsertCount()

        now = Date(timeIntervalSince1970: 1_000.1)
        client.yield(.fileChange(
            itemId: "file-1",
            [FilePatchChange(path: "A.swift", diff: "+a", kind: nil)]
        ))
        try await waitUntil { vm.transcript.contains { $0.id == "file-1" } }
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(store.upsertCount() == afterFirst)
        #expect(scheduledToken != nil)

        now = Date(timeIntervalSince1970: 1_002.0)
        vm.fireScheduledMidTurnPersistenceForTesting(token: scheduledToken!)
        try await waitUntil {
            store.persistedItems(for: sessionID).contains { $0.id == "file-1" }
        }
        #expect(store.upsertCount() > afterFirst)
    }

    @Test
    func flushTranscriptNowは保留deltaをバリアflushして書き切りを待つ() async throws {
        let store = TrackingTranscriptStore()
        let (vm, client, sessionID) = makeViewModel(store: store)

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.agentMessageDelta(itemId: "msg-1", "書きかけ"))
        // Give the event loop a tick; delta may still sit in the coalescer.
        try await Task.sleep(nanoseconds: 20_000_000)
        await vm.flushTranscriptNow()

        let text = store.persistedItems(for: sessionID).compactMap { item -> String? in
            if case .agentMessage(let id, let text, _) = item, id == "msg-1" { return text }
            return nil
        }.first
        #expect(text?.contains("書きかけ") == true)
    }
}

// MARK: - Termination flush race (stalled write must not hang reply)

/// upsert が実質永久に戻らない store。終了経路の timeout race 再現用。
private final class PermanentlyStallingTranscriptStore: TranscriptStore, @unchecked Sendable {
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { [] }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        // Never-resumed continuation は runtime 警告になるため、長 sleep で stall を模擬する。
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(60))
        }
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
}

@Suite("MidTurnPersistenceWhitebox: TerminationFlushRace")
@MainActor
struct MidTurnPersistenceWhiteboxTerminationFlushRaceTests {
    @Test
    func stalledWriteでもtimeout内に戻る() async {
        let store = PermanentlyStallingTranscriptStore()
        let sessionID = SessionID()
        let queue = TranscriptPersistenceQueue(sessionID: sessionID, store: store)
        queue.enqueueUpsert([
            .agentMessage(id: "stall", text: "never lands", timestamp: Date())
        ])

        let flushTask = Task { @MainActor in
            await queue.waitForPendingWrites()
        }

        let started = ContinuousClock.now
        await TerminationFlushRace.race(timeout: .milliseconds(80), against: flushTask)
        let elapsed = ContinuousClock.now - started

        // 80ms timeout + 余裕。TaskGroup 暗黙 await だと永久に戻らない。
        #expect(elapsed < .milliseconds(500))
    }

    @Test
    func flush完了がtimeoutより先なら即戻る() async {
        let store = TrackingTranscriptStore()
        let sessionID = SessionID()
        let queue = TranscriptPersistenceQueue(sessionID: sessionID, store: store)
        queue.enqueueUpsert([
            .agentMessage(id: "fast", text: "ok", timestamp: Date())
        ])

        let flushTask = Task { @MainActor in
            await queue.waitForPendingWrites()
        }

        let started = ContinuousClock.now
        await TerminationFlushRace.race(timeout: .seconds(5), against: flushTask)
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .milliseconds(500))
        #expect(store.upsertCount() == 1)
    }

    /// 直列 for-await だと先頭セッションの stall で後続が enqueue すらされない。
    /// `raceAllParallel` は全セッションを子タスクで同時起動するため、A が stall しても
    /// B は timeout 内に書き切れる（PhloxApp 終了 flush の再発防止）。
    @Test
    func セッションAがstallしてもセッションBはtimeout内にflushされる() async throws {
        let stallStore = PermanentlyStallingTranscriptStore()
        let okStore = TrackingTranscriptStore()
        let sessionA = SessionID()
        let sessionB = SessionID()
        let queueA = TranscriptPersistenceQueue(sessionID: sessionA, store: stallStore)
        let queueB = TranscriptPersistenceQueue(sessionID: sessionB, store: okStore)

        queueA.enqueueUpsert([
            .agentMessage(id: "a-stall", text: "never", timestamp: Date())
        ])
        queueB.enqueueUpsert([
            .agentMessage(id: "b-ok", text: "lands", timestamp: Date())
        ])

        let started = ContinuousClock.now
        await TerminationFlushRace.raceAllParallel(
            timeout: .milliseconds(120),
            bodies: [
                { await queueA.waitForPendingWrites() },
                { await queueB.waitForPendingWrites() },
            ]
        )
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .milliseconds(500))
        try await waitUntil { okStore.upsertCount() == 1 }
        #expect(okStore.upsertCount() == 1)
        #expect(okStore.persistedItems(for: sessionB).contains { $0.id == "b-ok" })
    }
}
