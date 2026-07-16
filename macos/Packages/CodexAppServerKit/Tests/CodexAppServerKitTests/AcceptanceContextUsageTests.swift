// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — ThreadEvent.tokenUsageUpdated を NormalizedChatEvent.turnUsage へマップする。
// contextUsedTokens = last.totalTokens ?? total.totalTokens、contextWindowTokens = modelContextWindow。
// 両方 nil なら従来どおりイベントを出さない（nil）。stale thread の遮断は既存の yield ガードの責務。

import Testing
import StructuredChatKit
@testable import CodexAppServerKit

private func breakdown(totalTokens: Int?) -> TokenUsageBreakdown {
    var value = TokenUsageBreakdown()
    value.totalTokens = totalTokens
    return value
}

private func threadTokenUsage(
    lastTotal: Int?,
    cumulativeTotal: Int?,
    contextWindow: Int?
) -> ThreadTokenUsage {
    var usage = ThreadTokenUsage()
    usage.last = lastTotal.map { breakdown(totalTokens: $0) }
    usage.total = cumulativeTotal.map { breakdown(totalTokens: $0) }
    usage.modelContextWindow = contextWindow
    return usage
}

@Test func tokenUsageUpdated_withLastAndWindow_mapsToTurnUsage() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-1",
        tokenUsage: threadTokenUsage(lastTotal: 12345, cumulativeTotal: 99999, contextWindow: 272000)
    )

    let normalized = CodexStructuredAgentClient.normalizedEvent(from: event)

    #expect(normalized == .turnUsage(TurnUsage(
        contextUsedTokens: 12345,
        contextWindowTokens: 272000
    )))
}

@Test func tokenUsageUpdated_withoutLast_fallsBackToCumulativeTotal() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-2",
        tokenUsage: threadTokenUsage(lastTotal: nil, cumulativeTotal: 999, contextWindow: 200000)
    )

    let normalized = CodexStructuredAgentClient.normalizedEvent(from: event)

    #expect(normalized == .turnUsage(TurnUsage(
        contextUsedTokens: 999,
        contextWindowTokens: 200000
    )))
}

@Test func tokenUsageUpdated_windowOnly_stillEmitsTurnUsage() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-3",
        tokenUsage: threadTokenUsage(lastTotal: nil, cumulativeTotal: nil, contextWindow: 200000)
    )

    let normalized = CodexStructuredAgentClient.normalizedEvent(from: event)

    #expect(normalized == .turnUsage(TurnUsage(
        contextUsedTokens: nil,
        contextWindowTokens: 200000
    )))
}

@Test func tokenUsageUpdated_allNil_emitsNothing() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-4",
        tokenUsage: threadTokenUsage(lastTotal: nil, cumulativeTotal: nil, contextWindow: nil)
    )

    let normalized = CodexStructuredAgentClient.normalizedEvent(from: event)

    #expect(normalized == nil)
}

@Test func tokenUsageUpdated_doesNotPopulateCostOrTokenDetails() {
    let event = ThreadEvent.tokenUsageUpdated(
        threadId: "thread-1",
        turnId: "turn-5",
        tokenUsage: threadTokenUsage(lastTotal: 100, cumulativeTotal: 500, contextWindow: 200000)
    )

    guard case .turnUsage(let usage)? = CodexStructuredAgentClient.normalizedEvent(from: event) else {
        Issue.record("expected .turnUsage")
        return
    }
    #expect(usage.costUSD == nil)
    #expect(usage.inputTokens == nil)
    #expect(usage.outputTokens == nil)
    #expect(usage.cacheReadTokens == nil)
    #expect(usage.cacheCreationTokens == nil)
}
