// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — ~/.claude/projects の履歴 JSONL からの一覧抽出と転写ロード。

import Foundation
import Testing
@testable import DashboardFeature

private func makeTempProjectsRoot() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-history-acceptance-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeJSONL(_ lines: [String], to url: URL, modifiedAt: Date? = nil) throws {
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    if let modifiedAt {
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }
}

@Test func claudeSessionHistory_directoryName_replacesNonAlphanumericsWithHyphen() {
    #expect(ClaudeSessionHistoryDiscovery.projectDirectoryName(
        forWorkingDirectory: "/Users/you/Projects/Phlox"
    ) == "-Users-you-Projects-Phlox")
    // ドットも `-` になる（実例: /Users/you/.claude → -Users-you--claude）
    #expect(ClaudeSessionHistoryDiscovery.projectDirectoryName(
        forWorkingDirectory: "/Users/you/.claude"
    ) == "-Users-you--claude")
}

@Test func claudeSessionHistory_entries_extractsPreviewTimestampBranch_andSortsByMtimeDesc() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-tmp-work", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let older = dir.appendingPathComponent("11111111-1111-4111-8111-111111111111.jsonl")
    try writeJSONL([
        #"{"type":"mode","mode":"default"}"#,
        #"{"type":"file-history-snapshot","snapshot":{}}"#,
        #"{"type":"user","message":{"role":"user","content":"こんにちは、最初の依頼です"},"uuid":"u-1","timestamp":"2026-07-01T10:00:00.000Z","cwd":"/tmp/work","sessionId":"11111111-1111-4111-8111-111111111111","gitBranch":"dev"}"#,
    ], to: older, modifiedAt: Date(timeIntervalSince1970: 1_750_000_000))

    let newer = dir.appendingPathComponent("22222222-2222-4222-8222-222222222222.jsonl")
    try writeJSONL([
        #"{"type":"mode","mode":"default"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"配列コンテンツの依頼"}]},"uuid":"u-2","timestamp":"2026-07-02T10:00:00.000Z","cwd":"/tmp/work","sessionId":"22222222-2222-4222-8222-222222222222"}"#,
    ], to: newer, modifiedAt: Date(timeIntervalSince1970: 1_760_000_000))

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    let entries = discovery.entries(forWorkingDirectory: "/tmp/work", limit: 10)

    try #require(entries.count == 2)
    // mtime 降順
    #expect(entries[0].sessionID == "22222222-2222-4222-8222-222222222222")
    #expect(entries[0].preview == "配列コンテンツの依頼")
    #expect(entries[0].gitBranch == nil)
    #expect(entries[1].sessionID == "11111111-1111-4111-8111-111111111111")
    #expect(entries[1].preview == "こんにちは、最初の依頼です")
    #expect(entries[1].gitBranch == "dev")

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expectedFirstUserAt = try #require(formatter.date(from: "2026-07-01T10:00:00.000Z"))
    let firstUserAt = try #require(entries[1].firstUserAt)
    #expect(abs(firstUserAt.timeIntervalSince(expectedFirstUserAt)) < 1.0)
}

@Test func claudeSessionHistory_entries_excludesMetaOnlySidechainAndCommandFiles() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-tmp-work", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // (a) 制御メタのみ（ユーザー発言なし）
    try writeJSONL([
        #"{"type":"mode","mode":"default"}"#,
        #"{"type":"summary","summary":"要約だけ"}"#,
    ], to: dir.appendingPathComponent("aaaaaaaa-0000-4000-8000-000000000001.jsonl"))

    // (b) サブエージェント転写（isSidechain: true）
    try writeJSONL([
        #"{"type":"user","message":{"role":"user","content":"サブエージェントのプロンプト"},"isSidechain":true,"uuid":"u-b","timestamp":"2026-07-01T00:00:00.000Z"}"#,
    ], to: dir.appendingPathComponent("aaaaaaaa-0000-4000-8000-000000000002.jsonl"))

    // (c) コマンドメタで始まるユーザー行のみ
    try writeJSONL([
        #"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"},"uuid":"u-c","timestamp":"2026-07-01T00:00:00.000Z"}"#,
    ], to: dir.appendingPathComponent("aaaaaaaa-0000-4000-8000-000000000003.jsonl"))

    // (d) 有効なセッション
    try writeJSONL([
        #"{"type":"user","message":{"role":"user","content":"有効な依頼"},"uuid":"u-d","timestamp":"2026-07-01T00:00:00.000Z"}"#,
    ], to: dir.appendingPathComponent("aaaaaaaa-0000-4000-8000-000000000004.jsonl"))

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    let entries = discovery.entries(forWorkingDirectory: "/tmp/work", limit: 10)

    try #require(entries.count == 1)
    #expect(entries[0].sessionID == "aaaaaaaa-0000-4000-8000-000000000004")
    #expect(entries[0].preview == "有効な依頼")
}

// fix round（ステージ1レビュー MUST 由来・PM 著）: UTF-8 マルチバイト文字が 16KiB チャンク境界で
// 割れても、1 行も silent に失わないこと。修正前の実装は該当チャンク全体を捨て 63% を喪失した。
@Test func claudeSessionHistory_loader_recoversAllMessagesAcrossUTF8ChunkBoundaries() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("ffffffff-0000-4000-8000-000000000001.jsonl")
    let body = String(repeating: "あ", count: 37)
    let lines = (0..<2000).map {
        #"{"type":"user","message":{"role":"user","content":"\#(body)\#($0)"},"uuid":"u\#($0)","timestamp":"2026-07-01T00:00:00.000Z"}"#
    }
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

    let items = ClaudeSessionTranscriptLoader().load(fileURL: file, maxItems: 5000)
    #expect(items.count == 2000)
}

@Test func claudeSessionHistory_entries_missingRootReturnsEmpty() {
    let discovery = ClaudeSessionHistoryDiscovery(
        projectsRoot: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    )
    #expect(discovery.entries(forWorkingDirectory: "/tmp/work", limit: 5).isEmpty)
}

@Test func claudeSessionHistory_loader_mapsUserAndAssistantTextInOrder_andTailsMaxItems() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("33333333-3333-4333-8333-333333333333.jsonl")
    try writeJSONL([
        #"{"type":"mode","mode":"default"}"#,
        #"{"type":"user","message":{"role":"user","content":"u1"},"uuid":"id-u1","timestamp":"2026-07-01T00:00:01.000Z"}"#,
        #"{"type":"assistant","message":{"id":"msg-1","role":"assistant","content":[{"type":"text","text":"a1"}]},"uuid":"id-a1","timestamp":"2026-07-01T00:00:02.000Z"}"#,
        #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"},"uuid":"id-meta","timestamp":"2026-07-01T00:00:03.000Z"}"#,
        #"{"type":"assistant","message":{"id":"msg-2","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{}},{"type":"text","text":"a2"}]},"uuid":"id-a2","timestamp":"2026-07-01T00:00:04.000Z"}"#,
        #"{"type":"user","message":{"role":"user","content":"u2"},"uuid":"id-u2","timestamp":"2026-07-01T00:00:05.000Z"}"#,
    ], to: file)

    let loader = ClaudeSessionTranscriptLoader()

    let all = loader.load(fileURL: file, maxItems: 10)
    try #require(all.count == 4)
    if case .userMessage(_, let text, _, _) = all[0] { #expect(text == "u1") } else { Issue.record("all[0] should be userMessage: \(all[0])") }
    if case .agentMessage(_, let text, _) = all[1] { #expect(text == "a1") } else { Issue.record("all[1] should be agentMessage: \(all[1])") }
    if case .agentMessage(_, let text, _) = all[2] { #expect(text == "a2") } else { Issue.record("all[2] should be agentMessage: \(all[2])") }
    if case .userMessage(_, let text, _, _) = all[3] { #expect(text == "u2") } else { Issue.record("all[3] should be userMessage: \(all[3])") }

    // 末尾側 maxItems 件
    let tail = loader.load(fileURL: file, maxItems: 3)
    try #require(tail.count == 3)
    if case .agentMessage(_, let text, _) = tail[0] { #expect(text == "a1") } else { Issue.record("tail[0] should be agentMessage: \(tail[0])") }
    if case .userMessage(_, let text, _, _) = tail[2] { #expect(text == "u2") } else { Issue.record("tail[2] should be userMessage: \(tail[2])") }
}
