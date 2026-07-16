import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func codexUsageProvider_usesLatestRolloutAndLastRateLimitsLine() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let oldDirectory = root.appending(path: "2026/01/01")
    let newDirectory = root.appending(path: "2026/01/02")
    try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)

    let oldFile = oldDirectory.appending(path: "rollout-old.jsonl")
    let newFile = newDirectory.appending(path: "rollout-new.jsonl")
    try """
    {"payload":{"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":2}}}}
    """.write(to: oldFile, atomically: true, encoding: .utf8)
    try """
    {"payload":{"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":2}}}}
    {"payload":{"rate_limits":{"primary":{"used_percent":44.5,"window_minutes":10080,"resets_at":3},"secondary":{"used_percent":12.25,"window_minutes":300,"resets_at":4}}}}
    """.write(to: newFile, atomically: true, encoding: .utf8)

    try setModificationDate(.init(timeIntervalSince1970: 1_000), for: oldFile)
    try setModificationDate(.init(timeIntervalSince1970: 2_000), for: newFile)

    let usage = await CodexUsageProvider(sessionsRoot: root).fetch()

    guard case let .ok(buckets) = usage.state else {
        Issue.record("Expected Codex usage buckets")
        return
    }
    #expect(usage.kind == .codex)
    #expect(buckets.count == 2)
    #expect(buckets.first { $0.id == "5h" }?.label == "5時間")
    #expect(buckets.first { $0.id == "5h" }?.usedPercent == 12.25)
    #expect(buckets.first { $0.id == "weekly" }?.label == "週次")
    #expect(buckets.first { $0.id == "weekly" }?.usedPercent == 44.5)
}

@Test func codexUsageProvider_prefersLatestDateDirectoryOverNewerMtimeInOlderDate() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let olderDateDirectory = root.appending(path: "2025/12/31")
    let latestDateDirectory = root.appending(path: "2026/01/02")
    try FileManager.default.createDirectory(at: olderDateDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: latestDateDirectory, withIntermediateDirectories: true)

    let olderDateFile = olderDateDirectory.appending(path: "rollout-older-date.jsonl")
    let latestDateFile = latestDateDirectory.appending(path: "rollout-latest-date.jsonl")
    try """
    {"payload":{"rate_limits":{"primary":{"used_percent":99.0,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":98.0,"window_minutes":10080,"resets_at":2}}}}
    """.write(to: olderDateFile, atomically: true, encoding: .utf8)
    try """
    {"payload":{"rate_limits":{"primary":{"used_percent":7.5,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":3.25,"window_minutes":10080,"resets_at":2}}}}
    """.write(to: latestDateFile, atomically: true, encoding: .utf8)

    // 古い日付側のファイルの方が更新時刻は新しい(touch 等で起こり得る)が、最新日付ディレクトリ側が選ばれる
    try setModificationDate(.init(timeIntervalSince1970: 9_000), for: olderDateFile)
    try setModificationDate(.init(timeIntervalSince1970: 1_000), for: latestDateFile)

    let usage = await CodexUsageProvider(sessionsRoot: root).fetch()

    guard case let .ok(buckets) = usage.state else {
        Issue.record("Expected Codex usage buckets")
        return
    }
    #expect(buckets.first { $0.id == "5h" }?.usedPercent == 7.5)
    #expect(buckets.first { $0.id == "weekly" }?.usedPercent == 3.25)
}

@Test func codexUsageProvider_descendsOnlyIntoLatestDatePathAndSkipsOlderYears() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    for path in ["2024/05/10", "2026/01/02", "2026/03/04"] {
        let directory = root.appending(path: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{}".write(to: directory.appending(path: "rollout-\(path.replacingOccurrences(of: "/", with: "-")).jsonl"), atomically: true, encoding: .utf8)
    }

    var listedDirectories: [String] = []
    let latest = CodexUsageProvider.latestRolloutFile(under: root) { url in
        listedDirectories.append(url.path)
        return (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: []
        )) ?? []
    }

    #expect(latest?.lastPathComponent == "rollout-2026-03-04.jsonl")
    // ルート → 最新年 → 最新月 → 最新日 だけを列挙し、古い年月のディレクトリへは降りない
    #expect(listedDirectories.count == 4)
    #expect(!listedDirectories.contains { $0.contains("2024") || $0.contains("2026/01") })
}

@Test func codexUsageProvider_fallsBackToEarlierDateWhenLatestDayHasNoRollouts() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let emptyLatestDay = root.appending(path: "2026/01/03")
    let dayWithRollout = root.appending(path: "2026/01/02")
    try FileManager.default.createDirectory(at: emptyLatestDay, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dayWithRollout, withIntermediateDirectories: true)
    try "{}".write(to: dayWithRollout.appending(path: "rollout-found.jsonl"), atomically: true, encoding: .utf8)

    let latest = CodexUsageProvider.latestRolloutFile(under: root) { url in
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: []
        )) ?? []
    }

    #expect(latest?.lastPathComponent == "rollout-found.jsonl")
}

@Test func codexUsageProvider_decodesResetsAtFromRolloutJSONL() throws {
    let text = """
    {"payload":{"rate_limits":{"primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1778734505},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1778817846}}}}
    """

    let buckets = try #require(CodexUsageProvider.buckets(fromJSONL: text))
    let fiveHour = try #require(buckets.first { $0.id == "5h" })
    let weekly = try #require(buckets.first { $0.id == "weekly" })

    #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1778734505))
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1778817846))
}

@Test func codexUsageProvider_returnsBucketsWithoutResetsAt() throws {
    let text = """
    {"payload":{"rate_limits":{"primary":{"used_percent":2.0,"window_minutes":300},"secondary":{"used_percent":12.0,"window_minutes":10080}}}}
    """

    let buckets = try #require(CodexUsageProvider.buckets(fromJSONL: text))

    #expect(buckets.first { $0.id == "5h" }?.resetsAt == nil)
    #expect(buckets.first { $0.id == "weekly" }?.resetsAt == nil)
}

@Test func codexUsageProvider_withoutRateLimitsReturnsUnavailable() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appending(path: "rollout-empty.jsonl")
    try """
    {"payload":{"message":"no usage here"}}
    {"other":true}
    """.write(to: file, atomically: true, encoding: .utf8)

    let usage = await CodexUsageProvider(sessionsRoot: root).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason == "セッション履歴なし")
}

@Test func codexUsageProvider_withoutFilesReturnsUnavailable() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let usage = await CodexUsageProvider(sessionsRoot: root).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason == "セッション履歴なし")
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-codex-usage-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
}
