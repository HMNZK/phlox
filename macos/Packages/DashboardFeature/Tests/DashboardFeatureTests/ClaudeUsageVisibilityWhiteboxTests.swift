// task-16 白箱テスト（ステージ1レビュー MEDIUM 由来・PM 著）
// UsageMonitor.expiringPassedResets は CLIUsage を再構築する唯一の箇所であり、
// dataAsOf（データ自体の時刻）がここで silent に失われると鮮度表示が壊れる。

import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func claudeUsage_expiringPassedResets_preservesDataAsOf() {
    let asOf = Date(timeIntervalSince1970: 1_783_096_554)
    let usage = CLIUsage(
        kind: .claudeCode,
        state: .ok([UsageBucket(
            id: "5h",
            label: "5時間",
            usedPercent: 99,
            resetsAt: Date(timeIntervalSince1970: 1_000)
        )]),
        updatedAt: Date(timeIntervalSince1970: 900),
        dataAsOf: asOf
    )

    // 5h は期限切れで不明になるが、元のデータ時刻は保持する。
    let normalized = UsageMonitor.expiringPassedResets(in: usage, now: Date(timeIntervalSince1970: 5_000))
    #expect(normalized.dataAsOf == asOf)
}
