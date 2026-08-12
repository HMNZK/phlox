import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Regression: Codex child history isolation")
@MainActor
struct CodexChildHistoryIsolationTests {
    @Test("child一覧は正式 sourceKinds と direct parent/source identity で隔離する")
    func childListExcludesForeignAncestorRootAndHistoryThreads() async throws {
        let transport = ChildHistoryIsolationTransport(parentID: "live-parent")
        let appServer = CodexAppServerClient(transport: transport)
        let client = CodexStructuredAgentClient(client: appServer)
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/workspace"
        )
        try await viewModel.startNew(
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        await viewModel.refreshCodexSubAgents()

        #expect(viewModel.codexSubAgentState?.children.map(\.id) == ["direct-review", "direct-spawn"])
        #expect(await transport.listParams == JSONValue.object([
            "sourceKinds": .array([
                .string("subAgent"),
                .string("subAgentReview"),
                .string("subAgentCompact"),
                .string("subAgentThreadSpawn"),
                .string("subAgentOther"),
            ]),
            "parentThreadId": .string("live-parent"),
        ]))

        await viewModel.terminate()
        await client.close()
    }
}

private final class ChildHistoryIsolationTransport: AppServerTransport, @unchecked Sendable {
    private actor State {
        var listParams: JSONValue?

        func recordListParams(_ params: JSONValue?) {
            listParams = params
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let state = State()
    private let parentID: String

    init(parentID: String) {
        self.parentID = parentID
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
    }

    var listParams: JSONValue? {
        get async { await state.listParams }
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        guard let id = request["id"] else { return }
        let method = request["method"]?.stringValue
        let result: JSONValue
        switch method {
        case "initialize":
            result = .object([
                "codexHome": .string("/tmp/codex-home"),
                "platformFamily": .string("macOS"),
                "platformOs": .string("macOS"),
                "userAgent": .string("child-isolation-test"),
            ])
        case "thread/start":
            result = .object(["thread": threadJSON(id: parentID, source: .string("appServer"))])
        case "thread/list":
            await state.recordListParams(request["params"])
            result = .object([
                "data": .array([
                    threadJSON(id: "direct-review", source: .string("review"), parent: parentID),
                    threadJSON(
                        id: "direct-spawn",
                        source: .object(["thread_spawn": .object([
                            "parent_thread_id": .string(parentID),
                            "depth": .number(1),
                        ])]),
                        parent: parentID
                    ),
                    threadJSON(id: "foreign-parent", source: .string("review"), parent: "other-parent"),
                    threadJSON(
                        id: "ancestor-only",
                        source: .object(["thread_spawn": .object([
                            "parent_thread_id": .string("other-parent"),
                            "depth": .number(2),
                        ])]),
                        parent: parentID
                    ),
                    threadJSON(
                        id: "ancestor-mismatch",
                        source: .object(["thread_spawn": .object([
                            "parent_thread_id": .string(parentID),
                            "ancestor_thread_id": .string("other-root"),
                            "depth": .number(2),
                        ])]),
                        parent: parentID
                    ),
                    threadJSON(id: "root", source: .string("appServer")),
                    threadJSON(id: "history", source: .string("cli")),
                    threadJSON(
                        id: "unknown-subagent",
                        source: .object(["unrecognized": .string("source")]),
                        parent: parentID
                    ),
                ]),
                "nextCursor": .null,
            ])
        case "thread/read":
            let threadID = request["params"]?["threadId"]?.stringValue ?? ""
            result = .object(["thread": threadJSON(id: threadID, source: .string("review"), parent: parentID)])
        case "model/list", "permissionProfile/list", "collaborationMode/list", "skills/list":
            result = .object(["data": .array([])])
        default:
            result = .object([:])
        }

        continuation.yield(try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])))
    }

    func close() async {
        continuation.finish()
    }

    private func threadJSON(
        id: String,
        source: JSONValue,
        parent: String? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string("/workspace"),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string(id),
            "sessionId": .string("session-\(id)"),
            "source": .object(["subAgent": source]),
            "status": .object(["type": .string("idle")]),
            "turns": .array([]),
            "updatedAt": .number(2),
        ]
        if id == parentID {
            object["source"] = .string("appServer")
        }
        if let parent { object["parentThreadId"] = .string(parent) }
        return .object(object)
    }
}
