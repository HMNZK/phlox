import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

/// 札の名前は、親が Task/Agent ツール入力に付けた description を、到着順によらず採る。
/// task_started が先に届いても、ツール入力の description が無視されない。
@Suite("SubAgent name arrival order")
struct SubAgentNameArrivalOrderTests {
    private static let toolUse =
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_N1","name":"Agent","input":{"subagent_type":"general-purpose","description":"親が付けた名前","prompt":"親の依頼文 PROMPT"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    private static let toolUseWithoutDescription =
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_N1","name":"Agent","input":{"subagent_type":"general-purpose","prompt":"親の依頼文 PROMPT"}}]},"parent_tool_use_id":null,"session_id":"S1"}"#
    private static func taskStarted(_ description: String?) -> String {
        let desc = description.map { #","description":"\#($0)""# } ?? ""
        return #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_N1","task_type":"local_agent","subagent_type":"general-purpose"\#(desc)}"#
    }
    private static let result = #"{"type":"result","subtype":"success","session_id":"S1","result":"done"}"#

    /// 開始イベントを順に並べ、最後に届いた（＝札に効く）description を返す。
    private func names(_ lines: [String]) async throws -> [String] {
        let mock = NameOrderMockTransport()
        let recorder = NameOrderMockRecorder(mock)
        let client = ClaudeChatClient(transportFactory: recorder.makeTransport)
        await client.start()
        var iterator = client.events.makeAsyncIterator()
        for line in lines { mock.receive(line) }
        await mock.close()
        var names: [String] = []
        for _ in 0..<100 {
            guard let event = await iterator.next() else { break }
            if case .subAgentStarted("toolu_N1", _, let description) = event { names.append(description) }
            if case .turnCompleted = event { break }
        }
        return names
    }

    @Test
    func toolInputFirstKeepsParentName() async throws {
        let names = try await names([Self.toolUse, Self.taskStarted("task_started の説明"), Self.result])
        #expect(names == ["親が付けた名前"])
    }

    @Test
    func toolInputAfterTaskStartedStillBecomesTheName() async throws {
        let names = try await names([Self.taskStarted("task_started の説明"), Self.toolUse, Self.result])
        #expect(names.last == "親が付けた名前")
    }

    @Test
    func toolInputAfterTaskStartedWithoutDescriptionStillBecomesTheName() async throws {
        let names = try await names([Self.taskStarted(nil), Self.toolUse, Self.result])
        #expect(names.last == "親が付けた名前")
    }

    @Test
    func toolInputAfterFastCompletionStillBecomesTheName() async throws {
        let completed =
            #"{"type":"system","subtype":"task_notification","task_id":"t1","tool_use_id":"toolu_N1","status":"completed","summary":"done","output_file":"/tmp/none.jsonl"}"#
        let names = try await names([Self.taskStarted("task_started の説明"), completed, Self.toolUse, Self.result])
        #expect(names.last == "親が付けた名前")
    }

    @Test
    func missingToolInputDescriptionNeverBecomesTheParentPromptJSON() async throws {
        let names = try await names([Self.toolUseWithoutDescription, Self.taskStarted("task_started の説明"), Self.result])
        #expect(names.last == "task_started の説明")
        #expect(!names.contains { $0.contains("PROMPT") })
    }
}

// 最小 transport（他テストの private 版は不可視のため自前定義）

private final class NameOrderMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }
}

private final class NameOrderMockRecorder: @unchecked Sendable {
    private let transport: NameOrderMockTransport
    init(_ transport: NameOrderMockTransport) { self.transport = transport }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        transport
    }
}
