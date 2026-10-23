import Foundation
import Testing
@testable import CodexAppServerKit

@Suite("Codex question policy and asynchronous answers")
struct CodexQuestionPolicyTests {
    @Test("新規・復元・リセットは有効な既存指示へ質問方針を一度だけ追記する")
    func preservesInstructionsAcrossLifecycle() async throws {
        let wire = QuestionPolicyTransport(configInstructions: "Keep the user's existing policy.")
        let client = CodexAppServerClient(
            transport: wire, additionalDeveloperInstructions: CodexQuestionPolicy.instructions
        )
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams(cwd: "/project"))
        _ = try await adapter.threadResume(ThreadResumeParams(threadId: "resumed", cwd: "/project"))
        await adapter.resetConversation()
        let messages = await wire.messages
        let starts = messages.filter { ["thread/start", "thread/resume"].contains($0["method"]?.stringValue ?? "") }
        #expect(starts.count == 3)
        for request in starts {
            #expect(request["params"]?["developerInstructions"]?.stringValue
                == "Keep the user's existing policy.\n\n" + CodexQuestionPolicy.instructions)
            #expect(request["params"]?["baseInstructions"] == nil)
        }
        let reads = messages.filter { $0["method"]?.stringValue == "config/read" }
        #expect(reads.count == 3)
        #expect(reads.allSatisfy { $0["params"]?["cwd"]?.stringValue == "/project" })
        await adapter.close()
    }

    @Test("明示した開発者指示を保ち、既に末尾にある方針を重複させない")
    func explicitInstructions() async throws {
        let wire = QuestionPolicyTransport(configInstructions: "Config instruction")
        let client = CodexAppServerClient(
            transport: wire, additionalDeveloperInstructions: CodexQuestionPolicy.instructions
        )
        await client.start()
        let existing = "Explicit instruction\n\n" + CodexQuestionPolicy.instructions
        _ = try await client.threadStart(ThreadStartParams(developerInstructions: existing))
        let messages = await wire.messages
        #expect(messages.count == 1)
        #expect(messages.first?["params"]?["developerInstructions"]?.stringValue == existing)
        await client.close()
    }

    @Test("設定取得が失敗したら既存指示を破棄して会話を開始しない")
    func configFailureDoesNotStartThread() async throws {
        let wire = QuestionPolicyTransport(failConfig: true)
        let client = CodexAppServerClient(
            transport: wire, additionalDeveloperInstructions: CodexQuestionPolicy.instructions
        )
        await client.start()
        await #expect(throws: JSONRPCClientError.self) {
            _ = try await client.threadStart(ThreadStartParams(cwd: "/project"))
        }
        #expect(await wire.messages.map { $0["method"]?.stringValue } == ["config/read"])
        await client.close()
    }

    @Test("非同期の回答は実行中ならsteer、完了後ならstartへ届ける")
    func routesAnswerToCurrentTurn() async throws {
        let wire = QuestionPolicyTransport()
        let client = CodexAppServerClient(transport: wire)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams())
        var events = adapter.threadEvents.makeAsyncIterator()
        try await wire.notify("turn/started", params: .object([
            "threadId": .string("thread-1"),
            "turn": .object(["id": .string("turn-1"), "status": .string("inProgress")]),
        ]))
        _ = await events.next()
        try await adapter.sendUserMessage("Question: continue?\nAnswer: yes", expectedThreadID: "thread-1")
        var messages = await wire.messages
        let steer = try #require(messages.first { $0["method"]?.stringValue == "turn/steer" })
        #expect(steer["params"]?["threadId"]?.stringValue == "thread-1")
        #expect(steer["params"]?["expectedTurnId"]?.stringValue == "turn-1")
        #expect(steer["params"]?["input"] == .array([.object([
            "type": .string("text"), "text": .string("Question: continue?\nAnswer: yes"),
        ])]))
        #expect(!messages.contains { $0["method"]?.stringValue == "turn/start" })
        try await wire.notify("turn/completed", params: .object([
            "threadId": .string("thread-1"),
            "turn": .object(["id": .string("turn-1"), "status": .string("completed")]),
        ]))
        _ = await events.next()
        try await adapter.sendUserMessage("Answer after completion", expectedThreadID: "thread-1")
        messages = await wire.messages
        #expect(messages.last?["method"]?.stringValue == "turn/start")
        #expect(messages.last?["params"]?["threadId"]?.stringValue == "thread-1")
        await adapter.close()
    }

    @Test("別会話への回答を送らず、steerの拒否をstartで再送しない")
    func rejectsWrongThreadAndDoesNotRetry() async throws {
        let wire = QuestionPolicyTransport(failSteer: true)
        let client = CodexAppServerClient(transport: wire)
        let adapter = CodexStructuredAgentClient(client: client)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams())
        await #expect(throws: CodexStructuredClientError.staleThreadOperation) {
            try await adapter.sendUserMessage("answer", expectedThreadID: "another-thread")
        }
        var events = adapter.threadEvents.makeAsyncIterator()
        try await wire.notify("turn/started", params: .object([
            "threadId": .string("thread-1"),
            "turn": .object(["id": .string("turn-1"), "status": .string("inProgress")]),
        ]))
        _ = await events.next()
        await #expect(throws: JSONRPCClientError.self) {
            try await adapter.sendUserMessage("answer", expectedThreadID: "thread-1")
        }
        let messages = await wire.messages
        #expect(messages.filter { $0["method"]?.stringValue == "turn/steer" }.count == 1)
        #expect(!messages.contains { $0["method"]?.stringValue == "turn/start" })
        await adapter.close()
    }

    @Test("steerが別ターンへの受理を返したら成功扱いにしない")
    func steerResponseIdentity() async throws {
        let wire = QuestionPolicyTransport(steerTurnID: "other-turn")
        let client = CodexAppServerClient(transport: wire)
        await client.start()
        await #expect(throws: CodexAppServerClientError.turnIDMismatch(requested: "turn-1", received: "other-turn")) {
            _ = try await client.turnSteer(TurnSteerParams(
                threadId: "thread-1", input: [.text("answer")], expectedTurnId: "turn-1"
            ))
        }
        await client.close()
    }
}

private actor QuestionPolicyTransport: AppServerTransport {
    nonisolated let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let configInstructions: String?
    private let failConfig: Bool
    private let failSteer: Bool
    private let steerTurnID: String
    private var threadCount = 0
    private(set) var messages: [JSONValue] = []

    init(configInstructions: String? = nil, failConfig: Bool = false,
         failSteer: Bool = false, steerTurnID: String = "turn-1") {
        self.configInstructions = configInstructions
        self.failConfig = failConfig
        self.failSteer = failSteer
        self.steerTurnID = steerTurnID
        (receivedLines, continuation) = AsyncStream.makeStream()
    }

    func send(_ data: Data) async throws {
        let message = try JSONDecoder().decode(JSONValue.self, from: data)
        messages.append(message)
        guard let id = message["id"], let method = message["method"]?.stringValue else { return }
        if method == "config/read" && failConfig || method == "turn/steer" && failSteer {
            try receive(.object(["id": id, "error": .object([
                "code": .number(-32000), "message": .string("rejected"),
            ])]))
            return
        }
        let result: JSONValue
        switch method {
        case "config/read":
            result = .object(["config": .object([
                "developer_instructions": configInstructions.map(JSONValue.string) ?? .null,
            ])])
        case "thread/start":
            threadCount += 1
            result = .object(["thread": .object(["id": .string("thread-\(threadCount)")])])
        case "thread/resume":
            result = .object(["thread": .object(["id": message["params"]?["threadId"] ?? .null])])
        case "turn/steer": result = .object(["turnId": .string(steerTurnID)])
        default: result = .object([:])
        }
        try receive(.object(["id": id, "result": result]))
    }

    func notify(_ method: String, params: JSONValue) throws {
        try receive(.object(["method": .string(method), "params": params]))
    }

    func close() async { continuation.finish() }

    private func receive(_ message: JSONValue) throws {
        continuation.yield(try JSONEncoder().encode(message))
    }
}
