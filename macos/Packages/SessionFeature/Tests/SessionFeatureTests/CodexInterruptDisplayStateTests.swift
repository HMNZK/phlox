import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Regression: Codex interrupt display state")
@MainActor
struct CodexInterruptDisplayStateTests {
    @Test("停止受理後の子の実報告でスピナーを消し、親の完了には混入しない", arguments: ["completed", "failed", "interrupted"])
    func childCompletionClearsProcessingIndicator(status: String) async throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".verification/session-activity-state/codex-display-\(status)").path
        let transport = InterruptDisplayTransport(directory: directory)
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        let viewModel = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: directory
        )
        var notificationRequests = 0
        viewModel.userNotificationGate = { _ in
            notificationRequests += 1
            return false
        }
        do {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"), sandbox: .named("workspace-write")
            )
            await viewModel.refreshCodexSubAgents()
            #expect(viewModel.codexSubAgentState?.children.map(\.id) == ["child"])
            #expect(viewModel.showsProcessingIndicator)

            try transport.turnEvent("turn/started", threadID: "parent", status: "inProgress")
            try await waitFor { viewModel.status == .running }
            await viewModel.turnInterrupt()

            #expect(transport.interruptedIDs == ["parent", "child"])
            #expect(viewModel.status == .idle)
            #expect(viewModel.codexSubAgentState?.children.first?.status == "active")
            #expect(viewModel.showsProcessingIndicator)
            #expect(viewModel.displayStatus == .running)
            #expect(!viewModel.hasUnseenCompletion)
            let completedParentTurns = viewModel.completedTurnSeq

            try transport.turnEvent("turn/completed", threadID: "child", status: status)
            try await waitFor { viewModel.codexSubAgentState?.children.first?.status == status }

            #expect(!viewModel.showsProcessingIndicator)
            #expect(viewModel.displayStatus == .idle)
            #expect(viewModel.completedTurnSeq == completedParentTurns)
            #expect(!viewModel.hasUnseenCompletion)
            #expect(notificationRequests == 0)

            try transport.turnEvent("turn/completed", threadID: "parent", status: "interrupted")
            try transport.turnEvent("turn/started", threadID: "parent", status: "inProgress", turnID: "next-parent-turn")
            try await waitFor { viewModel.status == .running }
            try transport.turnEvent("turn/completed", threadID: "parent", status: "completed", turnID: "next-parent-turn")
            try await waitFor { viewModel.hasUnseenCompletion }
            #expect(viewModel.completedTurnSeq == completedParentTurns + 1)
            #expect(notificationRequests == 2)
        } catch {
            print("Codex display failure \(error), thread=\(String(describing: viewModel.threadId)), status=\(viewModel.status), children=\(String(describing: viewModel.codexSubAgentState?.children)), turns=\(viewModel.completedTurnSeq), notifications=\(notificationRequests), events=\(viewModel.rawEventLog)")
            await viewModel.terminate()
            await client.close()
            throw error
        }
        await viewModel.terminate()
        await client.close()
    }

    private func waitFor(line: Int = #line, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw DisplayStateTimeout(line: line)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct DisplayStateTimeout: Error { let line: Int }

private final class InterruptDisplayTransport: AppServerTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let directory: String
    private let lock = NSLock()
    private var interrupts: [String] = []

    var interruptedIDs: [String] { lock.withLock { interrupts } }

    init(directory: String) {
        self.directory = directory
        let stream = AsyncStream<Data>.makeStream()
        receivedLines = stream.stream
        continuation = stream.continuation
    }

    func send(_ data: Data) async throws {
        let request = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let id = request["id"] else { return }
        let params = request["params"]
        let result: JSONValue
        switch request["method"]?.stringValue {
        case "initialize":
            result = .object([
                "codexHome": .string(directory), "platformFamily": .string("macOS"),
                "platformOs": .string("macOS"), "userAgent": .string("interrupt-display-test"),
            ])
        case "thread/start":
            result = .object(["thread": thread("parent")])
        case "thread/list":
            result = .object([
                "data": .array(params?["parentThreadId"]?.stringValue == "parent" ? [thread("child")] : []),
                "nextCursor": .null,
            ])
        case "thread/read":
            result = .object(["thread": thread(params?["threadId"]?.stringValue ?? "")])
        case "turn/interrupt":
            let threadID = params?["threadId"]?.stringValue ?? ""
            #expect(params?["turnId"] == .string("turn-\(threadID)"))
            lock.withLock { interrupts.append(threadID) }
            result = .object([:])
        case "model/list", "permissionProfile/list", "collaborationMode/list", "skills/list":
            result = .object(["data": .array([])])
        default:
            Issue.record("予期しない AppServer リクエスト: \(String(describing: request["method"]))")
            result = .object([:])
        }
        continuation.yield(try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": id, "result": result,
        ])))
    }

    func turnEvent(_ method: String, threadID: String, status: String, turnID: String? = nil) throws {
        continuation.yield(try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "method": .string(method),
            "params": .object([
                "threadId": .string(threadID),
                "turn": .object(["id": .string(turnID ?? "turn-\(threadID)"), "status": .string(status)]),
            ]),
        ])))
    }

    func close() async { continuation.finish() }

    private func thread(_ id: String) -> JSONValue {
        let isChild = id == "child"
        var fields: [String: JSONValue] = [
            "id": .string(id), "cwd": .string(directory), "preview": .string(id),
            "status": .object(["type": .string(isChild ? "active" : "idle")]),
            "source": isChild
                ? .object(["subAgent": .object(["thread_spawn": .object(["parent_thread_id": .string("parent")])])])
                : .string("appServer"),
            "turns": .array(isChild ? [.object(["id": .string("turn-child"), "status": .string("inProgress")])] : []),
        ]
        if isChild { fields["parentThreadId"] = .string("parent") }
        return .object(fields)
    }
}
