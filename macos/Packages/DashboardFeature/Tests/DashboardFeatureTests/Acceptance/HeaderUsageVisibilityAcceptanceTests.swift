import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: 下部使用量バーの表示設定")
struct HeaderUsageVisibilityAcceptanceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private var mixedUsages: [AgentKind: CLIUsage] {
        [
            .codex: CLIUsage(kind: .codex, state: .ok([
                UsageBucket(id: "5h", label: "5時間", usedPercent: 42),
            ]), updatedAt: now),
            .cursor: CLIUsage(kind: .cursor, state: .unavailable(reason: "内部理由"), updatedAt: now),
            .claudeCode: CLIUsage(kind: .claudeCode, state: .unavailable(reason: "内部理由"), updatedAt: now),
        ]
    }

    @Test func 表示設定は初期状態でオン() throws {
        #expect(UsageSettings.showInHeaderKey == "phlox.usage.showInHeader")
        #expect(try #require(UsageSettings.defaultsDictionary[UsageSettings.showInHeaderKey] as? Bool))
    }

    @Test func 未取得を含む全ハーネスを定義順で出す() {
        let groups = UsageDisplay.bottomBarGroups(usages: mixedUsages)
        #expect(groups.map(\.kind) == [.claudeCode, .codex, .cursor])
        #expect(groups[0].buckets == nil)
        #expect(groups[1].buckets?.map(\.id) == ["5h"])
        #expect(groups[2].buckets == nil)
    }
}
