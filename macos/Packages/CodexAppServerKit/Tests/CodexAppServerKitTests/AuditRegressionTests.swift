import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

// task-7 監査回帰テスト。以下の各ハザードが「未修正コードで crash/hang/取りこぼし」することを
// 符号化し、修正後は緑になる。与えられた受け入れテスト（このファイル）は編集対象だが、
// 実装を直して緑にする方針でありアサーションは弱めない。

// MARK: - I11: JSONValue.intValue の overflow/NaN クラッシュ（最優先・クラッシュ）

@Test func intValueReturnsNilForOverflowAndNaNAndKeepsValidIntegers() {
    // 未修正の `Int(value)` は 1e300 / NaN / ∞ で fatal error（プロセス abort）になる。
    // 修正後の `Int(exactly:)` は表現不能な値を nil にし、正常整数は従来値を返す。
    #expect(JSONValue.number(1e300).intValue == nil)
    #expect(JSONValue.number(Double.nan).intValue == nil)
    #expect(JSONValue.number(Double.infinity).intValue == nil)
    #expect(JSONValue.number(-Double.infinity).intValue == nil)

    // 正常整数はそのまま。
    #expect(JSONValue.number(42).intValue == 42)
    #expect(JSONValue.number(0).intValue == 0)
    #expect(JSONValue.number(-7).intValue == -7)
    // 2^53 は Double で厳密に表現でき Int にも収まる大整数。従来値を返す。
    #expect(JSONValue.number(9_007_199_254_740_992).intValue == 9_007_199_254_740_992)

    // Double(Int.max) は丸めで 2^63（Int.max+1）になり Int に収まらない → nil が正しい。
    #expect(JSONValue.number(Double(Int.max)).intValue == nil)

    // 小数部を持つ値は整数として扱わない（exactly: の意味）。
    #expect(JSONValue.number(42.5).intValue == nil)

    // 数値以外は従来どおり nil。
    #expect(JSONValue.string("42").intValue == nil)
    #expect(JSONValue.null.intValue == nil)
}

// MARK: - I8: stderr 未ドレインによる子プロセスの write ブロック（hang）

@Test func processTransportDoesNotHangWhenChildFloodsStderr() async throws {
    // 子が 64KiB を超える stderr を出してから stdout に応答を書く。stderr を並行ドレインしないと、
    // 子は stderr write でブロックし stdout に到達できず、transport は永遠に応答を返さない（hang）。
    let transport = ProcessTransport(
        command: "/usr/bin/perl",
        arguments: [
            "-e",
            "print STDERR \"x\" x 200000; print \"STDOUT_SURVIVED\\n\";",
        ]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["STDOUT_SURVIVED"])
}

// MARK: - I9: 終了直前の応答をドレインしてから finish（応答喪失なし）

@Test func processTransportDeliversFinalLineBeforeFinishAcrossRepeatedRuns() async throws {
    // 子が複数行を書いて即座に終了する。terminationHandler で即 finish すると、reader が最後の行を
    // 読み切る前にストリームが閉じ、終了直前の応答を取りこぼしうる。両 reader の EOF を待って
    // finish し、残データを読み切ってから閉じれば最終行は必ず届く。
    for _ in 0..<20 {
        let transport = ProcessTransport(
            command: "/bin/sh",
            arguments: ["-c", "printf '{\"id\":1}\\n{\"id\":2}\\n{\"id\":\"FINAL\"}\\n'"]
        )
        try transport.start()

        var lines: [String] = []
        for await line in transport.receivedLines {
            lines.append(String(data: line, encoding: .utf8) ?? "")
        }

        #expect(lines == ["{\"id\":1}", "{\"id\":2}", "{\"id\":\"FINAL\"}"])
    }
}

@Test func processTransportDeliversTrailingLineWithoutFinalNewline() async throws {
    // 末尾に改行のない最終行も、finish 時の残データ読み切りで喪失しない。
    let transport = ProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "printf 'line-1\\nline-2-no-newline'"]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["line-1", "line-2-no-newline"])
}

// MARK: - I10: 承認 await 中でも後続 response が処理される（直列 deadlock なし）

private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private actor ResultBox {
    private(set) var value: JSONValue?
    func set(_ newValue: JSONValue) { value = newValue }
    var isResolved: Bool { value != nil }
}

@Test func serverRequestApprovalDoesNotBlockSubsequentResponses() async throws {
    let transport = MockTransport()
    let gate = Gate()

    // 承認ハンドラは gate が開くまでブロックする。受信ループがこの await で直列化されていると、
    // ブロック中は後続の response も処理されず、client リクエストが永久に解決しない。
    let rpc = JSONRPCClient(transport: transport) { request in
        guard case .commandExecutionApproval = request else {
            throw JSONRPCClientError.unsupportedServerRequest(request.method)
        }
        await gate.wait()
        return try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept))
    }
    await rpc.start()

    // client リクエスト（id=1 を採番）を発行し、pending 登録を待つ。
    let box = ResultBox()
    let requestTask = Task {
        if let value = try? await rpc.requestJSON(method: "initialize", params: .object([:])) {
            await box.set(value)
        }
    }
    let requestSent = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "initialize" }
    }
    #expect(requestSent)

    // server→client リクエスト（承認・id=100）を配信。ハンドラは gate でブロックする。
    transport.receive("""
    {"jsonrpc":"2.0","id":100,"method":"item/commandExecution/requestApproval","params":{"threadId":"t","turnId":"tu","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}
    """)

    // 続けて client リクエストへの response（id=1）を配信。承認ハンドラがブロック中でも
    // この response は処理され、client リクエストが解決しなければならない。
    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"ok":true}}
    """)

    let resolvedWhileApprovalPending = await waitUntil { await box.isResolved }
    #expect(resolvedWhileApprovalPending)
    #expect(await box.value?["ok"]?.boolValueForTest == true)

    // 承認を解放すると、承認 response（id=100）が送られる。
    await gate.open()
    let approvalReplied = await waitUntil {
        await transport.sent.all().contains { $0["id"]?.intValue == 100 }
    }
    #expect(approvalReplied)
    let approvalResponse = try #require(await transport.sent.first { $0["id"]?.intValue == 100 })
    #expect(approvalResponse["result"]?["decision"]?.stringValue == "accept")

    requestTask.cancel()
    await rpc.close()
}

// MARK: - S: 空 threadId の interrupt 完了イベントを取りこぼさない

@Test func emptyThreadIdInterruptEventIsNotDroppedAfterThreadStart() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    // thread/start で currentThreadId を "thread-1" に確定させる。
    let startTask = Task { try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work")) }
    let startSent = await waitUntil {
        await transport.sent.all().contains { $0["method"]?.stringValue == "thread/start" }
    }
    #expect(startSent)
    let startRequest = try #require(await transport.sent.first { $0["method"]?.stringValue == "thread/start" })
    let startId = try #require(startRequest["id"]?.intValue)
    transport.receive("""
    {"jsonrpc":"2.0","id":\(startId),"result":{"thread":{"id":"thread-1","status":{"type":"idle"}}}}
    """)
    _ = try await startTask.value

    // threadId を欠いた turn/interrupted 通知（threadId は "" に補完される）。
    // フィルタが "" を別 thread として扱うと、この完了イベントが破棄される。
    let eventBox = ThreadEventBox()
    let consumer = Task {
        var iterator = adapter.threadEvents.makeAsyncIterator()
        if let event = await iterator.next() {
            await eventBox.set(event)
        }
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/interrupted","params":{"turnId":"turn-1"}}
    """)

    let received = await waitUntil { await eventBox.value != nil }
    #expect(received)
    if case .turnInterrupted(_, let turnId)? = await eventBox.value {
        #expect(turnId == "turn-1")
    } else {
        Issue.record("Expected turnInterrupted event to be delivered, got \(String(describing: await eventBox.value))")
    }

    consumer.cancel()
    await adapter.close()
}

private actor ThreadEventBox {
    private(set) var value: ThreadEvent?
    func set(_ newValue: ThreadEvent) { value = newValue }
}

private extension JSONValue {
    var boolValueForTest: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
