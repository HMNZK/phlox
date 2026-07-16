import Foundation
import Testing
@testable import DashboardFeature

private func makeTempProjectsRoot() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-history-whitebox-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func claudeSessionHistory_whitebox_toleratesEmptyBrokenAndMetaOnlyFiles() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-proj", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    FileManager.default.createFile(atPath: dir.appendingPathComponent("empty.jsonl").path, contents: Data())
    try "not json".write(to: dir.appendingPathComponent("broken.jsonl"), atomically: true, encoding: .utf8)
    try #"{"type":"summary","summary":"only meta"}"#.write(
        to: dir.appendingPathComponent("meta-only.jsonl"),
        atomically: true,
        encoding: .utf8
    )

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    #expect(discovery.entries(forWorkingDirectory: "/proj", limit: 10).isEmpty)
}

@Test func claudeSessionHistory_whitebox_boundedReadStopsBeforeLateUserLine() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-proj", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // 先頭 200 行を超えた位置のユーザー行は一覧に出ない（有界読み取り）。
    var lines: [String] = (1...210).map { #"{"type":"mode","mode":"line-\#($0)"}"# }
    lines.append(
        #"{"type":"user","message":{"role":"user","content":"too late"},"uuid":"late","timestamp":"2026-07-01T00:00:00.000Z"}"#
    )
    let file = dir.appendingPathComponent("bbbbbbbb-0000-4000-8000-000000000099.jsonl")
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    #expect(discovery.entries(forWorkingDirectory: "/proj", limit: 10).isEmpty)
}

@Test func claudeSessionHistory_whitebox_boundedReadFindsUserWithin200Lines() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-proj", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var lines: [String] = (1...150).map { #"{"type":"mode","mode":"line-\#($0)"}"# }
    lines.append(
        #"{"type":"user","message":{"role":"user","content":"within bound"},"uuid":"ok","timestamp":"2026-07-01T00:00:00.000Z"}"#
    )
    lines.append(contentsOf: (151...400).map { #"{"type":"mode","mode":"tail-\#($0)"}"# })
    let file = dir.appendingPathComponent("cccccccc-0000-4000-8000-000000000088.jsonl")
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    let entries = discovery.entries(forWorkingDirectory: "/proj", limit: 10)
    try #require(entries.count == 1)
    #expect(entries[0].preview == "within bound")
}

@Test func claudeSessionHistory_whitebox_previewTruncatesTo120Characters() throws {
    let root = try makeTempProjectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("-proj", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let longText = String(repeating: "あ", count: 200)
    let file = dir.appendingPathComponent("dddddddd-0000-4000-8000-000000000077.jsonl")
    try [
        #"{"type":"user","message":{"role":"user","content":"\#(longText)"},"uuid":"u","timestamp":"2026-07-01T00:00:00.000Z"}"#,
    ].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

    let discovery = ClaudeSessionHistoryDiscovery(projectsRoot: root)
    let entries = discovery.entries(forWorkingDirectory: "/proj", limit: 1)
    try #require(entries.count == 1)
    #expect(entries[0].preview.count == 120)
}
