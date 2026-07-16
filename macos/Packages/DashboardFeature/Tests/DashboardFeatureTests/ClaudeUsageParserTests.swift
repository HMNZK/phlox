import Foundation
import Testing
@testable import DashboardFeature

@Suite(.serialized)
struct ClaudeUsageProviderTests {

@Test func claudeUsageProvider_decodesRateLimitsCacheBuckets() throws {
    let data = Data("""
    {
      "ts": 1780923103.774998,
      "rate_limits": {
        "five_hour": {
          "used_percentage": 16,
          "resets_at": 1780936200
        },
        "seven_day": {
          "used_percentage": 42,
          "resets_at": 1781179200
        }
      }
    }
    """.utf8)

    let buckets = try #require(ClaudeUsageProvider.buckets(fromCacheData: data))

    #expect(buckets.map(\.id) == ["5h", "weekly"])
    #expect(buckets.first { $0.id == "5h" }?.label == "5時間")
    #expect(buckets.first { $0.id == "5h" }?.usedPercent == 16)
    #expect(buckets.first { $0.id == "weekly" }?.label == "週次")
    #expect(buckets.first { $0.id == "weekly" }?.usedPercent == 42)
}

@Test func claudeUsageProvider_returnsNilWithoutRateLimits() {
    let data = Data(#"{"ts":1780923103.774998}"#.utf8)

    #expect(ClaudeUsageProvider.buckets(fromCacheData: data) == nil)
}

@Test func claudeUsageProvider_fetchReadsCacheFile() async throws {
    let fileURL = try makeTemporaryClaudeUsageURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    try Data("""
    {"ts":1780923103.774998,"rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":43}}}
    """.utf8).write(to: fileURL, options: .atomic)

    let usage = await ClaudeUsageProvider(rateLimitsURL: fileURL).fetch()

    guard case let .ok(buckets) = usage.state else {
        Issue.record("Expected Claude usage buckets")
        return
    }
    #expect(usage.kind == .claudeCode)
    #expect(buckets.first { $0.id == "5h" }?.usedPercent == 25)
    #expect(buckets.first { $0.id == "weekly" }?.usedPercent == 43)
}

@Test func claudeUsageProvider_fetchWithoutCacheReturnsUnavailable() async throws {
    let fileURL = try makeTemporaryClaudeUsageURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let usage = await ClaudeUsageProvider(rateLimitsURL: fileURL).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason.contains("Claude使用量は未取得です"))
}

@Test func claudeUsageProvider_decodesResetsAtFromCache() throws {
    let data = Data("""
    {
      "ts": 1780923103.774998,
      "rate_limits": {
        "five_hour": {
          "used_percentage": 16,
          "resets_at": 1780936200
        },
        "seven_day": {
          "used_percentage": 42,
          "resets_at": 1781179200
        }
      }
    }
    """.utf8)

    let buckets = try #require(ClaudeUsageProvider.buckets(fromCacheData: data))
    let fiveHour = try #require(buckets.first { $0.id == "5h" })
    let weekly = try #require(buckets.first { $0.id == "weekly" })

    #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1780936200))
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1781179200))
}

@Test func claudeUsageProvider_returnsBucketsWithoutResetsAt() throws {
    let data = Data("""
    {
      "ts": 1780923103.774998,
      "rate_limits": {
        "five_hour": {"used_percentage": 16},
        "seven_day": {"used_percentage": 42}
      }
    }
    """.utf8)

    let buckets = try #require(ClaudeUsageProvider.buckets(fromCacheData: data))

    #expect(buckets.first { $0.id == "5h" }?.resetsAt == nil)
    #expect(buckets.first { $0.id == "weekly" }?.resetsAt == nil)
}

@Test func claudeUsageProvider_fetchRespectsDisabledDefault() async throws {
    let key = "phlox.usage.claudeScrape"
    let suiteName = "phlox-claude-usage-defaults-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let fileURL = try makeTemporaryClaudeUsageURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    try Data("""
    {"ts":1780923103.774998,"rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":43}}}
    """.utf8).write(to: fileURL, options: .atomic)
    defaults.set(false, forKey: key)

    let usage = await ClaudeUsageProvider(rateLimitsURL: fileURL, defaultsSuiteName: suiteName).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason == "取得無効")
}

}

private func makeTemporaryClaudeUsageURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-claude-usage-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("claude-usage-rate-limits.json")
}
