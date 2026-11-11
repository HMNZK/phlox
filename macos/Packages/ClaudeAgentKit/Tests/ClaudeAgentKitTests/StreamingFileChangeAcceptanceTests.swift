import Foundation
import Testing
import StructuredChatKit
import ClaudeAgentKit

@Suite("Streaming file change acceptance")
struct StreamingFileChangeAcceptanceTests {
    @Test("Edit は入力全体の完成前に、確定したファイルパスを通知する")
    func editPublishesPathBeforeInputAndAssistantComplete() async throws {
        let events = try await streamedFileChanges([
            #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-edit","content":[]}},"parent_tool_use_id":null}"#,
            try toolBlockStart(id: "tool-edit-stream", name: "Edit"),
            try toolInputDelta(#"{"file_path":"Sources/App.swift","old_string":"unfinished"#),
        ])

        #expect(events == [
            .fileChange(itemId: "tool-edit-stream", [
                FilePatchChange(path: "Sources/App.swift", diff: "", kind: "edit"),
            ]),
        ])
    }

    @Test("Write は途中のパスや文字列中の偽のキーを採用せず JSON escape を復号する")
    func writeWaitsForCompleteEscapedPath() async throws {
        let events = try await streamedFileChanges([
            #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-write","content":[]}},"parent_tool_use_id":null}"#,
            try toolBlockStart(id: "tool-write-stream", name: "Write"),
            try toolInputDelta(#"{"note":"\"file_path\":\"Wrong.swift\"","file_path":"Sources\/quote\"#),
            try toolInputDelta(#""name\u002e"#),
            try toolInputDelta(#"swift","content":"unfinished"#),
        ])

        #expect(events == [
            .fileChange(itemId: "tool-write-stream", [
                FilePatchChange(path: "Sources/quote\"name.swift", diff: "", kind: "write"),
            ]),
        ])
    }

    @Test("MultiEdit は先行通知と完成差分を同じ ID で一度ずつ通知する")
    func completedMultiEditUpdatesPreviewWithoutDuplicateItems() async throws {
        let events = try await streamedFileChanges([
            #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-multi","content":[]}},"parent_tool_use_id":null}"#,
            try toolBlockStart(id: "tool-multi-stream", name: "MultiEdit"),
            try toolInputDelta(#"{"file_path":"Sources/Config.swift","edits":["#),
            try toolInputDelta(#"{"old_string":"let enabled = false\n","new_string":"let enabled = true\n"}"#),
            try toolInputDelta("]}"),
            #"{"type":"stream_event","event":{"type":"content_block_stop","index":0},"parent_tool_use_id":null}"#,
            #"{"type":"assistant","message":{"id":"message-multi","content":[{"type":"tool_use","id":"tool-multi-stream","name":"MultiEdit","input":{"file_path":"Sources/Config.swift","edits":[{"old_string":"let enabled = false\n","new_string":"let enabled = true\n"}]}}]},"parent_tool_use_id":null}"#,
        ])

        #expect(events == [
            .fileChange(itemId: "tool-multi-stream", [
                FilePatchChange(path: "Sources/Config.swift", diff: "", kind: "edit"),
            ]),
            .fileChange(itemId: "tool-multi-stream", [
                FilePatchChange(
                    path: "Sources/Config.swift",
                    diff: "--- Sources/Config.swift\n+++ Sources/Config.swift\n@@\n-let enabled = false\n+let enabled = true\n",
                    kind: "edit"
                ),
            ]),
        ])
    }

    @Test("同じブロック番号の子ツール入力を親のファイル変更へ漏らさない")
    func childInputDoesNotReplaceOrLeakIntoParentPreview() async throws {
        let events = try await streamedFileChanges([
            #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-parent","content":[]}},"parent_tool_use_id":null}"#,
            try toolBlockStart(id: "tool-parent-edit", name: "Edit"),
            try toolInputDelta(#"{"file_path":"Sources/Parent"#),
            #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-child","content":[]}},"parent_tool_use_id":"tool-agent"}"#,
            try toolBlockStart(id: "tool-child-write", name: "Write", parent: "tool-agent"),
            try toolInputDelta(#"{"file_path":"Sources/Child.swift","content":"child"}"#, parent: "tool-agent"),
            #"{"type":"assistant","message":{"id":"message-child","content":[{"type":"tool_use","id":"tool-child-write","name":"Write","input":{"file_path":"Sources/Child.swift","content":"child"}}]},"parent_tool_use_id":"tool-agent"}"#,
            try toolInputDelta(#".swift","old_string":"unfinished"#),
        ])

        #expect(events == [
            .fileChange(itemId: "tool-parent-edit", [
                FilePatchChange(path: "Sources/Parent.swift", diff: "", kind: "edit"),
            ]),
        ])
    }
}

@Suite("ファイル編集の失敗は変更数へ残さない")
struct FailedFileChangeAcceptanceTests {
    @Test("適用に失敗した編集は確定前に同じファイルの差分を取り消す")
    func failedToolClearsTheUnappliedDiff() async throws {
        let events = try await streamedFileChanges([
            #"{"type":"assistant","message":{"id":"message-failed","content":[{"type":"tool_use","id":"tool-failed","name":"Edit","input":{"file_path":"Sources/Card.swift","old_string":"old\n","new_string":"new\n"}}]},"parent_tool_use_id":null}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool-failed","is_error":true,"content":"old_string was not found"}]},"parent_tool_use_id":null}"#,
        ])

        #expect(events == [
            .fileChange(itemId: "tool-failed", [
                FilePatchChange(path: "Sources/Card.swift",
                    diff: "--- Sources/Card.swift\n+++ Sources/Card.swift\n@@\n-old\n+new\n", kind: "edit"),
            ]),
            .fileChange(itemId: "tool-failed", [
                FilePatchChange(path: "Sources/Card.swift", diff: "", kind: "edit"),
            ]),
        ])
    }
}

private func toolBlockStart(id: String, name: String, parent: String? = nil) throws -> String {
    try streamLine([
        "type": "content_block_start",
        "index": 0,
        "content_block": ["type": "tool_use", "id": id, "name": name, "input": [:]],
    ], parent: parent)
}

private func toolInputDelta(_ partialJSON: String, parent: String? = nil) throws -> String {
    try streamLine([
        "type": "content_block_delta",
        "index": 0,
        "delta": ["type": "input_json_delta", "partial_json": partialJSON],
    ], parent: parent)
}

private func streamLine(_ event: [String: Any], parent: String?) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [
        "type": "stream_event",
        "event": event,
        "parent_tool_use_id": parent as Any? ?? NSNull(),
    ])
    return String(decoding: data, as: UTF8.self)
}

private func streamedFileChanges(_ lines: [String]) async throws -> [NormalizedChatEvent] {
    let transport = StreamingFileChangeTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in transport })
    try await client.start()
    for line in lines {
        transport.receive(line)
    }
    transport.receive(#"{"type":"result","subtype":"success","session_id":"stream-file-session","is_error":false}"#)

    var changes: [NormalizedChatEvent] = []
    for await event in client.events {
        if case .turnCompleted = event { break }
        if case .fileChange = event { changes.append(event) }
        if case .error(let message) = event { Issue.record("Unexpected stream error: \(message)") }
    }
    await client.close()
    return changes
}

private final class StreamingFileChangeTransport: LineDelimitedTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        (receivedLines, continuation) = AsyncStream.makeStream()
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation.finish() }
    func receive(_ line: String) { continuation.yield(Data(line.utf8)) }
}
