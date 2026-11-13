import Darwin
import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit


// MARK: - 待機の補助（`waitUntil`は条件を1回しか評価しないので、ここで定期的に確かめる）

/// 条件が満たされるまで10msごとに確かめる。期限までに満たされなければ false。
func eventually(timeout: Double = 5, _ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while true {
        if await condition() { return true }
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct StepTimeout: Error, CustomStringConvertible {
    let label: String
    let seconds: Double
    var description: String { "\(label) が\(seconds)秒以内に終わりませんでした（永久待ちの疑い）" }
}

private final class OneShot<T: Sendable>: @unchecked Sendable {
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

/// 期限つきで実行する。キャンセルに応えない待ちでも、期限で`StepTimeout`を投げてテストを失敗させる（ハングさせない）。
func within<T: Sendable>(
    _ seconds: Double = 10, _ label: String, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = OneShot(continuation)
        let work = Task {
            do { once.finish(.success(try await operation())) } catch { once.finish(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            once.finish(.failure(StepTimeout(label: label, seconds: seconds)))
            work.cancel()
        }
    }
}

// MARK: - 3層のフェンスと状態（MockTransport）

private actor EventLog {
    private(set) var events: [ThreadEvent] = []
    func append(_ event: ThreadEvent) { events.append(event) }
    func containsFence(_ id: UUID) -> Bool {
        events.contains { if case .handoverFence(let x) = $0, x == id { true } else { false } }
    }
    func deltas() -> [String] {
        events.compactMap { if case .agentMessageDelta(_, _, _, let delta) = $0 { delta } else { nil } }
    }
    func hasTurnCompleted() -> Bool {
        events.contains { if case .turnCompleted = $0 { true } else { false } }
    }
    func lastIsFence(_ id: UUID) -> Bool {
        if case .handoverFence(let x)? = events.last { return x == id }
        return false
    }
}

private func collect(_ client: CodexAppServerClient, into log: EventLog) -> Task<Void, Never> {
    let events = client.events
    return Task { for await event in events { await log.append(event) } }
}

private let turnStarted = #"{"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"inProgress","items":[]}}}"#
private let turnCompleted = #"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed","items":[]}}}"#
private func delta(turn: String, text: String) -> String {
    #"{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"\#(turn)","itemId":"item-\#(turn)","delta":"\#(text)"}}"#
}

@Test func fenceReachesTheTopOnlyAfterEveryEarlierEventAndCarriesTheirEffect() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let log = EventLog()
    let collector = collect(client, into: log)
    defer { collector.cancel() }
    await client.start()

    transport.receive(turnStarted)
    transport.receive(delta(turn: "turn-1", text: "a"))
    // 受信行は別タスクで処理される。フェンスはその後に流す（本番では`quiesce`が受信の消化を保証する）。
    #expect(await eventually { await log.deltas() == ["a"] }, "turn/started と delta が最上層へ届かない")
    let first = UUID()
    await client.beginHandoverFence(first)
    #expect(await eventually { await log.containsFence(first) }, "フェンスが最上層へ届かない")

    // フェンスは前のイベントの後ろに流れ、その時点の状態（実行中のturn）が採取されている。
    #expect(await log.lastIsFence(first))
    #expect(await log.deltas() == ["a"])
    let state = try #require(await client.takeFenceState(first))
    #expect(state.turns == [.init(threadId: "thread-1", activeTurnId: "turn-1", closedTurnIds: [], hasObservedLifecycle: true)])

    transport.receive(turnCompleted)
    #expect(await eventually { await log.hasTurnCompleted() }, "turn/completed が最上層へ届かない")
    let second = UUID()
    await client.beginHandoverFence(second)
    #expect(await eventually { await log.containsFence(second) }, "2つ目のフェンスが届かない")
    let after = try #require(await client.takeFenceState(second))
    #expect(after.turns == [.init(threadId: "thread-1", activeTurnId: nil, closedTurnIds: ["turn-1"], hasObservedLifecycle: true)])
}

@Test func adoptedTurnIdentityStillBlocksLateEventsOfAClosedTurn() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let log = EventLog()
    let collector = collect(client, into: log)
    defer { collector.cancel() }
    await client.applyHandoverState(CodexClientHandoverState(
        turns: [.init(threadId: "thread-1", activeTurnId: "turn-2", closedTurnIds: ["turn-1"], hasObservedLifecycle: true)],
        nextTurnStartGeneration: 5, rpc: JSONRPCHandoverState(nextRequestID: 10, pendingServerRequests: [])))
    await client.start()

    transport.receive(delta(turn: "turn-1", text: "late-from-closed-turn"))
    transport.receive(delta(turn: "turn-2", text: "current"))
    // 順序どおりなので、"current"が届けば閉じたturnの行も処理済み（遮断されていれば"current"だけが残る）。
    #expect(await eventually { await log.deltas() == ["current"] }, "採用後のイベントが届かない、または閉じたturnの遅延イベントが遮断されていない")
    let marker = UUID()
    await client.beginHandoverFence(marker)
    #expect(await eventually { await log.containsFence(marker) }, "フェンスが最上層へ届かない")

    #expect(await log.deltas() == ["current"])
    let state = try #require(await client.takeFenceState(marker))
    #expect(state.nextTurnStartGeneration == 5)
    #expect(state.rpc.nextRequestID == 10)
}

@Test func handoverStateRoundTripsEveryField() throws {
    let original = CodexHandoverState(
        stateVersion: CodexHandoverState.currentVersion,
        client: CodexClientHandoverState(
            turns: [.init(threadId: "t", activeTurnId: "u", closedTurnIds: ["a", "b"], hasObservedLifecycle: true)],
            nextTurnStartGeneration: 3,
            rpc: JSONRPCHandoverState(nextRequestID: 8, pendingServerRequests: [Data("{\"id\":9}".utf8)])),
        currentThreadId: "t", committedThreadId: "t", hasEstablishedThread: true, threadIdentityGeneration: 4,
        lastThreadStartParams: ThreadStartParams(cwd: "/tmp", model: "m"), pendingChildInterrupts: ["c": "p"],
        nativeImageInputEnabled: true, materializedImageDirectories: ["/tmp/img"])

    let decoded = try JSONDecoder().decode(CodexHandoverState.self, from: try JSONEncoder().encode(original))

    #expect(decoded == original)
}

// MARK: - 採用の失敗は復旧待ち（子には何もしない）

private func unreachableTransport() throws -> HolderTransport {
    let json = #"{"holderID":"h-x","protocolVersion":1,"holderPID":1,"childPID":1,"socketPath":"/tmp/phx-none/s/h-x.sock","startedAt":"2026-11-12T00:00:00Z","metadata":{}}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return HolderTransport(source: .adopt(record: try decoder.decode(HolderRecord.self, from: Data(json.utf8)), fromSeq: 0))
}

private func validState() -> CodexHandoverState {
    CodexHandoverState(
        stateVersion: CodexHandoverState.currentVersion,
        client: CodexClientHandoverState(
            turns: [], nextTurnStartGeneration: 0, rpc: JSONRPCHandoverState(nextRequestID: 1, pendingServerRequests: [])),
        currentThreadId: nil, committedThreadId: nil, hasEstablishedThread: false, threadIdentityGeneration: 0,
        lastThreadStartParams: nil, pendingChildInterrupts: [:], nativeImageInputEnabled: false,
        materializedImageDirectories: [])
}

private func adoptionFailure(_ state: Data, transport: HolderTransport) async -> String? {
    let structured = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
    await structured.prepareAdoption(state: state, transport: transport)
    do { try await structured.completeAdoption() } catch let error as HandoverError {
        if case .adoptionFailed(let reason) = error { return reason }
    } catch {}
    return nil
}

@Test func adoptionWithAnUnknownStateVersionFailsBeforeTouchingTheChild() async throws {
    let state = CodexHandoverState(
        stateVersion: 99,
        client: CodexClientHandoverState(
            turns: [], nextTurnStartGeneration: 0, rpc: JSONRPCHandoverState(nextRequestID: 1, pendingServerRequests: [])),
        currentThreadId: nil, committedThreadId: nil, hasEstablishedThread: false, threadIdentityGeneration: 0,
        lastThreadStartParams: nil, pendingChildInterrupts: [:], nativeImageInputEnabled: false,
        materializedImageDirectories: [])
    let reason = await adoptionFailure(try JSONEncoder().encode(state), transport: try unreachableTransport())

    // 接続に進む前に版で止まる（接続の失敗ではなく、版の不一致として報告される）。
    #expect(reason?.contains("版(99)") == true)
}

@Test func adoptionWithUnreadableStateFails() async throws {
    let reason = await adoptionFailure(Data("not json".utf8), transport: try unreachableTransport())
    #expect(reason?.contains("クライアント状態を読めません") == true)
}

private final class SendOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var text = "未完了（送信がまだ返っていない）"
    func set(_ value: String) { lock.withLock { text = value } }
    var value: String { lock.withLock { text } }
}

@Test func adoptionWithAnUnknownSendFailsAndLeavesTheChildAlone() async throws {
    // 子は最初の1KiBだけを読んで目印のファイル（$1）を作り、その後は標準入力を読まない。
    // 大きな送信の残りは書き切れず、holderには「受け付けたが結果不明」として残る。
    // 目印の作成は、holderが送信を受け付けた（beginSend）後にしか起きない。別の接続を取り付けると
    // 書込権を奪って送信中の接続を閉じるので、受け付ける前に取り付けると前提が壊れる（目印を待つ理由）。
    let fixture = try FakeServerFixture(
        script: #"dd bs=1024 count=1 of=/dev/null 2>/dev/null; : > "$1"; exec sleep 30"#)
    defer { fixture.cleanUp() }
    let started = Date()
    let writer = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    try writer.start()
    let outcome = SendOutcome()
    let blocked = Task {
        do {
            try await writer.send(Data(repeating: 0x61, count: 4 * 1024 * 1024) + Data([0x0A]))
            outcome.set("書き切れた（想定外）")
        } catch {
            outcome.set("エラー: \(error)")
        }
    }
    defer { blocked.cancel() }

    let markerSeen = await eventually(timeout: 10) { FileManager.default.fileExists(atPath: fixture.log) }
    try #require(markerSeen, "子が最初の入力を読んでいない（送信がholderへ届いていない）。送信結果=\(outcome.value) 経過=\(Date().timeIntervalSince(started))秒")

    // holderに結果不明の送信が残ったことを、別の接続の取り付け情報で確かめる。
    let probe = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    try probe.start()
    let unknown = probe.unknownSendIDs
    probe.releaseForHandover()
    try #require(!unknown.isEmpty, "holderに結果不明の送信が残らない。unknownSendIDs=\(unknown) 送信結果=\(outcome.value) 経過=\(Date().timeIntervalSince(started))秒")

    let adopting = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    let reason = await adoptionFailure(try JSONEncoder().encode(validState()), transport: adopting)

    #expect(reason?.contains("結果不明") == true, "採用が結果不明の送信で失敗していない: \(String(describing: reason))")
    // 子は終了も再生成もされない（同じPIDのまま生きている）。
    #expect(kill(fixture.record.childPID, 0) == 0)
}

@Test func sendsAfterAFailedCodexAdoptionNeverReachTheChild() async throws {
    // 採用に失敗した実行は復旧待ち。生きている子へは何も書かず、新しい子も作らない。
    let fixture = try FakeServerFixture()
    defer { fixture.cleanUp() }
    var state = validState()
    state.stateVersion = 99
    let transport = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    let structured = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
    await structured.prepareAdoption(state: try JSONEncoder().encode(state), transport: transport)
    await #expect(throws: HandoverError.self) { try await structured.completeAdoption() }

    await #expect(throws: (any Error).self) { try await structured.turnStart([.text("hello")]) }
    try await Task.sleep(for: .milliseconds(300))

    #expect(fixture.logLines.isEmpty, "復旧待ちのCodexが子へ書き込んだ: \(fixture.logLines)")
    #expect(kill(fixture.record.childPID, 0) == 0)
}

@Test func adoptionWhenTheHolderIsUnreachableFails() async throws {
    let state = CodexHandoverState(
        stateVersion: CodexHandoverState.currentVersion,
        client: CodexClientHandoverState(
            turns: [], nextTurnStartGeneration: 0, rpc: JSONRPCHandoverState(nextRequestID: 1, pendingServerRequests: [])),
        currentThreadId: nil, committedThreadId: nil, hasEstablishedThread: false, threadIdentityGeneration: 0,
        lastThreadStartParams: nil, pendingChildInterrupts: [:], nativeImageInputEnabled: false,
        materializedImageDirectories: [])
    let reason = await adoptionFailure(try JSONEncoder().encode(state), transport: try unreachableTransport())
    #expect(reason?.contains("holderへ接続できません") == true)
}

@Test func codexClientWithoutAHolderDefersTheHandover() async throws {
    let structured = CodexStructuredAgentClient(client: CodexAppServerClient(transport: MockTransport()))
    let reason = await structured.handoverGateReason()
    #expect(reason?.contains("holder経由ではありません") == true)
}

// MARK: - ProcessHolder と /bin/sh の偽 app-server による結合

/// 受け取った行を全てログへ書き、`initialize`/`thread/start`/`thread/read`/`turn/start`に応答する。
/// `turn/start`の後に承認要求（id 100）を送り、その応答（id 100）はログに書くだけ。
private let fakeAppServer = #"""
log="$1"
thread='{"id":"thread-1","cliVersion":"0.147.0","createdAt":1700000000,"ephemeral":false,"modelProvider":"openai","status":{"type":"idle"},"turns":[],"source":"appServer","cwd":"/tmp","sessionId":"session-1","preview":"p","updatedAt":1700000001}'
: > "$log"
while IFS= read -r line; do
  # JSONEncoderは"/"を"\/"にエスケープして送る。照合とログは、エスケープを外した形で行う。
  line=$(printf '%s' "$line" | sed 's|\\/|/|g')
  printf '%s\n' "$line" >> "$log"
  case "$line" in
    *'"result"'*) continue ;;
  esac
  id=$(printf '%s' "$line" | sed -n 's/^{"id":\([0-9][0-9]*\),.*/\1/p')
  case "$line" in
    *'"method":"initialize"'*)
      printf '{"jsonrpc":"2.0","id":%s,"result":{"codexHome":"/tmp","platformFamily":"unix","platformOs":"macos","userAgent":"fake"}}\n' "$id" ;;
    *'"method":"thread/start"'*|*'"method":"thread/read"'*)
      printf '{"jsonrpc":"2.0","id":%s,"result":{"thread":%s}}\n' "$id" "$thread" ;;
    *'"method":"turn/start"'*)
      printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
      printf '{"jsonrpc":"2.0","id":100,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}\n' ;;
  esac
done
"""#

/// ホストが送った要求行（`{"id":N,...`。キーは辞書順で出る）のID。
private func requestID(_ line: String) -> Int? {
    guard line.hasPrefix(#"{"id":"#), line.contains(#""method""#) else { return nil }
    return Int(line.dropFirst(6).prefix { $0.isNumber })
}

private struct FakeServerFixture {
    let holder: ProcessHolder
    let record: HolderRecord
    let root: String
    let log: String

    init(script: String = fakeAppServer) throws {
        let root = "/tmp/phx-cx-" + UUID().uuidString.prefix(8).lowercased()
        let log = root + "-log.txt"
        let spec = HolderSpawnSpec(
            command: "/bin/sh", arguments: ["-c", script, "fake", log],
            environment: ProcessInfo.processInfo.environment, workingDirectory: nil, metadata: ["session": "test"],
            recordDirectory: root + "/r", socketDirectory: root + "/s")
        let holder = ProcessHolder(spec: spec, orphanLinger: 5)
        self.record = try holder.start()
        self.holder = holder
        self.root = root
        self.log = log
    }

    var logLines: [String] {
        ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func count(_ needle: String) -> Int { logLines.filter { $0.contains(needle) }.count }

    func cleanUp() {
        kill(record.childPID, SIGKILL)
        try? FileManager.default.removeItem(atPath: root)
        try? FileManager.default.removeItem(atPath: log)
    }
}

private final class ApprovalProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var methods: [String] = []
    let blocks: Bool

    init(blocks: Bool) { self.blocks = blocks }

    var callCount: Int { lock.withLock { calls } }
    var requestMethods: [String] { lock.withLock { methods } }

    var handler: JSONRPCClient.ServerRequestHandler {
        { [self] request in
            lock.withLock { calls += 1; methods.append(request.method) }
            // 旧ホスト側の承認は、更新が終わるまで利用者が答えない（応答しない）。
            if blocks { try await Task.sleep(for: .seconds(3600)) }
            return try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept))
        }
    }
}

@Test func handoverKeepsTheChildAndPresentsTheApprovalOnceWithoutReinitializing() async throws {
    let fixture = try FakeServerFixture()
    defer { fixture.cleanUp() }
    // 失敗時の診断: 子が受け取った行の全て（永久待ちの原因を特定するため）。
    func diag(_ probes: ApprovalProbe...) -> String {
        "子の受信ログ=\(fixture.logLines) 承認ハンドラ呼び出し=\(probes.map(\.callCount))"
    }

    // --- 旧ホスト: 初期化→thread/start→turn/start。子が承認を要求し、利用者はまだ答えない。
    let oldTransport = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    try oldTransport.start()
    let oldProbe = ApprovalProbe(blocks: true)
    let old = CodexStructuredAgentClient(client: CodexAppServerClient(
        transport: oldTransport, serverRequestHandler: oldProbe.handler))
    await old.start()
    _ = try await within(10, "旧ホストのinitialize") {
        try await old.initialize(InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1")))
    }
    _ = try await within(10, "旧ホストのthread/start") { try await old.threadStart(ThreadStartParams()) }
    try await within(10, "旧ホストのturn/start") { try await old.turnStart([.text("go")]) }
    try #require(await eventually { oldProbe.callCount == 1 }, "旧ホストが承認要求を受け取れない \(diag(oldProbe))")
    #expect(await old.handoverGateReason() == nil)

    // --- 確定点→コミット（子は終了しない）。
    let preparation = try await within(15, "prepareHandover（フェンスの到達待ち）") { try await old.prepareHandover(fence: UUID()) }
    try await within(10, "commitHandover") { await old.commitHandover(confirmedThrough: preparation.appliedSeq) }
    #expect(kill(fixture.record.childPID, 0) == 0)
    // 手放した後の close()は子に触れない。
    try await within(10, "旧ホストのclose") { await old.close() }
    #expect(kill(fixture.record.childPID, 0) == 0)

    // --- 新ホスト: 採用。承認は再提示され、応答は同じIDで1回だけ子へ届く。
    let newTransport = HolderTransport(source: .adopt(record: preparation.holder, fromSeq: preparation.appliedSeq))
    let newProbe = ApprovalProbe(blocks: false)
    let adopted = CodexStructuredAgentClient(client: CodexAppServerClient(
        transport: newTransport, serverRequestHandler: newProbe.handler))
    await adopted.prepareAdoption(state: preparation.clientState, transport: newTransport)
    try await within(10, "completeAdoption") { try await adopted.completeAdoption() }

    try #require(await eventually { newProbe.callCount >= 1 }, "新ホストへ承認が再提示されない \(diag(oldProbe, newProbe))")
    // ログは子の標準入力＝ホストから子へ送った行だけ。承認への応答（"id":100）が届くのを待つ。
    #expect(await eventually { fixture.logLines.contains { $0.contains(#""id":100,"#) } }, "承認への応答が子へ届かない \(diag(oldProbe, newProbe))")
    try await Task.sleep(for: .milliseconds(300))
    #expect(newProbe.callCount == 1, "承認の再提示が1回でない \(diag(oldProbe, newProbe))") // 承認の再提示は1回
    #expect(newProbe.requestMethods == ["item/commandExecution/requestApproval"])
    #expect(oldProbe.callCount == 1)
    #expect(fixture.logLines.filter { $0.contains(#""id":100,"#) && $0.contains(#""result""#) }.count == 1, "応答が1回でない \(diag(oldProbe, newProbe))") // 応答は1回

    // initialize・thread/start・turn/startは増えず、thread/resumeは出ない。
    #expect(fixture.count(#""method":"initialize""#) == 1, "\(diag(oldProbe, newProbe))")
    #expect(fixture.count(#""method":"thread/start""#) == 1, "\(diag(oldProbe, newProbe))")
    #expect(fixture.count(#""method":"turn/start""#) == 1, "\(diag(oldProbe, newProbe))")
    #expect(fixture.count(#""method":"thread/resume""#) == 0, "\(diag(oldProbe, newProbe))")

    // 要求IDは旧ホストの続きの番号（既に使われたIDと重ならない）。
    let usedIDs = fixture.logLines.compactMap(requestID)
    _ = try await within(10, "採用後のthread/read") {
        try await adopted.threadRead(ThreadReadParams(threadId: "thread-1", includeTurns: false))
    }
    let readIDs = fixture.logLines.filter { $0.contains(#""method":"thread/read""#) }.compactMap(requestID)
    #expect(readIDs == [(usedIDs.max() ?? 0) + 1], "\(diag(oldProbe, newProbe))")
    #expect(kill(fixture.record.childPID, 0) == 0)

    try await within(10, "採用側のclose") { await adopted.close() }
}

@Test func adoptionWithAMissingSequenceRangeFailsAndLeavesTheChildAlone() async throws {
    // 子が5行（seq 1〜5）を出し、旧ホストがseq 5まで確認した（holderは破棄済み）。
    let fixture = try FakeServerFixture(script: "printf 'a\\nb\\nc\\nd\\ne\\n'; exec sleep 30")
    defer { fixture.cleanUp() }
    let first = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 0))
    try first.start()
    var lines = first.receivedLines.makeAsyncIterator()
    for _ in 0..<5 { _ = await lines.next() }
    first.confirm(through: 5)
    _ = await first.stderrTail()
    first.releaseForHandover()

    // 反映済みの番号が2のまま採用しようとすると、欠落として断る。
    let stale = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 2))
    let reason = await adoptionFailure(try JSONEncoder().encode(validState()), transport: stale)

    #expect(reason?.contains("保持する行が足りません") == true, "欠落に気づかず採用した: \(String(describing: reason))")
    #expect(kill(fixture.record.childPID, 0) == 0)
    // 手放しただけで確認は送っていない。
    let retry = HolderTransport(source: .adopt(record: fixture.record, fromSeq: 5))
    try retry.start()
    #expect(retry.adoptionContinuityFault() == nil)
    retry.releaseForHandover()
}
