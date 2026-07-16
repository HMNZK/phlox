import Foundation
import StructuredChatKit
import Testing
@testable import CursorAgentKit

// task-8 回帰テスト（audit）: CursorAgentKit の 4 つの正しさハザードを固定する。
//   I12  追い越しターンが先行 inFlightRun を cancel せず旧プロセスが最長 300 秒並走する。
//   S1   exit0 でも stderr 1 バイトで stdout のパース結果を全破棄する（stderr 致命は exit≠0 限定へ）。
//   S2   result の subtype!=success を無言破棄する（失敗理由を .error で観測できるようにする）。
//   S3   itemId "reasoning"/"assistant-N" がターンを跨いで衝突する（ターン salt を接頭辞へ）。
//
// I12 は GatedFirstRunner 相当の `OvertakenRunner`（waitForFirstEntered / release でレース窓を
// 手動制御）で決定論的に検証する（実時間 sleep のマジック値に依存しない）。

// MARK: - Helpers

private func auditJSONLine(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private actor AuditEventLog {
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { events.append(event) }
    func snapshot() -> [NormalizedChatEvent] { events }
}

/// turnStart を実行し、close() で stream を閉じてからその 1 ターンぶんの全イベントを回収する。
/// turnStart は返る前に自ターンのイベントを（unbounded stream へ）同期的に yield し終えているので、
/// close() 後にドレインすれば error / turnCompleted の有無を取りこぼさず検証できる。
private func drainTurn(
    client: CursorChatClient,
    input: [ChatInput]
) async throws -> [NormalizedChatEvent] {
    let log = AuditEventLog()
    let collector = Task { for await event in client.events { await log.append(event) } }
    try await client.turnStart(input)
    await client.close()
    _ = await collector.value
    return await log.snapshot()
}

// MARK: - I12: 追い越しターンが先行 inFlightRun を cancel する

/// 1 回目の run はゲート解除 or キャンセルまで待機し、キャンセルを観測したら記録して throw する。
/// 2 回目以降（＝追い越しターン）は scripted な成功結果を即時返す。
private final class OvertakenRunner: OneShotProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var firstEntered = false
    private var firstCancelled = false
    private var released = false
    private let secondLines: [Data]

    init(secondLines: [String]) {
        self.secondLines = secondLines.map { Data($0.utf8) }
    }

    var calls: Int { withLock { callCount } }
    func release() { withLock { released = true } }

    func waitForFirstEntered(timeout: TimeInterval) async -> Bool {
        await poll(timeout: timeout) { self.withLock { self.firstEntered } }
    }

    func waitForFirstCancelled(timeout: TimeInterval) async -> Bool {
        await poll(timeout: timeout) { self.withLock { self.firstCancelled } }
    }

    private func poll(timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) async throws -> OneShotProcessResult {
        let call = withLock { callCount += 1; return callCount }
        if call == 1 {
            withLock { firstEntered = true }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if Task.isCancelled {
                    withLock { firstCancelled = true }
                    throw CancellationError()
                }
                if withLock({ released }) { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            withLock { firstCancelled = Task.isCancelled }
            // ここへ来るのは未修正コード経路（cancel されず release で抜けた場合）。ハングを避けて成功で返す。
            return OneShotProcessResult(exitCode: 0, outputLines: [])
        }
        return OneShotProcessResult(exitCode: 0, outputLines: secondLines)
    }
}

@Test func cursorOvertakingTurnCancelsPriorInFlightRun() async throws {
    let secondResult = auditJSONLine(["type": "result", "subtype": "success", "session_id": "sess-second"])
    let runner = OvertakenRunner(secondLines: [secondResult])
    let client = CursorChatClient(command: "cursor-agent", runner: runner)

    // 1 ターン目を走らせ、その run が in-flight（awaiting）に入るまで待つ。
    let firstTurn = Task { try? await client.turnStart([.text("first")]) }
    try #require(await runner.waitForFirstEntered(timeout: 5.0), "first run never started")

    // 追い越しターン: 先行 run が in-flight のまま 2 ターン目を開始する。
    try await client.turnStart([.text("second")])
    #expect(runner.calls == 2)

    // 契約: 追い越された先行 run は cancel される（さもなくば旧プロセスが最長 300 秒並走する）。
    #expect(await runner.waitForFirstCancelled(timeout: 2.0),
            "追い越しターンが先行 inFlightRun を cancel していない（旧プロセスが並走し続ける）")

    runner.release() // 安全策: 未修正コード経路で先行 run を確実に終わらせる。
    _ = await firstTurn.value
    await client.close()
}

// MARK: - S1: exit0 + stderr で stdout を破棄しない（仕様変更）

@Test func cursorExitZeroWithStderrKeepsStdoutAndWarns() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(
        lines: [
            auditJSONLine(["type": "result", "subtype": "success", "session_id": "sess-ok"]),
        ],
        errorLines: ["minor stderr noise"]
    )
    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()

    let events = try await drainTurn(client: client, input: [.text("go")])

    // 新契約: exit0 の stderr は stdout のパース結果を破棄しない（turnCompleted に到達する）。
    #expect(events.contains(.turnCompleted(nativeSessionId: "sess-ok")),
            "exit0 + stderr で stdout（result/success）が破棄されている")
    // stderr は致命エラーではなく非致命の warning として観測できる。
    #expect(events.contains(.warning(message: "cursor-agent wrote to stderr: minor stderr noise")))
    #expect(!events.contains { if case .error = $0 { return true } else { return false } },
            "exit0 の stderr が .error に昇格している（致命扱いは exit≠0 限定のはず）")
}

// MARK: - S2: result subtype!=success の失敗理由を .error で yield する

@Test func cursorNonSuccessResultYieldsErrorBody() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        auditJSONLine([
            "type": "result",
            "subtype": "error",
            "session_id": "sess-e",
            "result": "model refused the request",
        ]),
    ])
    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()

    let events = try await drainTurn(client: client, input: [.text("go")])

    let errorMessages = events.compactMap { event -> String? in
        if case .error(let message) = event { return message } else { return nil }
    }
    // 契約: 失敗理由（result 本文）が .error として観測できる（無言破棄しない）。
    #expect(errorMessages.contains { $0.contains("model refused the request") },
            "非 success result の失敗理由が .error に現れない: \(errorMessages)")
    // 冗長な汎用 "completed without result/success" を二重に出さない（result は観測済み）。
    #expect(!errorMessages.contains { $0.contains("completed without result/success") },
            "result を観測しているのに汎用 completed-without-result エラーが二重に出ている")
    #expect(!events.contains { if case .turnCompleted = $0 { return true } else { return false } },
            "失敗 result なのに turnCompleted に到達している")
}

// MARK: - S3: itemId がターンを跨いで衝突しない

@Test func cursorItemIdsDoNotCollideAcrossTurns() async throws {
    let runner = MockOneShotProcessRunner()
    for _ in 0..<2 {
        runner.enqueueSuccess(lines: [
            auditJSONLine(["type": "thinking", "subtype": "delta", "text": "planning", "session_id": "s"]),
            auditJSONLine([
                "type": "assistant",
                "message": ["role": "assistant", "content": [["type": "text", "text": "hi"]]],
                "session_id": "s",
            ]),
            auditJSONLine(["type": "result", "subtype": "success", "session_id": "s"]),
        ])
    }
    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()

    let log = AuditEventLog()
    let collector = Task { for await event in client.events { await log.append(event) } }
    try await client.turnStart([.text("first")])
    try await client.turnStart([.text("second")])
    await client.close()
    _ = await collector.value
    let events = await log.snapshot()

    let reasoningIds = events.compactMap { event -> String? in
        if case .reasoningDelta(let id, _) = event { return id } else { return nil }
    }
    let assistantIds = events.compactMap { event -> String? in
        if case .agentMessageDelta(let id, _) = event { return id } else { return nil }
    }

    #expect(reasoningIds.count == 2, "各ターンが 1 つずつ reasoning を出すはず: \(reasoningIds)")
    #expect(assistantIds.count == 2, "各ターンが 1 つずつ assistant を出すはず: \(assistantIds)")
    #expect(reasoningIds.first != reasoningIds.last,
            "reasoning itemId がターンを跨いで衝突している: \(reasoningIds)")
    #expect(assistantIds.first != assistantIds.last,
            "assistant itemId がターンを跨いで衝突している: \(assistantIds)")
}
