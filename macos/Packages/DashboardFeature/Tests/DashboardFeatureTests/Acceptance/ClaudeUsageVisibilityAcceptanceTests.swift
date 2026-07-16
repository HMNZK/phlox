// task-16 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-16.md — Claude Usage 行を消さず、未取得/stale を理由つきで可視化する。

import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func claudeUsage_visibleKinds_keepsClaudeRowWhenUnavailable() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let usages: [AgentKind: CLIUsage] = [
        .claudeCode: CLIUsage(kind: .claudeCode, state: .unavailable(reason: "未取得"), updatedAt: now),
        .codex: CLIUsage(kind: .codex, state: .unavailable(reason: "未取得"), updatedAt: now),
    ]
    let visible = UsageDisplay.visibleKinds(usages: usages, showUnavailable: false)
    // Claude は供給が構造的に止まりうるため、unavailable でも行を消さない
    #expect(visible.contains(.claudeCode))
    // Codex/Cursor の既存挙動（unavailable は非表示）は変えない
    #expect(!visible.contains(.codex))
    #expect(!visible.contains(.cursor))
}

@Test func claudeUsage_stalenessNote_missingDataExplainsHowToUpdate() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ClaudeUsageStaleness.note(now: now, dataAsOf: nil)
        == "未取得（ターミナルの Claude セッション実行時に更新されます）")
}

@Test func claudeUsage_stalenessNote_freshDataHasNoNote() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ClaudeUsageStaleness.note(now: now, dataAsOf: now.addingTimeInterval(-29 * 60)) == nil)
}

@Test func claudeUsage_stalenessNote_boundaries() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func note(minutesAgo: Double) -> String? {
        ClaudeUsageStaleness.note(now: now, dataAsOf: now.addingTimeInterval(-minutesAgo * 60))
    }
    #expect(note(minutesAgo: 30) == "30分前の値")
    #expect(note(minutesAgo: 59) == "59分前の値")
    #expect(note(minutesAgo: 60) == "1時間前の値")
    #expect(note(minutesAgo: 23 * 60) == "23時間前の値")
    #expect(note(minutesAgo: 24 * 60) == "1日前の値")
    #expect(note(minutesAgo: 72 * 60) == "3日前の値")
}

@Test func claudeUsage_provider_carriesDataTimestampFromCache() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-usage-acceptance-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let cacheURL = dir.appendingPathComponent("claude-usage-rate-limits.json")
    try #"{"ts": 1783096554, "rate_limits": {"five_hour": {"used_percentage": 42.0, "resets_at": 1783111200}}}"#
        .write(to: cacheURL, atomically: true, encoding: .utf8)

    let provider = ClaudeUsageProvider(rateLimitsURL: cacheURL)
    let usage = await provider.fetch()

    guard case .ok(let buckets) = usage.state else {
        Issue.record("expected .ok, got \(usage.state)")
        return
    }
    #expect(buckets.first?.usedPercent == 42.0)
    let dataAsOf = try #require(usage.dataAsOf)
    #expect(abs(dataAsOf.timeIntervalSince1970 - 1_783_096_554) < 1.0)
}
