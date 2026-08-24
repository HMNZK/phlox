import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class ToolPermissionMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private final class ToolPermissionTransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [ToolPermissionMockTransport] = []

    func make(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = ToolPermissionMockTransport()
        lock.withLock { transports.append(transport) }
        return transport
    }

    func transport(at index: Int) -> ToolPermissionMockTransport? {
        lock.withLock {
            guard transports.indices.contains(index) else { return nil }
            return transports[index]
        }
    }
}

private final class ToolPermissionEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [NormalizedChatEvent] = []

    func append(_ event: NormalizedChatEvent) {
        lock.withLock { collected.append(event) }
    }

    var all: [NormalizedChatEvent] {
        lock.withLock { collected }
    }
}

private let bashPermissionRequestLine = """
{"type":"control_request","request_id":"permission-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"echo hi","timeout":10,"nested":{"enabled":true}},"tool_use_id":"toolu-permission-1"}}
"""

private let secondBashPermissionRequestLine = """
{"type":"control_request","request_id":"permission-2","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"echo second"},"tool_use_id":"toolu-permission-2"}}
"""

private func makeToolPermissionClient(
    _ transport: ToolPermissionMockTransport,
    permissionMode: String? = nil,
    allowedTools: [String] = []
) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: [:],
        permissionMode: permissionMode,
        allowedTools: allowedTools,
        transportFactory: { _, _, _, _ in transport }
    )
}

private func collectToolPermissionEvents(
    from client: ClaudeChatClient
) -> (ToolPermissionEventCollector, Task<Void, Never>) {
    let collector = ToolPermissionEventCollector()
    let events = client.events
    let task = Task {
        for await event in events {
            collector.append(event)
        }
    }
    return (collector, task)
}

private func permissionControlResponses(
    in transport: ToolPermissionMockTransport
) -> [[String: Any]] {
    transport.sentStrings().compactMap { line in
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "control_response"
        else { return nil }
        return object
    }
}

private func waitForPermissionCondition(
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

private func permissionQuestion(
    requestId: String,
    in collector: ToolPermissionEventCollector
) -> ChatUserQuestion? {
    for event in collector.all {
        if case .userQuestionRequested(let id, let questions) = event, id == requestId {
            return questions.first
        }
    }
    return nil
}

private func originalBashInput() throws -> [String: Any] {
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(bashPermissionRequestLine.utf8)) as? [String: Any]
    )
    let request = try #require(object["request"] as? [String: Any])
    return try #require(request["input"] as? [String: Any])
}

@Test func bashPermissionRequestYieldsUserQuestion() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)

    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    let question = try #require(permissionQuestion(requestId: "permission-1", in: collector))
    #expect(question.header == "Bash")
    #expect(question.question == "Allow Bash? echo hi")
    #expect(question.options.map(\.label) == ["Allow", "Deny"])
    #expect(!question.multiSelect)
    #expect(permissionControlResponses(in: transport).isEmpty)

    await client.close()
    task.cancel()
}

@Test func allowingToolPermissionSendsOriginalInput() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)
    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    let question = try #require(permissionQuestion(requestId: "permission-1", in: collector))
    await client.respondToUserQuestion(
        requestId: "permission-1",
        answers: [question.question: ["Allow"]]
    )

    try await waitForPermissionCondition("allow 応答が送信される") {
        permissionControlResponses(in: transport).count == 1
    }
    let envelope = try #require(permissionControlResponses(in: transport).first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "allow")
    let updatedInput = try #require(response["updatedInput"] as? [String: Any])
    let originalInput = try originalBashInput()
    #expect(NSDictionary(dictionary: updatedInput).isEqual(to: NSDictionary(dictionary: originalInput)))
    #expect(updatedInput["answers"] == nil)

    await client.close()
    task.cancel()
}

@Test func allowedToolPermissionAutoAllowsWithoutQuestion() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(
        transport,
        permissionMode: "auto",
        allowedTools: ["Bash"]
    )
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)

    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("allowedTools の allow 応答が送信される") {
        permissionControlResponses(in: transport).count == 1
    }
    #expect(collector.all.contains { event in
        if case .userQuestionRequested(let requestId, _) = event {
            return requestId == "permission-1"
        }
        return false
    } == false)
    let envelope = try #require(permissionControlResponses(in: transport).first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "allow")
    let updatedInput = try #require(response["updatedInput"] as? [String: Any])
    let originalInput = try originalBashInput()
    #expect(NSDictionary(dictionary: updatedInput).isEqual(to: NSDictionary(dictionary: originalInput)))

    await client.close()
    task.cancel()
}

@Test func bypassPermissionsAutoAllowsWithoutQuestion() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport, permissionMode: "bypassPermissions")
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)

    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("bypass の allow 応答が送信される") {
        permissionControlResponses(in: transport).count == 1
    }
    #expect(collector.all.contains { event in
        if case .userQuestionRequested(let requestId, _) = event {
            return requestId == "permission-1"
        }
        return false
    } == false)
    let envelope = try #require(permissionControlResponses(in: transport).first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "allow")
    let updatedInput = try #require(response["updatedInput"] as? [String: Any])
    let originalInput = try originalBashInput()
    #expect(NSDictionary(dictionary: updatedInput).isEqual(to: NSDictionary(dictionary: originalInput)))

    await client.close()
    task.cancel()
}

@Test func denyingToolPermissionSendsDenyResponse() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)
    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    let question = try #require(permissionQuestion(requestId: "permission-1", in: collector))
    await client.respondToUserQuestion(
        requestId: "permission-1",
        answers: [question.question: ["Deny"]]
    )

    try await waitForPermissionCondition("deny 応答が送信される") {
        permissionControlResponses(in: transport).count == 1
    }
    let envelope = try #require(permissionControlResponses(in: transport).first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "deny")
    #expect(response["message"] as? String == "Denied by user in Phlox")
    #expect(response["updatedInput"] == nil)

    await client.close()
    task.cancel()
}

@Test func permissionQuestionRemovesPromptSpoofingCharacters() {
    let command = "echo \u{202E}hidden\u{2066}\u{200B}\u{0000}\u{0085}\u{2028}\u{2029}\u{061C}\t\nnext"
    let question = ClaudeChatClient.makeToolPermissionQuestion(
        toolName: "Bash",
        input: ["command": command]
    )

    #expect(!question.question.contains("\u{202E}"))
    #expect(!question.question.contains("\u{2066}"))
    #expect(!question.question.contains("\u{200B}"))
    #expect(!question.question.contains("\u{0000}"))
    #expect(!question.question.contains("\u{0085}"))
    #expect(!question.question.contains("\u{2028}"))
    #expect(!question.question.contains("\u{2029}"))
    #expect(!question.question.contains("\u{061C}"))
    #expect(!question.question.contains("\t"))
    #expect(!question.question.contains("\n"))
    #expect(question.question.contains("echo hidden"))
    #expect(question.question.contains(" next"))
}

@Test func toolPermissionToolNameIsSanitizedInHeader() {
    let question = ClaudeChatClient.makeToolPermissionQuestion(
        toolName: "Bash\u{2028}\u{2029}\u{061C}\tX",
        input: ["command": "echo hi"]
    )

    #expect(question.header == "Bash X")
    #expect(question.question.hasPrefix("Allow Bash X?"))
}

@Test func truncatedToolPermissionSummaryDisclosesFullLength() {
    let summary = String(repeating: "x", count: 260)
    let truncated = ClaudeChatClient.truncatedToolPermissionSummary(summary)
    let notice = "…（全 260 文字）"

    #expect(truncated.count == 200)
    #expect(truncated.hasSuffix(notice))
    #expect(truncated == String(summary.prefix(200 - notice.count)) + notice)
}

@Test func unknownAndEmptyPermissionAnswersDeny() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)

    transport.receive(bashPermissionRequestLine)
    try await waitForPermissionCondition("最初の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    let question = try #require(permissionQuestion(requestId: "permission-1", in: collector))
    await client.respondToUserQuestion(
        requestId: "permission-1",
        answers: [question.question: ["Maybe"]]
    )

    transport.receive(secondBashPermissionRequestLine)
    try await waitForPermissionCondition("2つ目の許可質問が yield される") {
        permissionQuestion(requestId: "permission-2", in: collector) != nil
    }
    await client.respondToUserQuestion(requestId: "permission-2", answers: [:])

    try await waitForPermissionCondition("未知ラベルと空回答の deny が送信される") {
        permissionControlResponses(in: transport).count == 2
    }
    for envelope in permissionControlResponses(in: transport) {
        let responseEnvelope = try #require(envelope["response"] as? [String: Any])
        let response = try #require(responseEnvelope["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "deny")
        #expect(response["updatedInput"] == nil)
    }

    await client.close()
    task.cancel()
}

@Test func expiringToolPermissionSendsBestEffortDeny() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)
    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    await client.close()

    let responses = permissionControlResponses(in: transport)
    #expect(responses.count == 1)
    let envelope = try #require(responses.first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "deny")
    #expect(response["message"] as? String == "Denied by user in Phlox")
    try await waitForPermissionCondition("失効イベントが yield される") {
        collector.all.contains(.userQuestionResolved(
            requestId: "permission-1",
            outcome: .expired
        ))
    }
    task.cancel()
}

@Test func streamEndExpiresToolPermissionWithoutSendingDeny() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)
    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    await transport.close()

    try await waitForPermissionCondition("stream 終了で失効する") {
        collector.all.contains(.userQuestionResolved(
            requestId: "permission-1",
            outcome: .expired
        ))
    }
    #expect(permissionControlResponses(in: transport).isEmpty)
    task.cancel()
}

@Test func respawnExpiresToolPermissionAndOnlyOldTransportGetsDeny() async throws {
    let factory = ToolPermissionTransportFactory()
    let client = ClaudeChatClient(environment: [:], transportFactory: factory.make)
    await client.start()
    let firstTransport = try #require(factory.transport(at: 0))
    let (collector, task) = collectToolPermissionEvents(from: client)

    firstTransport.receive(bashPermissionRequestLine)
    try await waitForPermissionCondition("旧世代の許可質問が保留になる") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }

    try await client.resume(sessionRef: "new-session")
    let secondTransport = try #require(factory.transport(at: 1))
    try await waitForPermissionCondition("respawn で旧許可質問が失効する") {
        collector.all.contains(.userQuestionResolved(
            requestId: "permission-1",
            outcome: .expired
        ))
    }

    let oldResponses = permissionControlResponses(in: firstTransport)
    #expect(oldResponses.count == 1)
    let oldEnvelope = try #require(oldResponses.first?["response"] as? [String: Any])
    let oldResponse = try #require(oldEnvelope["response"] as? [String: Any])
    #expect(oldResponse["behavior"] as? String == "deny")
    #expect(permissionControlResponses(in: secondTransport).isEmpty)

    await client.respondToUserQuestion(requestId: "permission-1", answers: ["Allow Bash? echo hi": ["Allow"]])
    #expect(permissionControlResponses(in: secondTransport).isEmpty)

    await client.close()
    task.cancel()
}

@Test func interruptSendsOneDenyForToolPermission() async throws {
    let transport = ToolPermissionMockTransport()
    let client = makeToolPermissionClient(transport)
    await client.start()
    let (collector, task) = collectToolPermissionEvents(from: client)
    transport.receive(bashPermissionRequestLine)

    try await waitForPermissionCondition("Bash の許可質問が yield される") {
        permissionQuestion(requestId: "permission-1", in: collector) != nil
    }
    try await client.interrupt()

    try await waitForPermissionCondition("interrupt の deny が送信される") {
        permissionControlResponses(in: transport).count == 1
    }
    let envelope = try #require(permissionControlResponses(in: transport).first?["response"] as? [String: Any])
    let response = try #require(envelope["response"] as? [String: Any])
    #expect(response["behavior"] as? String == "deny")
    #expect(permissionControlResponses(in: transport).count == 1)

    await client.close()
    task.cancel()
}
