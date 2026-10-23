import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

@Suite struct ResumeTurnIdentityTests {
    @Test(arguments: [true, false])
    func completedRestoredTurnDoesNotBlockNextTurn(usageBeforeResponse: Bool) async throws {
        let transport = MockTransport()
        let client = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        let recorder = ResumeTurnRecorder()
        let collector = Task {
            for await event in adapter.orderedEvents { await recorder.append(event) }
        }
        let resume = Task { try await adapter.threadResume(ThreadResumeParams(threadId: "thread")) }
        let request = try await resumeRequest(transport)
        if usageBeforeResponse {
            usage(transport, turn: "old")
            try await barrier(transport, recorder: recorder)
        }
        try respond(transport, request: request, turns: #"[{"id":"old","status":"completed","items":[]}]"#)
        _ = try await resume.value
        #expect(await client.activeTurnId(for: "thread") == nil)
        if !usageBeforeResponse {
            usage(transport, turn: "old")
            try await barrier(transport, recorder: recorder)
        }
        started(transport, turn: "new")
        delta(transport, turn: "new", text: "answer")
        completed(transport, turn: "new")
        usage(transport, turn: "old")
        delta(transport, turn: "old", text: "stale")
        completed(transport, turn: "old")
        completed(transport, turn: "new")
        usage(transport, turn: "new")
        try await barrier(transport, recorder: recorder)
        #expect(await recorder.normalized.filter { if case .turnUsage = $0 { false } else { true } } == [
            .turnStarted, .agentMessageDelta(itemId: "message", "answer"), .turnCompleted(nativeSessionId: "thread"),
        ])
        #expect(await recorder.usageCount == (usageBeforeResponse ? 1 : 0))
        #expect(await client.activeTurnId(for: "thread") == nil)
        await adapter.close()
        await collector.value
    }

    @Test(arguments: [true, false])
    func startedTurnReplacesTentativeUsageWhenResumeHasNoTurns(restoredInProgress: Bool) async throws {
        let transport = MockTransport()
        let client = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        let recorder = ResumeTurnRecorder()
        let collector = Task {
            for await event in adapter.orderedEvents { await recorder.append(event) }
        }
        let resume = Task { try await adapter.threadResume(ThreadResumeParams(threadId: "thread")) }
        let request = try await resumeRequest(transport)
        if restoredInProgress {
            usage(transport, turn: "old")
            try await barrier(transport, recorder: recorder)
        }
        try respond(transport, request: request, turns: restoredInProgress
            ? #"[{"id":"new","status":"inProgress","items":[]}]"# : "[]")
        _ = try await resume.value
        if !restoredInProgress {
            usage(transport, turn: "old")
            try await barrier(transport, recorder: recorder)
        }
        started(transport, turn: "new")
        delta(transport, turn: "new", text: "answer")
        completed(transport, turn: "new")
        usage(transport, turn: "old")
        try await barrier(transport, recorder: recorder)
        #expect(await client.activeTurnId(for: "thread") == nil)
        started(transport, turn: "next")
        delta(transport, turn: "next", text: "next answer")
        completed(transport, turn: "next")
        delta(transport, turn: "old", text: "stale")
        completed(transport, turn: "old")
        try await barrier(transport, recorder: recorder)
        #expect(await recorder.normalized.dropFirst() == [
            .turnStarted, .agentMessageDelta(itemId: "message", "answer"), .turnCompleted(nativeSessionId: "thread"),
            .turnStarted, .agentMessageDelta(itemId: "message", "next answer"), .turnCompleted(nativeSessionId: "thread"),
        ])
        #expect(await recorder.usageCount == 1)
        #expect(await client.activeTurnId(for: "thread") == nil)
        await adapter.close()
        await collector.value
    }

    @Test func staleResumeResponsePreservesObservedTurnAndClosesPastTurns() async throws {
        let transport = MockTransport()
        let client = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        let recorder = ResumeTurnRecorder()
        let collector = Task {
            for await event in adapter.orderedEvents { await recorder.append(event) }
        }
        let resume = Task { try await adapter.threadResume(ThreadResumeParams(threadId: "thread")) }
        let request = try await resumeRequest(transport)
        started(transport, turn: "new")
        try await barrier(transport, recorder: recorder)
        try respond(transport, request: request, turns: #"[{"id":"old","status":"completed","items":[]},{"id":"stale-active","status":"inProgress","items":[]},{"id":"new","status":"completed","items":[]}]"#)
        _ = try await resume.value
        #expect(await client.activeTurnId(for: "thread") == "new")
        usage(transport, turn: "old")
        started(transport, turn: "stale-active")
        delta(transport, turn: "old", text: "stale")
        completed(transport, turn: "old")
        delta(transport, turn: "new", text: "answer")
        completed(transport, turn: "new")
        usage(transport, turn: "old")
        delta(transport, turn: "old", text: "stale after completion")
        completed(transport, turn: "old")
        try await barrier(transport, recorder: recorder)
        #expect(await recorder.normalized == [
            .turnStarted, .agentMessageDelta(itemId: "message", "answer"), .turnCompleted(nativeSessionId: "thread"),
        ])
        #expect(await client.activeTurnId(for: "thread") == nil)
        await adapter.close()
        await collector.value
    }

    private func resumeRequest(_ transport: MockTransport) async throws -> JSONValue {
        #expect(await waitUntil(events: transport.sent.changes) {
            await transport.sent.first { $0["method"]?.stringValue == "thread/resume" } != nil
        })
        return try #require(await transport.sent.first { $0["method"]?.stringValue == "thread/resume" })
    }

    private func respond(_ transport: MockTransport, request: JSONValue, turns: String) throws {
        let id = try jsonLine(#require(request["id"]))
        transport.receive("""
        {"jsonrpc":"2.0","id":\(id),"result":{"thread":{"id":"thread","status":{"type":"idle"},"turns":\(turns)}}}
        """)
    }

    private func usage(_ transport: MockTransport, turn: String) {
        transport.receive("""
        {"jsonrpc":"2.0","method":"thread/tokenUsage/updated","params":{"threadId":"thread","turnId":"\(turn)","tokenUsage":{"last":{"totalTokens":10},"modelContextWindow":200000}}}
        """)
    }

    private func started(_ transport: MockTransport, turn: String) {
        transport.receive("""
        {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread","turn":{"id":"\(turn)","status":"inProgress","items":[]}}}
        """)
    }

    private func delta(_ transport: MockTransport, turn: String, text: String) {
        transport.receive("""
        {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread","turnId":"\(turn)","itemId":"message","delta":"\(text)"}}
        """)
    }

    private func completed(_ transport: MockTransport, turn: String) {
        transport.receive("""
        {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread","turn":{"id":"\(turn)","status":"completed","items":[]}}}
        """)
    }

    private func barrier(_ transport: MockTransport, recorder: ResumeTurnRecorder) async throws {
        let expected = await recorder.barriers + 1
        transport.receive(#"{"jsonrpc":"2.0","method":"skills/changed","params":{}}"#)
        try #require(await waitUntil(events: recorder.changes) { await recorder.barriers == expected })
    }
}

private actor ResumeTurnRecorder {
    private(set) var normalized: [NormalizedChatEvent] = []
    private(set) var barriers = 0
    nonisolated let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (changes, continuation) = AsyncStream.makeStream() }

    func append(_ event: CodexStructuredEvent) {
        switch event {
        case .normalizedWithIdentity(_, _, let event), .normalized(let event): normalized.append(event)
        case .thread(.skillsChanged): barriers += 1
        case .thread: break
        }
        continuation.yield()
    }

    var usageCount: Int {
        normalized.filter { if case .turnUsage = $0 { true } else { false } }.count
    }
}
