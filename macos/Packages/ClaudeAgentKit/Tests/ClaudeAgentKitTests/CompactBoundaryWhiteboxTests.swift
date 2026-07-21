import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class CompactBoundaryMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}

@Suite("Compact boundary 白箱（task-2）")
struct CompactBoundaryWhiteboxTests {
    @Test func autoTriggerとpreTokensが透過される() async throws {
        let mock = CompactBoundaryMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(
            #"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"auto","pre_tokens":200000},"uuid":"u3","session_id":"s1"}"#
        )
        mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

        let first = await iterator.next()
        #expect(first == .compactionBoundary(trigger: "auto", preTokens: 200_000))
        await client.close()
    }

    @Test func metadataが空辞書でもnilでyieldされる() async throws {
        let mock = CompactBoundaryMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(
            #"{"type":"system","subtype":"compact_boundary","compact_metadata":{},"uuid":"u4","session_id":"s1"}"#
        )
        mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

        let first = await iterator.next()
        #expect(first == .compactionBoundary(trigger: nil, preTokens: nil))
        await client.close()
    }
}
