import Foundation
import Testing
@testable import DashboardFeature

// MARK: - Test helpers

private func makeTemporaryCodexHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-codex-discovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupTemporaryCodexHome(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func fixedDate(_ date: Date) -> @Sendable () -> Date {
    { date }
}

private func isoTimestampString(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func rolloutFilenameTimestamp(for date: Date) -> String {
    isoTimestampString(for: date)
        .replacingOccurrences(of: ":", with: "-")
}

@discardableResult
private func writeRolloutFile(
    codexHome: URL,
    date: Date,
    sessionID: String,
    cwd: String,
    timestamp: Date,
    firstLineOverride: String? = nil,
    filenameSessionID: String? = nil
) throws -> URL {
    let dayDirectory = CodexSessionDiscovery.dayDirectory(
        for: date,
        under: codexHome.appendingPathComponent("sessions", isDirectory: true)
    )
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)

    let filenameID = (filenameSessionID ?? sessionID).lowercased()
    let filename = "rollout-\(rolloutFilenameTimestamp(for: timestamp))-\(filenameID).jsonl"
    let fileURL = dayDirectory.appendingPathComponent(filename)

    let firstLine = firstLineOverride ?? """
    {"type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(cwd)","timestamp":"\(isoTimestampString(for: timestamp))"}}
    """
    try firstLine.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}

// MARK: - CodexSessionDiscoveryTests

@Test func codexSessionDiscovery_matchingCWDAndNewFile_returnsID() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)

    let sessionID = "019e9177-d565-78e2-95b9-174015ba898e"
    let cwd = "/tmp/codex-project"
    let rolloutPath = try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: sessionID,
        cwd: cwd,
        timestamp: spawnTime
    ).path

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: cwd,
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == sessionID.lowercased())
    #expect(!snapshot.contains(rolloutPath))
}

@Test func codexSessionDiscovery_mismatchedCWD_isExcluded() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)

    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "019e9177-d565-78e2-95b9-174015ba898e",
        cwd: "/tmp/other-project",
        timestamp: spawnTime
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: "/tmp/codex-project",
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == nil)
}

@Test func codexSessionDiscovery_existingSnapshotEntry_isExcluded() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))

    let sessionID = "019e9177-d565-78e2-95b9-174015ba898e"
    let cwd = "/tmp/codex-project"
    _ = try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: sessionID,
        cwd: cwd,
        timestamp: spawnTime
    )

    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)
    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: cwd,
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == nil)
}

@Test func codexSessionDiscovery_filenameUUIDMismatch_isExcluded() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)

    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "019e9177-d565-78e2-95b9-174015ba898e",
        cwd: "/tmp/codex-project",
        timestamp: spawnTime,
        filenameSessionID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: "/tmp/codex-project",
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == nil)
}

@Test func codexSessionDiscovery_claimedID_isExcluded() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)
    let sessionID = "019e9177-d565-78e2-95b9-174015ba898e"

    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: sessionID,
        cwd: "/tmp/codex-project",
        timestamp: spawnTime
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: "/tmp/codex-project",
        excluding: snapshot,
        claimedIDs: [sessionID.lowercased()]
    )

    #expect(discovered == nil)
}

@Test func codexSessionDiscovery_multipleCandidates_picksClosestTimestamp() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)
    let cwd = "/tmp/codex-project"

    let fartherID = "11111111-1111-1111-1111-111111111111"
    let closerID = "22222222-2222-2222-2222-222222222222"

    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: fartherID,
        cwd: cwd,
        timestamp: spawnTime.addingTimeInterval(-1.5)
    )
    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: closerID,
        cwd: cwd,
        timestamp: spawnTime.addingTimeInterval(-0.2)
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: cwd,
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == closerID.lowercased())
}

@Test func codexSessionDiscovery_skipsBrokenEmptyOrNonSessionMetaFiles() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_000)
    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(spawnTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)
    let cwd = "/tmp/codex-project"
    let validID = "33333333-3333-3333-3333-333333333333"

    let dayDirectory = CodexSessionDiscovery.dayDirectory(
        for: spawnTime,
        under: codexHome.appendingPathComponent("sessions", isDirectory: true)
    )
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)

    try Data().write(to: dayDirectory.appendingPathComponent("rollout-empty-\(validID).jsonl"))
    try "{not-json".write(
        to: dayDirectory.appendingPathComponent("rollout-broken-\(validID).jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try """
    {"type":"turn_started","payload":{}}
    """.write(
        to: dayDirectory.appendingPathComponent("rollout-other-\(validID).jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: validID,
        cwd: cwd,
        timestamp: spawnTime
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: cwd,
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == validID.lowercased())
}

@Test func codexSessionDiscovery_crossesDateBoundary() throws {
    let codexHome = try makeTemporaryCodexHome()
    defer { cleanupTemporaryCodexHome(codexHome) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let spawnTime = calendar.date(from: DateComponents(
        year: 2026, month: 6, day: 11, hour: 23, minute: 59, second: 30
    ))!
    let currentTime = calendar.date(from: DateComponents(
        year: 2026, month: 6, day: 12, hour: 0, minute: 0, second: 5
    ))!

    let discovery = CodexSessionDiscovery(codexHome: codexHome, now: fixedDate(currentTime))
    let snapshot = discovery.snapshotExistingRollouts(around: spawnTime)
    let sessionID = "44444444-4444-4444-4444-444444444444"
    let cwd = "/tmp/codex-project"

    try writeRolloutFile(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: sessionID,
        cwd: cwd,
        timestamp: spawnTime
    )

    let discovered = discovery.discoverNativeSessionID(
        spawnTime: spawnTime,
        workingDirectory: cwd,
        excluding: snapshot,
        claimedIDs: []
    )

    #expect(discovered == sessionID.lowercased())
}

@Test func codexSessionDiscovery_parsesTimestampWithTimezoneAndFractionalSeconds() throws {
    let timestamp = "2026-06-12T01:02:03.456789Z"
    let parsed = CodexSessionDiscovery.parseTimestamp(timestamp)
    #expect(parsed != nil)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(parsed == formatter.date(from: timestamp))
}
