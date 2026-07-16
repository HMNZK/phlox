import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class WhiteboxItemIdTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }

    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }
}

@Test
func whiteboxSubAgentTextAndThinkingUseMessageScopedItemIds() async throws {
    let mock = WhiteboxItemIdTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(#"{"type":"system","subtype":"init","session_id":"S1","tools":["Agent"]}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"parent","role":"assistant","content":[{"type":"tool_use","id":"toolu_whitebox","name":"Agent","input":{"subagent_type":"general-purpose","description":"probe","prompt":"go","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S1"}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"child-message","role":"assistant","content":[{"type":"text","text":"A"}]},"parent_tool_use_id":"toolu_whitebox","session_id":"S1"}"#)
    mock.receive(#"{"type":"assistant","message":{"id":"child-message","role":"assistant","content":[{"type":"text","text":"B"},{"type":"thinking","thinking":"C"}]},"parent_tool_use_id":"toolu_whitebox","session_id":"S1"}"#)
    await mock.close()

    var activities: [(SubAgentActivityKind, String?, String)] = []
    for _ in 0..<20 {
        guard let event = await iterator.next() else { break }
        if case .subAgentActivity("toolu_whitebox", let kind, let itemId, let text) = event,
           kind == .message || kind == .reasoning {
            activities.append((kind, itemId, text))
        }
        if activities.count == 3 { break }
    }

    try #require(activities.count == 3)
    let firstTextId = try #require(activities[0].1)
    #expect(activities[0].0 == .message)
    #expect(activities[0].2 == "A")
    #expect(activities[1].0 == .message)
    #expect(activities[1].1 == firstTextId)
    #expect(activities[1].2 == "B")
    #expect(activities[2].0 == .reasoning)
    #expect(try #require(activities[2].1) != firstTextId)
    #expect(activities[2].2 == "C")
}
