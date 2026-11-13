import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

/// 送信を記録し、サーバ要求への応答（method無し・id有り）だけを結果不明で失敗させる。`close()`の回数も数える。
final class ResponseFailingTransport: AppServerTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var responses: [JSONValue] = []
    private var delivered: [JSONValue] = []
    private var closeCalls = 0
    var failResponses = true
    /// 応答の送信が失敗するときのエラー（既定は結果不明）。
    var failure: Error = HolderError.sendResultUnknown(UUID())

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let value = try JSONDecoder.appServer.decode(JSONValue.self, from: data.filter { $0 != 0x0A })
        let isResponse = value["method"] == nil && value["id"] != nil
        guard isResponse else { return }
        lock.withLock { responses.append(value) }
        if failResponses { throw failure }
        lock.withLock { delivered.append(value) }
    }

    func close() async {
        lock.withLock { closeCalls += 1 }
        continuation.finish()
    }

    func receive(_ json: String) { continuation.yield(Data(json.utf8)) }
    func finishInput() { continuation.finish() }
    var responseCount: Int { lock.withLock { responses.count } }
    func responses(forID id: Int) -> [JSONValue] { lock.withLock { responses.filter { $0["id"]?.intValue == id } } }
    /// 実際に届いた（送信が失敗しなかった）応答。
    func deliveredResponses(forID id: Int) -> [JSONValue] { lock.withLock { delivered.filter { $0["id"]?.intValue == id } } }
    var closeCount: Int { lock.withLock { closeCalls } }
}

private let approvalLine = """
{"jsonrpc":"2.0","id":9,"method":"item/commandExecution/requestApproval","params":{"threadId":"t","turnId":"tu","itemId":"i","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}
"""

private func acceptHandler() -> JSONRPCClient.ServerRequestHandler {
    { _ in try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept)) }
}

private actor HandlerGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

private actor ErrorLog {
    private(set) var errors: [JSONRPCClientError] = []
    func append(_ error: JSONRPCClientError) { errors.append(error) }
}

// MARK: - 応答の送信失敗で同じIDへ再送しない

@Test func failedResponseSendIsNotRetriedWithAnErrorResponseForTheSameID() async throws {
    let transport = ResponseFailingTransport()
    let rpc = JSONRPCClient(transport: transport, serverRequestHandler: acceptHandler())
    let log = ErrorLog()
    let errors = await rpc.errors
    let errorTask = Task { for await error in errors { await log.append(error) } }
    defer { errorTask.cancel() }
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { transport.responses(forID: 9).count >= 1 }, "ID 9 への応答が子へ届かない（応答の総数=\(transport.responseCount)）")
    // 再送があれば、少し待つ間に2つ目が現れる。
    try await Task.sleep(for: .milliseconds(300))

    #expect(transport.responses(forID: 9).count == 1)
    #expect(transport.responses(forID: 9).first?["result"]?["decision"]?.stringValue == "accept")
    #expect(await eventually { await log.errors.contains { if case .responseNotDelivered = $0 { true } else { false } } })
    // 送信に失敗した要求は、記録に残さない（確定点で再投入も再送もしない）。
    #expect(await rpc.captureHandoverState().pendingServerRequests.isEmpty)
}

@Test func handlerErrorStillRepliesWithExactlyOneErrorResponse() async throws {
    let transport = ResponseFailingTransport()
    transport.failResponses = false
    let rpc = JSONRPCClient(transport: transport) { _ in throw JSONRPCClientError.unsupportedServerRequest("x") }
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { transport.responses(forID: 9).count >= 1 }, "ID 9 への応答が子へ届かない（応答の総数=\(transport.responseCount)）")
    try await Task.sleep(for: .milliseconds(200))

    #expect(transport.responses(forID: 9).count == 1)
    #expect(transport.responses(forID: 9).first?["error"]?["code"]?.intValue == -32601)
}

@Test func failedErrorResponseSendIsNotRetriedEither() async throws {
    let transport = ResponseFailingTransport()
    let rpc = JSONRPCClient(transport: transport) { _ in throw JSONRPCClientError.unsupportedServerRequest("x") }
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { transport.responses(forID: 9).count >= 1 }, "ID 9 への応答が子へ届かない（応答の総数=\(transport.responseCount)）")
    try await Task.sleep(for: .milliseconds(200))

    #expect(transport.responses(forID: 9).count == 1)
}

// MARK: - 状態の採取・適用

@Test func unansweredServerRequestIsCapturedVerbatimAndDroppedOnceAnswered() async throws {
    let transport = ResponseFailingTransport()
    transport.failResponses = false
    let gate = HandlerGate()
    let rpc = JSONRPCClient(transport: transport) { _ in
        await gate.wait()
        return try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept))
    }
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { await rpc.captureHandoverState().pendingServerRequests.count == 1 }, "サーバ要求が記録されない（受信されていない）")
    let captured = await rpc.captureHandoverState()
    #expect(captured.pendingServerRequests == [Data(approvalLine.utf8)])
    #expect(await rpc.handoverGateReason() == nil)

    await gate.release()
    #expect(await eventually { transport.responses(forID: 9).count == 1 }, "ID 9 への応答が子へ届かない（応答の総数=\(transport.responseCount)）")
    #expect(await eventually { await rpc.captureHandoverState().pendingServerRequests.isEmpty })
}

@Test func nextRequestIDIsCarriedAcrossAdoption() async throws {
    let first = MockTransport()
    let old = JSONRPCClient(transport: first)
    await old.start()
    Task { _ = try? await old.requestJSON(method: "thread/read", params: .object([:])) }
    #expect(await waitUntil(events: first.sent.changes) { await !first.sent.all().isEmpty })
    first.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    #expect(await eventually { await old.handoverGateReason() == nil })
    let state = await old.captureHandoverState()
    #expect(state.nextRequestID == 2)

    let second = MockTransport()
    let adopted = JSONRPCClient(transport: second)
    await adopted.applyHandoverState(JSONRPCHandoverState(nextRequestID: 10, pendingServerRequests: []))
    await adopted.start()
    Task { _ = try? await adopted.requestJSON(method: "thread/read", params: .object([:])) }
    #expect(await waitUntil(events: second.sent.changes) { await !second.sent.all().isEmpty })
    #expect(await second.sent.all().first?["id"]?.intValue == 10)
}

@Test func requestsAwaitingAResponseBlockTheHandoverGate() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()
    Task { _ = try? await rpc.requestJSON(method: "thread/read", params: .object([:])) }
    #expect(await waitUntil(events: transport.sent.changes) { await !transport.sent.all().isEmpty })

    #expect(await rpc.handoverGateReason() != nil)
    transport.receive(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    #expect(await eventually { await rpc.handoverGateReason() == nil })
}

@Test func reinjectedServerRequestIsAnsweredOnceWithTheSameID() async throws {
    let transport = ResponseFailingTransport()
    transport.failResponses = false
    let rpc = JSONRPCClient(transport: transport, serverRequestHandler: acceptHandler())

    // 受信を始める前に再投入する（引き継ぎの手順）。
    await rpc.reinjectServerRequests([Data(approvalLine.utf8)])
    await rpc.start()

    #expect(await eventually { transport.responses(forID: 9).count >= 1 }, "ID 9 への応答が子へ届かない（応答の総数=\(transport.responseCount)）")
    try await Task.sleep(for: .milliseconds(200))
    #expect(transport.responses(forID: 9).count == 1)
}

private final class EndFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

@Test func detachingDoesNotCloseTheTransportOrEndTheNotificationStream() async throws {
    let transport = ResponseFailingTransport()
    let rpc = JSONRPCClient(transport: transport)
    let ended = EndFlag()
    let notifications = await rpc.notifications
    let watcher = Task {
        for await _ in notifications {}
        ended.set()
    }
    defer { watcher.cancel() }
    await rpc.start()

    await rpc.detachForHandover()
    transport.finishInput()
    try await Task.sleep(for: .milliseconds(300))

    #expect(transport.closeCount == 0)
    // 入力の途切れを終了として扱わない: 通知ストリームは閉じない。
    #expect(!ended.isSet)
}

// MARK: - 確実に未送信の失敗は応答を失わない（M4）

@Test func responseBlockedByAHandoverIsKeptForTheCheckpointAndResentIfTheHandoverIsCancelled() async throws {
    let transport = ResponseFailingTransport()
    transport.failure = HolderError.handoverInProgress
    let rpc = JSONRPCClient(transport: transport, serverRequestHandler: acceptHandler())
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { transport.responses(forID: 9).count >= 1 }, "応答の送信が試みられない")
    // 確実に未送信なので記録が残り、確定点に載る（新ホストが再提示できる）。
    #expect(await eventually { await rpc.captureHandoverState().pendingServerRequests == [Data(approvalLine.utf8)] },
            "確実に未送信の応答の要求が確定点から落ちている")
    #expect(transport.deliveredResponses(forID: 9).isEmpty)

    // 更新が中止された: 送信が再開し、保持した応答が同じIDで1回だけ届く。
    transport.failResponses = false
    await rpc.resendUndeliveredResponses()
    #expect(transport.deliveredResponses(forID: 9).count == 1)
    #expect(transport.deliveredResponses(forID: 9).first?["result"]?["decision"]?.stringValue == "accept")
    #expect(await rpc.captureHandoverState().pendingServerRequests.isEmpty)

    // 2回目の再送では何も送らない。
    await rpc.resendUndeliveredResponses()
    #expect(transport.deliveredResponses(forID: 9).count == 1)
}

@Test func notWriterIsAlsoCertainlyUnsent() async throws {
    let transport = ResponseFailingTransport()
    transport.failure = HolderError.notWriter
    let rpc = JSONRPCClient(transport: transport, serverRequestHandler: acceptHandler())
    await rpc.start()

    transport.receive(approvalLine)
    #expect(await eventually { await rpc.captureHandoverState().pendingServerRequests.count == 1 }, "応答の記録が消えた")
}

@Test func resendStaysPendingWhileTheTransportStillRefusesTheResponse() async throws {
    let transport = ResponseFailingTransport()
    transport.failure = HolderError.handoverInProgress
    let rpc = JSONRPCClient(transport: transport, serverRequestHandler: acceptHandler())
    await rpc.start()
    transport.receive(approvalLine)
    #expect(await eventually { await rpc.captureHandoverState().pendingServerRequests.count == 1 })

    await rpc.resendUndeliveredResponses()   // まだ確実に未送信のまま
    #expect(await rpc.captureHandoverState().pendingServerRequests.count == 1)
    #expect(transport.deliveredResponses(forID: 9).isEmpty)
}
