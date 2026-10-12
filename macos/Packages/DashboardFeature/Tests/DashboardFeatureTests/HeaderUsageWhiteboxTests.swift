import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("下部使用量バー whitebox")
struct HeaderUsageWhiteboxTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func showInHeaderKeyは保存互換のため維持する() {
        #expect(UsageSettings.showInHeaderKey == "phlox.usage.showInHeader")
    }

    @Test func 空のバケットは表示グループを作らない() {
        let usages = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { kind in
            (kind, CLIUsage(kind: kind, state: .ok([]), updatedAt: now))
        })

        #expect(UsageDisplay.bottomBarGroups(usages: usages).isEmpty)
    }

    @Test func 未取得の値は残量ゼロと区別する() throws {
        let usage = CLIUsage(kind: .cursor, state: .unavailable(reason: "内部理由"), updatedAt: now)
        let groups = UsageDisplay.bottomBarGroups(usages: [.cursor: usage])
        let group = try #require(groups.first { $0.kind == .cursor })
        #expect(group.buckets == nil)
        #expect(UsageDisplay.bottomBarUnavailableText(locale: Locale(identifier: "ja")) == "取得できません")
    }
}
