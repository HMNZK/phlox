import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

@Test func startBuildsLongLivedStreamJsonClaudeCommandWithoutUnconditionalBypass() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let phloxSessionID = "11111111-1111-4111-8111-111111111111"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": phloxSessionID],
        transportFactory: recorder.makeTransport
    )

    await client.start()

    let start = recorder.starts.first
    #expect(start?.command == "claude")
    #expect(start?.arguments == [
        "-p",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--session-id", phloxSessionID,
    ])
    #expect(start?.arguments.contains("--permission-mode") == false)
    #expect(start?.arguments.contains("acceptEdits") == false)
    #expect(start?.arguments.contains("--allowedTools") == false)
    #expect(start?.arguments.contains("--resume") == false)
    #expect(mock.didStart)
    await client.close()
}

@Test func doesNotAppendSystemPromptEvenWhenOrchestrationGuideEnvIsSet() async throws {
    // ADR 0035: オーケストレーションガイドの自動注入は全種別で廃止。
    // ClaudeChatClient は env に PHLOX_ORCHESTRATION_GUIDE があっても
    // --append-system-prompt を付けない（クライアント層の負の回帰ガード）。
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(
        environment: [
            "PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111",
            "PHLOX_ORCHESTRATION_GUIDE": "SHOULD-NOT-APPEAR",
        ],
        transportFactory: recorder.makeTransport
    )

    await client.start()

    let arguments = recorder.starts.first?.arguments ?? []
    #expect(!arguments.contains("--append-system-prompt"))
    #expect(!arguments.contains("SHOULD-NOT-APPEAR"))
    await client.close()
}

@Test func startUsesExplicitPhloxSessionIDOverEnvironment() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let injectedSessionID = "22222222-2222-4222-8222-222222222222"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "33333333-3333-4333-8333-333333333333"],
        phloxSessionID: injectedSessionID,
        transportFactory: recorder.makeTransport
    )

    await client.start()

    let arguments = recorder.starts.first?.arguments ?? []
    #expect(arguments.contains("--session-id"))
    #expect(arguments.contains(injectedSessionID))
    #expect(!arguments.contains("33333333-3333-4333-8333-333333333333"))
    #expect(!arguments.contains("--resume"))
    await client.close()
}

@Test func resumeBuildsCommandWithResumeSessionReference() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111"],
        transportFactory: recorder.makeTransport
    )

    try await client.resume(sessionRef: "session-123")

    let arguments = recorder.starts.first?.arguments ?? []
    #expect(arguments.contains("--resume"))
    #expect(arguments.contains("session-123"))
    #expect(!arguments.contains("--session-id"))
    #expect(recorder.starts.count == 1)
    #expect(mock.didStart)
    await client.close()
}

@Test func startDoesNotSpawnTwiceWhenAlreadyStarted() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    await client.start()

    #expect(recorder.starts.count == 1)
    #expect(await iterator.next() == .warning(message: "Claude chat client is already started"))
    await client.close()
}

@Test func turnStartSendsUserTurnAsOneStreamJsonLine() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("hello"), .text("world")])

    #expect(await iterator.next() == .turnStarted)
    let sent = mock.sentStrings()
    #expect(sent.count == 1)
    #expect(sent.first?.hasSuffix("\n") == true)

    let payload = try #require(sent.first?.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    #expect(object["type"] as? String == "user")
    let message = try #require(object["message"] as? [String: Any])
    #expect(message["role"] as? String == "user")
    let content = try #require(message["content"] as? [[String: Any]])
    #expect(content.count == 2)
    #expect(content[0]["type"] as? String == "text")
    #expect(content[0]["text"] as? String == "hello")
    #expect(content[1]["type"] as? String == "text")
    #expect(content[1]["text"] as? String == "world")
    await client.close()
}

@Test func turnStartDeniedByPreApprovalDoesNotSendUserTurn() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(
        preApprovalPolicy: { request in
            #expect(request.summary == "hello")
            return .deny("not approved")
        },
        transportFactory: recorder.makeTransport
    )
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("hello")])

    #expect(mock.sentStrings().isEmpty)
    #expect(await iterator.next() == .error(message: "Claude turn blocked by approval policy: not approved"))
    await client.close()
}

@Test func turnStartApprovedByPreApprovalSendsUserTurn() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(
        preApprovalPolicy: { request in
            #expect(request.summary == "hello")
            return .approve
        },
        transportFactory: recorder.makeTransport
    )
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("hello")])

    let start = try #require(recorder.starts.first)
    #expect(start.arguments.contains("--permission-mode"))
    #expect(start.arguments.contains("acceptEdits"))
    #expect(start.arguments.contains("--allowedTools"))
    #expect(start.arguments.contains(ClaudeChatClient.defaultAllowedTools.joined(separator: ",")))
    #expect(await iterator.next() == .turnStarted)
    #expect(mock.sentStrings().count == 1)
    await client.close()
}

@Test func assistantTextAndThinkingBecomeNormalizedDeltas() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"text","text":"hello"},{"type":"thinking","thinking":"plan"}]}}
    """)

    #expect(await iterator.next() == .agentMessageDelta(itemId: "msg-1:text", "hello"))
    #expect(await iterator.next() == .reasoningDelta(itemId: "msg-1:thinking", "plan"))
    await client.close()
}

@Test func thinkingThenTextInSameMessageUseDistinctItemIds() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"thinking","thinking":"plan"},{"type":"text","text":"hello"}]}}
    """)

    let reasoning = await iterator.next()
    let message = await iterator.next()
    #expect(reasoning == .reasoningDelta(itemId: "msg-1:thinking", "plan"))
    #expect(message == .agentMessageDelta(itemId: "msg-1:text", "hello"))
    if case .reasoningDelta(let reasoningId, _) = reasoning,
       case .agentMessageDelta(let messageId, _) = message {
        #expect(reasoningId != messageId)
    }
    await client.close()
}

@Test func toolUseEventsBecomeCommandExecutionAndFileChangeEvents() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-read","name":"Read","input":{"file_path":"Sources/App.swift"}},{"type":"tool_use","id":"tool-edit","name":"Edit","input":{"file_path":"Sources/App.swift","old_string":"let old = true\\n","new_string":"let old = false\\n"}}]}}
    """)

    #expect(await iterator.next() == .commandExecution(itemId: "tool-read", command: "Read Sources/App.swift", outputDelta: ""))
    let expectedDiff = """
    --- Sources/App.swift
    +++ Sources/App.swift
    @@
    -let old = true
    +let old = false

    """
    #expect(await iterator.next() == .fileChange(itemId: "tool-edit", [
        FilePatchChange(path: "Sources/App.swift", diff: expectedDiff, kind: "edit"),
    ]))
    await client.close()
}

@Test func editDiffPreservesTrailingNewlineDeletion() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-edit","name":"Edit","input":{"file_path":"Sources/App.swift","old_string":"let value = 1\\n","new_string":"let value = 1"}}]}}
    """)

    let expectedDiff = """
    --- Sources/App.swift
    +++ Sources/App.swift
    @@
    -let value = 1
    +let value = 1
    \\ No newline at end of file

    """
    #expect(await iterator.next() == .fileChange(itemId: "tool-edit", [
        FilePatchChange(path: "Sources/App.swift", diff: expectedDiff, kind: "edit"),
    ]))
    await client.close()
}

@Test func writeDiffPreservesMissingTrailingNewline() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-write","name":"Write","input":{"file_path":"Sources/New.swift","content":"let value = 1"}}]}}
    """)

    let expectedDiff = """
    --- /dev/null
    +++ Sources/New.swift
    @@
    +let value = 1
    \\ No newline at end of file

    """
    #expect(await iterator.next() == .fileChange(itemId: "tool-write", [
        FilePatchChange(path: "Sources/New.swift", diff: expectedDiff, kind: "write"),
    ]))
    await client.close()
}

@Test func toolResultIsJoinedToMatchingCommandExecutionItem() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"assistant","message":{"id":"msg-1","content":[{"type":"tool_use","id":"tool-read","name":"Read","input":{"file_path":"README.md"}}]}}
    """)
    mock.receive("""
    {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool-read","content":"file body"}]}}
    """)

    #expect(await iterator.next() == .commandExecution(itemId: "tool-read", command: "Read README.md", outputDelta: ""))
    #expect(await iterator.next() == .commandExecution(itemId: "tool-read", command: nil, outputDelta: "file body"))
    await client.close()
}

@Test func sessionIdFromInitAndResultCompletesTurn() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"system","subtype":"init","session_id":"session-abc"}
    """)
    mock.receive("""
    {"type":"result","subtype":"success","session_id":"session-abc","is_error":false}
    """)

    #expect(await iterator.next() == .turnCompleted(nativeSessionId: "session-abc"))
    await client.close()
}

@Test func errorResultWithoutMessageIncludesSubtype() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"result","subtype":"error_max_turns","is_error":true}
    """)

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message != "Claude reported an error")
        #expect(message.contains("error_max_turns"))
    } else {
        Issue.record("Expected error event for error result without message, got \(String(describing: event))")
    }
    await client.close()
}

@Test func errorResultWithNumericApiStatusDoesNotCrash() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"result","subtype":"error_during_execution","is_error":true,"api_error_status":503}
    """)

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("error_during_execution"))
        #expect(message.contains("503"))
    } else {
        Issue.record("Expected error event for numeric API status result, got \(String(describing: event))")
    }
    await client.close()
}

@Test func errorResultWithNullApiErrorTypeDoesNotCrash() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"result","subtype":"error_during_execution","is_error":true,"api_error_type":null}
    """)

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("error_during_execution"))
        #expect(message.contains("api_error_type"))
        #expect(message.contains("null"))
    } else {
        Issue.record("Expected error event for null API error type result, got \(String(describing: event))")
    }
    await client.close()
}

@Test func successResultDoesNotEmitError() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"result","subtype":"success","is_error":false,"result":"done"}
    """)

    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

@Test func unknownTopLevelEventEmitsWarningBeforeContinuing() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"control_request","request_id":"approval-1"}
    """)
    mock.receive("""
    {"type":"result","subtype":"success","is_error":false}
    """)

    let event = await iterator.next()
    if case .warning(let message) = event {
        #expect(message.contains("control_request"))
    } else {
        Issue.record("Expected warning event for unknown top-level event, got \(String(describing: event))")
    }
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

@Test func invalidJsonAndErrorResultsBecomeErrorEvents() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("{not-json")
    mock.receive("""
    {"type":"result","subtype":"error","is_error":true,"message":"failed"}
    """)

    #expect(await iterator.next() == .error(message: "Failed to parse Claude stream-json line"))
    #expect(await iterator.next() == .error(message: "failed"))
    await client.close()
}

@Test func stdoutEOFBeforeResultEmitsErrorToEndCurrentTurn() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("run")])
    #expect(await iterator.next() == .turnStarted)

    await mock.close()

    #expect(await iterator.next() == .error(message: "Claude process ended before completing the current turn"))
    await client.close()
}

@Test func stdoutEOFBeforeResultIncludesStderrTailWhenAvailable() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("run")])
    #expect(await iterator.next() == .turnStarted)

    mock.stderrTailText = "boom from stderr"
    await mock.close()

    let event = await iterator.next()
    if case .error(let message) = event {
        #expect(message.contains("Claude process ended before completing the current turn"))
        #expect(message.contains("boom from stderr"))
    } else {
        Issue.record("Expected error event with stderr tail, got \(String(describing: event))")
    }
    await client.close()
}

@Test func staleStreamEndWaitingForStderrTailDoesNotClearResumedTransport() async throws {
    let recorder = FreshTransportRecorder()
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("old")])
    #expect(await iterator.next() == .turnStarted)

    let stderrGate = recorder.transports[0].blockStderrTail()
    await recorder.transports[0].close()
    await stderrGate.waitUntilWaiting()

    try await client.resume(sessionRef: "new-session")
    let resumedTransport = try #require(recorder.transports.last)

    await stderrGate.release()
    try await Task.sleep(for: .milliseconds(50))

    try await client.turnStart([.text("new")])
    #expect(await iterator.next() == .turnStarted)

    let arguments = recorder.starts.last?.arguments ?? []
    #expect(arguments.contains("--resume"))
    #expect(arguments.contains("new-session"))
    #expect(resumedTransport.sentStrings().count == 1)
    await client.close()
}

@Test func interruptSendsSIGINTWithoutClosingTransport() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)

    try await client.interrupt()

    #expect(mock.didInterrupt)
    #expect(!mock.didClose)
    #expect(await iterator.next() == .turnInterrupted(nativeSessionId: nil))

    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)
    #expect(mock.sentStrings().count == 2)
    await client.close()
}

@Test func startIncludesModelWhenConfigured() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let phloxSessionID = "55555555-5555-4555-8555-555555555555"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": phloxSessionID],
        model: "opus",
        transportFactory: recorder.makeTransport
    )

    await client.start()

    let arguments = recorder.starts.first?.arguments ?? []
    #expect(arguments.contains("--model"))
    #expect(arguments.contains("opus"))
    // No policy and no explicit permission override -> no permission-mode flag.
    #expect(arguments.contains("--permission-mode") == false)
    await client.close()
}

@Test func startUsesExplicitPermissionModeOverride() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111"],
        permissionMode: "plan",
        model: "sonnet",
        transportFactory: recorder.makeTransport
    )

    await client.start()

    let arguments = recorder.starts.first?.arguments ?? []
    #expect(arguments.contains("--permission-mode"))
    #expect(arguments.contains("plan"))
    #expect(arguments.contains("--model"))
    #expect(arguments.contains("sonnet"))
    #expect(!arguments.contains("acceptEdits"))
    await client.close()
}

@Test func updateSettingsBeforeFirstCompletedTurnRespawnsWithSessionId() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "99999999-9999-4999-8999-999999999999"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions")
    try await client.turnStart([.text("hello")])

    #expect(await iterator.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    let arguments = recorder.starts[1].arguments
    #expect(arguments.contains("--session-id"))
    #expect(arguments.contains(sid))
    #expect(!arguments.contains("--resume"))
    #expect(recorder.transports[1].sentStrings().count == 1)
    await client.close()
}

@Test func updateSettingsTriggersResumeRespawnWithNewModel() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "44444444-4444-4444-8444-444444444444"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)

    // Complete the first turn so the client is idle before applying settings.
    recorder.transports[0].receive("""
    {"type":"result","subtype":"success","session_id":"\(sid)","is_error":false}
    """)
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: sid))

    await client.updateSettings(model: "sonnet", permissionMode: nil)
    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 2)
    let secondArgs = recorder.starts[1].arguments
    #expect(secondArgs.contains("--model"))
    #expect(secondArgs.contains("sonnet"))
    #expect(secondArgs.contains("--resume"))
    #expect(secondArgs.contains(sid))
    #expect(!secondArgs.contains("--session-id"))
    // The respawned turn still delivers the user message.
    #expect(recorder.transports[1].sentStrings().count == 1)
    await client.close()
}

@Test func resumeNoConversationFailureSelfHealsWithSessionIdAndReplaysRawLine() async throws {
    let recorder = FreshTransportRecorder()
    let ref = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    try await client.resume(sessionRef: ref)
    var iterator = client.events.makeAsyncIterator()

    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)
    let originalLine = try #require(recorder.transports[0].sentStrings().first)

    recorder.transports[0].stderrTailText = "No conversation found with session ID: \(ref)"
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"error_during_execution","is_error":true,"permission_denials":[]}"#
    )
    await recorder.transports[0].close()

    try await waitUntil {
        recorder.starts.count == 2 && recorder.transports[1].sentStrings() == [originalLine]
    }

    let arguments = recorder.starts[1].arguments
    #expect(arguments.contains("--session-id"))
    #expect(arguments.contains(ref))
    #expect(!arguments.contains("--resume"))

    recorder.transports[1].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(ref)","is_error":false}"#
    )
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: ref))
    await client.close()
}

@Test func updateSettingsDoesNotRespawnWhileTurnInFlight() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "66666666-6666-4666-8666-666666666666"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("first")])
    #expect(await iterator.next() == .turnStarted)

    // The first turn is still in-flight (no result received). A settings update
    // must not respawn mid-turn.
    await client.updateSettings(model: "sonnet", permissionMode: nil)
    try await client.turnStart([.text("second")])
    #expect(await iterator.next() == .turnStarted)

    #expect(recorder.starts.count == 1)
    await client.close()
}

// task-8 白箱: resetConversation() は現在の transport を閉じ、`--resume`/`--session-id` を付けない
// 新規 spawn（.none）へ切り替える。start() 時の --session-id spawn（旧会話）との対比。
@Test func claudeResetConversationRespawnsFreshTransportWithoutResume() async throws {
    let recorder = FreshTransportRecorder()
    let phloxSessionID = "11111111-1111-4111-8111-111111111111"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": phloxSessionID],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    #expect(recorder.starts.count == 1)
    #expect(recorder.starts[0].arguments.contains("--session-id"))

    await client.resetConversation()

    #expect(recorder.starts.count == 2)
    let resetStart = recorder.starts[1]
    #expect(!resetStart.arguments.contains("--resume"))
    #expect(!resetStart.arguments.contains("--session-id"))
    #expect(!resetStart.arguments.contains(phloxSessionID))
    #expect(resetStart.arguments == [
        "-p",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
    ])

    // 旧 transport は閉じ、新しい transport が起動している（再作成）。
    #expect(recorder.transports.count == 2)
    #expect(recorder.transports[0].didClose)
    #expect(recorder.transports[1].didStart)

    await client.close()
}

private struct TransportStart: Sendable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
}

private final class TransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let transport: MockTransport
    private var recordedStarts: [TransportStart] = []

    init(_ transport: MockTransport) {
        self.transport = transport
    }

    var starts: [TransportStart] {
        lock.withLock { recordedStarts }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        lock.withLock {
            recordedStarts.append(TransportStart(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            ))
        }
        return transport
    }
}

private final class FreshTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts: [TransportStart] = []
    private var recordedTransports: [MockTransport] = []

    var starts: [TransportStart] {
        lock.withLock { recordedStarts }
    }

    var transports: [MockTransport] {
        lock.withLock { recordedTransports }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = MockTransport()
        lock.withLock {
            recordedStarts.append(TransportStart(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            ))
            recordedTransports.append(transport)
        }
        return transport
    }
}

private actor StderrTailGate {
    private var released = false
    private var hasWaiter = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiterObservers: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        hasWaiter = true
        waiterObservers.forEach { $0.resume() }
        waiterObservers.removeAll()
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilWaiting() async {
        guard !hasWaiter else { return }
        await withCheckedContinuation { continuation in
            waiterObservers.append(continuation)
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private final class MockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    private var started = false
    private var interrupted = false
    private var closed = false
    private var stderrText: String?
    private var stderrGate: StderrTailGate?

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    var didStart: Bool {
        lock.withLock { started }
    }

    var didInterrupt: Bool {
        lock.withLock { interrupted }
    }

    var didClose: Bool {
        lock.withLock { closed }
    }

    var stderrTailText: String? {
        get {
            lock.withLock { stderrText }
        }
        set {
            lock.withLock {
                stderrText = newValue
            }
        }
    }

    func blockStderrTail() -> StderrTailGate {
        let gate = StderrTailGate()
        lock.withLock {
            stderrGate = gate
        }
        return gate
    }

    func start() throws {
        lock.withLock {
            started = true
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock {
            sent.append(data)
        }
    }

    func interrupt() async {
        lock.withLock {
            interrupted = true
        }
    }

    func close() async {
        lock.withLock {
            closed = true
        }
        continuation?.finish()
    }

    func stderrTail() async -> String? {
        let gate = lock.withLock { stderrGate }
        if let gate {
            await gate.waitUntilReleased()
        }
        return stderrTailText
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.withLock {
            sent.map { String(data: $0, encoding: .utf8) ?? "" }
        }
    }
}

// task-9 rework (Codex stage2 HIGH): updateSettings は置換セマンティクス。
// nil で --model / --permission-mode をクリアして既定（フラグ無し）へ戻せること。
@Test func claudeUpdateSettingsCanClearModelAndPermissionMode() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "77777777-7777-4777-8777-777777777777"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        permissionMode: "plan",
        model: "opus",
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()
    try await client.turnStart([.text("first")])
    _ = await iterator.next()
    recorder.transports[0].receive(#"{"type":"result","subtype":"success","session_id":"77777777-7777-4777-8777-777777777777","is_error":false}"#)
    _ = await iterator.next()

    await client.updateSettings(model: nil, permissionMode: nil)
    try await client.turnStart([.text("second")])

    let args = recorder.starts[1].arguments
    #expect(!args.contains("--model"))
    #expect(!args.contains("--permission-mode"))
    #expect(args.contains("--resume"))
    await client.close()
}

// task-9 rework (stage1 提案): permission-mode の respawn 反映 ＋ settingsDirty クリア後の非再respawn。
@Test func claudeUpdateSettingsClearsDirtyAndPermissionModeAppliesViaRespawn() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "88888888-8888-4888-8888-888888888888"
    let client = ClaudeChatClient(environment: ["PHLOX_SESSION_ID": sid], transportFactory: recorder.makeTransport)
    await client.start()
    var it = client.events.makeAsyncIterator()
    try await client.turnStart([.text("a")]); #expect(await it.next() == .turnStarted)
    recorder.transports[0].receive(#"{"type":"result","subtype":"success","session_id":"88888888-8888-4888-8888-888888888888","is_error":false}"#)
    #expect(await it.next() == .turnCompleted(nativeSessionId: sid))

    await client.updateSettings(model: nil, permissionMode: "plan")
    try await client.turnStart([.text("b")]); #expect(await it.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    #expect(recorder.starts[1].arguments.contains("plan"))
    recorder.transports[1].receive(#"{"type":"result","subtype":"success","session_id":"88888888-8888-4888-8888-888888888888","is_error":false}"#)
    #expect(await it.next() == .turnCompleted(nativeSessionId: sid))

    // 3ターン目は settingsDirty がクリア済みなので respawn しない。
    try await client.turnStart([.text("c")]); #expect(await it.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    await client.close()
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "waitUntil timed out")
}

// rate_limit_event（無害な利用量情報）は警告にせず黙って無視する（実機で「hello」正常応答の
// 直後に赤エラー枠として表示された 2026-07-03 の実測に基づく回帰テスト）。
@Test func rateLimitEventIsSilentlyIgnored() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour"}}
    """)
    mock.receive("""
    {"type":"result","subtype":"success","is_error":false}
    """)

    // rate_limit_event 由来の warning を挟まず、直接 turnCompleted が来ること。
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

// tool_progress（ツール実行中の進捗情報）は警告にせず黙って無視する（実機で
// 「Unknown Claude event type: tool_progress」が赤エラー枠として表示された
// 2026-07-19 の実測に基づく回帰テスト。rate_limit_event と同型）。
@Test func toolProgressEventIsSilentlyIgnored() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive("""
    {"type":"tool_progress","tool_use_id":"toolu_1","progress":{"status":"running"}}
    """)
    mock.receive("""
    {"type":"result","subtype":"success","is_error":false}
    """)

    // tool_progress 由来の warning を挟まず、直接 turnCompleted が来ること。
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

// task-22: effort が buildArguments に反映され、2引数 updateSettings では effort を触らない。
@Test func claudeUpdateSettingsEffortAppearsInRespawnArguments() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions", effort: "medium")
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    let args = recorder.starts[1].arguments
    #expect(args.contains("--effort"))
    #expect(args.contains("medium"))
    await client.close()
}

// task-25: バックグラウンドタスク system イベントの正規化（白箱）。
@Test func taskStartedSystemEventIsNormalized() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_01","description":"sleep","task_type":"local_bash"}"#
    )

    #expect(await iterator.next() == .backgroundTaskStarted(
        taskId: "t1",
        taskType: "local_bash",
        description: "sleep",
        toolUseId: "toolu_01"
    ))
    await client.close()
}

@Test func taskStartedMissingOptionalFieldsUseDefaults() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(
        #"{"type":"system","subtype":"task_started","task_id":"t2","task_type":"local_agent"}"#
    )

    #expect(await iterator.next() == .backgroundTaskStarted(
        taskId: "t2",
        taskType: "local_agent",
        description: "",
        toolUseId: nil
    ))
    await client.close()
}

@Test func taskNotificationSystemEventIsNormalized() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(
        #"{"type":"system","subtype":"task_notification","task_id":"t1","status":"completed","summary":"done"}"#
    )

    #expect(await iterator.next() == .backgroundTaskCompleted(
        taskId: "t1",
        status: "completed",
        summary: "done"
    ))
    await client.close()
}

@Test func taskNotificationUnknownStatusIsPreserved() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(
        #"{"type":"system","subtype":"task_notification","task_id":"t9","status":"failed","summary":"boom"}"#
    )

    #expect(await iterator.next() == .backgroundTaskCompleted(
        taskId: "t9",
        status: "failed",
        summary: "boom"
    ))
    await client.close()
}

@Test func taskUpdatedSystemEventEmitsNothing() async throws {
    let mock = MockTransport()
    let recorder = TransportRecorder(mock)
    // 密封化: ambient PHLOX_SESSION_ID が既定環境から漏れ nativeSessionId を汚さないよう空環境で構築。
    let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
    await client.start()

    var iterator = client.events.makeAsyncIterator()
    mock.receive(
        #"{"type":"system","subtype":"task_updated","task_id":"t1","patch":{"status":"completed"}}"#
    )
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    #expect(await iterator.next() == .turnCompleted(nativeSessionId: nil))
    await client.close()
}

@Test func claudeTwoArgumentUpdateSettingsLeavesEffortUnset() async throws {
    let recorder = FreshTransportRecorder()
    let sid = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sid],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    await client.updateSettings(model: "opus", permissionMode: "bypassPermissions")
    try await client.turnStart([.text("hello")])
    #expect(await iterator.next() == .turnStarted)

    #expect(!recorder.starts[1].arguments.contains("--effort"))
    await client.close()
}
