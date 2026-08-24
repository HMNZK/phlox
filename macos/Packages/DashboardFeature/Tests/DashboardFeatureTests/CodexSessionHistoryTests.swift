import Foundation
import SQLite3
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test func codexSessionHistory_entriesFilterCWDAndRestoreTranscript() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-history-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let day = root.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

    let matchingID = "11111111-1111-4111-8111-111111111111"
    let matchingFile = day.appendingPathComponent(
        "rollout-2026-08-24T10-00-00-\(matchingID).jsonl"
    )
    try [
        #"{"type":"session_meta","payload":{"id":"\#(matchingID)","cwd":"/tmp/work","timestamp":"2026-08-24T10:00:00.000Z"}}"#,
        #"{"type":"response_item","timestamp":"2026-08-24T10:01:00.000Z","payload":{"type":"message","id":"u1","role":"user","content":[{"type":"input_text","text":"  最初の依頼  "}]}}"#,
        #"{"type":"response_item","timestamp":"2026-08-24T10:02:00.000Z","payload":{"type":"message","id":"a1","role":"assistant","content":[{"type":"output_text","text":"回答です"}]}}"#,
    ].joined(separator: "\n").write(to: matchingFile, atomically: true, encoding: .utf8)

    let unrelatedID = "22222222-2222-4222-8222-222222222222"
    let unrelatedFile = day.appendingPathComponent(
        "rollout-2026-08-24T10-03-00-\(unrelatedID).jsonl"
    )
    try #"{"type":"session_meta","payload":{"id":"\#(unrelatedID)","cwd":"/tmp/other","timestamp":"2026-08-24T10:03:00.000Z"}}"#
        .write(to: unrelatedFile, atomically: true, encoding: .utf8)

    let discovery = CodexSessionHistoryDiscovery(codexHome: root)
    let entries = discovery.entries(forWorkingDirectory: "/tmp/work", limit: 10)

    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.sessionID == matchingID)
    #expect(entry.preview == "最初の依頼")

    let transcript = CodexSessionHistoryDiscovery.loadTranscript(fileURL: matchingFile, maxItems: 10)
    #expect(transcript.map(\.plainText) == ["User:   最初の依頼  ", "Agent: 回答です"])
}

@Test func codexSessionHistory_scansNewestMetadataFirstAndStopsAfterLimit() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-history-limit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let day = root.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

    func writeRollout(
        id: String,
        cwd: String,
        modifiedAt: Date,
        preview: String? = nil
    ) throws {
        var contents = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\",\"timestamp\":\"2026-08-24T10:00:00.000Z\"}}"
        if let preview {
            contents += "\n{\"type\":\"response_item\",\"timestamp\":\"2026-08-24T10:01:00.000Z\",\"payload\":{\"type\":\"message\",\"id\":\"u1\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"\(preview)\"}]}}"
        }
        let file = day.appendingPathComponent("rollout-\(id).jsonl")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
    }

    for index in 0..<100 {
        try writeRollout(
            id: String(format: "%08d-0000-4000-8000-%012d", index, index),
            cwd: "/tmp/other",
            modifiedAt: Date(timeIntervalSince1970: 2_000 + Double(index))
        )
    }
    let olderMatch = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let newerMatch = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let unscannedMatch = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    try writeRollout(
        id: olderMatch,
        cwd: "/tmp/work",
        modifiedAt: Date(timeIntervalSince1970: 1_010),
        preview: "older"
    )
    try writeRollout(
        id: newerMatch,
        cwd: "/tmp/work",
        modifiedAt: Date(timeIntervalSince1970: 1_020),
        preview: "newer"
    )
    try writeRollout(
        id: unscannedMatch,
        cwd: "/tmp/work",
        modifiedAt: Date(timeIntervalSince1970: 1_001),
        preview: "must not be scanned"
    )
    for index in 100..<1_000 {
        try writeRollout(
            id: String(format: "%08d-0000-4000-8000-%012d", index, index),
            cwd: "/tmp/other",
            modifiedAt: Date(timeIntervalSince1970: 900 - Double(index))
        )
    }

    final class ScanCounter: @unchecked Sendable {
        var value = 0
    }
    let counter = ScanCounter()
    let discovery = CodexSessionHistoryDiscovery(codexHome: root)
    let entries = discovery.entries(forWorkingDirectory: "/tmp/work", limit: 2) { _ in
        counter.value += 1
    }

    #expect(entries.map(\.sessionID) == [newerMatch, olderMatch])
    #expect(counter.value == 102)
}

@Test func codexSessionHistory_cwdMismatchDoesNotReadPreviewBody() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-history-prefix-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let day = root.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let file = day.appendingPathComponent("rollout-mismatch.jsonl")
    let hugePreview = String(repeating: "x", count: 2 * 1024 * 1024)
    let contents = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"mismatch\",\"cwd\":\"/tmp/other\"}}\n"
        + "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"\(hugePreview)\"}]}}"
    try contents.write(to: file, atomically: true, encoding: .utf8)

    final class ReadCounter: @unchecked Sendable {
        var reads = 0
        var bytes = 0
    }
    let counter = ReadCounter()
    let discovery = CodexSessionHistoryDiscovery(codexHome: root)
    let entries = discovery.entries(
        forWorkingDirectory: "/tmp/work",
        limit: 1,
        onRead: { bytes in
            counter.reads += 1
            counter.bytes += bytes
        }
    )

    #expect(entries.isEmpty)
    #expect(counter.reads == 1)
    #expect(counter.bytes == CodexSessionHistoryDiscovery.maxSessionMetaBytes)
}

@Test func codexSessionHistory_prefersStateDatabaseAndDoesNotScanJSONL() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-history-state-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("state_5.sqlite")
    try createStateDatabase(at: databaseURL)
    try insertThread(at: databaseURL, id: "newer", rolloutPath: "/tmp/newer.jsonl", cwd: "/tmp/work", preview: "  新しい履歴  ", firstUserMessage: "", updatedAtMilliseconds: 2_000)
    try insertThread(at: databaseURL, id: "fallback", rolloutPath: "/tmp/fallback.jsonl", cwd: "/tmp/work", preview: "", firstUserMessage: "DB の本文", updatedAtMilliseconds: 1_000)
    try insertThread(at: databaseURL, id: "other-cwd", rolloutPath: "/tmp/other.jsonl", cwd: "/tmp/other", preview: "除外", firstUserMessage: "", updatedAtMilliseconds: 3_000)

    final class ScanCounter: @unchecked Sendable {
        var value = 0
    }
    let counter = ScanCounter()
    let entries = CodexSessionHistoryDiscovery(codexHome: root).entries(
        forWorkingDirectory: "/tmp/work",
        limit: 2,
        onScan: { _ in counter.value += 1 }
    )

    #expect(entries.map(\.sessionID) == ["newer", "fallback"])
    #expect(entries.map(\.preview) == ["新しい履歴", "DB の本文"])
    #expect(entries[0].fileURL.path == "/tmp/newer.jsonl")
    #expect(entries[0].lastModified == Date(timeIntervalSince1970: 2))
    #expect(counter.value == 0)

    let noMatchCounter = ScanCounter()
    let noMatchEntries = CodexSessionHistoryDiscovery(codexHome: root).entries(
        forWorkingDirectory: "/tmp/missing",
        limit: 2,
        onScan: { _ in noMatchCounter.value += 1 }
    )
    #expect(noMatchEntries.isEmpty)
    #expect(noMatchCounter.value == 0)
}

@Test func codexSessionHistory_fallsBackWhenStateDatabaseSchemaIsUnavailable() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-history-state-fallback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("state_5.sqlite")
    try createOldStateDatabase(at: databaseURL)
    let day = root.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let rollout = day.appendingPathComponent("rollout-fallback.jsonl")
    let contents = #"{"type":"session_meta","payload":{"id":"fallback","cwd":"/tmp/work"}}"#
        + "\n"
        + #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"JSONL fallback"}]}}"#
    try contents.write(to: rollout, atomically: true, encoding: .utf8)

    final class ScanCounter: @unchecked Sendable {
        var value = 0
    }
    let counter = ScanCounter()
    let entries = CodexSessionHistoryDiscovery(codexHome: root).entries(
        forWorkingDirectory: "/tmp/work",
        limit: 1,
        onScan: { _ in counter.value += 1 }
    )

    #expect(entries.map(\.sessionID) == ["fallback"])
    #expect(entries.first?.preview == "JSONL fallback")
    #expect(counter.value == 1)
}

private func createStateDatabase(at url: URL) throws {
    var database: OpaquePointer?
    let result = sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard result == SQLITE_OK, let database else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 1)
    }
    defer { sqlite3_close_v2(database) }
    let schema = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      rollout_path TEXT NOT NULL,
      cwd TEXT NOT NULL,
      preview TEXT NOT NULL DEFAULT '',
      first_user_message TEXT NOT NULL DEFAULT '',
      updated_at_ms INTEGER,
      archived INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX idx_threads_archived_cwd_updated_at_ms
      ON threads(archived, cwd, updated_at_ms DESC, id DESC);
    """
    guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 2)
    }
}

private func createOldStateDatabase(at url: URL) throws {
    var database: OpaquePointer?
    let result = sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard result == SQLITE_OK, let database else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 3)
    }
    defer { sqlite3_close_v2(database) }
    guard sqlite3_exec(database, "CREATE TABLE threads (id TEXT PRIMARY KEY);", nil, nil, nil) == SQLITE_OK else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 4)
    }
}

private func insertThread(
    at url: URL,
    id: String,
    rolloutPath: String,
    cwd: String,
    preview: String,
    firstUserMessage: String,
    updatedAtMilliseconds: Int64
) throws {
    var database: OpaquePointer?
    let result = sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE, nil)
    guard result == SQLITE_OK, let database else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 5)
    }
    defer { sqlite3_close_v2(database) }
    var statement: OpaquePointer?
    let sql = "INSERT INTO threads(id, rollout_path, cwd, preview, first_user_message, updated_at_ms) VALUES(?, ?, ?, ?, ?, ?);"
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 6)
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let values = [id, rolloutPath, cwd, preview, firstUserMessage]
    for (index, value) in values.enumerated() {
        guard value.withCString({ sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }) == SQLITE_OK else {
            throw NSError(domain: "CodexSessionHistoryTests", code: 7)
        }
    }
    guard sqlite3_bind_int64(statement, 6, updatedAtMilliseconds) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_DONE else {
        throw NSError(domain: "CodexSessionHistoryTests", code: 8)
    }
}
