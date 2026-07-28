import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class InitSlashCommandsWhiteboxTransport: LineDelimitedTransport, @unchecked Sendable {
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

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}

@Suite("Whitebox: init の slash_commands 正規化（task-2）")
struct InitSlashCommandsWhiteboxTests {
    @Test("文字列配列の slash_commands を加工せずに更新イベントとして出す")
    func stringSlashCommandsAreYieldedUnchanged() async throws {
        let transport = InitSlashCommandsWhiteboxTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"type":"system","subtype":"init","slash_commands":["Config","claude-security:scan","__remote-workflow","compact"]}"#)
        transport.receive(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1}}"#)

        let first = await iterator.next()
        #expect(first == .availableCommandsUpdated(commands: ["Config", "claude-security:scan", "__remote-workflow", "compact"]))
        await client.close()
    }

    @Test("文字列以外が混ざる slash_commands は更新イベントを出さない")
    func mixedTypeSlashCommandsYieldNothing() async throws {
        let transport = InitSlashCommandsWhiteboxTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in transport })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"type":"system","subtype":"init","slash_commands":["compact",42]}"#)
        transport.receive(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1}}"#)

        let first = await iterator.next()
        #expect(first == .compactionBoundary(trigger: "manual", preTokens: 1))
        await client.close()
    }
}
