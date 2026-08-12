import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

/// thread/start に対して呼ばれるたびに別の thread id（thread-1, thread-2, …）を返し、
/// turn/start・turn/interrupt には空 result を返す自動応答トランスポート。resetConversation の
/// 「新規 thread で以後の turnStart が続く」白箱検証に使う。
final class RespondingTransport: AppServerTransport, @unchecked Sendable {
    let sent = SentMessages()
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let resumeThreadId: String
    private let lock = NSLock()
    private var threadStartCount = 0

    init(resumeThreadId: String = "thread-resumed") {
        self.resumeThreadId = resumeThreadId
        var continuation: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func send(_ data: Data) async throws {
        try await sent.append(data)
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = Data(data[..<newline])
        } else {
            line = data
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String,
              let id = object["id"]
        else { return }
        let result: [String: Any]
        switch method {
        case "thread/start":
            let n = lock.withLock { () -> Int in
                threadStartCount += 1
                return threadStartCount
            }
            result = ["thread": ["id": "thread-\(n)", "status": ["type": "idle"]]]
        case "thread/resume":
            result = ["thread": ["id": resumeThreadId, "status": ["type": "idle"]]]
        default:
            result = [:]
        }
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        let responseData = try JSONSerialization.data(withJSONObject: response)
        continuation.yield(responseData)
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// task-8 白箱: resetConversation() は新しい thread を開始し、以後の turnStart がそちらへ向かう。
@Test func codexResetConversationStartsNewThreadAndRetargetsTurns() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    let started = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    #expect(started.thread.id == "thread-1")
    try await adapter.turnStart([.text("first")])

    await adapter.resetConversation()
    try await adapter.turnStart([.text("second")])

    let sent = await transport.sent.all()
    let turnStartThreadIds = sent.compactMap { message -> String? in
        guard message["method"]?.stringValue == "turn/start" else { return nil }
        return message["params"]?["threadId"]?.stringValue
    }
    // 1ターン目は thread-1、reset 後の2ターン目は新規 thread-2 へ向かう。
    #expect(turnStartThreadIds == ["thread-1", "thread-2"])

    await adapter.close()
}

// 成功した thread/resume 後も resetConversation が新しい thread を開始し、
// 以後の turnStart がその新 thread へ向かう回帰を保持する。
@Test func codexResetAfterSuccessfulResumeStartsNewThreadAndRetargetsTurns() async throws {
    let transport = RespondingTransport(resumeThreadId: "restored")
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    let resumed = try await adapter.threadResume(ThreadResumeParams(threadId: "restored", cwd: "/tmp/work"))
    #expect(resumed.thread.id == "restored")
    try await adapter.turnStart([.text("first")])

    await adapter.resetConversation()
    try await adapter.turnStart([.text("second")])

    let sent = await transport.sent.all()
    let turnStartThreadIds = sent.compactMap { message -> String? in
        guard message["method"]?.stringValue == "turn/start" else { return nil }
        return message["params"]?["threadId"]?.stringValue
    }
    #expect(turnStartThreadIds == ["restored", "thread-1"])

    await adapter.close()
}

@Test func childInterruptedCompletionDoesNotNormalizeIntoParentTurnStop() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    _ = try await adapter.turnInterrupt(TurnInterruptParams(threadId: "child-1", turnId: "turn-child"))

    let recorder = OrderedEventRecorder()
    let collector = Task {
        for await event in adapter.orderedEvents {
            await recorder.append(event)
        }
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"child-1","turn":{"id":"turn-child","status":"interrupted","items":[]}}}
    """)

    #expect(await waitUntil(events: recorder.changes) { await recorder.count == 1 })
    #expect(await recorder.events == [
        .thread(.turnCompleted(
            threadId: "child-1",
            turn: TurnSummary(id: "turn-child", status: "interrupted", items: [])
        )),
    ])
    try await Task.sleep(for: .milliseconds(20))
    #expect(await recorder.count == 1)

    collector.cancel()
    await adapter.close()
}

// 現行契約: thread/resume が要求 ID と異なる thread を返した場合はエラーとし、
// 返された別 thread へ currentThreadId や後続 turn を retarget しない。
@Test func codexResumeRejectsMismatchedThreadWithoutRetargetingTurns() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    do {
        _ = try await adapter.threadResume(ThreadResumeParams(threadId: "restored", cwd: "/tmp/work"))
        Issue.record("thread/resume の ID mismatch が成功扱いになっている")
    } catch let error as CodexAppServerClientError {
        #expect(error == .threadIDMismatch(requested: "restored", received: "thread-resumed"))
    } catch {
        Issue.record("thread/resume の ID mismatch が想定外のエラーになっている: \(error)")
    }

    let sent = await transport.sent.all()
    #expect(sent.contains { $0["method"]?.stringValue == "thread/resume" })
    #expect(!sent.contains { $0["method"]?.stringValue == "turn/start" })
    #expect(await adapter.activeThreadId() == nil)

    await adapter.close()
}

@Test func codexStructuredAdapterDegradesImagesWithSingleWarningAndTextOnlyInput() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))

    var iterator = adapter.events.makeAsyncIterator()
    try await adapter.turnStart([
        .text("describe"),
        .image(data: Data([1, 2, 3]), mediaType: "image/png"),
        .image(data: Data([4, 5, 6]), mediaType: "image/jpeg"),
    ])

    #expect(await iterator.next() == .warning(message: "画像添付は Claude と画像対応モデルの Codex に対応"))
    let sent = await transport.sent.all()
    let turnStart = try #require(sent.first { message in
        message["method"]?.stringValue == "turn/start"
    })
    let input = try #require(turnStart["params"]?["input"])
    #expect(input == .array([
        .object([
            "text": .string("describe"),
            "type": .string("text"),
        ]),
    ]))

    await adapter.close()
}

@Test func codexStructuredAdapterMaterializesImagesAsLocalImage() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    let writes = ImageWriteRecorder()
    await adapter.setImageInputWriterForTesting { data, url in
        writes.append(data, url)
        try data.write(to: url)
    }
    try await adapter.turnStart([.text("describe"), .image(data: Data([1, 2, 3]), mediaType: "image/png")])

    let request = try #require(await transport.sent.first { $0["method"]?.stringValue == "turn/start" })
    guard case .array(let inputs) = request["params"]?["input"] else {
        Issue.record("turn/start input が配列でない")
        return
    }
    #expect(inputs.contains { $0["type"] == .string("localImage") })
    #expect(writes.data == [Data([1, 2, 3])])
    await adapter.close()
}

private final class ImageWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data: [Data] = []

    func append(_ value: Data, _ url: URL) {
        lock.lock()
        data.append(value)
        lock.unlock()
    }
}

private actor OrderedEventRecorder {
    private(set) var events: [CodexStructuredEvent] = []
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func append(_ event: CodexStructuredEvent) {
        events.append(event)
        changeContinuation.yield()
    }

    var count: Int { events.count }
}

@Test func codexStructuredAdapterMaterializationFailureDoesNotSendTurn() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)
    await adapter.setImageInputWriterForTesting { _, _ in
        throw NSError(domain: "test", code: 1)
    }

    await #expect(throws: CodexStructuredClientError.imageMaterializationFailed) {
        try await adapter.turnStart([.text("describe"), .image(data: Data([1, 2, 3]), mediaType: "image/png")])
    }
    #expect(await transport.sent.first { $0["method"]?.stringValue == "turn/start" } == nil)
    await adapter.close()
}

@Test func clientNormalizesKnownNotificationsAndIgnoresUnknown() async throws {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/name/updated","params":{"threadId":"thread-1","name":"ignored"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-1","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}
    """)

    let event = await iterator.next()
    guard case .threadStatusChanged(let threadId, let status) = event else {
        Issue.record("Expected thread status event")
        return
    }
    #expect(threadId == "thread-1")
    #expect(status == .active(flags: ["waitingOnApproval"]))
    await client.close()
}

// task-1 統合シーム: codex-rs の実ワイヤ形状を生 JSON から既存デコード経路へ通し、
// willRetry=true が ThreadEvent に保持され、非終端 warning に正規化されることを固定する。
@Test func codexRetryableErrorWireNotificationNormalizesToWarning() async {
    let (threadEvent, normalizedEvent) = await decodeErrorNotificationThroughClient("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"stream disconnected; retrying"},"willRetry":true,"threadId":"thread-1","turnId":"turn-1"}}
    """)

    #expect(threadEvent == .error(
        threadId: "thread-1",
        turnId: "turn-1",
        message: "stream disconnected; retrying",
        willRetry: true
    ))
    #expect(normalizedEvent == .warning(message: "stream disconnected; retrying"))
}

// willRetry=false は同じ生 JSON 経路で終端 error に正規化される。
@Test func codexNonRetryableErrorWireNotificationNormalizesToError() async {
    let (threadEvent, normalizedEvent) = await decodeErrorNotificationThroughClient("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"quota exceeded"},"willRetry":false,"threadId":"thread-1","turnId":"turn-1"}}
    """)

    #expect(threadEvent == .error(
        threadId: "thread-1",
        turnId: "turn-1",
        message: "quota exceeded",
        willRetry: false
    ))
    #expect(normalizedEvent == .error(message: "quota exceeded"))
}

// 旧 app-server 互換で willRetry が欠落しても、nil を非再試行として安全側の error にする。
@Test func codexErrorWireNotificationWithoutWillRetryNormalizesToError() async {
    let (threadEvent, normalizedEvent) = await decodeErrorNotificationThroughClient("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"unknown failure"},"threadId":"thread-1","turnId":"turn-1"}}
    """)

    #expect(threadEvent == .error(
        threadId: "thread-1",
        turnId: "turn-1",
        message: "unknown failure",
        willRetry: nil
    ))
    #expect(normalizedEvent == .error(message: "unknown failure"))
}

@Test func transportEOFProducesTerminalEventAfterRetryableError() async {
    let transport = MockTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    let recorder = NormalizedEventRecorder()
    await adapter.start()

    let collector = Task {
        for await event in adapter.events {
            await recorder.append(event)
        }
        await recorder.markFinished()
    }

    transport.receive("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"retrying"},"willRetry":true,"threadId":"thread-1","turnId":"turn-1"}}
    """)
    #expect(await waitUntil(events: recorder.changes) {
        await recorder.contains(.warning(message: "retrying"))
    })

    // adapter.close() ではなく、子プロセス異常終了相当の EOF を発生させる。
    await transport.close()

    #expect(await waitUntil(events: recorder.changes) { await recorder.containsTerminalProcessExitError })
    #expect(await waitUntil(events: recorder.changes) { await recorder.isFinished })
    await adapter.close()
    _ = await collector.result
}

@Test func retryableErrorWithoutThreadIdDoesNotLoseActiveTurnBeforeEOF() async {
    let transport = MockTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    let recorder = NormalizedEventRecorder()
    await adapter.start()

    let collector = Task {
        for await event in adapter.events {
            await recorder.append(event)
        }
        await recorder.markFinished()
    }

    transport.receive("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"retrying-1"},"willRetry":true,"threadId":"thread-1","turnId":"turn-1"}}
    """)
    #expect(await waitUntil(events: recorder.changes) {
        await recorder.contains(.warning(message: "retrying-1"))
    })

    transport.receive("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"retrying-2"},"willRetry":true}}
    """)
    #expect(await waitUntil(events: recorder.changes) {
        await recorder.contains(.warning(message: "retrying-2"))
    })

    await transport.close()

    #expect(await waitUntil(events: recorder.changes) { await recorder.containsTerminalProcessExitError })
    #expect(await waitUntil(events: recorder.changes) { await recorder.isFinished })
    await adapter.close()
    _ = await collector.result
}

@Test func normalCloseDoesNotProduceFalseTerminalProcessExitError() async {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let recorder = ThreadEventRecorder()
    await client.start()

    let collector = Task {
        for await event in client.events {
            await recorder.append(event)
        }
        await recorder.markFinished()
    }

    transport.receive("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"retrying"},"willRetry":true,"threadId":"thread-1","turnId":"turn-1"}}
    """)
    #expect(await waitUntil(events: recorder.changes) {
        await recorder.contains(.error(
            threadId: "thread-1",
            turnId: "turn-1",
            message: "retrying",
            willRetry: true
        ))
    })

    await client.close()

    #expect(await waitUntil(events: recorder.changes) { await recorder.isFinished })
    #expect(await recorder.containsTerminalProcessExitError == false)
    _ = await collector.result
}

@Test func orderedEventsFinishAfterStructuredClientClose() async {
    let transport = MockTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    let recorder = NormalizedEventRecorder()
    await adapter.start()

    let collector = Task {
        for await _ in adapter.orderedEvents {}
        await recorder.markFinished()
    }

    await adapter.close()

    #expect(await waitUntil(events: recorder.changes) { await recorder.isFinished })
    _ = await collector.result
}

@Test func orderedEventsFinishAfterTransportEOF() async {
    let transport = MockTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    let recorder = NormalizedEventRecorder()
    await adapter.start()

    let collector = Task {
        for await _ in adapter.orderedEvents {}
        await recorder.markFinished()
    }

    await transport.close()

    #expect(await waitUntil(events: recorder.changes) { await recorder.isFinished })
    await adapter.close()
    _ = await collector.result
}

private func decodeErrorNotificationThroughClient(
    _ json: String
) async -> (ThreadEvent?, NormalizedChatEvent?) {
    let transport = MockTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    var threadEvents = adapter.threadEvents.makeAsyncIterator()
    var normalizedEvents = adapter.events.makeAsyncIterator()
    transport.receive(json)

    let result = (await threadEvents.next(), await normalizedEvents.next())
    await adapter.close()
    return result
}

private actor NormalizedEventRecorder {
    private var recordedEvents: [NormalizedChatEvent] = []
    private(set) var isFinished = false
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func append(_ event: NormalizedChatEvent) {
        recordedEvents.append(event)
        changeContinuation.yield()
    }

    func markFinished() {
        isFinished = true
        changeContinuation.yield()
    }

    func contains(_ event: NormalizedChatEvent) -> Bool {
        recordedEvents.contains(event)
    }

    var containsTerminalProcessExitError: Bool {
        recordedEvents.contains { event in
            guard case .error(let message) = event else { return false }
            return message.contains("app-server process exited")
        }
    }
}

private actor ThreadEventRecorder {
    private var recordedEvents: [ThreadEvent] = []
    private(set) var isFinished = false
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init() {
        var captured: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        changeContinuation = captured!
    }

    func append(_ event: ThreadEvent) {
        recordedEvents.append(event)
        changeContinuation.yield()
    }

    func markFinished() {
        isFinished = true
        changeContinuation.yield()
    }

    func contains(_ event: ThreadEvent) -> Bool {
        recordedEvents.contains(event)
    }

    var containsTerminalProcessExitError: Bool {
        recordedEvents.contains { event in
            guard case .error(_, _, let message, _) = event else { return false }
            return message.contains("app-server process exited")
        }
    }
}
