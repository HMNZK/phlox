import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class ContextWindowWhiteboxTransport: LineDelimitedTransport, @unchecked Sendable {
    var receivedLines: AsyncStream<Data> { AsyncStream { $0.finish() } }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async {}
}

private func makeContextWindowWhiteboxClient() -> ClaudeChatClient {
    ClaudeChatClient(transportFactory: { _, _, _, _ in ContextWindowWhiteboxTransport() })
}

@Test func parseTurnUsageBreaksConsumptionTieByLargerContextWindow() async throws {
    let client = makeContextWindowWhiteboxClient()
    let usage = await client.parseTurnUsage(from: [
        "total_cost_usd": 0.1,
        "usage": [
            "input_tokens": 100,
            "output_tokens": 10,
            "cache_read_input_tokens": 50,
            "cache_creation_input_tokens": 25,
        ],
        "modelUsage": [
            "small-window": [
                "inputTokens": 100,
                "cacheReadInputTokens": 50,
                "cacheCreationInputTokens": 25,
                "contextWindow": 200_000,
            ],
            "large-window": [
                "inputTokens": 100,
                "cacheReadInputTokens": 50,
                "cacheCreationInputTokens": 25,
                "contextWindow": 1_000_000,
            ],
        ],
    ])

    #expect(usage?.contextWindowTokens == 1_000_000)
    #expect(usage?.contextUsedTokens == nil)
}

@Test func turnUsageDecodesWhenContextFieldsAreMissing() throws {
    let data = Data("""
    {"costUSD":1.5,"inputTokens":10,"outputTokens":20,"cacheReadTokens":30,"cacheCreationTokens":40}
    """.utf8)

    let usage = try JSONDecoder().decode(TurnUsage.self, from: data)

    #expect(usage == TurnUsage(
        costUSD: 1.5,
        inputTokens: 10,
        outputTokens: 20,
        cacheReadTokens: 30,
        cacheCreationTokens: 40,
        contextUsedTokens: nil,
        contextWindowTokens: nil
    ))
}
