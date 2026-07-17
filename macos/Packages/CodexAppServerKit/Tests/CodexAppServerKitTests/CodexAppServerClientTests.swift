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
    private let lock = NSLock()
    private var threadStartCount = 0

    init() {
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
            result = ["thread": ["id": "thread-resumed", "status": ["type": "idle"]]]
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

// task-8 差し戻し MUST1 回帰: threadResume（復元セッション）でも lastThreadStartParams を捕捉し、
// resetConversation → turnStart が新 thread へ届く（従来は currentThreadId=nil で threadNotStarted）。
@Test func codexResetAfterResumeStartsNewThreadAndRetargetsTurns() async throws {
    let transport = RespondingTransport()
    let client = CodexAppServerClient(transport: transport)
    let adapter = CodexStructuredAgentClient(client: client)
    await adapter.start()

    let resumed = try await adapter.threadResume(ThreadResumeParams(threadId: "restored", cwd: "/tmp/work"))
    #expect(resumed.thread.id == "thread-resumed")
    try await adapter.turnStart([.text("first")])

    await adapter.resetConversation()
    // reset 後の turnStart は throw せず新 thread へ届くこと（回帰の核心）。
    try await adapter.turnStart([.text("second")])

    let sent = await transport.sent.all()
    let turnStartThreadIds = sent.compactMap { message -> String? in
        guard message["method"]?.stringValue == "turn/start" else { return nil }
        return message["params"]?["threadId"]?.stringValue
    }
    // 復元 thread → reset 後は thread/start による新 thread-1 へ向かう。
    #expect(turnStartThreadIds == ["thread-resumed", "thread-1"])

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

    #expect(await iterator.next() == .warning(message: "画像添付は Claude のみ対応"))
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
    #expect(await waitUntil { await recorder.contains(.warning(message: "retrying")) })

    // adapter.close() ではなく、子プロセス異常終了相当の EOF を発生させる。
    await transport.close()

    #expect(await waitUntil { await recorder.containsTerminalProcessExitError })
    #expect(await waitUntil { await recorder.isFinished })
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
    #expect(await waitUntil { await recorder.contains(.warning(message: "retrying-1")) })

    transport.receive("""
    {"jsonrpc":"2.0","method":"error","params":{"error":{"message":"retrying-2"},"willRetry":true}}
    """)
    #expect(await waitUntil { await recorder.contains(.warning(message: "retrying-2")) })

    await transport.close()

    #expect(await waitUntil { await recorder.containsTerminalProcessExitError })
    #expect(await waitUntil { await recorder.isFinished })
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
    #expect(await waitUntil {
        await recorder.contains(.error(
            threadId: "thread-1",
            turnId: "turn-1",
            message: "retrying",
            willRetry: true
        ))
    })

    await client.close()

    #expect(await waitUntil { await recorder.isFinished })
    #expect(await recorder.containsTerminalProcessExitError == false)
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

    func append(_ event: NormalizedChatEvent) {
        recordedEvents.append(event)
    }

    func markFinished() {
        isFinished = true
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

    func append(_ event: ThreadEvent) {
        recordedEvents.append(event)
    }

    func markFinished() {
        isFinished = true
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
