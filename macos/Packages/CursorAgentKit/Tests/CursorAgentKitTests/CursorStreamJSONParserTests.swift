import Foundation
import StructuredChatKit
import Testing
@testable import CursorAgentKit

// これらのテストは PM が実 cursor-agent から取得した生 stream-json
// (tasks/fixtures/cursor-events/real-events.jsonl) を素材に、tool_call の出力抽出が
// 実データのネスト構造 (tool_call[<種別キー>].result.success.*) を正しく辿ることを固定する。

private func realEventLines() throws -> [String] {
    // フィクスチャは同一テストターゲット配下（cwd 非依存・#filePath の兄弟 Fixtures/）。
    // .../CursorAgentKitTests/CursorStreamJSONParserTests.swift → 同 .../CursorAgentKitTests/Fixtures/
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/real-events.jsonl")
    let content = try String(contentsOf: fixture, encoding: .utf8)
    return content
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
}

private func deleteGlobEventLines() throws -> [String] {
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/delete-glob-events.jsonl")
    let content = try String(contentsOf: fixture, encoding: .utf8)
    return content
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
}

private func deleteGlobEventLine(where predicate: (String) -> Bool) throws -> String {
    let lines = try deleteGlobEventLines()
    let match = lines.first(where: predicate)
    return try #require(match)
}

private func realEventLine(where predicate: (String) -> Bool) throws -> String {
    let lines = try realEventLines()
    let match = lines.first(where: predicate)
    return try #require(match)
}

private func encodeJSONLine(_ object: [String: Any]) -> Data {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return data
}

private func commandOutput(in events: [NormalizedChatEvent]) -> String? {
    for event in events {
        if case .commandExecution(_, _, let outputDelta) = event {
            return outputDelta
        }
    }
    return nil
}

private func commandLabel(in events: [NormalizedChatEvent]) -> String? {
    for event in events {
        if case .commandExecution(_, let command, _) = event {
            return command
        }
    }
    return nil
}

private func fileChanges(in events: [NormalizedChatEvent]) -> [FilePatchChange]? {
    for event in events {
        if case .fileChange(_, let changes) = event {
            return changes
        }
    }
    return nil
}

private func reasoningText(in events: [NormalizedChatEvent]) -> String? {
    for event in events {
        if case .reasoningDelta(_, let text) = event {
            return text
        }
    }
    return nil
}

@Test func deleteToolCallCompletedEmitsDeletionFileChangeFromPrevContent() throws {
    var parser = CursorStreamJSONParser()

    let started = try deleteGlobEventLine { $0.contains("\"deleteToolCall\"") && $0.contains("\"started\"") }
    let completed = try deleteGlobEventLine { $0.contains("\"deleteToolCall\"") && $0.contains("\"completed\"") }

    _ = try parser.ingest(line: Data(started.utf8))
    let events = try parser.ingest(line: Data(completed.utf8))

    let changes = try #require(fileChanges(in: events))
    let change = try #require(changes.first)
    #expect(change.path == "/work/victim.txt")
    #expect(change.kind == "delete")
    #expect(change.diff.contains("\n-hello world\n"))
    #expect(change.diff.contains("\n-second line\n"))
    #expect(!change.diff.contains("\n+hello world\n"))
    #expect(!change.diff.contains("\n+second line\n"))
}

@Test func deleteAndGlobToolCallLabelsUseToolKindNotMetadataKeys() throws {
    var parser = CursorStreamJSONParser()

    let deleteStarted = try deleteGlobEventLine { $0.contains("\"deleteToolCall\"") && $0.contains("\"started\"") }
    let globStarted = try deleteGlobEventLine { $0.contains("\"globToolCall\"") && $0.contains("\"started\"") }

    let deleteEvents = try parser.ingest(line: Data(deleteStarted.utf8))
    let globEvents = try parser.ingest(line: Data(globStarted.utf8))

    #expect(commandLabel(in: deleteEvents) == "Delete")
    #expect(commandLabel(in: globEvents) == "Glob")
}

@Test func globToolCallCompletedExtractsFilesAsOutput() throws {
    var parser = CursorStreamJSONParser()

    let started = try deleteGlobEventLine { $0.contains("\"globToolCall\"") && $0.contains("\"started\"") }
    let completed = try deleteGlobEventLine { $0.contains("\"globToolCall\"") && $0.contains("\"completed\"") }

    _ = try parser.ingest(line: Data(started.utf8))
    let events = try parser.ingest(line: Data(completed.utf8))

    let output = try #require(commandOutput(in: events))
    #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(output.contains("keep.txt"))
}

@Test func realShellToolCallCompletedExtractsStdout() throws {
    var parser = CursorStreamJSONParser()

    let started = try realEventLine {
        $0.contains("\"subtype\": \"started\"") && $0.contains("shellToolCall")
    }
    let completed = try realEventLine {
        $0.contains("\"subtype\": \"completed\"") && $0.contains("\"stdout\"")
    }

    _ = try parser.ingest(line: Data(started.utf8))
    let events = try parser.ingest(line: Data(completed.utf8))

    let output = try #require(commandOutput(in: events))
    // 修正前: extractToolOutput が json["result"](トップ)を見るため "" になり fail する。
    // 修正後: tool_call.shellToolCall.result.success.stdout を辿り実出力が入る。
    #expect(output.contains("TOOLOUT_MARKER_42"))
}

@Test func realReadToolCallCompletedExtractsContent() throws {
    var parser = CursorStreamJSONParser()

    let completed = try realEventLine { $0.contains("line-two-READMARK") }
    let completedJSON = try #require(
        try JSONSerialization.jsonObject(with: Data(completed.utf8)) as? [String: Any]
    )
    let callId = try #require(completedJSON["call_id"] as? String)

    // フィクスチャには read の started 行が無いため、同一 call_id の started を合成して
    // pending を登録する（出力抽出の検証対象は completed のネスト構造）。
    _ = try parser.ingest(line: encodeJSONLine([
        "type": "tool_call",
        "subtype": "started",
        "call_id": callId,
        "tool_call": ["readToolCall": ["args": ["path": "sample.txt"]]],
    ]))
    let events = try parser.ingest(line: Data(completed.utf8))

    let output = try #require(commandOutput(in: events))
    // 修正後は tool_call.readToolCall.result.success.content が入る。
    #expect(output.contains("line-two-READMARK"))
}

@Test func realThinkingDeltaProducesReasoning() throws {
    var parser = CursorStreamJSONParser()

    let thinking = try realEventLine {
        $0.contains("\"type\": \"thinking\"")
            && $0.contains("\"subtype\": \"delta\"")
            && $0.contains("\"text\"")
    }

    let events = try parser.ingest(line: Data(thinking.utf8))

    // Cursor の thinking パースは現状正常。回帰防止のためこの振る舞いを固定する。
    #expect(events.contains { event in
        if case .reasoningDelta(let itemId, _) = event { return itemId == "reasoning" }
        return false
    })
    let text = try #require(reasoningText(in: events))
    #expect(!text.isEmpty)
}
