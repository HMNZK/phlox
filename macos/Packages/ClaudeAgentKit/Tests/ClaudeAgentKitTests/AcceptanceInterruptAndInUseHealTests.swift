import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-24 受け入れテスト（PM 著・実装役は編集禁止）。
// 実測根拠（2026-07-03・Poppy セッションの CLI トランスクリプト）:
//   - ターンが中断/エラーで終わっても、CLI は会話ファイルを既に生成している。
//   - よって「success のみを会話実在の証拠にする」判定は不足で、その後の設定 respawn が
//     --session-id <既存ID> を選び "Session ID ... is already in use." で即死する。
//   - 中断（interrupt）後、CLI は error_during_execution の result を返すことがあり、
//     これを赤エラーとして表示すべきではない（ターンは turnInterrupted で閉じている）。
// 契約:
//   1. session-id spawn で任意の result（success/error 問わず）を受信したら会話実在と判定する。
//   2. interrupt() 後に届いた当該ターンの error result は .error として yield しない。
//   3. session-id spawn が result なしで死に stderr が "is already in use" を含むとき、
//      --resume <id> で respawn して送信済み1行を再送する（対称 self-heal・無音）。
//   4. self-heal はターンごとに最大1回（resume 失敗 heal と合わせ、ping-pong の無限 respawn を禁止）。

// MARK: - 1. エラー result でも会話実在と判定 → 次の設定 respawn は --resume

@Test func errorResultOnSessionIdSpawnEstablishesConversationForNextRespawn() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-1111-4111-8111-111111111111"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    let errorEvent = await iterator.next()
    if case .error = errorEvent {} else {
        Issue.record("Expected surfaced error for session-id spawn error result, got \(String(describing: errorEvent))")
    }

    await client.updateSettings(model: "haiku", permissionMode: "bypassPermissions", effort: "low")
    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    let args = recorder.starts[1].arguments
    #expect(args.contains("--resume"))
    #expect(!args.contains("--session-id"))
    await client.close()
}

// MARK: - 2. interrupt 後の error result は .error にしない（中断は turnInterrupted で完結）

@Test func errorResultArrivingAfterInterruptIsNotSurfacedAsError() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-2222-4222-8222-222222222222"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    try await client.interrupt()
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: sid))

    // CLI が中断の結果として返す error result（Poppy 実測の再現）。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )

    // .error は yield されない。次のターンが普通に始まることで無イベントを検証する。
    try await client.turnStart([.text("next")])
    #expect(await iterator.next() == .turnStarted)
    await client.close()
}

// MARK: - 2b. 中断ターンの後始末エラーが「次ターン開始後」に遅れて届いても吸収する
// （stream は FIFO なので、中断時にターンが開いていたなら次の error_during_execution 1件は
//   後始末と確定できる。turnStart で吸収を解除すると新ターンに前ターンの赤エラーが漏れる。
//   ステージ2レビュー検出の MUST を符号化・2026-07-03）

@Test func interruptedTurnErrorArrivingAfterNextTurnStartIsStillSuppressed() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-5555-4555-8555-555555555555"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)

    try await client.interrupt()
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: sid))

    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    // 前ターン interrupt の後始末 result が遅れて到着（FIFO 上、新ターンの result より必ず先）。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )

    // .error を挟まず新ターンの success で完了する。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(sid)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: sid))
    await client.close()
}

// MARK: - 2c. 遅延後始末エラーの吸収は「新ターンの状態」に触れない
// （吸収は前ターンの後始末であり、開いている新ターンの currentTurnOpen/currentTurnLine を
//   閉じてはならない。閉じると再中断時に吸収がアームされず2度目の後始末が赤エラー化する。
//   ステージ2再レビュー検出の MUST を符号化・2026-07-03）

@Test func delayedInterruptedCleanupDoesNotCloseNextTurnState() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-6666-4666-8666-666666666666"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)

    try await client.interrupt()
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: sid))

    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    // 前ターンの後始末エラーが第2ターン中に遅延到着 → 吸収（第2ターンの状態は不変のはず）。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )

    // 第2ターンを中断 → ターンが開いたままなら吸収が再アームされる。
    try await client.interrupt()
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: sid))

    // 第2ターンの後始末エラーも吸収され、赤エラーにならない。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )

    try await client.turnStart([.text("third")])
    #expect(await iterator.next() == .turnStarted)
    await client.close()
}

// MARK: - 2d. 後始末吸収の直後に新ターンがプロセス死しても沈黙しない
// （吸収が新ターンの currentTurnOpen を巻き添えにすると、直後の result なし死で
//   .error も .turnCompleted も出ない silent hang になる。ステージ1再レビュー提案の符号化）

@Test func interruptedTurnCleanupAbsorbDoesNotSwallowNextTurnProcessDeath() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-7777-4777-8777-777777777777"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)
    try await client.interrupt()
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: sid))

    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    // 前ターンの後始末 error が遅延到着（吸収される・新ターン状態は不変のはず）。
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    // 直後に second ターンが result なしでプロセス死。
    recorder.transports[0].stderrTailText = "boom"
    await recorder.transports[0].close()

    // second ターンの死は .error として表面化される（沈黙しない）。
    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("boom"))
    } else {
        Issue.record("Expected surfaced error for second turn process death, got \(String(describing: event))")
    }
    await client.close()
}

// MARK: - 3. already-in-use の対称 self-heal: --resume respawn＋再送で無音回復

@Test func sessionIdAlreadyInUseDeathSelfHealsWithResumeRespawnAndReplays() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-3333-4333-8333-333333333333"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    // 設定 respawn で --session-id が選ばれたが、実は会話が既に存在していた、という
    // 誤判定シナリオ（判定をどう改善しても取りこぼしうるため、heal で自己回復する）。
    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions", effort: "high")
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    let originalLine = try #require(recorder.transports[1].sentStrings().first)

    // 実測（claude 2.1.198）: --session-id 既存IDは result を出さず stderr に
    // "Session ID ... is already in use." を書いて exit 1 する。
    recorder.transports[1].stderrTailText = "Error: Session ID \(sid) is already in use."
    await recorder.transports[1].close()

    try await waitUntilT24 {
        recorder.starts.count == 3 && recorder.transports.count == 3
            && !recorder.transports[2].sentStrings().isEmpty
    }
    let healArgs = recorder.starts[2].arguments
    #expect(healArgs.contains("--resume"))
    #expect(healArgs.contains(sid))
    #expect(!healArgs.contains("--session-id"))
    #expect(recorder.transports[2].sentStrings() == [originalLine])

    recorder.transports[2].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(sid)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: sid))
    await client.close()
}

// MARK: - 4. heal はターンごとに最大1回（ping-pong 無限 respawn の禁止）

@Test func healPingPongIsBoundedToOneHealPerTurn() async throws {
    let recorder = HealT24Recorder()
    let sid = "f0f0f0f0-4444-4444-8444-444444444444"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: nil, effort: nil)
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts.count == 2)

    // 1回目: already-in-use → --resume heal（無音）。
    recorder.transports[1].stderrTailText = "Error: Session ID \(sid) is already in use."
    await recorder.transports[1].close()
    try await waitUntilT24 { recorder.starts.count == 3 && recorder.transports.count == 3 }

    // 2回目: heal 先（--resume）も "No conversation found" で死ぬ矛盾状態。
    // ここで --session-id へ再 heal すると無限 ping-pong になるため、エラーを表面化して止まること。
    recorder.transports[2].stderrTailText = "No conversation found with session ID: \(sid)"
    recorder.transports[2].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    await recorder.transports[2].close()

    let event = await iterator.next()
    if case .error = event {} else {
        Issue.record("Expected surfaced error after second failure in one turn, got \(String(describing: event))")
    }
    #expect(recorder.starts.count == 3)
    await client.close()
}

// MARK: - テストダブル（この受け入れファイル内で自己完結）

private struct HealT24Start: Sendable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
}

private final class HealT24Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts: [HealT24Start] = []
    private var recordedTransports: [HealT24MockTransport] = []

    var starts: [HealT24Start] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStarts
    }

    var transports: [HealT24MockTransport] {
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
        let transport = HealT24MockTransport()
        lock.lock()
        defer { lock.unlock() }
        recordedStarts.append(HealT24Start(
            command: command,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        ))
        recordedTransports.append(transport)
        return transport
    }
}

private final class HealT24MockTransport: LineDelimitedTransport, @unchecked Sendable {
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

private func waitUntilT24(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "waitUntilT24 timed out")
}
