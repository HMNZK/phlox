import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// ADR 0222: 停止・終了と遅れて届く通知でチャットの状態を矛盾させない（Claude クライアント側）。
// 送信の書き込み・SIGINT を途中で止められる transport で、モデル検査の反例の順に動かす。

private final class GatedTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var lineContinuation: AsyncStream<Data>.Continuation?
    private var pendingSend: CheckedContinuation<Void, Error>?
    private var pendingInterrupt: CheckedContinuation<Void, Never>?
    private var gatesSend = false
    private var gatesInterrupt = false
    private var sends = 0
    let receivedLines: AsyncStream<Data>
    let exitCode: Int32
    var stderr: String?

    init(exitCode: Int32 = 0) {
        self.exitCode = exitCode
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        lineContinuation = captured
    }

    func gateNextSend() { lock.withLock { gatesSend = true } }
    func gateNextInterrupt() { lock.withLock { gatesInterrupt = true } }
    var sendEntered: Bool { lock.withLock { pendingSend != nil } }
    var interruptEntered: Bool { lock.withLock { pendingInterrupt != nil } }
    var sentCount: Int { lock.withLock { sends } }

    func start() throws {}
    func send(_ data: Data) async throws {
        guard lock.withLock({ sends += 1; return gatesSend }) else { return }
        try await withCheckedThrowingContinuation { c in
            lock.withLock { gatesSend = false; pendingSend = c }
        }
    }
    func releaseSend(failing: Bool = false) {
        let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { pendingSend = nil }
            return pendingSend
        }
        if failing { c?.resume(throwing: LineDelimitedProcessTransportError.stdinClosed) } else { c?.resume() }
    }
    func interrupt() async {
        guard lock.withLock({ gatesInterrupt }) else { return }
        await withCheckedContinuation { c in lock.withLock { gatesInterrupt = false; pendingInterrupt = c } }
    }
    func releaseInterrupt() {
        lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { pendingInterrupt = nil }
            return pendingInterrupt
        }?.resume()
    }
    func close() async { lineContinuation?.finish() }
    func terminationStatus() async -> Int32? { exitCode }
    func stderrTail() async -> String? { stderr }
    func receive(_ line: String) { lineContinuation?.yield(Data(line.utf8)) }
    func exit() { lineContinuation?.finish() }
}

private final class StartCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { items.append(event) } }
    var all: [NormalizedChatEvent] { lock.withLock { items } }
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    #expect(condition())
}

private let cleanupError = #"{"type":"result","subtype":"error_during_execution","is_error":true}"#

@Test func stopWhileTurnLineIsBeingWrittenAbsorbsTheCleanupError() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()
    var events = client.events.makeAsyncIterator()

    transport.gateNextSend()
    let send = Task { try await client.turnStart([.text("hello")]) }
    #expect(await events.next() == .turnStarted)
    try await waitUntil { transport.sendEntered }

    try await client.interrupt()
    let interrupted = await events.next()
    guard case .turnInterrupted = interrupted else { Issue.record("got \(String(describing: interrupted))"); return }

    transport.releaseSend()
    try await send.value
    transport.receive(cleanupError)

    // 後始末エラーは吸収され、同じ受信列で後に届く結果が .error を挟まず次の通知になる。
    try await client.turnStart([.text("next")])
    #expect(await events.next() == .turnStarted)
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)
    let completed = await events.next()
    guard case .turnCompleted = completed else { Issue.record("got \(String(describing: completed))"); return }
    await client.close()
}

@Test func writeFailureAfterStopIsTheStopNotAnError() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()
    var events = client.events.makeAsyncIterator()

    transport.gateNextSend()
    let send = Task { try await client.turnStart([.text("hello")]) }
    #expect(await events.next() == .turnStarted)
    try await waitUntil { transport.sendEntered }

    try await client.interrupt()
    let interrupted = await events.next()
    guard case .turnInterrupted = interrupted else { Issue.record("got \(String(describing: interrupted))"); return }

    // SIGINT で終わったプロセスへの書き込みが失敗する。
    transport.releaseSend(failing: true)
    try await send.value

    try await client.turnStart([.text("next")])
    #expect(await events.next() == .turnStarted)
    await client.close()
}

@Test func writeFailureOfATurnSentAfterTheStopIsStillAnError() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    try await client.start()
    var events = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await events.next() == .turnStarted)
    try await client.interrupt()
    let interrupted = await events.next()
    guard case .turnInterrupted = interrupted else { Issue.record("got \(String(describing: interrupted))"); return }

    // 停止が終わった後に送った指示が、終わりかけの CLI への書き込みで失敗する。黙って消さない。
    transport.gateNextSend()
    let send = Task { try await client.turnStart([.text("second")]) }
    #expect(await events.next() == .turnStarted)
    try await waitUntil { transport.sendEntered }
    transport.releaseSend(failing: true)
    await #expect(throws: LineDelimitedProcessTransportError.self) { try await send.value }
    await client.close()  // 列を閉じ、.error が無くても次で止まらないようにする
    let failed = await events.next()
    guard case .error = failed else { Issue.record("got \(String(describing: failed))"); return }
}

@Test func turnStartedDuringInterruptIsNotFollowedByThatInterruptsTurnInterrupted() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    transport.gateNextInterrupt()
    let interrupt = Task { try await client.interrupt() }
    try await waitUntil { transport.interruptEntered }

    // SIGINT を送っている間に次のターンを送る。
    try await client.turnStart([.text("second")])
    transport.releaseInterrupt()
    try await interrupt.value
    await client.close()
    await collector.value

    let all = events.all
    let lastStarted = all.lastIndex(of: .turnStarted) ?? -1
    #expect(lastStarted >= 0)
    #expect(!all[(lastStarted + 1)...].contains { if case .turnInterrupted = $0 { true } else { false } })
}

@Test func turnStartAfterReportedExitDoesNotRestartTheProcess() async throws {
    let transport = GatedTransport(exitCode: 5)
    let starts = StartCounter()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        starts.increment()
        return transport
    })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    transport.exit()
    try await waitUntil { events.all.contains(.processExited(exitCode: 5)) }

    await #expect(throws: ClaudeChatClientError.self) {
        try await client.turnStart([.text("after exit")])
    }
    #expect(starts.count == 1)
    #expect(!events.all.contains(.turnStarted))
    await client.close()
    collector.cancel()
}

@Test func turnStartedWhileTheStopDeniesAPermissionStillEnds() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    transport.receive(#"{"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}"#)
    try await waitUntil { events.all.contains { if case .userQuestionRequested = $0 { true } else { false } } }

    // 停止が許可要求へ deny を書き込んでいる間に、次のターンを送る。
    transport.gateNextSend()
    let interrupt = Task { try await client.interrupt() }
    try await waitUntil { transport.sendEntered }
    try await client.turnStart([.text("second")])
    transport.releaseSend()
    try await interrupt.value
    transport.exit()  // SIGINT で CLI が終わる

    // 停止が閉じたターンは、何らかの終わりの通知で終わる（処理中のまま残らない）。
    try await waitUntil {
        let all = events.all
        guard let last = all.lastIndex(of: .turnStarted) else { return false }
        return all[(last + 1)...].contains {
            switch $0 { case .turnInterrupted, .error, .processExited: true; default: false }
        }
    }
    await client.close()
    await collector.value
}

@Test func writeFailureAfterSelfHealReplayKeepsTheHealedTurn() async throws {
    let dying = GatedTransport()
    dying.stderr = "Error: Session ID 22222222-2222-4222-8222-222222222222 is already in use."
    let healed = GatedTransport()
    let starts = StartCounter()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "22222222-2222-4222-8222-222222222222"],
        transportFactory: { _, _, _, _ in
            defer { starts.increment() }
            return starts.count == 0 ? dying : healed
        }
    )
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    // 書き込み中に CLI が「使用中」で死に、自己修復が新しい CLI へ同じ行を送り直す。
    dying.gateNextSend()
    let send = Task { try await client.turnStart([.text("hello")]) }
    try await waitUntil { dying.sendEntered }
    dying.exit()
    try await waitUntil { starts.count == 2 }
    // その後で元の書き込みが失敗しても、修復したターンを壊さない。
    dying.releaseSend(failing: true)
    try await send.value

    healed.receive(#"{"type":"result","subtype":"success","is_error":false}"#)
    try await waitUntil { events.all.contains { if case .turnCompleted = $0 { true } else { false } } }
    #expect(!events.all.contains { if case .error = $0 { true } else { false } })
    await client.close()
    await collector.value
}

@Test func turnSentRightAfterStopWaitsForTheStoppedProcessAndRestarts() async throws {
    let first = GatedTransport()
    let second = GatedTransport()
    let starts = StartCounter()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        defer { starts.increment() }
        return starts.count == 0 ? first : second
    })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    // SIGINT で CLI が終わる前に次を送る。終わりかけの CLI へは書き込まない。
    let send = Task { try await client.turnStart([.text("second")]) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(first.sentCount == 1)
    first.exit()
    try await send.value

    #expect(starts.count == 2)
    #expect(first.sentCount == 1)
    #expect(second.sentCount == 1)
    #expect(!events.all.contains { if case .error = $0 { true } else { false } })
    await client.close()
    await collector.value
}

@Test func closeWhileWaitingForTheStoppedProcessDoesNotRestart() async throws {
    let transport = GatedTransport()
    let starts = StartCounter()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        starts.increment()
        return transport
    })
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    let send = Task { try await client.turnStart([.text("second")]) }
    try await Task.sleep(for: .milliseconds(50))
    await client.close()

    await #expect(throws: ClaudeChatClientError.self) { try await send.value }
    #expect(starts.count == 1)
    #expect(transport.sentCount == 1)
}

@Test func cleanupErrorsOfTwoStopsReadAfterBothStopsAreAbsorbed() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    // CLI が SIGINT で終わらず、2 回の停止の後始末が両方の停止の後に読まれる。
    try await client.turnStart([.text("first")])
    try await client.interrupt()
    try await client.turnStart([.text("second")])
    try await client.interrupt()
    transport.receive(cleanupError)
    transport.receive(cleanupError)
    try await client.turnStart([.text("third")])
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    try await waitUntil { events.all.contains { if case .turnCompleted = $0 { true } else { false } } }
    #expect(!events.all.contains { if case .error = $0 { true } else { false } })
    #expect(transport.sentCount == 3)  // 終わらない CLI には待った後に同じ CLI へ送る
    await client.close()
    await collector.value
}

@Test func absorptionStopsAfterTheCountedCleanups() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    try await client.turnStart([.text("second")])
    try await client.interrupt()
    transport.receive(cleanupError)
    transport.receive(cleanupError)
    try await client.turnStart([.text("third")])
    transport.receive(cleanupError)  // 3 件目は third の本物のエラー

    try await waitUntil { events.all.contains { if case .error = $0 { true } else { false } } }
    await client.close()
    await collector.value
}

@Test func resultAlreadyInFlightAtStopUsesUpThatStopsAbsorption() async throws {
    let transport = GatedTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    // 停止したターン自身の結果。このターンの後始末は来ない。
    transport.receive(#"{"type":"result","subtype":"success","is_error":false}"#)
    try await client.turnStart([.text("second")])
    try await client.interrupt()
    transport.receive(cleanupError)  // second の後始末
    try await client.turnStart([.text("third")])
    transport.receive(cleanupError)  // third の本物のエラー

    try await waitUntil { events.all.contains { if case .error = $0 { true } else { false } } }
    await client.close()
    await collector.value
}

@Test func stopDuringTheWaitKeepsTheWaitForTheNextSend() async throws {
    let first = GatedTransport()
    let second = GatedTransport()
    let starts = StartCounter()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        defer { starts.increment() }
        return starts.count == 0 ? first : second
    })
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    let stopped = Task { try await client.turnStart([.text("stopped")]) }
    try await Task.sleep(for: .milliseconds(50))
    try await client.interrupt()
    try await stopped.value  // CLI が終わらないまま待ちの上限で戻る

    // 2 回目の停止の SIGINT で CLI が終わる前に送る。これも待つ。
    let next = Task { try await client.turnStart([.text("next")]) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(first.sentCount == 1)
    first.exit()
    try await next.value

    #expect(starts.count == 2)
    #expect(second.sentCount == 1)
    await client.close()
}

@Test func stopWhileTheSendWaitsForTheStoppedProcessCancelsThatSend() async throws {
    let transport = GatedTransport()
    let starts = StartCounter()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        starts.increment()
        return transport
    })
    let events = Events()
    let stream = client.events
    let collector = Task { for await event in stream { events.append(event) } }
    try await client.start()

    try await client.turnStart([.text("first")])
    try await client.interrupt()
    let send = Task { try await client.turnStart([.text("second")]) }
    try await Task.sleep(for: .milliseconds(50))
    // 待っている間に停止し、その後で CLI が終わる。止めた送信を新しい CLI で始めない。
    try await client.interrupt()
    transport.exit()
    try await send.value

    #expect(starts.count == 1)
    #expect(transport.sentCount == 1)
    #expect(events.all.filter { $0 == .turnStarted }.count == 1)
    await client.close()
    await collector.value
}
