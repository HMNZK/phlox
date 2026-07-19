import Foundation
import StructuredChatKit
import Testing
@testable import ClaudeAgentKit

private final class ControlProtocolMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sentLines: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        lock.withLock { sentLines.append(data) }
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    var sent: [Data] {
        lock.withLock { sentLines }
    }
}

private final class ControlProtocolTransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [ControlProtocolMockTransport] = []

    func make(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = ControlProtocolMockTransport()
        lock.withLock { transports.append(transport) }
        return transport
    }

    func transport(at index: Int) -> ControlProtocolMockTransport? {
        lock.withLock {
            guard transports.indices.contains(index) else { return nil }
            return transports[index]
        }
    }
}

private final class ControlProtocolEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []

    func append(_ event: NormalizedChatEvent) {
        lock.withLock { events.append(event) }
    }

    func contains(_ event: NormalizedChatEvent) -> Bool {
        lock.withLock { events.contains(event) }
    }

    func count(where predicate: (NormalizedChatEvent) -> Bool) -> Int {
        lock.withLock { events.count(where: predicate) }
    }
}

private func waitForControlProtocolCondition(
    _ comment: Comment,
    condition: @escaping () -> Bool
) async throws {
    for _ in 0..<300 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), comment)
}

private func collectControlProtocolEvents(
    from client: ClaudeChatClient
) -> (ControlProtocolEventLog, Task<Void, Never>) {
    let log = ControlProtocolEventLog()
    let events = client.events
    let task = Task {
        for await event in events {
            log.append(event)
        }
    }
    return (log, task)
}

/// send を任意タイミングまで suspend できる transport（allow 送信中の interrupt 競合再現用）。
private final class SuspendingSendTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sentLines: [Data] = []
    private var sendGate: CheckedContinuation<Void, Never>?
    private var suspendNextSend = false
    private var sendStartedCount = 0

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}

    func armSuspendingSend() {
        lock.withLock { suspendNextSend = true }
    }

    func send(_ data: Data) async throws {
        let shouldSuspend = lock.withLock {
            sendStartedCount += 1
            let armed = suspendNextSend
            suspendNextSend = false
            return armed
        }
        if shouldSuspend {
            await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                lock.withLock { sendGate = gate }
            }
        }
        lock.withLock { sentLines.append(data) }
    }

    func releaseSend() {
        let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let captured = sendGate
            sendGate = nil
            return captured
        }
        gate?.resume()
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    var sent: [Data] {
        lock.withLock { sentLines }
    }

    var sendsStarted: Int {
        lock.withLock { sendStartedCount }
    }
}

private func controlResponses(in lines: [Data], requestId: String) -> [String] {
    lines.compactMap { line -> String? in
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "control_response",
              let response = object["response"] as? [String: Any],
              response["request_id"] as? String == requestId,
              let inner = response["response"] as? [String: Any]
        else { return nil }
        return inner["behavior"] as? String
    }
}

@Test func askUserQuestionDefaultsMissingDescriptionAndMultiSelect() async throws {
    let factory = ControlProtocolTransportFactory()
    let client = ClaudeChatClient(environment: [:], transportFactory: factory.make)
    await client.start()
    let transport = try #require(factory.transport(at: 0))
    let (log, collector) = collectControlProtocolEvents(from: client)

    transport.receive(#"{"type":"control_request","request_id":"defaults","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Choose","header":"Choice","options":[{"label":"A"}]}]}}}"#)

    let expected = NormalizedChatEvent.userQuestionRequested(
        requestId: "defaults",
        questions: [
            ChatUserQuestion(
                question: "Choose",
                header: "Choice",
                options: [ChatUserQuestionOption(label: "A", description: nil)],
                multiSelect: false
            ),
        ]
    )
    try await waitForControlProtocolCondition("省略値が既定値で解釈される") {
        log.contains(expected)
    }

    await client.close()
    collector.cancel()
}

@Test func respawnExpiresPendingAndOldResponseNeverWritesToNewTransport() async throws {
    let factory = ControlProtocolTransportFactory()
    let client = ClaudeChatClient(environment: [:], transportFactory: factory.make)
    await client.start()
    let firstTransport = try #require(factory.transport(at: 0))
    let (log, collector) = collectControlProtocolEvents(from: client)

    firstTransport.receive(#"{"type":"control_request","request_id":"old-generation","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Old?","header":"Old","options":[{"label":"Yes"}],"multiSelect":false}]}}}"#)
    let requested = NormalizedChatEvent.userQuestionRequested(
        requestId: "old-generation",
        questions: [
            ChatUserQuestion(
                question: "Old?",
                header: "Old",
                options: [ChatUserQuestionOption(label: "Yes", description: nil)],
                multiSelect: false
            ),
        ]
    )
    try await waitForControlProtocolCondition("旧世代の質問が保留になる") {
        log.contains(requested)
    }

    try await client.resume(sessionRef: "new-session")
    let secondTransport = try #require(factory.transport(at: 1))
    try await waitForControlProtocolCondition("respawn で旧質問が失効する") {
        log.contains(.userQuestionResolved(requestId: "old-generation", outcome: .expired))
    }

    await client.respondToUserQuestion(requestId: "old-generation", answers: ["Old?": ["Yes"]])

    #expect(secondTransport.sent.isEmpty)
    #expect(log.count { event in
        if case .userQuestionResolved(requestId: "old-generation", outcome: .answered) = event {
            return true
        }
        return false
    } == 0)

    await client.close()
    collector.cancel()
}

// allow 送信（transport.send）の suspend 中に interrupt() が走っても、同一
// request_id へ deny を重ねて二重 control_response にしない（stage2 MEDIUM の回帰ガード）。
@Test func interruptDoesNotDenyQuestionWhoseAllowSendIsInFlight() async throws {
    let transport = SuspendingSendTransport()
    let client = ClaudeChatClient(
        environment: [:],
        transportFactory: { _, _, _, _ in transport }
    )
    await client.start()
    let (log, collector) = collectControlProtocolEvents(from: client)

    transport.receive(#"{"type":"control_request","request_id":"in-flight","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Send?","header":"Send","options":[{"label":"Yes"}],"multiSelect":false}]}}}"#)
    try await waitForControlProtocolCondition("質問が保留になる") {
        log.count { event in
            if case .userQuestionRequested(requestId: "in-flight", questions: _) = event {
                return true
            }
            return false
        } == 1
    }

    transport.armSuspendingSend()
    let respondTask = Task {
        await client.respondToUserQuestion(requestId: "in-flight", answers: ["Send?": ["Yes"]])
    }
    try await waitForControlProtocolCondition("allow 送信が suspend 中になる") {
        transport.sendsStarted == 1
    }

    try await client.interrupt()

    transport.releaseSend()
    await respondTask.value

    let behaviors = controlResponses(in: transport.sent, requestId: "in-flight")
    #expect(behaviors == ["allow"], "suspend 中の allow に deny を重ねない（二重応答禁止）")

    await client.close()
    collector.cancel()
}
