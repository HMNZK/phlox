import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-1 受け入れテスト（PM 著・凍結）。契約: tasks/task-1.md。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。
// イベント検証は「収集タスク＋ポーリング」方式（未実装でもハングせず時間内に red になる）。

// MARK: - ハーネス

private final class AskQMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        lock.withLock { sent.append(data) }
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func stderrTail() async -> String? { nil }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func finishStream() {
        continuation?.finish()
    }

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private struct AskQTransportStart {
    var arguments: [String]
}

private final class AskQTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let transport: AskQMockTransport
    private var recordedStarts: [AskQTransportStart] = []

    init(_ transport: AskQMockTransport) {
        self.transport = transport
    }

    var starts: [AskQTransportStart] {
        lock.withLock { recordedStarts }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        lock.withLock { recordedStarts.append(AskQTransportStart(arguments: arguments)) }
        return transport
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [NormalizedChatEvent] = []

    func append(_ event: NormalizedChatEvent) {
        lock.withLock { collected.append(event) }
    }

    var all: [NormalizedChatEvent] {
        lock.withLock { collected }
    }

    func firstIndex(of event: NormalizedChatEvent) -> Int? {
        lock.withLock { collected.firstIndex(of: event) }
    }
}

/// client.events を収集タスクへ吸い上げる（テスト終了時に task をキャンセル）。
private func collectEvents(of client: ClaudeChatClient) -> (EventCollector, Task<Void, Never>) {
    let collector = EventCollector()
    let events = client.events
    let task = Task {
        for await event in events {
            collector.append(event)
        }
    }
    return (collector, task)
}

private func makeClient(_ recorder: AskQTransportRecorder) -> ClaudeChatClient {
    // environment: [:] — Phlox 配下実行時の PHLOX_SESSION_ID 漏れを遮断する（決定論）。
    ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
}

/// AskUserQuestion の can_use_tool control_request（未知フィールド previewHint を含む＝
/// パススルー忠実性の検証用）。
private let askUserQuestionLine = """
{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool",\
"tool_name":"AskUserQuestion","input":{"questions":[{"question":"デプロイ先は?",\
"header":"Deploy","options":[{"label":"staging","description":"検証環境"},\
{"label":"prod"}],"multiSelect":false,"previewHint":"keep-me"}]},"tool_use_id":"toolu_1"}}
"""

private let expectedQuestions = [
    ChatUserQuestion(
        question: "デプロイ先は?",
        header: "Deploy",
        options: [
            ChatUserQuestionOption(label: "staging", description: "検証環境"),
            ChatUserQuestionOption(label: "prod", description: nil),
        ],
        multiSelect: false
    ),
]

private let expectedRequestedEvent = NormalizedChatEvent.userQuestionRequested(
    requestId: "req-1",
    questions: expectedQuestions
)

private func controlResponses(in transport: AskQMockTransport) -> [[String: Any]] {
    transport.sentStrings().compactMap { line in
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "control_response"
        else { return nil }
        return obj
    }
}

private func waitFor(
    _ comment: Comment,
    timeoutMs: Int = 3000,
    _ condition: @escaping () -> Bool
) async throws {
    for _ in 0..<(timeoutMs / 10) {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(condition(), comment)
}

// MARK: - 受け入れ条件

@Test func spawnArgumentsIncludePermissionPromptToolStdio() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()

    let arguments = recorder.starts.first?.arguments ?? []
    let pairIndex = arguments.firstIndex(of: "--permission-prompt-tool")
    #expect(pairIndex != nil)
    if let pairIndex, pairIndex + 1 < arguments.count {
        #expect(arguments[pairIndex + 1] == "stdio")
    } else {
        Issue.record("--permission-prompt-tool has no value: \(arguments)")
    }
    await client.close()
}

@Test func askUserQuestionRequestYieldsUserQuestionRequested() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive(askUserQuestionLine)

    try await waitFor("userQuestionRequested が yield される") {
        collector.all.contains(expectedRequestedEvent)
    }
    await client.close()
    task.cancel()
}

@Test func respondWritesAllowControlResponseWithPassthroughAndYieldsAnswered() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive(askUserQuestionLine)
    try await waitFor("質問受信") { collector.all.contains(expectedRequestedEvent) }

    await client.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])

    let responses = controlResponses(in: mock)
    #expect(responses.count == 1)
    let envelope = try #require(responses.first?["response"] as? [String: Any])
    #expect(envelope["subtype"] as? String == "success")
    #expect(envelope["request_id"] as? String == "req-1")
    let inner = try #require(envelope["response"] as? [String: Any])
    #expect(inner["behavior"] as? String == "allow")
    let updatedInput = try #require(inner["updatedInput"] as? [String: Any])

    // パススルー忠実性: 原文 input.questions（未知フィールド previewHint 含む）と JSON 等価。
    let originalData = askUserQuestionLine.data(using: .utf8)!
    let originalObj = try JSONSerialization.jsonObject(with: originalData) as! [String: Any]
    let originalRequest = originalObj["request"] as! [String: Any]
    let originalInput = originalRequest["input"] as! [String: Any]
    let originalQuestions = originalInput["questions"] as! [Any]
    let passedQuestions = try #require(updatedInput["questions"] as? [Any])
    #expect(NSArray(array: passedQuestions).isEqual(to: originalQuestions))

    // single-select の answers 値は String（label そのもの）。
    let answers = try #require(updatedInput["answers"] as? [String: Any])
    #expect(answers["デプロイ先は?"] as? String == "staging")

    // 回答イベントが yield される。
    try await waitFor("userQuestionResolved(.answered) が yield される") {
        collector.all.contains(.userQuestionResolved(
            requestId: "req-1",
            outcome: .answered(answers: ["デプロイ先は?": ["staging"]])
        ))
    }
    await client.close()
    task.cancel()
}

@Test func multiSelectAnswersEncodeAsArray() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive("""
    {"type":"control_request","request_id":"req-2","request":{"subtype":"can_use_tool",\
    "tool_name":"AskUserQuestion","input":{"questions":[{"question":"どの機能を含める?",\
    "header":"Scope","options":[{"label":"A"},{"label":"B"},{"label":"C"}],\
    "multiSelect":true}]},"tool_use_id":"toolu_2"}}
    """)
    try await waitFor("質問受信") {
        collector.all.contains { event in
            if case .userQuestionRequested(let requestId, _) = event { return requestId == "req-2" }
            return false
        }
    }

    await client.respondToUserQuestion(requestId: "req-2", answers: ["どの機能を含める?": ["A", "C"]])

    let responses = controlResponses(in: mock)
    #expect(responses.count == 1)
    let envelope = try #require(responses.first?["response"] as? [String: Any])
    let inner = try #require(envelope["response"] as? [String: Any])
    let updatedInput = try #require(inner["updatedInput"] as? [String: Any])
    let answers = try #require(updatedInput["answers"] as? [String: Any])
    #expect(answers["どの機能を含める?"] as? [String] == ["A", "C"])
    await client.close()
    task.cancel()
}

@Test func nonAskUserQuestionToolGetsImmediateDenyWithoutEvent() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive("""
    {"type":"control_request","request_id":"req-3","request":{"subtype":"can_use_tool",\
    "tool_name":"Bash","input":{"command":"echo hi"},"tool_use_id":"toolu_3"}}
    """)

    try await waitFor("deny が返送される") { controlResponses(in: mock).count == 1 }
    let envelope = try #require(controlResponses(in: mock).first?["response"] as? [String: Any])
    #expect(envelope["request_id"] as? String == "req-3")
    let inner = try #require(envelope["response"] as? [String: Any])
    #expect(inner["behavior"] as? String == "deny")
    let message = inner["message"] as? String ?? ""
    #expect(message.contains("Phlox"))

    // 質問イベントは yield されない。
    mock.receive("""
    {"type":"result","subtype":"success","is_error":false}
    """)
    try await waitFor("turn 完了") { collector.all.contains(.turnCompleted(nativeSessionId: nil)) }
    let hasQuestionEvent = collector.all.contains { event in
        if case .userQuestionRequested = event { return true }
        return false
    }
    #expect(!hasQuestionEvent)
    await client.close()
    task.cancel()
}

@Test func unknownRequestIdRespondWritesNothing() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()

    await client.respondToUserQuestion(requestId: "no-such-request", answers: ["Q": ["A"]])

    #expect(controlResponses(in: mock).isEmpty)
    await client.close()
}

@Test func pendingQuestionExpiresOnStreamEnd() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive(askUserQuestionLine)
    try await waitFor("質問受信") { collector.all.contains(expectedRequestedEvent) }

    mock.finishStream()

    try await waitFor("stream 終了で失効する") {
        collector.all.contains(.userQuestionResolved(requestId: "req-1", outcome: .expired))
    }

    // 失効後の回答は無送信の no-op。
    await client.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])
    #expect(controlResponses(in: mock).isEmpty)
    task.cancel()
}

@Test func pendingQuestionExpiresOnInterrupt() async throws {
    let mock = AskQMockTransport()
    let recorder = AskQTransportRecorder(mock)
    let client = makeClient(recorder)
    await client.start()
    let (collector, task) = collectEvents(of: client)

    mock.receive(askUserQuestionLine)
    try await waitFor("質問受信") { collector.all.contains(expectedRequestedEvent) }

    try await client.interrupt()

    // 保留質問には deny を返して CLI のブロックを解く。
    try await waitFor("deny が返送される") { controlResponses(in: mock).count == 1 }
    let envelope = try #require(controlResponses(in: mock).first?["response"] as? [String: Any])
    #expect(envelope["request_id"] as? String == "req-1")
    let inner = try #require(envelope["response"] as? [String: Any])
    #expect(inner["behavior"] as? String == "deny")

    // 失効イベント → turnInterrupted の順で yield される。
    let expiredEvent = NormalizedChatEvent.userQuestionResolved(requestId: "req-1", outcome: .expired)
    let interruptedEvent = NormalizedChatEvent.turnInterrupted(nativeSessionId: nil)
    try await waitFor("失効と turnInterrupted の両方が yield される") {
        collector.all.contains(expiredEvent) && collector.all.contains(interruptedEvent)
    }
    let expiredIndex = try #require(collector.firstIndex(of: expiredEvent))
    let interruptedIndex = try #require(collector.firstIndex(of: interruptedEvent))
    #expect(expiredIndex < interruptedIndex)
    await client.close()
    task.cancel()
}
