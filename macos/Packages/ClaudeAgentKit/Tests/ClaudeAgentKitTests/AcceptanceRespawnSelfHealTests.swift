import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-21 受け入れテスト（PM 著・実装役は編集禁止）。
// 契約:
// 1. settings dirty respawn は「会話の実在」で引数を選ぶ:
//    - 未確立（success result 未受信かつ resume(sessionRef:) 未呼び出し）→ `--session-id`（--resume 禁止）
//    - success result 受信済み、または resume(sessionRef:) 済み → `--resume`
// 2. resume spawn が error_during_execution + stderr「No conversation found with session ID」で
//    死んだ場合、.error を出さずに `--session-id <ref>` で respawn し、送信済みターンを再送する（self-heal）。
// 3. self-heal は構造的に一回限り（heal 先は session-id spawn なので再 heal 条件を満たさない）。
// 4. result なしでプロセスが死んだときの .error メッセージに stderr 末尾を含める。

// MARK: - 1. Daffodil バグ本体: 初回ターン前の settings respawn は --session-id

@Test func settingsRespawnBeforeFirstCompletedTurnUsesSessionIdNotResume() async throws {
    let recorder = HealTransportRecorder()
    let sid = "b401fa47-87cd-46f3-ad1c-d71076fb5205"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    // ChatSessionViewModel.loadSpawnAgentSettings 相当: 起動直後に必ず設定が適用される。
    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions")
    try await client.turnStart([.text("hello")])

    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    let respawnArgs = recorder.starts[1].arguments
    #expect(!respawnArgs.contains("--resume"))
    #expect(respawnArgs.contains("--session-id"))
    #expect(respawnArgs.contains(sid))
    // ユーザーメッセージは新 transport に配送される。
    #expect(recorder.transports[1].sentStrings().count == 1)
    await client.close()
}

// MARK: - 2. 会話確立後（success result 受信後）の settings respawn は従来どおり --resume

@Test func settingsRespawnAfterCompletedTurnUsesResume() async throws {
    let recorder = HealTransportRecorder()
    let sid = "44444444-4444-4444-8444-444444444444"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(sid)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: sid))

    await client.updateSettings(model: "sonnet", permissionMode: nil)
    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    let respawnArgs = recorder.starts[1].arguments
    #expect(respawnArgs.contains("--resume"))
    #expect(respawnArgs.contains(sid))
    #expect(!respawnArgs.contains("--session-id"))
    await client.close()
}

// MARK: - 3. 復元経路の回帰ガード: resume(sessionRef:) 済みなら settings respawn も --resume
// （ここで --session-id を選ぶと実在会話が "Session ID already in use" で即死する）

@Test func settingsRespawnAfterResumeKeepsResumeArgument() async throws {
    let recorder = HealTransportRecorder()
    let ref = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: recorder.makeTransport
    )
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    // 復元直後の loadSpawnAgentSettings 相当。
    await client.updateSettings(model: "sonnet", permissionMode: "bypassPermissions")
    try await client.turnStart([.text("hi")])

    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    let respawnArgs = recorder.starts[1].arguments
    #expect(respawnArgs.contains("--resume"))
    #expect(respawnArgs.contains(ref))
    #expect(!respawnArgs.contains("--session-id"))
    await client.close()
}

// MARK: - 4. self-heal: 存在しない会話への resume 失敗を --session-id respawn + 再送で無音回復

@Test func resumeFailureWithNoConversationFoundSelfHealsAndReplays() async throws {
    let recorder = HealTransportRecorder()
    let ref = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: recorder.makeTransport
    )
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)
    let originalLine = try #require(recorder.transports[0].sentStrings().first)

    // CLI 実挙動（2026-07-03 実測・claude 2.1.198）: --resume 未存在ID は
    // error_during_execution の result を出し、stderr に理由を書いて exit 1 する。
    recorder.transports[0].stderrTailText = "No conversation found with session ID: \(ref)"
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    await recorder.transports[0].close()

    // heal: --session-id <ref> で respawn し、同一メッセージを再送する。
    try await waitUntil {
        recorder.starts.count == 2 && recorder.transports.count == 2
            && !recorder.transports[1].sentStrings().isEmpty
    }
    let healArgs = recorder.starts[1].arguments
    #expect(healArgs.contains("--session-id"))
    #expect(healArgs.contains(ref))
    #expect(!healArgs.contains("--resume"))
    #expect(recorder.transports[1].sentStrings() == [originalLine])

    // heal 後の成功で、.error を挟まず（かつ .turnStarted を重複させず）ターンが完了する。
    recorder.transports[1].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(ref)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: ref))
    await client.close()
}

// MARK: - 5. heal は一回限り: heal 先 spawn の失敗は .error として表面化し、再 heal しない

@Test func healedSpawnFailureSurfacesErrorWithoutSecondHeal() async throws {
    let recorder = HealTransportRecorder()
    let ref = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: recorder.makeTransport
    )
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    recorder.transports[0].stderrTailText = "No conversation found with session ID: \(ref)"
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    await recorder.transports[0].close()

    try await waitUntil {
        recorder.starts.count == 2 && recorder.transports.count == 2
            && !recorder.transports[1].sentStrings().isEmpty
    }

    // heal 先（--session-id spawn）も失敗させる。
    recorder.transports[1].stderrTailText = "No conversation found with session ID: \(ref)"
    recorder.transports[1].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    await recorder.transports[1].close()

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("error_during_execution"))
    } else {
        Issue.record("Expected surfaced error after healed spawn failure, got \(String(describing: event))")
    }
    // 再 heal（3 個目の spawn）は起きない。
    #expect(recorder.starts.count == 2)
    await client.close()
}

// MARK: - 7. ターン外の resume 即死（復元直後）: 無音 heal で以後のターンが成立する
// 実測（claude 2.1.198・2026-07-03）: `-p --resume <未存在ID>` は stdin 入力を待たず起動直後に
// num_turns:0 の error result を吐いて exit 1 する。よって heal はターン中に限定できない。

@Test func resumeStartupDeathWithNoConversationFoundSelfHealsWithoutErrorOrTurn() async throws {
    let recorder = HealTransportRecorder()
    let ref = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: recorder.makeTransport
    )
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    recorder.transports[0].stderrTailText = "No conversation found with session ID: \(ref)"
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":0,"permission_denials":[]}"#
    )
    await recorder.transports[0].close()

    // 無音 heal: .error を出さず --session-id <ref> で respawn（ターンが無いので再送もなし）。
    try await waitUntil { recorder.starts.count == 2 }
    let healArgs = recorder.starts[1].arguments
    #expect(healArgs.contains("--session-id"))
    #expect(healArgs.contains(ref))
    #expect(!healArgs.contains("--resume"))
    #expect(recorder.transports[1].sentStrings().isEmpty)

    // heal 後のターンが普通に成立する（.error が先に出ていれば最初の next() で検出される）。
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.transports[1].sentStrings().count == 1)
    recorder.transports[1].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(ref)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: ref))
    await client.close()
}

// MARK: - 6. result なしのプロセス死: .error メッセージに stderr 末尾を含める

@Test func processDeathWithoutResultIncludesStderrTailInError() async throws {
    let recorder = HealTransportRecorder()
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "99999999-9999-4999-8999-999999999999"],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("run")])
    #expect(await iterator.next() == .turnStarted)

    recorder.transports[0].stderrTailText = "boom from stderr"
    await recorder.transports[0].close()

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("Claude process ended before completing the current turn"))
        #expect(message.contains("boom from stderr"))
    } else {
        Issue.record("Expected error event with stderr tail, got \(String(describing: event))")
    }
    await client.close()
}

// MARK: - テストダブル（この受け入れファイル内で自己完結）

private struct HealTransportStart: Sendable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
}

private final class HealTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts: [HealTransportStart] = []
    private var recordedTransports: [HealMockTransport] = []

    var starts: [HealTransportStart] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStarts
    }

    var transports: [HealMockTransport] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTransports
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = HealMockTransport()
        lock.lock()
        defer { lock.unlock() }
        recordedStarts.append(HealTransportStart(
            command: command,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        ))
        recordedTransports.append(transport)
        return transport
    }
}

private final class HealMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    private var stderrText: String?

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    var stderrTailText: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stderrText
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stderrText = newValue
        }
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        record(data)
    }

    private func record(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        sent.append(data)
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func stderrTail() async -> String? {
        stderrTailText
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent.map { String(data: $0, encoding: .utf8) ?? "" }
    }
}

private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "waitUntil timed out")
}
