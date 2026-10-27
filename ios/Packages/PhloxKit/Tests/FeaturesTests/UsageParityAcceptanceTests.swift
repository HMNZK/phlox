import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
struct UsageParityAcceptanceTests {
    @Test("前面で使用量を繰り返し取り直し、キャンセル後は停止する")
    func observationStopsOnCancellation() async throws {
        let api = MockAPI()
        let model = UsageViewModel(api: api)
        let observation = Task { await model.observe(interval: .milliseconds(5)) }
        for _ in 0..<100 {
            if await api.cliUsageCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await api.cliUsageCount >= 2)
        observation.cancel()
        await observation.value
        let count = await api.cliUsageCount
        try await Task.sleep(for: .milliseconds(20))
        #expect(await api.cliUsageCount == count)
    }

    @Test("Claudeの期限切れ枠を古い残量のまま表示しない")
    func expiredClaudeBucketIsHidden() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = CLIUsage(kind: .claudeCode, state: .ok, buckets: [
            UsageBucket(id: "5h", label: "5時間", usedPercent: 90, resetsAt: now.addingTimeInterval(-1)),
            UsageBucket(id: "weekly", label: "週次", usedPercent: 20, resetsAt: now.addingTimeInterval(100)),
        ], updatedAt: now.addingTimeInterval(-10), dataAsOf: now.addingTimeInterval(-10))
        let model = UsageViewModel(api: MockAPI(), agents: [usage], state: .loaded,
                                   lastSuccessfulAt: now, now: { now })
        #expect(model.presentationAgents.flatMap(\.buckets).map(\.id) == ["weekly"])
    }
}
