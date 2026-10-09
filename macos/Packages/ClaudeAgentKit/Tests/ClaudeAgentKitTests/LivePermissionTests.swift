import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private extension ClaudeChatClient {
    func hasQuestion(_ id: String) -> Bool { pendingUserQuestions[id] != nil }
    func permissionTimeoutTask() -> Task<Void, Never>? { pendingPermissionRequest?.timeoutTask }
}

private final class PermissionTransport: LineDelimitedTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var sent: [Data] = []
    private var closed = false
    var failsSend = false
    var blocksClose = false
    private var closeWaiter: CheckedContinuation<Void, Never>?
    init() {
        let stream = AsyncStream<Data>.makeStream()
        receivedLines = stream.stream
        continuation = stream.continuation
    }
    func start() throws {}
    func send(_ data: Data) async throws {
        if failsSend { throw LineDelimitedProcessTransportError.stdinClosed }
        lock.withLock { sent.append(data) }
    }
    func interrupt() async {}
    func close() async {
        if blocksClose {
            await withCheckedContinuation { waiter in
                lock.withLock { closed = true; closeWaiter = waiter }
            }
        } else {
            lock.withLock { closed = true }
        }
        continuation.finish()
    }
    func finishClose() {
        let waiter = lock.withLock { let saved = closeWaiter; closeWaiter = nil; return saved }
        waiter?.resume()
    }
    var didClose: Bool { lock.withLock { closed } }
    var objects: [[String: Any]] {
        lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }
    func receive(_ object: [String: Any]) throws {
        continuation.yield(try JSONSerialization.data(withJSONObject: object))
    }
    func permissionRequest() async throws -> [String: Any] {
        for _ in 0..<200 {
            if let request = objects.first(where: {
                ($0["request"] as? [String: Any])?["subtype"] as? String == "set_permission_mode"
            }) { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ClaudeChatClientError.permissionRequestTimedOut
    }
    func reply(id: String, success: Bool) throws {
        try receive(["type": "control_response", "response": [
            "request_id": id, "subtype": success ? "success" : "error", "error": "rejected",
        ]])
    }
}

private final class PermissionTransportPair: @unchecked Sendable {
    let first = PermissionTransport()
    let second = PermissionTransport()
    private let lock = NSLock()
    private var started = false
    func make() -> PermissionTransport {
        lock.withLock {
            if started { return second }
            started = true
            return first
        }
    }
}

@Suite struct LivePermissionTests {
    private func makeClient(_ transport: PermissionTransport) -> ClaudeChatClient {
        ClaudeChatClient(permissionMode: "bypassPermissions", transportFactory: { _, _, _, _ in transport })
    }

    @Test func runningTurnChangesPermissionOnlyAfterAcknowledgementWithoutRespawn() async throws {
        let transport = PermissionTransport()
        let client = makeClient(transport)
        await client.start()
        try await client.turnStart([.text("test")])
        let change = Task { try await client.setPermissionMode("manual") }
        let request = try await transport.permissionRequest()
        let id = try #require(request["request_id"] as? String)
        #expect((request["request"] as? [String: Any])?["mode"] as? String == "manual")
        #expect(await client.currentPermissionMode == "bypassPermissions")
        await #expect(throws: ClaudeChatClientError.permissionRequestInProgress) {
            try await client.turnStart([.text("must wait for permissions")])
        }
        await #expect(throws: ClaudeChatClientError.permissionRequestInProgress) {
            try await client.setPermissionMode("plan")
        }
        try transport.reply(id: "unrelated", success: true)
        #expect(await client.currentPermissionMode == "bypassPermissions")
        try transport.reply(id: id, success: true)
        try await change.value
        #expect(await client.currentPermissionMode == "manual")
        #expect(await client.spawnGeneration == 1)
        #expect(await client.currentTurnOpen)
        #expect(!transport.didClose)
        await client.handleEvent([
            "type": "control_request", "request_id": "tool-1",
            "request": ["subtype": "can_use_tool", "tool_name": "Bash", "input": ["command": "pwd"]],
        ], generation: 1)
        #expect(await client.hasQuestion("tool-1"))
        await client.close()
    }

    @Test func rejectedChangeKeepsConfirmedPermissionAndProcess() async throws {
        let transport = PermissionTransport()
        let client = makeClient(transport)
        await client.start()
        let change = Task { try await client.setPermissionMode("manual") }
        let request = try await transport.permissionRequest()
        try transport.reply(id: try #require(request["request_id"] as? String), success: false)
        await #expect(throws: ClaudeChatClientError.permissionRequestFailed("rejected")) { try await change.value }
        do { try await change.value }
        catch { #expect(error.localizedDescription == "rejected") }
        #expect(await client.currentPermissionMode == "bypassPermissions")
        #expect(!transport.didClose)
        await client.close()
    }

    @Test func timeoutAndSendFailureStopUnconfirmedProcess() async throws {
        for failsSend in [false, true] {
            let transport = PermissionTransport()
            transport.failsSend = failsSend
            let client = makeClient(transport)
            await client.setPermissionRequestTimeoutForTesting(.milliseconds(20))
            await client.start()
            if failsSend {
                await #expect(throws: LineDelimitedProcessTransportError.stdinClosed) {
                    try await client.setPermissionMode("manual")
                }
            } else {
                await #expect(throws: ClaudeChatClientError.permissionRequestTimedOut) {
                    try await client.setPermissionMode("manual")
                }
            }
            #expect(transport.didClose)
            #expect(await client.transport == nil)
            #expect(await client.currentPermissionMode == "bypassPermissions")
            await client.close()
        }
    }

    @Test func closedProcessReleasesWaitingChange() async throws {
        let transport = PermissionTransport()
        let client = makeClient(transport)
        await client.start()
        let change = Task { try await client.setPermissionMode("manual") }
        _ = try await transport.permissionRequest()
        await client.close()
        await #expect(throws: ClaudeChatClientError.transportClosed) { try await change.value }
        #expect(await client.currentPermissionMode == "bypassPermissions")
    }

    @Test func failedChangeDuringRunningTurnNotifiesInterruption() async throws {
        for failsSend in [false, true] {
            let transport = PermissionTransport()
            let client = makeClient(transport)
            await client.setPermissionRequestTimeoutForTesting(.milliseconds(20))
            await client.start()
            try await client.turnStart([.text("running")])
            var events = client.events.makeAsyncIterator()
            #expect(await events.next() == .turnStarted)
            transport.failsSend = failsSend
            if failsSend {
                await #expect(throws: LineDelimitedProcessTransportError.stdinClosed) {
                    try await client.setPermissionMode("manual")
                }
            } else {
                await #expect(throws: ClaudeChatClientError.permissionRequestTimedOut) {
                    try await client.setPermissionMode("manual")
                }
            }
            await client.close()
            #expect(await events.next() == .turnInterrupted(nativeSessionId: nil))
        }
    }

    @Test func permissionBeforeStartIsUsedInFirstProcess() async throws {
        let transport = PermissionTransport()
        let client = makeClient(transport)
        try await client.setPermissionMode("manual")
        let args = await client.buildArguments(sessionArgument: .resume("saved"))
        #expect(args.contains("manual"))
        #expect(args.contains("--allow-dangerously-skip-permissions"))
        #expect(!args.contains("--dangerously-skip-permissions"))
        #expect(!args.contains("--allowedTools"))
        #expect(transport.objects.isEmpty)
        await client.close()
    }

    @Test func settingsConfiguredBeforeStartAndResumeDoNotCauseRedundantRespawn() async throws {
        for resumes in [false, true] {
            let transport = PermissionTransport()
            let client = makeClient(transport)
            await client.updateSettings(model: "sonnet", permissionMode: "manual", effort: "high")
            if resumes { try await client.resume(sessionRef: "saved") }
            else { await client.start() }
            try await client.turnStart([.text("test")])
            #expect(await client.spawnGeneration == 1)
            #expect(!transport.didClose)
            await client.close()
        }
    }

    @Test func closingOldPermissionProcessDoesNotInterruptANewConversation() async throws {
        let pair = PermissionTransportPair()
        pair.first.blocksClose = true
        let client = ClaudeChatClient(permissionMode: "bypassPermissions", transportFactory: { _, _, _, _ in pair.make() })
        await client.setPermissionRequestTimeoutForTesting(.milliseconds(100))
        await client.start()
        try await client.turnStart([.text("old")])
        var events = client.events.makeAsyncIterator()
        #expect(await events.next() == .turnStarted)
        let change = Task { try await client.setPermissionMode("manual") }
        _ = try await pair.first.permissionRequest()
        let timeout = try #require(await client.permissionTimeoutTask())
        for _ in 0..<400 {
            if pair.first.didClose { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(pair.first.didClose)
        await client.resetConversation()
        await #expect(throws: ClaudeChatClientError.transportClosed) { try await change.value }
        try await client.turnStart([.text("new")])
        #expect(await events.next() == .turnStarted)
        pair.first.finishClose()
        await timeout.value
        #expect(await client.currentTurnOpen)
        await client.close()
        #expect(await events.next() == nil)
    }

    @Test(arguments: [true, false])
    func latePermissionResponseAfterTimeoutDoesNotConfirmAClosingProcess(success: Bool) async throws {
        let transport = PermissionTransport()
        transport.blocksClose = true
        let client = makeClient(transport)
        await client.setPermissionRequestTimeoutForTesting(.milliseconds(20))
        await client.start()
        try await client.turnStart([.text("running")])
        var events = client.events.makeAsyncIterator()
        _ = await events.next()
        let change = Task { try await client.setPermissionMode("manual") }
        let request = try await transport.permissionRequest()
        let id = try #require(request["request_id"] as? String)
        let timeout = try #require(await client.permissionTimeoutTask())
        for _ in 0..<200 {
            if transport.didClose { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.didClose)
        // 終了を始める直前に受信タスクが actor へ渡した応答を再現する。
        let accepted = await client.handlePermissionResponse([
            "request_id": id, "subtype": success ? "success" : "error", "error": "late rejection",
        ])
        #expect(!accepted)
        #expect(await client.currentPermissionMode == "bypassPermissions")
        transport.finishClose()
        await timeout.value
        await #expect(throws: ClaudeChatClientError.permissionRequestTimedOut) { try await change.value }
        await client.close()
        guard case .turnInterrupted = await events.next() else {
            Issue.record("Closing the uncertain process must interrupt the running turn")
            return
        }
    }
}
