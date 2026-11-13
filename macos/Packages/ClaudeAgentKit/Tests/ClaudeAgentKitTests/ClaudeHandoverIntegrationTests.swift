import Darwin
import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

/// 計画的なホスト更新（ADR 0233）のClaude縦の結合。実holderと`/bin/sh`の偽CLIで、
/// 確定点の作成→コミット→採用→未回答の質問の再提示→一度だけの応答、を通す。待機にはすべて期限を付ける。

private let askLine = """
{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool",\
"tool_name":"AskUserQuestion","input":{"questions":[{"question":"デプロイ先は?",\
"header":"Deploy","options":[{"label":"staging","description":"検証環境"},\
{"label":"prod"}],"multiSelect":false}]},"tool_use_id":"toolu_1"}}
"""

private struct StepTimedOut: Error, CustomStringConvertible {
    let label: String
    var description: String { "\(label) が期限内に終わりませんでした（永久待ちの疑い）" }
}

private final class OneShotResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<T, Error>
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func finish(_ result: Result<T, Error>) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { continuation.resume(with: result) }
    }
}

/// 期限つきで実行する（キャンセルに応えない待ちでも、期限で失敗させてハングさせない）。
private func within<T: Sendable>(
    _ seconds: Double, _ label: String, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = OneShotResult(continuation)
        let work = Task {
            do { once.finish(.success(try await operation())) } catch { once.finish(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            once.finish(.failure(StepTimedOut(label: label)))
            work.cancel()
        }
    }
}

private func eventually(timeout: Double = 5, _ condition: @escaping @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while true {
        if condition() { return true }
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { lock.withLock { events.append(event) } }
    var all: [NormalizedChatEvent] { lock.withLock { events } }
    var questionCount: Int {
        all.filter { if case .userQuestionRequested(let id, _) = $0 { id == "req-1" } else { false } }.count
    }
}

private func collect(_ client: ClaudeChatClient) -> (EventBox, Task<Void, Never>) {
    let box = EventBox()
    let events = client.events
    return (box, Task { for await event in events { box.append(event) } })
}

private struct AskingChildHolder {
    let holder: ProcessHolder
    let record: HolderRecord
    let root: String
    let log: String

    init() throws {
        let root = "/tmp/phx-ci-" + UUID().uuidString.prefix(8).lowercased()
        let log = root + "-stdin.txt"
        // 質問を1回出し、以後に受け取った標準入力の行を全てログへ記録する。
        let script = #"printf '%s\n' "$ASK"; while IFS= read -r l; do printf '%s\n' "$l" >> "$LOG"; done"#
        let environment = ProcessInfo.processInfo.environment.merging(["ASK": askLine, "LOG": log]) { _, new in new }
        let spec = HolderSpawnSpec(
            command: "/bin/sh", arguments: ["-c", script], environment: environment, workingDirectory: nil,
            metadata: [:], recordDirectory: root + "/r", socketDirectory: root + "/s")
        let holder = ProcessHolder(spec: spec, orphanLinger: 5)
        self.record = try holder.start()
        self.holder = holder
        self.root = root
        self.log = log
    }

    var stdinLines: [String] {
        ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func cleanUp() {
        kill(record.childPID, SIGKILL)
        try? FileManager.default.removeItem(atPath: root)
        try? FileManager.default.removeItem(atPath: log)
    }
}

@Test func handoverCarriesAnUnansweredQuestionAndAnswersItExactlyOnceOnTheNewHost() async throws {
    let child = try AskingChildHolder()
    defer { child.cleanUp() }
    let record = child.record

    // --- 旧ホスト: 質問を受け取り、確定点を作ってコミットする。
    let old = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        HolderTransport(source: .adopt(record: record, fromSeq: 0))
    })
    let (oldEvents, oldCollector) = collect(old)
    defer { oldCollector.cancel() }
    try await within(15, "旧ホストの起動") { try await old.start() }
    #expect(await eventually { oldEvents.questionCount == 1 }, "旧ホストが質問を受け取れない")
    #expect(await old.handoverGateReason() == nil)

    let preparation = try await within(20, "prepareHandover") { try await old.prepareHandover(fence: UUID()) }
    try await within(10, "commitHandover") { await old.commitHandover(confirmedThrough: preparation.appliedSeq) }
    // コミット後も子は生きていて、旧ホストは何も答えていない。
    #expect(kill(record.childPID, 0) == 0)
    #expect(child.stdinLines.isEmpty)

    // --- 新ホスト: 採用して、質問が再提示される（子は同じプロセス）。
    let adoptedTransport = HolderTransport(source: .adopt(record: preparation.holder, fromSeq: preparation.appliedSeq))
    let adopted = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in
        Issue.record("採用で新しい子の起動が要求された")
        return HolderTransport(source: .adopt(record: record, fromSeq: 0))
    })
    let (newEvents, newCollector) = collect(adopted)
    defer { newCollector.cancel() }
    await adopted.prepareAdoption(state: preparation.clientState, transport: adoptedTransport)
    try await within(15, "completeAdoption") { try await adopted.completeAdoption() }
    #expect(await eventually { newEvents.questionCount == 1 }, "質問が新ホストへ再提示されない: \(newEvents.all)")

    // --- 一度だけ応答する（二重に答えても、子へは1回しか届かない）。
    try await within(10, "回答") {
        await adopted.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])
    }
    #expect(await eventually { child.stdinLines.filter { $0.contains("control_response") }.count >= 1 }, "回答が子へ届かない")
    try await within(10, "2回目の回答") {
        await adopted.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["prod"]])
    }
    try await Task.sleep(for: .milliseconds(300))
    let responses = child.stdinLines.filter { $0.contains("control_response") && $0.contains("req-1") }
    #expect(responses.count == 1, "回答が1回でない: \(child.stdinLines)")
    #expect(newEvents.questionCount == 1, "質問が2回以上再提示された")
    #expect(kill(record.childPID, 0) == 0)
    // 採用で新しい子を作らない。
    try await within(10, "採用側のclose") { await adopted.close() }
}
