import Foundation
import StructuredChatKit
import Testing
@testable import CursorAgentKit

// task-5 受け入れテスト（PM 著・実装役は編集禁止 / loopflow acceptance_tests）
//
// 契約: interrupt() は実行中の one-shot run に 2 秒以内に Task キャンセルを伝播させ、
// キャンセルされたターン由来のイベント（.error 含む）を以後 yield せず、
// 次の turnStart を待たせず即時実行させる。

/// 1回目の run はキャンセルされるまで待機し（ハング防止に 5 秒で自主脱出）、
/// 2回目以降は成功結果を即時返すフェイク runner。
private final class CancellationObservingRunner: OneShotProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var firstRunEntered = false
    private var cancellationSeen = false
    private let successLines: [Data]

    init(successLines: [String]) {
        self.successLines = successLines.map { Data($0.utf8) }
    }

    var calls: Int { lock.withLock { callCount } }

    func waitForFirstRunEntered(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ firstRunEntered }) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return lock.withLock { firstRunEntered }
    }

    func waitForCancellation(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ cancellationSeen }) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return lock.withLock { cancellationSeen }
    }

    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) async throws -> OneShotProcessResult {
        let call = lock.withLock { () -> Int in
            callCount += 1
            return callCount
        }
        if call == 1 {
            lock.withLock { firstRunEntered = true }
            let start = Date()
            while !Task.isCancelled, Date().timeIntervalSince(start) < 5 {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            lock.withLock { cancellationSeen = Task.isCancelled }
            throw CancellationError()
        }
        return OneShotProcessResult(exitCode: 0, outputLines: successLines)
    }
}

private actor EventLog {
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { events.append(event) }
    func snapshot() -> [NormalizedChatEvent] { events }
}

@Test
func interrupt_cancelsInFlightRun_suppressesStaleEvents_andNextTurnStartsImmediately() async throws {
    let resultLine = #"{"type":"result","subtype":"success","session_id":"sess-accept"}"#
    let runner = CancellationObservingRunner(successLines: [resultLine])
    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    let log = EventLog()
    let collector = Task {
        for await event in client.events { await log.append(event) }
    }

    let firstTurn = Task { try? await client.turnStart([.text("first")]) }
    let entered = await runner.waitForFirstRunEntered(timeout: 5.0)
    try #require(entered, "first run never started")

    try await client.interrupt()

    // 契約1: in-flight run へ 2 秒以内にキャンセルが伝播する。
    #expect(await runner.waitForCancellation(timeout: 2.0), "interrupt が実行中の one-shot run をキャンセルしていない")
    _ = await firstTurn.value

    // 契約3: 次の turnStart は待たされず新しい run を実行して完了する。
    try await client.turnStart([.text("second")])
    #expect(runner.calls == 2)

    await client.close()
    _ = await collector.value

    let events = await log.snapshot()

    // 契約2: 中断ターン由来の .error を yield しない。
    let errorMessages = events.compactMap { event in
        if case .error(let message) = event { message } else { nil }
    }
    #expect(errorMessages.isEmpty, "中断ターンのイベントが漏れている: \(errorMessages)")

    // .turnInterrupted はちょうど 1 回。2 ターン目は turnCompleted に到達する。
    let interruptedCount = events.filter { event in
        if case .turnInterrupted = event { true } else { false }
    }.count
    #expect(interruptedCount == 1)
    let sawCompleted = events.contains { event in
        if case .turnCompleted = event { true } else { false }
    }
    #expect(sawCompleted, "中断後の再ターンが完了していない")
}
