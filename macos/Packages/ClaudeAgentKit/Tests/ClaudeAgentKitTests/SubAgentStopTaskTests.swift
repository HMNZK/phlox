import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

/// 個別のサブエージェント停止（stream-json の control_request `stop_task`）。
@Suite("SubAgent stop_task")
struct SubAgentStopTaskTests {
    private static let taskStarted =
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_S1","task_type":"local_agent","subagent_type":"general-purpose","description":"d"}"#

    private func makeClient() async -> (ClaudeChatClient, StopTaskTransport, EventLog) {
        let (client, transports, log) = await makeClientWithSpawns()
        return (client, transports.first!, log)
    }

    /// 起動し直し（resume）を検証するため、spawn のたびに新しい transport を返す。
    private func makeClientWithSpawns() async -> (ClaudeChatClient, TransportBox, EventLog) {
        let box = TransportBox()
        let client = ClaudeChatClient(transportFactory: { _, _, _, _ in box.make() })
        await client.start()
        return (client, box, EventLog(client.events))
    }

    private static let agentToolUse =
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_S1","name":"Agent","input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    private static let stoppedNotification =
        #"{"type":"system","subtype":"task_notification","task_id":"t1","tool_use_id":"toolu_S1","status":"stopped","summary":"","output_file":"/tmp/none.jsonl"}"#
    private static func agentToolResult(isError: Bool) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_S1","is_error":\#(isError),"content":"The user doesn't want to proceed with this tool use."}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    }

    @Test
    func taskStartedMakesTheChildStoppable() async {
        let (client, transport, log) = await makeClient()
        defer { withExtendedLifetime(client) {} }
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
    }

    @Test
    func stopWritesStopTaskWithTheTaskID() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })

        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 1)

        let requests = transport.sentObjects().compactMap { $0["request"] as? [String: Any] }
        let stop = try #require(requests.first { $0["subtype"] as? String == "stop_task" })
        #expect(stop["task_id"] as? String == "t1")
    }

    @Test
    func stopOfAnUnknownChildThrowsAndWritesNothing() async {
        let (client, transport, _) = await makeClient()
        await #expect(throws: ClaudeChatClientError.subAgentTaskUnknown) {
            try await client.stopSubAgent(toolUseId: "toolu_none", attempt: 1)
        }
        #expect(transport.sentObjects().isEmpty)
    }

    @Test
    func errorControlResponseReleasesTheStop() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 1)
        let requestID = try #require(transport.sentObjects().first?["request_id"] as? String)

        transport.receive(#"{"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"no such task"}}"#)

        #expect(await log.wait { $0 == .subAgentStopFailed(toolUseId: "toolu_S1", attempt: 1) })
    }

    @Test
    func successControlResponseIsNotAFailure() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 1)
        let requestID = try #require(transport.sentObjects().first?["request_id"] as? String)

        transport.receive(#"{"type":"control_response","response":{"subtype":"success","request_id":"\#(requestID)"}}"#)
        transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","result":"done"}"#)

        // 後続の result まで処理されたあとで、失敗イベントが出ていないこと。
        #expect(await log.wait { if case .turnCompleted = $0 { true } else { false } })
        #expect(!log.events.contains { if case .subAgentStopFailed = $0 { true } else { false } })
    }

    @Test
    func agentToolResultAfterStoppedNotificationIsNotReportedAsCompletionOrFailure() async throws {
        for isError in [false, true] {
            let (client, transport, log) = await makeClient()
            defer { withExtendedLifetime(client) {} }
            transport.receive(Self.agentToolUse)
            transport.receive(Self.taskStarted)
            transport.receive(Self.stoppedNotification)
            transport.receive(Self.agentToolResult(isError: isError))
            transport.receive(#"{"type":"result","subtype":"success","session_id":"S1","result":"done"}"#)

            #expect(await log.wait { if case .turnCompleted = $0 { true } else { false } })
            let completions = log.events.compactMap { event -> String? in
                if case .subAgentCompleted(_, let status, _, _) = event { return status }
                return nil
            }
            #expect(completions == ["stopped"], "is_error=\(isError)")
            #expect(!log.events.contains { if case .subAgentOutput = $0 { true } else { false } }, "is_error=\(isError)")
        }
    }

    @Test
    func failureCarriesTheAttemptOfTheRequest() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 7)
        let requestID = try #require(transport.sentObjects().first?["request_id"] as? String)

        transport.receive(#"{"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"x"}}"#)

        #expect(await log.wait { $0 == .subAgentStopFailed(toolUseId: "toolu_S1", attempt: 7) })
    }

    @Test
    func restartFailsPendingStopAndForgetsTheOldTaskIDs() async throws {
        let (client, box, log) = await makeClientWithSpawns()
        let transport = try #require(box.first)
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 3)

        try await client.resume(sessionRef: "S1")

        #expect(await log.wait { $0 == .subAgentStopFailed(toolUseId: "toolu_S1", attempt: 3) })
        await #expect(throws: ClaudeChatClientError.subAgentTaskUnknown) {
            try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 4)
        }
        let leftover = await client.pendingStopTaskRequests
        #expect(leftover.isEmpty)
    }

    @Test
    func closeFailsPendingStop() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 2)

        await client.close()

        #expect(await log.wait { $0 == .subAgentStopFailed(toolUseId: "toolu_S1", attempt: 2) })
    }

    @Test
    func processExitFailsPendingStop() async throws {
        let (client, transport, log) = await makeClient()
        transport.receive(Self.taskStarted)
        #expect(await log.wait { $0 == .subAgentStopAvailable(toolUseId: "toolu_S1") })
        try await client.stopSubAgent(toolUseId: "toolu_S1", attempt: 5)

        await transport.close()   // プロセスが終了して受信が尽きる

        #expect(await log.wait { $0 == .subAgentStopFailed(toolUseId: "toolu_S1", attempt: 5) })
    }

    @Test
    func stoppedNotificationCompletesTheChildAsStopped() async {
        let (client, transport, log) = await makeClient()
        defer { withExtendedLifetime(client) {} }
        transport.receive(Self.taskStarted)
        transport.receive(#"{"type":"system","subtype":"task_notification","task_id":"t1","tool_use_id":"toolu_S1","status":"stopped","summary":"","output_file":"/tmp/none.jsonl"}"#)
        #expect(await log.wait {
            if case .subAgentCompleted("toolu_S1", "stopped", _, _) = $0 { true } else { false }
        })
    }
}

/// イベントを別タスクで溜める。`wait` は条件に合うイベントが来るまで最大 2 秒待つ（退行しても固まらない）。
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [NormalizedChatEvent] = []
    private var reader: Task<Void, Never>?

    init(_ stream: AsyncStream<NormalizedChatEvent>) {
        reader = Task { [weak self] in
            for await event in stream { self?.lock.withLock { self?.log.append(event) } }
        }
    }
    deinit { reader?.cancel() }

    var events: [NormalizedChatEvent] { lock.withLock { log } }

    func wait(_ match: (NormalizedChatEvent) -> Bool) async -> Bool {
        for _ in 0..<200 {
            if events.contains(where: match) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private final class TransportBox: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [StopTaskTransport] = []
    var first: StopTaskTransport? { lock.withLock { made.first } }
    func make() -> StopTaskTransport {
        let transport = StopTaskTransport()
        lock.withLock { made.append(transport) }
        return transport
    }
}

private final class StopTaskTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws { lock.withLock { sent.append(data) } }
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }
    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }

    /// 送った JSON 行（初期化で送られる行は含めない。stop_task 系のみ）。
    func sentObjects() -> [[String: Any]] {
        lock.withLock {
            sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .filter { ($0["request"] as? [String: Any])?["subtype"] as? String == "stop_task" }
        }
    }
}
