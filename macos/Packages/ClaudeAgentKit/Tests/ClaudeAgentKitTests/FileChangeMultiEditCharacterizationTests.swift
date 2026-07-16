import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

// task-7: fileChangeEvent の MultiEdit 分岐（ClaudeChatClient.swift:958-970）の現挙動を固定する特性化テスト。

@Test func multiEditCombinesMultipleEditsIntoSingleFileChangeWithJoinedDiff() async throws {
    let mock = MultiEditMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-multiedit","name":"MultiEdit","input":{"file_path":"Sources/App.swift","edits":[{"old_string":"let a = 1\\n","new_string":"let a = 2\\n"},{"old_string":"let b = true\\n","new_string":"let b = false\\n"}]}}]}}
    """)

    let firstEditDiff = """
    --- Sources/App.swift
    +++ Sources/App.swift
    @@
    -let a = 1
    +let a = 2

    """
    let secondEditDiff = """
    --- Sources/App.swift
    +++ Sources/App.swift
    @@
    -let b = true
    +let b = false

    """
    let expectedCombinedDiff = firstEditDiff + "\n" + secondEditDiff

    #expect(await iterator.next() == .fileChange(itemId: "tool-multiedit", [
        FilePatchChange(path: "Sources/App.swift", diff: expectedCombinedDiff, kind: "edit"),
    ]))
    await client.close()
}

@Test func multiEditWithEmptyEditsArrayStillEmitsFileChangeWithEmptyDiff() async throws {
    let mock = MultiEditMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-multiedit-empty","name":"MultiEdit","input":{"file_path":"Sources/Empty.swift","edits":[]}}]}}
    """)

    #expect(await iterator.next() == .fileChange(itemId: "tool-multiedit-empty", [
        FilePatchChange(path: "Sources/Empty.swift", diff: "", kind: "edit"),
    ]))
    await client.close()
}

@Test func multiEditEditMissingOldStringUsesNullSourceInDiff() async throws {
    let mock = MultiEditMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-multiedit-write","name":"MultiEdit","input":{"file_path":"Sources/New.swift","edits":[{"new_string":"let created = true\\n"}]}}]}}
    """)

    let expectedDiff = """
    --- /dev/null
    +++ Sources/New.swift
    @@
    +let created = true

    """
    #expect(await iterator.next() == .fileChange(itemId: "tool-multiedit-write", [
        FilePatchChange(path: "Sources/New.swift", diff: expectedDiff, kind: "edit"),
    ]))
    await client.close()
}

@Test func multiEditWithoutFilePathFallsBackToCommandExecution() async throws {
    let mock = MultiEditMockTransport()
    let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-multiedit-no-path","name":"MultiEdit","input":{"edits":[{"old_string":"x","new_string":"y"}]}}]}}
    """)

    let event = await iterator.next()
    guard case .commandExecution(let itemId, let command, let outputDelta) = event else {
        Issue.record("expected commandExecution fallback, got \(String(describing: event))")
        await client.close()
        return
    }
    #expect(itemId == "tool-multiedit-no-path")
    #expect(outputDelta == "")
    #expect(command?.hasPrefix("MultiEdit ") == true)
    #expect(command?.contains(#""edits""#) == true)
    await client.close()
}

private final class MultiEditMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {}

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}
