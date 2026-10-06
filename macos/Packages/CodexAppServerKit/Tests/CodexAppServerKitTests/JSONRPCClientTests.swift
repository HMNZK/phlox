import Foundation
import Testing
@testable import CodexAppServerKit

@Test func requestResponseMatchesByID() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    async let response: InitializeResponse = rpc.request(
        method: "initialize",
        params: InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
    )

    let sent = await waitUntil(events: transport.sent.changes) {
        await !transport.sent.all().isEmpty
    }
    #expect(sent)
    let request = try #require(await transport.sent.all().first)
    #expect(request["method"]?.stringValue == "initialize")
    #expect(request["id"]?.intValue == 1)

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"macos","userAgent":"codex-test"}}
    """)

    let decoded = try await response
    #expect(decoded.userAgent == "codex-test")
    await rpc.close()
}

@Test func notificationRoutesToTypedStream() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    var iterator = await rpc.notifications.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","delta":"hello"}}
    """)

    let notification = await iterator.next()
    guard case .agentMessageDelta(let value) = notification else {
        Issue.record("Expected agent message delta")
        return
    }
    #expect(value.delta == "hello")
    await rpc.close()
}

@Test func approvalRequestUsesHandlerAndRepliesWithDecision() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport) { request in
        guard case .commandExecutionApproval(let approval) = request else {
            throw JSONRPCClientError.unsupportedServerRequest(request.method)
        }
        #expect(approval.command == "pwd")
        return try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept))
    }
    await rpc.start()

    transport.receive("""
    {"jsonrpc":"2.0","id":7,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}
    """)

    let replied = await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["id"]?.intValue == 7 }
    }
    #expect(replied)
    let response = try #require(await transport.sent.first { $0["id"]?.intValue == 7 })
    #expect(response["result"]?["decision"]?.stringValue == "accept")
    await rpc.close()
}

@Test func unknownServerRequestReceivesUnsupportedError() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    transport.receive("""
    {"jsonrpc":"2.0","id":9,"method":"item/tool/requestUserInput","params":{"itemId":"item-1"}}
    """)

    let replied = await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["id"]?.intValue == 9 }
    }
    #expect(replied)
    let response = try #require(await transport.sent.first { $0["id"]?.intValue == 9 })
    #expect(response["error"]?["code"]?.intValue == -32601)
    #expect(response["error"]?["message"]?.stringValue?.contains("Unsupported") == true)
    await rpc.close()
}

@Test func malformedJSONIsReportedAndPendingRequestsFailOnClose() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    var errorIterator = await rpc.errors.makeAsyncIterator()
    transport.receive("{ not json }")
    let error = await errorIterator.next()
    guard case .malformedMessage = error else {
        Issue.record("Expected malformed JSON error")
        return
    }

    async let response: InitializeResponse = rpc.request(
        method: "initialize",
        params: InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
    )
    let sent = await waitUntil(events: transport.sent.changes) {
        await !transport.sent.all().isEmpty
    }
    #expect(sent)
    await rpc.close()

    do {
        _ = try await response
        Issue.record("Expected transport closed error")
    } catch JSONRPCClientError.transportClosed {
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

// 承認ハンドラの await 中でも後続の response が処理される（受信ループが直列化されて deadlock しない）。
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
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func set(_ newValue: JSONValue) {
        value = newValue
        changeContinuation.yield()
    }
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
    let requestSent = await waitUntil(events: transport.sent.changes) {
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

    let resolvedWhileApprovalPending = await waitUntil(events: box.changes) {
        await box.isResolved
    }
    #expect(resolvedWhileApprovalPending)
    #expect(await box.value?["ok"]?.boolValueForTest == true)

    // 承認を解放すると、承認 response（id=100）が送られる。
    await gate.open()
    let approvalReplied = await waitUntil(events: transport.sent.changes) {
        await transport.sent.all().contains { $0["id"]?.intValue == 100 }
    }
    #expect(approvalReplied)
    let approvalResponse = try #require(await transport.sent.first { $0["id"]?.intValue == 100 })
    #expect(approvalResponse["result"]?["decision"]?.stringValue == "accept")

    requestTask.cancel()
    await rpc.close()
}

private extension JSONValue {
    var boolValueForTest: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
