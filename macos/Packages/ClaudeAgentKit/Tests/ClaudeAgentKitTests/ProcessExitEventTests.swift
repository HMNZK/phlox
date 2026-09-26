import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// 04 B3: CLI プロセスが自分で終わったら、終了コードつきの processExited を流す。

private final class ExitingTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>
    let exitCode: Int32

    init(exitCode: Int32) {
        self.exitCode = exitCode
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func terminationStatus() async -> Int32? { exitCode }
    func exit() { continuation?.finish() }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { items.append(event) } }
    var all: [NormalizedChatEvent] { lock.withLock { items } }
}

private func makeClient(_ transport: ExitingTransport) -> (ClaudeChatClient, Events, Task<Void, Never>) {
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let task = Task { for await event in stream { events.append(event) } }
    return (client, events, task)
}

@Test func idleProcessExitYieldsTheExitCode() async throws {
    let transport = ExitingTransport(exitCode: 5)
    let (client, events, task) = makeClient(transport)
    await client.start()

    transport.exit()
    for _ in 0..<200 where !events.all.contains(.processExited(exitCode: 5)) {
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(events.all.contains(.processExited(exitCode: 5)))
    await client.close()
    task.cancel()
}

private enum HealStartError: Error { case failed }

/// 1 本目は「使用中」で落ち、自己修復の 2 本目は起動に失敗する。
private final class HealFailingTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>
    let failsToStart: Bool
    let failsToSend: Bool

    init(failsToStart: Bool, failsToSend: Bool = false) {
        self.failsToStart = failsToStart
        self.failsToSend = failsToSend
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws { if failsToStart { throw HealStartError.failed } }
    func send(_ data: Data) async throws { if failsToSend { throw HealStartError.failed } }
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { "Error: Session ID is already in use" }
    func terminationStatus() async -> Int32? { 7 }
    func exit() { continuation?.finish() }
}

@Test func failedSelfHealYieldsTheOriginalExitCode() async throws {
    let first = HealFailingTransport(failsToStart: false)
    let transports = [first, HealFailingTransport(failsToStart: true)]
    let index = OSAllocatedUnfairLockBox()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "d4d4d4d4-4444-4444-8444-444444444444"],
        transportFactory: { _, _, _, _ in transports[index.next()] }
    )
    let events = Events()
    let stream = client.events
    let task = Task { for await event in stream { events.append(event) } }
    await client.start()
    try await client.turnStart([.text("turn")])

    first.exit()
    for _ in 0..<200 where !events.all.contains(.processExited(exitCode: 7)) {
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(events.all.contains { if case .error(let message) = $0 { message.contains("self-heal") } else { false } })
    #expect(events.all.contains(.processExited(exitCode: 7)))
    await client.close()
    task.cancel()
}

private final class OSAllocatedUnfairLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value = min(value + 1, 1) }; return value } }
}

// 修復用のプロセスが起動し、ターンの再送だけ失敗したときは、プロセスは動いているので終了にしない。
@Test func selfHealWhoseReplayFailsDoesNotYieldProcessExited() async throws {
    let first = HealFailingTransport(failsToStart: false)
    let transports = [first, HealFailingTransport(failsToStart: false, failsToSend: true)]
    let index = OSAllocatedUnfairLockBox()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "e5e5e5e5-5555-4555-8555-555555555555"],
        transportFactory: { _, _, _, _ in transports[index.next()] }
    )
    let events = Events()
    let stream = client.events
    let task = Task { for await event in stream { events.append(event) } }
    await client.start()
    try await client.turnStart([.text("turn")])

    first.exit()
    for _ in 0..<200 where !events.all.contains(where: { if case .error = $0 { true } else { false } }) {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    // エラーの直後に流れる終了があれば、ここまでに届く。
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(events.all.contains { if case .error(let message) = $0 { message.contains("self-heal") } else { false } })
    #expect(!events.all.contains { if case .processExited = $0 { true } else { false } })
    await client.close()
    task.cancel()
}

/// 終了コードを返す前に、テストが放すまで待つ。
private final class GatedExitTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var waiting = false
    let receivedLines: AsyncStream<Data>
    let gate: AsyncStream<Void>
    let release: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
        (gate, release) = AsyncStream<Void>.makeStream()
    }

    var isWaitingForStatus: Bool { lock.withLock { waiting } }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func terminationStatus() async -> Int32? {
        lock.withLock { waiting = true }
        for await _ in gate { break }
        return 3
    }
    func exit() { continuation?.finish() }
}

// 古いプロセスの終了コードを待つ間に次の送信で新しいプロセスが起動したら、古い終了は知らせない。
@Test func exitOfTheOldProcessIsNotReportedAfterTheNextTurnRespawns() async throws {
    let first = GatedExitTransport()
    let transports: [any LineDelimitedTransport] = [first, ExitingTransport(exitCode: 0)]
    let index = OSAllocatedUnfairLockBox()
    let spawns = SpawnCounter()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "f6f6f6f6-6666-4666-8666-666666666666"],
        transportFactory: { _, _, _, _ in spawns.increment(); return transports[index.next()] }
    )
    let events = Events()
    let stream = client.events
    let task = Task { for await event in stream { events.append(event) } }
    await client.start()

    first.exit()
    for _ in 0..<200 where !first.isWaitingForStatus {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(first.isWaitingForStatus)
    try await client.turnStart([.text("next")])
    #expect(spawns.count == 2)
    first.release.yield()
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(!events.all.contains { if case .processExited = $0 { true } else { false } })
    await client.close()
    task.cancel()
}

private final class SpawnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// 実物と同じく、閉じると（SIGTERM で）すぐ終わり、終了を待つ間だけ close() から戻らない。
private final class SlowCloseTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async {
        continuation?.finish()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    func terminationStatus() async -> Int32? { 143 }
}

// 設定の変更を反映するために古いプロセスを閉じて起動し直しても、その終了（143）をセッションの終了として知らせない。
@Test func respawnForNewSettingsDoesNotReportTheClosedProcessAsExited() async throws {
    let transports: [any LineDelimitedTransport] = [SlowCloseTransport(), ExitingTransport(exitCode: 0)]
    let index = OSAllocatedUnfairLockBox()
    let spawns = SpawnCounter()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "a7a7a7a7-7777-4777-8777-777777777777"],
        transportFactory: { _, _, _, _ in spawns.increment(); return transports[index.next()] }
    )
    let events = Events()
    let stream = client.events
    let task = Task { for await event in stream { events.append(event) } }
    await client.start()

    await client.updateSettings(model: "sonnet", permissionMode: nil, effort: "high")
    try await client.turnStart([.text("next")])
    #expect(spawns.count == 2)
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(!events.all.contains { if case .processExited = $0 { true } else { false } })
    await client.close()
    task.cancel()
}
