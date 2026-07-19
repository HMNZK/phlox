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
