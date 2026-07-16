import Foundation
import Testing
@testable import CodexAppServerKit

@Test func requestResponseMatchesByID() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    async let response: InitializeResponse = rpc.request(
        method: "initialize",
        params: InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
    )

    let sent = await waitUntil { await !transport.sent.all().isEmpty }
    #expect(sent)
    let request = try #require(await transport.sent.all().first)
    #expect(request["method"]?.stringValue == "initialize")
    #expect(request["id"]?.intValue == 1)

    transport.receive("""
    {"jsonrpc":"2.0","id":1,"result":{"codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"macos","userAgent":"codex-test"}}
    """)

    let decoded = try await response
    #expect(decoded.userAgent == "codex-test")
    await rpc.close()
}

@Test func notificationRoutesToTypedStream() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    var iterator = await rpc.notifications.makeAsyncIterator()
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","delta":"hello"}}
    """)

    let notification = await iterator.next()
    guard case .agentMessageDelta(let value) = notification else {
        Issue.record("Expected agent message delta")
        return
    }
    #expect(value.delta == "hello")
    await rpc.close()
}

@Test func approvalRequestUsesHandlerAndRepliesWithDecision() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport) { request in
        guard case .commandExecutionApproval(let approval) = request else {
            throw JSONRPCClientError.unsupportedServerRequest(request.method)
        }
        #expect(approval.command == "pwd")
        return try encodeToJSONValue(ApprovalDecisionResponse(decision: .accept))
    }
    await rpc.start()

    transport.receive("""
    {"jsonrpc":"2.0","id":7,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","startedAtMs":1,"command":"pwd","cwd":"/tmp"}}
    """)

    let replied = await waitUntil {
        await transport.sent.all().contains { $0["id"]?.intValue == 7 }
    }
    #expect(replied)
    let response = try #require(await transport.sent.first { $0["id"]?.intValue == 7 })
    #expect(response["result"]?["decision"]?.stringValue == "accept")
    await rpc.close()
}

@Test func unknownServerRequestReceivesUnsupportedError() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    transport.receive("""
    {"jsonrpc":"2.0","id":9,"method":"item/tool/requestUserInput","params":{"itemId":"item-1"}}
    """)

    let replied = await waitUntil {
        await transport.sent.all().contains { $0["id"]?.intValue == 9 }
    }
    #expect(replied)
    let response = try #require(await transport.sent.first { $0["id"]?.intValue == 9 })
    #expect(response["error"]?["code"]?.intValue == -32601)
    #expect(response["error"]?["message"]?.stringValue?.contains("Unsupported") == true)
    await rpc.close()
}

@Test func malformedJSONIsReportedAndPendingRequestsFailOnClose() async throws {
    let transport = MockTransport()
    let rpc = JSONRPCClient(transport: transport)
    await rpc.start()

    var errorIterator = await rpc.errors.makeAsyncIterator()
    transport.receive("{ not json }")
    let error = await errorIterator.next()
    guard case .malformedMessage = error else {
        Issue.record("Expected malformed JSON error")
        return
    }

    async let response: InitializeResponse = rpc.request(
        method: "initialize",
        params: InitializeParams(clientInfo: ClientInfo(name: "PhloxTests", version: "1"))
    )
    let sent = await waitUntil { await !transport.sent.all().isEmpty }
    #expect(sent)
    await rpc.close()

    do {
        _ = try await response
        Issue.record("Expected transport closed error")
    } catch JSONRPCClientError.transportClosed {
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
