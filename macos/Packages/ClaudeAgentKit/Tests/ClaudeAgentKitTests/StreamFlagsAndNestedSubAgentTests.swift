import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

@Suite("Claude Code stream flags")
struct StreamFlagsAndNestedSubAgentTests {
    @Test
    func streamFlagsAndOptionalArgumentsAreConfigurable() async throws {
        let defaultTransport = StreamFlagsTestTransport()
        let defaultRecorder = StreamFlagsTransportRecorder(defaultTransport)
        let defaultClient = ClaudeChatClient(
            environment: [:],
            transportFactory: defaultRecorder.makeTransport
        )
        await defaultClient.start()

        let defaultArguments = try #require(defaultRecorder.starts.first)
        #expect(defaultArguments.contains("--forward-subagent-text"))
        #expect(defaultArguments.contains("--include-partial-messages"))
        #expect(!defaultArguments.contains("--setting-sources"))
        #expect(!defaultArguments.contains("--agents"))
        await defaultClient.close()

        let configuredTransport = StreamFlagsTestTransport()
        let configuredRecorder = StreamFlagsTransportRecorder(configuredTransport)
        let configuredClient = ClaudeChatClient(
            environment: [:],
            includePartialMessages: false,
            settingSources: "user,project",
            agents: #"{"reviewer":{"description":"Review","prompt":"Review the change"}}"#,
            transportFactory: configuredRecorder.makeTransport
        )
        await configuredClient.start()

        let configuredArguments = try #require(configuredRecorder.starts.first)
        #expect(configuredArguments.contains("--forward-subagent-text"))
        #expect(!configuredArguments.contains("--include-partial-messages"))
        #expect(configuredArguments.contains("--setting-sources"))
        #expect(configuredArguments.contains("user,project"))
        #expect(configuredArguments.contains("--agents"))
        #expect(configuredArguments.contains(#"{"reviewer":{"description":"Review","prompt":"Review the change"}}"#))
        await configuredClient.close()
    }

    @Test
    func forkSessionAddsResumeAndForkFlags() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)

        try await client.forkSession(from: "session-to-fork")

        let arguments = try #require(recorder.starts.first)
        #expect(arguments.contains("--resume"))
        #expect(arguments.contains("session-to-fork"))
        #expect(arguments.contains("--fork-session"))
        #expect(!arguments.contains("--session-id"))
        await client.close()
    }

    @Test
    func forkSettingsRespawnBeforeInitNeverResumesForkSource() async throws {
        let recorder = ForkTransportRecorder()
        let client = ClaudeChatClient(
            environment: ["PHLOX_SESSION_ID": "fork-source"],
            transportFactory: recorder.makeTransport
        )

        try await client.forkSession(from: "fork-source")
        await client.updateSettings(model: "sonnet", permissionMode: nil)
        try await client.turnStart([.text("after fork")])

        #expect(recorder.starts.count == 2)
        let respawnArguments = try #require(recorder.starts.last)
        #expect(!respawnArguments.contains("--resume"))
        #expect(!respawnArguments.contains("--session-id"))
        #expect(!respawnArguments.contains("fork-source"))
        #expect(!respawnArguments.contains("--fork-session"))
        await client.close()
    }

    @Test
    func partialTextAndThinkingAreNormalizedWithoutCompletedMessageDuplication() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"msg-partial","content":[]}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"thinking","thinking":""}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"plan"}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"msg-partial","content":[{"type":"text","text":"Hello"},{"type":"thinking","thinking":"plan"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let textEvents = events.compactMap { event -> (String, String)? in
            guard case .agentMessageDelta(let itemId, let text) = event else { return nil }
            return (itemId, text)
        }
        let reasoningEvents = events.compactMap { event -> (String, String)? in
            guard case .reasoningDelta(let itemId, let text) = event else { return nil }
            return (itemId, text)
        }

        #expect(textEvents.map(\.1) == ["Hel", "lo"])
        #expect(textEvents.map(\.0) == ["msg-partial:text", "msg-partial:text"])
        #expect(reasoningEvents.count == 1)
        #expect(reasoningEvents.first?.0 == "msg-partial:thinking")
        #expect(reasoningEvents.first?.1 == "plan")
        #expect(!events.contains { event in
            if case .agentMessageDelta(_, "Hello") = event { return true }
            return false
        })
        await client.close()
    }

    @Test
    func partialSubAgentTextUsesSubAgentActivity() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"main-tool","content":[{"type":"tool_use","id":"toolu-sub","name":"Agent","input":{"subagent_type":"Explore","description":"探す"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"sub-message","content":[]}},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"SUB-TEXT"}},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"thinking","thinking":""}},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"SUB-THINKING"}},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"sub-message","content":[{"type":"text","text":"SUB-TEXT"},{"type":"thinking","thinking":"SUB-THINKING"}]},"parent_tool_use_id":"toolu-sub"}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"main-message","content":[{"type":"text","text":"MAIN-TEXT"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let subAgentMessages = events.compactMap { event -> (String, String)? in
            guard case .subAgentActivity("toolu-sub", .message, let itemId, let text) = event else { return nil }
            return (itemId ?? "", text)
        }
        let subAgentReasoning = events.compactMap { event -> (String, String)? in
            guard case .subAgentActivity("toolu-sub", .reasoning, let itemId, let text) = event else { return nil }
            return (itemId ?? "", text)
        }
        #expect(subAgentMessages.map(\.0) == ["sub-message:text"])
        #expect(subAgentMessages.map(\.1) == ["SUB-TEXT"])
        #expect(subAgentReasoning.map(\.0) == ["sub-message:thinking"])
        #expect(subAgentReasoning.map(\.1) == ["SUB-THINKING"])
        #expect(!events.contains {
            if case .agentMessageDelta(_, let text) = $0 { return text.contains("SUB-TEXT") }
            return false
        })
        #expect(events.contains {
            if case .agentMessageDelta(_, "MAIN-TEXT") = $0 { return true }
            return false
        })
        await client.close()
    }

    @Test
    func initMcpServerErrorsBecomeOneWarningWithServerAndDetail() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"type":"system","subtype":"init","session_id":"S1","mcp_server_errors":[{"name":"github","type":"connection","message":"connection refused"}]}"#)
        transport.receive(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1}}"#)

        let first = await iterator.next()
        guard case .warning(let message) = first else {
            Issue.record("system.init の mcp_server_errors が warning になっていない: \(String(describing: first))")
            await client.close()
            return
        }
        #expect(message.contains("github"))
        #expect(message.contains("connection refused"))
        await client.close()
    }

    @Test
    func initMcpServerErrorsUnexpectedShapeIsIgnoredWithoutWarning() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        transport.receive(#"{"type":"system","subtype":"init","session_id":"S1","mcp_server_errors":{"github":"connection refused"}}"#)
        transport.receive(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1}}"#)

        let event = await iterator.next()
        guard case .compactionBoundary(let trigger, let preTokens) = event else {
            Issue.record("想定外形状の mcp_server_errors が warning になった: \(String(describing: event))")
            await client.close()
            return
        }
        #expect(trigger == "manual")
        #expect(preTokens == 1)
        await client.close()
    }

    @Test
    func nestedSubAgentStreamEventsStayWithTheirNearestToolUse() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"main-a","content":[{"type":"tool_use","id":"toolu-root-a","name":"Agent","input":{"subagent_type":"Explore","description":"親A"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"child-a","content":[{"type":"tool_use","id":"toolu-child-a","name":"Agent","input":{"subagent_type":"Explore","description":"子A"}}]},"parent_tool_use_id":"toolu-root-a"}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"grandchild-a","content":[{"type":"tool_use","id":"toolu-grandchild-a","name":"Task","input":{"subagent_type":"Explore","description":"孫A","prompt":"孫プロンプト"}}]},"parent_tool_use_id":"toolu-child-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"grandchild-message","content":[]}},"parent_tool_use_id":"toolu-grandchild-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":"toolu-grandchild-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"GRANDCHILD-A"}},"parent_tool_use_id":"toolu-grandchild-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"child-message","content":[]}},"parent_tool_use_id":"toolu-child-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":"toolu-child-a"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"CHILD-A"}},"parent_tool_use_id":"toolu-child-a"}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"main-b","content":[{"type":"tool_use","id":"toolu-root-b","name":"Agent","input":{"subagent_type":"Explore","description":"親B"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"root-b-message","content":[]}},"parent_tool_use_id":"toolu-root-b"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":"toolu-root-b"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ROOT-B"}},"parent_tool_use_id":"toolu-root-b"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let startedIDs = events.compactMap { event -> String? in
            guard case .subAgentStarted(let toolUseId, _, _) = event else { return nil }
            return toolUseId
        }
        #expect(startedIDs == ["toolu-root-a", "toolu-child-a", "toolu-grandchild-a", "toolu-root-b"])
        let promptEvents = events.compactMap { event -> (String, String)? in
            guard case .subAgentActivity(let toolUseId, .prompt, _, let text) = event else { return nil }
            return (toolUseId, text)
        }
        #expect(promptEvents.map(\.0) == ["toolu-grandchild-a"])
        #expect(promptEvents.map(\.1) == ["孫プロンプト"])
        #expect(events.contains {
            if case .subAgentActivity("toolu-grandchild-a", .message, _, "GRANDCHILD-A") = $0 { return true }
            return false
        })
        #expect(events.contains {
            if case .subAgentActivity("toolu-child-a", .message, _, "CHILD-A") = $0 { return true }
            return false
        })
        #expect(events.contains {
            if case .subAgentActivity("toolu-root-b", .message, _, "ROOT-B") = $0 { return true }
            return false
        })
        #expect(!events.contains {
            if case .subAgentActivity("toolu-root-a", _, _, let text) = $0 {
                return text.contains("GRANDCHILD-A") || text.contains("CHILD-A")
            }
            return false
        })
        for event in events {
            if case .agentMessageDelta(_, let text) = event {
                #expect(!text.contains("CHILD-A"))
                #expect(!text.contains("GRANDCHILD-A"))
                #expect(!text.contains("ROOT-B"))
            }
        }
        await client.close()
    }

    @Test
    func nestedSubAgentToolResultCompletesGrandchildChip() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"root","content":[{"type":"tool_use","id":"toolu-root","name":"Agent","input":{"subagent_type":"Explore","description":"親"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"child","content":[{"type":"tool_use","id":"toolu-grandchild","name":"Task","input":{"subagent_type":"Explore","description":"孫"}}]},"parent_tool_use_id":"toolu-root"}"#)
        transport.receive(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu-grandchild","content":"GRANDCHILD-OUTPUT"}]},"parent_tool_use_id":"toolu-root"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let completed = events.compactMap { event -> (String, String, String)? in
            guard case .subAgentCompleted(let toolUseId, let status, let summary, _) = event else { return nil }
            return (toolUseId, status, summary)
        }
        #expect(completed.map(\.0) == ["toolu-grandchild"])
        #expect(completed.map(\.1) == ["completed"])
        #expect(completed.map(\.2) == ["GRANDCHILD-OUTPUT"])
        await client.close()
    }

    @Test
    func topLevelAndNestedToolResultsCompleteBothSubAgentChips() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"root","content":[{"type":"tool_use","id":"toolu-root","name":"Agent","input":{"subagent_type":"Explore","description":"親"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"child","content":[{"type":"tool_use","id":"toolu-child","name":"Task","input":{"subagent_type":"Explore","description":"子"}}]},"parent_tool_use_id":"toolu-root"}"#)
        transport.receive(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu-root","content":"ROOT-OUTPUT"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu-child","content":"CHILD-OUTPUT"}]},"parent_tool_use_id":"toolu-root"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let completed = events.compactMap { event -> (String, String)? in
            guard case .subAgentCompleted(let toolUseId, let status, _, _) = event else { return nil }
            return (toolUseId, status)
        }
        #expect(completed.map(\.0) == ["toolu-root", "toolu-child"])
        #expect(completed.map(\.1) == ["completed", "completed"])
        #expect(events.contains {
            if case .subAgentOutput("toolu-root", "ROOT-OUTPUT") = $0 { return true }
            return false
        })
        await client.close()
    }

    @Test
    func grandchildContentBlockSeenBeforeAssistantDoesNotLeakToolResultToMain() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        // 孫の assistant 完成イベントより先に、孫ターンの content_block_start を受け取る。
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":"toolu-grandchild"}"#)
        transport.receive(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu-grandchild","content":"GRANDCHILD-OUTPUT"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"child","content":[{"type":"tool_use","id":"toolu-grandchild","name":"Task","input":{"subagent_type":"Explore","description":"孫"}}]},"parent_tool_use_id":"toolu-root"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        #expect(!events.contains {
            if case .commandExecution(_, _, let output) = $0 { return output.contains("GRANDCHILD-OUTPUT") }
            return false
        })
        #expect(events.contains {
            if case .subAgentOutput("toolu-grandchild", "GRANDCHILD-OUTPUT") = $0 { return true }
            return false
        })
        await client.close()
    }

    @Test
    func backgroundSubAgentPartialTrackingSurvivesResultBoundary() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"launcher","content":[{"type":"tool_use","id":"toolu-bg","name":"Agent","input":{"subagent_type":"Explore","run_in_background":true}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"bg-msg","content":[]}},"parent_tool_use_id":"toolu-bg"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"AAA"}},"parent_tool_use_id":"toolu-bg"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"BBB"}},"parent_tool_use_id":"toolu-bg"}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"bg-msg","content":[{"type":"text","text":"AAABBB"}]},"parent_tool_use_id":"toolu-bg"}"#)

        let events = await collectEvents(from: client, stopAfterSubAgentMessages: 2)
        let sub = events.compactMap { event -> (String, String)? in
            guard case .subAgentActivity("toolu-bg", .message, let itemId, let text) = event else { return nil }
            return (itemId ?? "", text)
        }
        #expect(sub.map(\.0) == ["bg-msg:text", "bg-msg:text"])
        #expect(sub.map(\.1) == ["AAA", "BBB"])
        await client.close()
    }

    @Test
    func completedSubAgentPartialTrackingIsReleased() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"assistant","message":{"id":"launcher","content":[{"type":"tool_use","id":"toolu-done","name":"Agent","input":{"subagent_type":"Explore"}}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"done-msg","content":[]}},"parent_tool_use_id":"toolu-done"}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"DONE"}},"parent_tool_use_id":"toolu-done"}"#)
        transport.receive(#"{"type":"system","subtype":"task_notification","task_id":"task-done","tool_use_id":"toolu-done","status":"completed","summary":"done"}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)
        _ = await collectEvents(from: client)

        #expect(await client.partialMessageIdsByParent.isEmpty)
        #expect(await client.partialItemIdsByKey.isEmpty)
        #expect(await client.partialItemIds.isEmpty)
        #expect(await client.partialContentKeys.isEmpty)
        #expect(await client.completedSubAgentToolUseIds.isEmpty)
        await client.close()
    }

    @Test
    func completedPartialContentArrivesBeforeNextMessageStart() async throws {
        let transport = StreamFlagsTestTransport()
        let recorder = StreamFlagsTransportRecorder(transport)
        let client = ClaudeChatClient(environment: [:], transportFactory: recorder.makeTransport)
        await client.start()

        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-1","content":[]}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"FIRST"}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"message-1","content":[{"type":"text","text":"FIRST"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"message_start","message":{"id":"message-2","content":[]}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"SECOND"}},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"assistant","message":{"id":"message-2","content":[{"type":"text","text":"SECOND"}]},"parent_tool_use_id":null}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","is_error":false}"#)

        let events = await collectEvents(from: client)
        let textEvents = events.compactMap { event -> String? in
            guard case .agentMessageDelta(_, let text) = event else { return nil }
            return text
        }
        #expect(textEvents == ["FIRST", "SECOND"])
        await client.close()
    }

    private func collectEvents(
        from client: ClaudeChatClient,
        stopAfterSubAgentMessages: Int? = nil
    ) async -> [NormalizedChatEvent] {
        let box = StreamFlagsEventBox()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                var subAgentMessageCount = 0
                for await event in client.events {
                    box.append(event)
                    if case .subAgentActivity(_, .message, _, _) = event {
                        subAgentMessageCount += 1
                    }
                    if let stopAfterSubAgentMessages,
                       subAgentMessageCount >= stopAfterSubAgentMessages {
                        break
                    }
                    if stopAfterSubAgentMessages == nil,
                       case .turnCompleted = event {
                        break
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
            }
            _ = await group.next()
            group.cancelAll()
        }
        return box.snapshot()
    }
}

private final class StreamFlagsEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NormalizedChatEvent] = []

    func append(_ event: NormalizedChatEvent) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [NormalizedChatEvent] {
        lock.withLock { events }
    }
}

private final class StreamFlagsTestTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}

private final class StreamFlagsTransportRecorder: @unchecked Sendable {
    private let transport: StreamFlagsTestTransport
    private let lock = NSLock()
    private var recordedStarts: [[String]] = []

    init(_ transport: StreamFlagsTestTransport) {
        self.transport = transport
    }

    var starts: [[String]] {
        lock.withLock { recordedStarts }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        lock.withLock {
            recordedStarts.append(arguments)
        }
        return transport
    }
}

private final class ForkTransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts: [[String]] = []
    private var transports: [StreamFlagsTestTransport] = []

    var starts: [[String]] {
        lock.withLock { recordedStarts }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let transport = StreamFlagsTestTransport()
        lock.withLock {
            recordedStarts.append(arguments)
            transports.append(transport)
        }
        return transport
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
