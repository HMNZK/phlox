import Foundation
import Testing
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// task-10 が公開する plan DTO/event と既存 AgentTaskItem への写像を固定する。
@Suite("Contract: Codex plan event seam")
struct ContractCodexPlanEventSeamTests {
    @Test("実 JSON-RPC plan 通知は typed event で thread/turn と順序を保持する")
    func updatePreservesIdentityAndOrder() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "turn/plan/updated",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "plan": .array([
                    .object(["step": .string("確認"), "status": .string("pending")]),
                ]),
                "explanation": .string("説明"),
            ])
        )

        guard case .planUpdated(let threadId, let turnId, let plan, let explanation)? = event else {
            Issue.record("turn/plan/updated が CodexAppServerClient.events の typed event になっていない")
            return
        }
        #expect(threadId == "thread-1")
        #expect(turnId == "turn-1")
        #expect(plan == [TurnPlanStep(step: "確認", status: .pending)])
        #expect(explanation == "説明")
    }

    @Test("typed plan event の status を既存 AgentTaskItem へ正規化する")
    func statusMappingUsesExistingTaskType() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "turn/plan/updated",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "plan": .array([
                    .object(["step": .string("p"), "status": .string("pending")]),
                    .object(["step": .string("i"), "status": .string("inProgress")]),
                    .object(["step": .string("c"), "status": .string("completed")]),
                ]),
            ])
        )

        guard let event, case .planUpdated = event else {
            Issue.record("typed plan event が取得できない")
            return
        }
        guard case .taskListUpdated(let tasks)? = CodexStructuredAgentClient.normalizedEvent(from: event) else {
            Issue.record("plan event が task-list normalized event に変換されていない")
            return
        }
        #expect(tasks.map(\.status) == [.pending, .inProgress, .completed])
        #expect(tasks.map(\.title) == ["p", "i", "c"])
        #expect(tasks.map(\.id) == ["codex-plan-0-p", "codex-plan-1-i", "codex-plan-2-c"])
    }

    @Test("typed plan event の未知 status は task item を部分生成しない")
    func unknownStatusDoesNotPartiallyApply() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "turn/plan/updated",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "plan": .array([
                    .object(["step": .string("不明"), "status": .string("unknown")]),
                ]),
            ])
        )

        guard let event, case .planUpdated = event else {
            Issue.record("typed plan event が取得できない")
            return
        }
        guard case .taskListUpdated(let tasks)? = CodexStructuredAgentClient.normalizedEvent(from: event) else {
            Issue.record("未知 status の plan event が task-list event に変換されていない")
            return
        }
        #expect(tasks.isEmpty)
    }

    @Test("normalized event の出力は既存 AgentTaskItem collection である")
    func outputIsTheExistingAgentTaskItemCollection() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "turn/plan/updated",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "plan": .array([
                    .object(["step": .string("既存型"), "status": .string("completed")]),
                ]),
            ])
        )

        guard let event, case .planUpdated = event else {
            Issue.record("typed plan event が取得できない")
            return
        }
        guard case .taskListUpdated(let tasks)? = CodexStructuredAgentClient.normalizedEvent(from: event) else {
            Issue.record("plan event が task-list normalized event に変換されていない")
            return
        }
        #expect(tasks == [AgentTaskItem(id: "codex-plan-0-既存型", title: "既存型", status: .completed)])
    }
}

/// SessionFeature 側にも transport fake を再実装せず、CodexAppServerClient の実受信経路を使う。
final class CodexPlanSkillFakeTransport: AppServerTransport, @unchecked Sendable {
    private actor Recorder {
        private var messages: [JSONValue] = []

        func append(_ message: JSONValue) {
            messages.append(message)
        }

        func first(method: String) -> JSONValue? {
            messages.first { $0["method"]?.stringValue == method }
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let recorder = Recorder()
    private let skillsListResult: JSONValue

    init(skillsListResult: JSONValue = .object(["data": .array([])])) {
        self.skillsListResult = skillsListResult
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await recorder.append(request)

        guard let id = request["id"]?.intValue else { return }
        let result = request["method"]?.stringValue == "skills/list"
            ? skillsListResult
            : .object([:])
        let response: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ message: JSONValue) throws {
        continuation.yield(try JSONEncoder().encode(message))
    }

    func firstRequest(method: String) async -> JSONValue? {
        await recorder.first(method: method)
    }
}

func receiveCodexThreadEvent(method: String, params: JSONValue) async throws -> ThreadEvent? {
    let transport = CodexPlanSkillFakeTransport()
    let client = CodexAppServerClient(transport: transport)
    do {
        await client.start()

        let eventTask = Task { await firstCodexThreadEvent(from: client.events) }
        do {
            try transport.receive(.object([
                "jsonrpc": .string("2.0"),
                "method": .string(method),
                "params": params,
            ]))
        } catch {
            eventTask.cancel()
            _ = await eventTask.value
            await client.close()
            throw error
        }
        let event = await eventTask.value
        await client.close()
        return event
    } catch {
        await client.close()
        throw error
    }
}

func firstCodexThreadEvent(from events: AsyncStream<ThreadEvent>) async -> ThreadEvent? {
    await withTaskGroup(of: ThreadEvent?.self) { group in
        group.addTask {
            for await event in events {
                return event
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
