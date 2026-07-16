import Foundation
import StructuredChatKit
import Testing
@testable import CursorAgentKit

final class MockOneShotProcessRunner: OneShotProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable, Sendable {
        var command: String
        var arguments: [String]
        var environment: [String: String]
        var workingDirectory: URL?
    }

    private let lock = NSLock()
    private var invocations: [Invocation] = []
    private var scriptedResults: [Result<OneShotProcessResult, Error>] = []

    func enqueueSuccess(lines: [String], exitCode: Int32 = 0, errorLines: [String] = []) {
        let outputLines = lines.map { Data($0.utf8) }
        let errorOutputLines = errorLines.map { Data($0.utf8) }
        lock.withLock {
            scriptedResults.append(.success(OneShotProcessResult(
                exitCode: exitCode,
                outputLines: outputLines,
                errorLines: errorOutputLines
            )))
        }
    }

    func enqueueFailure(_ error: Error) {
        lock.withLock {
            scriptedResults.append(.failure(error))
        }
    }

    func recordedInvocations() -> [Invocation] {
        lock.withLock { invocations }
    }

    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) async throws -> OneShotProcessResult {
        let invocation = Invocation(
            command: command,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        let result = lock.withLock {
            invocations.append(invocation)
            guard !scriptedResults.isEmpty else {
                return Result<OneShotProcessResult, Error>.success(
                    OneShotProcessResult(exitCode: 0, outputLines: [])
                )
            }
            return scriptedResults.removeFirst()
        }
        return try result.get()
    }
}

private func eventsDuringTurn(
    client: CursorChatClient,
    input: [ChatInput]
) async throws -> [NormalizedChatEvent] {
    try await client.turnStart(input)
    var events: [NormalizedChatEvent] = []
    for await event in client.events {
        events.append(event)
        if case .turnCompleted = event {
            break
        }
        if case .error = event {
            break
        }
    }
    return events
}

private func jsonLine(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

@Test func cursorStreamJSONParserMapsCoreEvents() throws {
    var parser = CursorStreamJSONParser()

    let initEvents = try parser.ingest(line: Data(jsonLine([
        "type": "system",
        "subtype": "init",
        "session_id": "sess-abc",
        "cwd": "/tmp",
        "model": "Composer",
    ]).utf8))
    #expect(initEvents.isEmpty)
    #expect(parser.nativeSessionId == "sess-abc")

    let thinkingEvents = try parser.ingest(line: Data(jsonLine([
        "type": "thinking",
        "subtype": "delta",
        "text": "planning",
        "session_id": "sess-abc",
    ]).utf8))
    #expect(thinkingEvents == [.reasoningDelta(itemId: "reasoning", "planning")])

    let assistantEvents = try parser.ingest(line: Data(jsonLine([
        "type": "assistant",
        "message": [
            "role": "assistant",
            "content": [["type": "text", "text": "hello"]],
        ],
        "session_id": "sess-abc",
    ]).utf8))
    #expect(assistantEvents == [.agentMessageDelta(itemId: "assistant-0", "hello")])

    let readStarted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "started",
        "call_id": "call-read-1",
        "tool_call": ["readToolCall": ["args": ["path": "README.md"]]],
        "session_id": "sess-abc",
    ]).utf8))
    // started 時点で出力空のまま行を描画する（completed で出力が埋まる）
    #expect(readStarted == [
        .commandExecution(itemId: "call-read-1", command: "Read README.md", outputDelta: ""),
    ])

    let readCompleted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "completed",
        "call_id": "call-read-1",
        "tool_call": ["readToolCall": ["result": ["success": ["content": "# Title"]]]],
        "session_id": "sess-abc",
    ]).utf8))
    #expect(readCompleted == [
        .commandExecution(itemId: "call-read-1", command: "Read README.md", outputDelta: "# Title"),
    ])

    let editStarted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "started",
        "call_id": "call-edit-1",
        "tool_call": [
            "editToolCall": [
                "args": [
                    "path": "Foo.swift",
                    "streamContent": "let x = 1",
                ],
            ],
        ],
        "session_id": "sess-abc",
    ]).utf8))
    // 編集系も started 時点で差分を描画する
    #expect(editStarted.count == 1)
    if case .fileChange(let itemId, let changes) = editStarted[0] {
        #expect(itemId == "call-edit-1")
        #expect(changes.first?.path == "Foo.swift")
        #expect(changes.first?.diff.contains("+let x = 1") == true)
    } else {
        Issue.record("Expected fileChange event at started")
    }

    let editCompleted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "completed",
        "call_id": "call-edit-1",
        "tool_call": ["editToolCall": ["result": ["success": [:]]]],
        "session_id": "sess-abc",
    ]).utf8))
    #expect(editCompleted.count == 1)
    if case .fileChange(let itemId, let changes) = editCompleted[0] {
        #expect(itemId == "call-edit-1")
        #expect(changes.count == 1)
        #expect(changes[0].path == "Foo.swift")
        #expect(changes[0].diff.contains("+let x = 1"))
    } else {
        Issue.record("Expected fileChange event")
    }

    let resultEvents = try parser.ingest(line: Data(jsonLine([
        "type": "result",
        "subtype": "success",
        "session_id": "sess-abc",
        "result": "done",
    ]).utf8))
    #expect(resultEvents == [.turnCompleted(nativeSessionId: "sess-abc")])
}

@Test func cursorStreamRendersToolCallsInChronologicalOrder() throws {
    var parser = CursorStreamJSONParser()

    // 前置きテキスト（ツール呼び出し前）
    let intro = try parser.ingest(line: Data(jsonLine([
        "type": "assistant",
        "message": ["role": "assistant", "content": [["type": "text", "text": "確認します"]]],
    ]).utf8))
    #expect(intro == [.agentMessageDelta(itemId: "assistant-0", "確認します")])

    // shell ツールは started 時点で実コマンドを表示して描画する（"shellToolCall" ではない）
    let shellStarted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "started",
        "call_id": "c-shell",
        "tool_call": ["shellToolCall": ["args": ["command": "ls -la"]]],
    ]).utf8))
    #expect(shellStarted == [
        .commandExecution(itemId: "c-shell", command: "ls -la", outputDelta: ""),
    ])

    let shellCompleted = try parser.ingest(line: Data(jsonLine([
        "type": "tool_call",
        "subtype": "completed",
        "call_id": "c-shell",
        "tool_call": ["shellToolCall": ["result": ["success": ["output": "total 0"]]]],
    ]).utf8))
    #expect(shellCompleted == [
        .commandExecution(itemId: "c-shell", command: "ls -la", outputDelta: "total 0"),
    ])

    // ツール後の最終回答は前置きと別 id になり、ツール行の後ろに独立したバブルとして並ぶ
    let summary = try parser.ingest(line: Data(jsonLine([
        "type": "assistant",
        "message": ["role": "assistant", "content": [["type": "text", "text": "完了しました"]]],
    ]).utf8))
    let summaryEvent = try #require(summary.first)
    guard case .agentMessageDelta(let summaryId, let summaryText) = summaryEvent else {
        Issue.record("Expected agentMessageDelta for summary")
        return
    }
    #expect(summaryText == "完了しました")
    #expect(summaryId != "assistant-0")
}

@Test func cursorChatClientTurnStartMapsStreamJSONToNormalizedEvents() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "system",
            "subtype": "init",
            "session_id": "sess-1",
            "cwd": "/tmp",
            "model": "Composer",
        ]),
        jsonLine([
            "type": "thinking",
            "subtype": "delta",
            "text": "thinking",
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [["type": "text", "text": "answer"]],
            ],
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "tool_call",
            "subtype": "started",
            "call_id": "call-read-1",
            "tool_call": ["readToolCall": ["args": ["path": "README.md"]]],
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "tool_call",
            "subtype": "completed",
            "call_id": "call-read-1",
            "tool_call": ["readToolCall": ["result": ["success": ["content": "file body"]]]],
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "tool_call",
            "subtype": "started",
            "call_id": "call-edit-1",
            "tool_call": [
                "editToolCall": [
                    "args": [
                        "path": "Bar.swift",
                        "streamContent": "print(\"hi\")",
                    ],
                ],
            ],
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "tool_call",
            "subtype": "completed",
            "call_id": "call-edit-1",
            "tool_call": ["editToolCall": ["result": ["success": [:]]]],
            "session_id": "sess-1",
        ]),
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "sess-1",
            "result": "done",
        ]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()

    let events = try await eventsDuringTurn(client: client, input: [.text("hello")])
    #expect(events.contains(.turnStarted))
    #expect(events.contains(.reasoningDelta(itemId: "reasoning", "thinking")))
    #expect(events.contains(.agentMessageDelta(itemId: "assistant-0", "answer")))
    #expect(events.contains(
        .commandExecution(itemId: "call-read-1", command: "Read README.md", outputDelta: "file body")
    ))

    let fileChange = events.first {
        if case .fileChange(let itemId, _) = $0 { return itemId == "call-edit-1" }
        return false
    }
    #expect(fileChange != nil)
    if case .fileChange(_, let changes) = fileChange {
        #expect(changes.first?.path == "Bar.swift")
        #expect(changes.first?.diff.contains("+print(\"hi\")") == true)
    }

    #expect(events.contains(.turnCompleted(nativeSessionId: "sess-1")))

    let invocation = runner.recordedInvocations().first
    #expect(invocation?.command == "cursor-agent")
    #expect(invocation?.arguments == ["-p", "hello", "--output-format", "stream-json", "-f"])
    #expect(invocation?.arguments.contains("--resume") == false)

    await client.close()
}

@Test func cursorChatClientDegradesImagesWithSingleWarningAndTextOnlyPrompt() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "sess-image",
            "result": "done",
        ]),
    ])
    let client = CursorChatClient(command: "cursor-agent", runner: runner)

    let events = try await eventsDuringTurn(client: client, input: [
        .text("describe"),
        .image(data: Data([1, 2, 3]), mediaType: "image/png"),
        .image(data: Data([4, 5, 6]), mediaType: "image/jpeg"),
    ])

    let warnings = events.compactMap { event -> String? in
        if case .warning(let message) = event { return message }
        return nil
    }
    #expect(warnings == ["画像添付は Claude のみ対応"])
    let invocation = try #require(runner.recordedInvocations().first)
    #expect(invocation.arguments.firstIndex(of: "-p").map { invocation.arguments[$0 + 1] } == "describe")

    await client.close()
}

@Test func cursorChatClientWithoutPreApprovalDoesNotPassForce() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "sess-1",
        ]),
    ])

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("hello")])

    let invocation = runner.recordedInvocations().first
    #expect(invocation?.arguments == ["-p", "hello", "--output-format", "stream-json"])
    #expect(invocation?.arguments.contains("-f") == false)

    await client.close()
}

@Test func cursorChatClientDeniedByPreApprovalDoesNotRunProcess() async throws {
    let runner = MockOneShotProcessRunner()
    let client = CursorChatClient(
        command: "cursor-agent",
        preApprovalPolicy: { request in
            #expect(request.summary == "hello")
            return .deny("not approved")
        },
        runner: runner
    )
    await client.start()

    let events = try await eventsDuringTurn(client: client, input: [.text("hello")])

    #expect(runner.recordedInvocations().isEmpty)
    #expect(events.contains(.error(message: "Cursor turn blocked by approval policy: not approved")))

    await client.close()
}

@Test func cursorChatClientSecondTurnAddsResumeWithStoredSessionId() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "system",
            "subtype": "init",
            "session_id": "sess-first",
        ]),
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "sess-first",
        ]),
    ])
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "system",
            "subtype": "init",
            "session_id": "sess-first",
        ]),
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "sess-first",
        ]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("first")])
    _ = try await eventsDuringTurn(client: client, input: [.text("second")])

    let invocations = runner.recordedInvocations()
    #expect(invocations.count == 2)
    #expect(invocations[0].arguments == ["-p", "first", "--output-format", "stream-json", "-f"])
    #expect(invocations[1].arguments == [
        "-p", "second", "--output-format", "stream-json", "-f", "--resume", "sess-first",
    ])

    await client.close()
}

@Test func cursorTurnStartIncludesModelAndModeWhenConfigured() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"]),
    ])

    let client = CursorChatClient(
        command: "cursor-agent",
        model: "gpt-5.2",
        mode: "plan",
        preApprovalPolicy: { _ in .approve },
        runner: runner
    )
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("hi")])

    let invocation = runner.recordedInvocations().first
    #expect(invocation?.arguments == [
        "-p", "hi", "--output-format", "stream-json", "--model", "gpt-5.2", "--mode", "plan", "-f",
    ])

    await client.close()
}

@Test func cursorTurnStartOmitsModelAndModeWhenUnset() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("hi")])

    let invocation = runner.recordedInvocations().first
    #expect(invocation?.arguments == ["-p", "hi", "--output-format", "stream-json", "-f"])
    #expect(invocation?.arguments.contains("--model") == false)
    #expect(invocation?.arguments.contains("--mode") == false)

    await client.close()
}

@Test func cursorUpdateSettingsReflectedOnNextTurn() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "system", "subtype": "init", "session_id": "sess-1"]),
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"]),
    ])
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("first")])
    await client.updateSettings(model: "auto", mode: nil)
    _ = try await eventsDuringTurn(client: client, input: [.text("second")])

    let invocations = runner.recordedInvocations()
    #expect(invocations.count == 2)
    #expect(invocations[0].arguments.contains("--model") == false)
    #expect(invocations[1].arguments.contains("--model"))
    #expect(invocations[1].arguments.contains("auto"))
    // auto-approve (-f) must survive the settings update
    #expect(invocations[1].arguments.contains("-f"))

    await client.close()
}

@Test func cursorChatClientResumeUsesProvidedSessionId() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine([
            "type": "system",
            "subtype": "init",
            "session_id": "restored-session",
        ]),
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "restored-session",
        ]),
    ])

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    try await client.resume(sessionRef: "restored-session")
    _ = try await eventsDuringTurn(client: client, input: [.text("continue")])

    let invocations = runner.recordedInvocations()
    #expect(invocations.count == 1)
    #expect(invocations[0].arguments.contains("--resume"))
    #expect(invocations[0].arguments.contains("restored-session"))

    await client.close()
}

@Test func cursorChatClientNonZeroExitEmitsError() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [], exitCode: 2)

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    let events = try await eventsDuringTurn(client: client, input: [.text("fail")])
    #expect(events.contains(.error(message: "cursor-agent exited with code 2")))
    #expect(!events.contains(where: { event in
        if case .turnCompleted = event { return true }
        return false
    }))

    await client.close()
}

@Test func cursorChatClientNonZeroExitIncludesStderrInError() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [], exitCode: 42, errorLines: ["permission denied", "try --force"])

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    let events = try await eventsDuringTurn(client: client, input: [.text("fail with stderr")])
    #expect(events.contains(.error(message: "cursor-agent exited with code 42: permission denied\ntry --force")))
    #expect(!events.contains(where: { event in
        if case .turnCompleted = event { return true }
        return false
    }))

    await client.close()
}

@Test func cursorChatClientInvalidJSONEmitsParseError() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        "not-json",
        jsonLine([
            "type": "result",
            "subtype": "success",
            "session_id": "must-not-complete",
        ]),
    ])

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    let events = try await eventsDuringTurn(client: client, input: [.text("bad")])
    #expect(events.contains(where: { event in
        if case .error(let message) = event {
            return message.contains("Failed to parse cursor stream-json")
        }
        return false
    }))
    #expect(!events.contains(where: { event in
        if case .turnCompleted = event { return true }
        return false
    }))

    await client.close()
}

// task-8 仕様変更（audit S1）: exit0 の stderr は stdout を破棄しない。以前はこのテストが
// 「exit0 + stderr → .error に昇格し turnCompleted を出さない」現行挙動を仕様固定していたが、
// stderr 1 バイトでターンぶんの stdout を全破棄するのは過剰であり、cursor-agent は成功しつつ
// stderr へ診断を書くため、致命扱いは exit≠0 限定へ変更した（decision-log 記録）。
// 新挙動: stderr は非致命の .warning として観測でき、stdout（result/success）は保持される。
@Test func cursorChatClientStderrWithZeroExitEmitsWarningAndKeepsStdout() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(
        lines: [
            jsonLine([
                "type": "result",
                "subtype": "success",
                "session_id": "sess-with-stderr",
            ]),
        ],
        errorLines: ["cursor-agent diagnostic on stderr"]
    )

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    let events = try await eventsDuringTurn(client: client, input: [.text("stderr")])
    // stderr は非致命の warning として観測できる（.error への昇格はしない）。
    #expect(events.contains(.warning(message: "cursor-agent wrote to stderr: cursor-agent diagnostic on stderr")))
    #expect(!events.contains(where: { event in
        if case .error = event { return true }
        return false
    }))
    // stdout（result/success）は破棄されず turnCompleted に到達する。
    #expect(events.contains(.turnCompleted(nativeSessionId: "sess-with-stderr")))

    await client.close()
}

// task-9 rework (Codex stage2 HIGH): updateSettings は置換セマンティクス。
// nil で --model / --mode をクリアして既定（フラグ無し）へ戻せること。
@Test func cursorUpdateSettingsCanClearModelAndMode() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"])])
    runner.enqueueSuccess(lines: [jsonLine(["type": "result", "subtype": "success", "session_id": "sess-1"])])

    let client = CursorChatClient(
        command: "cursor-agent",
        model: "gpt-5.2",
        mode: "plan",
        preApprovalPolicy: { _ in .approve },
        runner: runner
    )
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("first")])
    await client.updateSettings(model: nil, mode: nil)
    _ = try await eventsDuringTurn(client: client, input: [.text("second")])

    let secondArgs = runner.recordedInvocations()[1].arguments
    #expect(!secondArgs.contains("--model"))
    #expect(!secondArgs.contains("--mode"))
    #expect(secondArgs.contains("-f"))
    await client.close()
}

// task-8 白箱: resetConversation() は resumeSessionId をクリアし、次の one-shot spawn から
// --resume が外れる（新規会話へ切り替わる）。既存の「2ターン目は --resume が付く」テストとの対比。
@Test func cursorResetConversationClearsResumeSoNextTurnHasNoResume() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "system", "subtype": "init", "session_id": "sess-first"]),
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-first"]),
    ])
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-second"]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("first")])

    await client.resetConversation()

    _ = try await eventsDuringTurn(client: client, input: [.text("second")])

    let invocations = runner.recordedInvocations()
    #expect(invocations.count == 2)
    #expect(!invocations[1].arguments.contains("--resume"))
    #expect(!invocations[1].arguments.contains("sess-first"))
    #expect(invocations[1].arguments == ["-p", "second", "--output-format", "stream-json", "-f"])

    await client.close()
}

// task-5 白箱: interrupt() の世代ガードが「旧 run が中断直後に *正常完了* した」競合窓でも
// 旧ターンのイベントを漏らさないことを検証する。1回目の run はゲート解除まで待機し、
// キャンセルを無視して正常な result を返す（＝中断とほぼ同時の正常完了を模擬）。
private final class GatedFirstRunner: OneShotProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var firstEntered = false
    private var released = false
    private let firstLines: [Data]

    init(firstLines: [String]) {
        self.firstLines = firstLines.map { Data($0.utf8) }
    }

    var calls: Int { lock.withLock { callCount } }

    func release() { lock.withLock { released = true } }

    func waitForFirstEntered(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ firstEntered }) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return lock.withLock { firstEntered }
    }

    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) async throws -> OneShotProcessResult {
        let call = lock.withLock { () -> Int in
            callCount += 1
            return callCount
        }
        if call == 1 {
            lock.withLock { firstEntered = true }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if lock.withLock({ released }) { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            // 意図的にキャンセルを無視して正常完了する（中断直後の正常完了レースの再現）。
            return OneShotProcessResult(exitCode: 0, outputLines: firstLines)
        }
        return OneShotProcessResult(exitCode: 0, outputLines: [])
    }
}

private actor CollectedEvents {
    private var events: [NormalizedChatEvent] = []
    func append(_ event: NormalizedChatEvent) { events.append(event) }
    func snapshot() -> [NormalizedChatEvent] { events }
}

@Test func cursorInterruptSuppressesNormallyCompletedStaleTurn() async throws {
    let firstResult = jsonLine(["type": "result", "subtype": "success", "session_id": "sess-first"])
    let runner = GatedFirstRunner(firstLines: [firstResult])
    let client = CursorChatClient(command: "cursor-agent", runner: runner)

    let log = CollectedEvents()
    let collector = Task {
        for await event in client.events { await log.append(event) }
    }

    let firstTurn = Task { try? await client.turnStart([.text("first")]) }
    try #require(await runner.waitForFirstEntered(timeout: 5.0), "first run never started")

    // 中断 → その直後に旧 run を正常完了させる。世代ガードで旧ターンは無効化済みのはず。
    try await client.interrupt()
    runner.release()
    _ = await firstTurn.value

    await client.close()
    _ = await collector.value

    let events = await log.snapshot()

    // 中断された旧ターンが正常完了しても、その turnCompleted / error は漏れない。
    #expect(!events.contains { if case .turnCompleted = $0 { true } else { false } },
            "中断後に正常完了した旧ターンの turnCompleted が漏れた")
    #expect(!events.contains { if case .error = $0 { true } else { false } })
    let interruptedCount = events.filter { if case .turnInterrupted = $0 { true } else { false } }.count
    #expect(interruptedCount == 1)
}

// task-5 白箱: interrupt() は獲得済みの resumeSessionId を破棄せず、次ターンの --resume に使う。
@Test func cursorInterruptPreservesResumeSessionIdForNextTurn() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "system", "subtype": "init", "session_id": "sess-keep"]),
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-keep"]),
    ])
    runner.enqueueSuccess(lines: [
        jsonLine(["type": "result", "subtype": "success", "session_id": "sess-keep"]),
    ])

    let client = CursorChatClient(command: "cursor-agent", preApprovalPolicy: { _ in .approve }, runner: runner)
    await client.start()
    _ = try await eventsDuringTurn(client: client, input: [.text("first")])
    try await client.interrupt()
    try await client.turnStart([.text("second")])

    let invocations = runner.recordedInvocations()
    #expect(invocations.count == 2)
    #expect(invocations[1].arguments.contains("--resume"))
    #expect(invocations[1].arguments.contains("sess-keep"))

    await client.close()
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
