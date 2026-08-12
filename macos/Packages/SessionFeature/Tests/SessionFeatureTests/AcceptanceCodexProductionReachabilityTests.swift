import Foundation
import Observation
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// Codex の本番構成（app-server transport → structured client → ViewModel）を通し、
/// 履歴・plan・背景端末の既存 surface が実際の状態を受け取れることを検査する。
@Suite("Acceptance: Codex production reachability")
@MainActor
struct AcceptanceCodexProductionReachabilityTests {
    private let cwd = "/workspace/codex"

    @Test("Codex 履歴は一覧・詳細・再開後の reload まで同じ thread ID を保つ")
    func codexHistoryListDetailResumeAndReloadUseProductionClient() async throws {
        let (viewModel, client, transport) = try await makeStack()
        let history = try #require(viewModel.codexSessionHistory)

        await history.refresh()
        #expect(history.entries.map(\.id) == ["history-1", "history-2"])
        #expect(history.select(threadID: "history-2"))

        let detail = try #require(try await history.readSelected())
        #expect(detail.id == "history-2")
        #expect(viewModel.codexHistoryItems(for: detail).map(\.id) == ["history-user", "history-agent"])

        _ = try await history.resume(threadID: "history-2")
        await viewModel.reloadCodexHistory(threadID: "history-2")

        #expect(viewModel.threadId == "history-2")
        #expect(viewModel.codexSessionHistory?.selectedThreadID == "history-2")
        #expect(viewModel.codexBackgroundTerminalState?.threadId == "history-2")
        #expect(await transport.methods().filter { $0 == "thread/resume" }.count == 1)
        #expect(await transport.methods().filter { $0 == "thread/read" }.count == 2)

        await client.close()
    }

    @Test("orderedEvents は実 Codex client から VM の plan と transcript へ同順で届く")
    func orderedEventsReachPlanStateAndTranscript() async throws {
        let (viewModel, client, transport) = try await makeStack()
        let threadID = try #require(viewModel.threadId)

        transport.receive(planNotification(threadID: threadID))
        await waitFor {
            viewModel.transcript.contains { item in
                guard case .taskList = item else { return false }
                return true
            }
        }

        #expect(viewModel.codexPlanTaskState?.threadId == threadID)
        #expect(viewModel.codexPlanTaskState?.turnId == "turn-1")
        #expect(viewModel.codexPlanTaskState?.tasks.map(\.title) == ["inspect", "verify"])
        #expect(viewModel.transcript.contains { item in
            guard case .taskList(_, let tasks, _) = item else { return false }
            return tasks.map(\.status) == [.inProgress, .pending]
        })

        transport.receive(backgroundItemCompletedNotification(threadID: threadID))
        await waitFor { viewModel.transcriptItemIDs.contains("background-item") }

        let state = try #require(viewModel.codexBackgroundTerminalState)
        await state.refresh()
        #expect(state.items.map(\.itemId) == ["background-item", "other-item"])
        #expect(state.items.first?.processId == "background-process")
        #expect(state.select(itemId: "background-item"))
        #expect(state.selectedTerminal?.command == "swift test")
        #expect(state.detail(for: "background-item")?.cwd == cwd)
        #expect(state.jumpTarget(
            for: "background-item",
            transcriptItemIds: viewModel.transcriptItemIDs
        ) == "background-item")
        #expect(state.jumpTarget(for: "missing-item", transcriptItemIds: viewModel.transcriptItemIDs) == nil)

        #expect(await state.stop(itemId: "background-item"))
        #expect(state.items.map(\.itemId) == ["other-item"])
        #expect(await transport.methods().filter { $0 == "thread/backgroundTerminals/list" }.count == 2)
        #expect(await transport.methods().filter { $0 == "thread/backgroundTerminals/terminate" }.count == 1)

        await client.close()
    }

    @Test("CodexSessionSurface は履歴・背景端末の本番状態を描画できる")
    func codexSessionSurfaceRendersProductionState() async throws {
        let (viewModel, client, _) = try await makeStack()
        let history = try #require(viewModel.codexSessionHistory)
        await history.refresh()
        #expect(history.select(threadID: "history-1"))
        _ = try await history.read(threadID: "history-1")

        let state = try #require(viewModel.codexBackgroundTerminalState)
        await state.refresh()
        #expect(state.select(itemId: "background-item"))

        let renderer = ImageRenderer(
            content: CodexSessionSurface(viewModel: viewModel, onJump: { _ in })
                .frame(width: 720, height: 360)
        )
        #expect(try #require(renderer.nsImage).size.width > 0)
        await client.close()
    }

    private func makeStack() async throws -> (
        ChatSessionViewModel,
        CodexStructuredAgentClient,
        CodexProductionTransport
    ) {
        let transport = CodexProductionTransport(cwd: cwd)
        let appServer = CodexAppServerClient(transport: transport)
        let client = CodexStructuredAgentClient(client: appServer)
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: cwd
        )
        try await viewModel.startNew(
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        return (viewModel, client, transport)
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async {
        guard !condition() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = ObservationWaiter(condition: condition, continuation: continuation)
            waiter.arm()
        }
    }

    private func planNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"turn/plan/updated","params":{"threadId":"\(threadID)","turnId":"turn-1","plan":[{"step":"inspect","status":"inProgress"},{"step":"verify","status":"pending"}],"explanation":"check"}}
        """
    }

    private func backgroundItemCompletedNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"\(threadID)","turnId":"turn-1","item":{"type":"backgroundTerminal","id":"background-item","itemId":"background-item","text":"completed"}}}
        """
    }
}

@MainActor
private final class ObservationWaiter {
    private let condition: @MainActor () -> Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false

    init(
        condition: @escaping @MainActor () -> Bool,
        continuation: CheckedContinuation<Void, Never>
    ) {
        self.condition = condition
        self.continuation = continuation
    }

    func arm() {
        guard !resumed else { return }
        if condition() {
            resumed = true
            continuation?.resume()
            continuation = nil
            return
        }
        withObservationTracking {
            _ = condition()
        } onChange: { [self] in
            Task { @MainActor [self] in
                arm()
            }
        }
    }
}

private final class CodexProductionTransport: AppServerTransport, @unchecked Sendable {
    private actor State {
        private var requests: [JSONValue] = []
        private var terminated = false

        func append(_ request: JSONValue) {
            requests.append(request)
        }

        func methods() -> [String] {
            requests.compactMap { $0["method"]?.stringValue }
        }

        func markTerminated() {
            terminated = true
        }

        var isTerminated: Bool { terminated }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let state = State()
    private let cwd: String

    init(cwd: String) {
        self.cwd = cwd
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await state.append(request)

        guard let id = request["id"] else { return }
        let method = request["method"]?.stringValue
        let result: JSONValue
        switch method {
        case "initialize":
            result = .object([
                "codexHome": .string("/tmp/codex-home"),
                "platformFamily": .string("macOS"),
                "platformOs": .string("macOS"),
                "userAgent": .string("codex-production-test"),
            ])
        case "thread/start", "thread/resume":
            let threadID = method == "thread/start"
                ? "live-thread"
                : request["params"]?["threadId"]?.stringValue ?? "history-1"
            result = .object(["thread": threadJSON(id: threadID)])
        case "thread/list":
            result = .object([
                "data": .array([
                    threadJSON(id: "history-1", name: "first history"),
                    threadJSON(id: "history-2", name: "second history"),
                ]),
                "nextCursor": .null,
            ])
        case "thread/read":
            let threadID = request["params"]?["threadId"]?.stringValue ?? "history-1"
            result = .object(["thread": threadJSON(id: threadID, includeHistoryItems: true)])
        case "model/list":
            result = .object(["data": .array([.object([
                "id": .string("gpt-5-codex"),
                "displayName": .string("GPT-5 Codex"),
                "description": .string(""),
                "hidden": .bool(false),
                "supportedReasoningEfforts": .array([.string("medium")]),
                "defaultReasoningEffort": .string("medium"),
                "isDefault": .bool(true),
            ])])])
        case "permissionProfile/list", "collaborationMode/list":
            result = .object(["data": .array([])])
        case "skills/list":
            result = .object(["data": .array([])])
        case "thread/backgroundTerminals/list":
            result = await state.isTerminated
                ? .object(["data": .array([.object([
                    "itemId": .string("other-item"),
                    "processId": .string("other-process"),
                    "command": .string("swift build"),
                    "cwd": .string(cwd),
                ])]), "nextCursor": .null])
                : .object(["data": .array([
                    .object([
                        "itemId": .string("background-item"),
                        "processId": .string("background-process"),
                        "command": .string("swift test"),
                        "cwd": .string(cwd),
                    ]),
                    .object([
                        "itemId": .string("other-item"),
                        "processId": .string("other-process"),
                        "command": .string("swift build"),
                        "cwd": .string(cwd),
                    ]),
                ]), "nextCursor": .null])
        case "thread/backgroundTerminals/terminate":
            await state.markTerminated()
            result = .object(["terminated": .bool(true)])
        default:
            result = .object([:])
        }

        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }

    func methods() async -> [String] {
        await state.methods()
    }

    private func threadJSON(
        id: String,
        name: String? = nil,
        includeHistoryItems: Bool = false
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string(cwd),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string(name ?? id),
            "sessionId": .string("session-(id)"),
            "source": .string("appServer"),
            "status": .object(["type": .string("idle")]),
            "turns": .array([]),
            "updatedAt": .number(2),
        ]
        if let name { object["name"] = .string(name) }
        if includeHistoryItems {
            object["turns"] = .array([.object([
                "id": .string("turn-history"),
                "status": .string("completed"),
                "items": .array([
                    .object([
                        "id": .string("history-user"),
                        "type": .string("userMessage"),
                        "text": .string("past question"),
                    ]),
                    .object([
                        "id": .string("history-agent"),
                        "type": .string("agentMessage"),
                        "text": .string("past answer"),
                    ]),
                ]),
            ])])
        }
        return .object(object)
    }
}
