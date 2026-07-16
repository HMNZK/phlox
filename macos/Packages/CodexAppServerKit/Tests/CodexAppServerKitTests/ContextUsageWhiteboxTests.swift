import Testing
import StructuredChatKit
@testable import CodexAppServerKit

private func contextUsageBreakdown(totalTokens: Int?) -> TokenUsageBreakdown {
    var value = TokenUsageBreakdown()
    value.totalTokens = totalTokens
    return value
}

private func contextUsageThreadTokenUsage(
    lastTotal: Int?,
    cumulativeTotal: Int?,
    contextWindow: Int?
) -> ThreadTokenUsage {
    var usage = ThreadTokenUsage()
    usage.last = lastTotal.map { contextUsageBreakdown(totalTokens: $0) }
    usage.total = cumulativeTotal.map { contextUsageBreakdown(totalTokens: $0) }
    usage.modelContextWindow = contextWindow
    return usage
}

@Test func tokenUsageUpdatedUsesLastTotalBeforeCumulativeTotal() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-1",
        tokenUsage: contextUsageThreadTokenUsage(
            lastTotal: 321,
            cumulativeTotal: 9_999,
            contextWindow: 200_000
        )
    )

    let normalized = CodexStructuredAgentClient.normalizedEvent(from: event)

    #expect(normalized == .turnUsage(TurnUsage(
        contextUsedTokens: 321,
        contextWindowTokens: 200_000
    )))
}

@Test func tokenUsageUpdatedWithNoContextFieldsEmitsNil() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-2",
        tokenUsage: contextUsageThreadTokenUsage(
            lastTotal: nil,
            cumulativeTotal: nil,
            contextWindow: nil
        )
    )

    #expect(CodexStructuredAgentClient.normalizedEvent(from: event) == nil)
}
