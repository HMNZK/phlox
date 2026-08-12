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
        try await waitFor("plan が transcript へ届く") {
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

        transport.receive(backgroundItemStartedNotification(threadID: threadID))
        try await waitFor("background item が transcript へ届く") {
            viewModel.transcriptItemIDs.contains("background-item")
        }
        try await transport.waitForMethod("thread/backgroundTerminals/list")

        let state = try #require(viewModel.codexBackgroundTerminalState)
        try await waitFor("itemStarted 後の background 一覧が VM へ届く") {
            state.items.map(\.itemId) == ["background-item", "other-item"]
        }

        transport.receive(turnCompletedNotification(threadID: threadID))
        try await transport.waitForMethod("thread/backgroundTerminals/list")
        try await waitFor("turnCompleted 後も background 一覧が再読込される") {
            state.items.map(\.itemId) == ["background-item", "other-item"]
        }

        #expect(await transport.methods().filter { $0 == "thread/backgroundTerminals/list" }.count == 2)
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
        #expect(await transport.methods().filter { $0 == "thread/backgroundTerminals/list" }.count == 3)
        #expect(await transport.methods().filter { $0 == "thread/backgroundTerminals/terminate" }.count == 1)

        await client.close()
    }

    @Test("thread/list の空 turns を child read で補完し、遅い古い refresh を捨てる")
    func codexSubAgentRefreshUsesReadAndGenerationGuard() async throws {
        let (viewModel, client, transport) = try await makeStack(subAgentOutOfOrder: true)

        let first = Task { await viewModel.refreshCodexSubAgents() }
        try await transport.waitForMethod("thread/read:child-old")
        let second = Task { await viewModel.refreshCodexSubAgents() }
        await first.value
        await second.value

        let child = try #require(viewModel.codexSubAgentState?.children)
        #expect(child.map(\.id) == ["child-new"])
        #expect(child.first?.activeTurnId == "child-new-turn")
        #expect(await transport.methods().filter { $0 == "thread/read" }.count == 2)

        await viewModel.stopCodexSubAgent(threadID: "child-new")
        #expect(viewModel.codexSubAgentState?.stopState(for: "child-new") == .stopping)
        #expect((await transport.methods()).contains("turn/interrupt"))
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

        let source = try sourceText("CodexSessionSurface.swift")
        #expect(source.contains(#".accessibilityIdentifier("CodexSessionSurface")"#))
        #expect(source.contains(#".accessibilityIdentifier("CodexHistory.row.\(thread.id)")"#))
        #expect(source.contains(#".accessibilityIdentifier("CodexHistory.resume.\(thread.id)")"#))
        #expect(source.contains(#".accessibilityIdentifier("CodexHistory.detail.\(selected.id)")"#))
        #expect(source.contains(#".accessibilityIdentifier("CodexBackgroundTerminal.\(terminal.itemId)")"#))
        #expect(source.contains(#".accessibilityIdentifier("CodexBackgroundTerminal.detail.\(selected.itemId)")"#))
        #expect(source.contains(#"Text(thread.name ?? thread.preview)"#))
        #expect(source.contains(#"Text(terminal.command)"#))
        #expect(source.contains(#"Button("再開")"#))
        #expect(source.contains(#"Button("ジャンプ")"#))
        #expect(source.contains(#"Button("停止")"#))
        #expect(source.contains("history.readIfPossible(threadID: thread.id)"))
        #expect(source.contains("history.resumeIfPossible(threadID: thread.id)"))
        #expect(source.contains("terminals.select(itemId: terminal.itemId)"))
        #expect(source.contains("terminals.stop(itemId: terminal.itemId)"))
        #expect(source.contains("onJump(target)"))
        await client.close()
    }

    private func makeStack() async throws -> (
        ChatSessionViewModel,
        CodexStructuredAgentClient,
        CodexProductionTransport
    ) {
        try await makeStack(subAgentOutOfOrder: false)
    }

    private func makeStack(subAgentOutOfOrder: Bool) async throws -> (
        ChatSessionViewModel,
        CodexStructuredAgentClient,
        CodexProductionTransport
    ) {
        let transport = CodexProductionTransport(cwd: cwd, subAgentOutOfOrder: subAgentOutOfOrder)
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

    private func waitFor(
        _ description: String,
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        guard !condition() else { return }
        let waiter = ObservationWaiter(condition: condition)
        let result = await withTaskGroup(of: AcceptanceWaitRaceResult.self) { group in
            group.addTask {
                await waiter.wait() ? .fulfilled : .cancelled
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let result = await group.next() ?? .cancelled
            group.cancelAll()
            waiter.cancel()
            await group.waitForAll()
            return result
        }
        switch result {
        case .fulfilled:
            return
        case .timedOut:
            throw AcceptanceWaitError.timedOut(description)
        case .cancelled:
            throw AcceptanceWaitError.cancelled
        }
    }

    private func planNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"turn/plan/updated","params":{"threadId":"\(threadID)","turnId":"turn-1","plan":[{"step":"inspect","status":"inProgress"},{"step":"verify","status":"pending"}],"explanation":"check"}}
        """
    }

    private func backgroundItemStartedNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"\(threadID)","turnId":"turn-1","item":{"type":"commandExecution","id":"background-item","itemId":"background-item","processId":"background-process","command":"swift test","cwd":"\(cwd)","text":"background started"}}}
        """
    }

    private func turnCompletedNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"\(threadID)","turn":{"id":"turn-1","status":"completed","items":[]}}}
        """
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private enum AcceptanceWaitError: Error, CustomStringConvertible {
    case timedOut(String)
    case cancelled
    case streamFinished(String)

    var description: String {
        switch self {
        case .timedOut(let description):
            return "Timed out waiting for \(description)"
        case .cancelled:
            return "Observation waiter cancelled before the condition became true"
        case .streamFinished(let description):
            return "Event stream finished before \(description)"
        }
    }
}

private enum AcceptanceWaitRaceResult: Sendable {
    case fulfilled
    case timedOut
    case cancelled
}

@MainActor
private final class ObservationWaiter {
    private let condition: @MainActor () -> Bool
    private let signals: AsyncStream<Void>
    private let signalContinuation: AsyncStream<Void>.Continuation
    private var cancelled = false

    init(condition: @escaping @MainActor () -> Bool) {
        self.condition = condition
        var captured: AsyncStream<Void>.Continuation?
        signals = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { captured = $0 }
        signalContinuation = captured!
    }

    func wait() async -> Bool {
        guard !condition() else { return true }
        arm()
        for await _ in signals {
            guard !cancelled else { return false }
            if condition() { return true }
            arm()
        }
        return !cancelled && condition()
    }

    func cancel() {
        cancelled = true
        signalContinuation.finish()
    }

    private func arm() {
        withObservationTracking {
            _ = condition()
        } onChange: { [self] in
            Task { @MainActor [self] in
                signalContinuation.yield()
            }
        }
    }
}

private final class CodexProductionTransport: AppServerTransport, @unchecked Sendable {
    private actor State {
        private var requests: [JSONValue] = []
        private var terminated = false
        private var subAgentListCalls = 0

        func append(_ request: JSONValue) {
            requests.append(request)
        }

        func methods() -> [String] {
            requests.compactMap { $0["method"]?.stringValue }
        }

        func markTerminated() {
            terminated = true
        }

        func nextSubAgentListCall() -> Int {
            subAgentListCalls += 1
            return subAgentListCalls
        }

        var isTerminated: Bool { terminated }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    let methodEvents: AsyncStream<String>
    private let methodEventContinuation: AsyncStream<String>.Continuation
    private let childNewReadEvents: AsyncStream<Void>
    private let childNewReadEventContinuation: AsyncStream<Void>.Continuation
    private let state = State()
    private let cwd: String
    private let subAgentOutOfOrder: Bool

    init(cwd: String, subAgentOutOfOrder: Bool = false) {
        self.cwd = cwd
        self.subAgentOutOfOrder = subAgentOutOfOrder
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
        var methodCaptured: AsyncStream<String>.Continuation?
        methodEvents = AsyncStream(bufferingPolicy: .unbounded) { methodCaptured = $0 }
        methodEventContinuation = methodCaptured!
        var childNewReadCaptured: AsyncStream<Void>.Continuation?
        childNewReadEvents = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            childNewReadCaptured = $0
        }
        childNewReadEventContinuation = childNewReadCaptured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await state.append(request)

        guard let id = request["id"] else { return }
        let method = request["method"]?.stringValue
        if let method { methodEventContinuation.yield(method) }
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
            if subAgentOutOfOrder,
               request["params"]?["parentThreadId"]?.stringValue == "live-thread" {
                let call = await state.nextSubAgentListCall()
                let childID = call == 1 ? "child-old" : "child-new"
                result = .object([
                    "data": .array([childJSON(id: childID, parent: "live-thread", includeTurns: false)]),
                    "nextCursor": .null,
                ])
            } else {
                result = .object([
                    "data": .array([
                        threadJSON(id: "history-1", name: "first history"),
                        threadJSON(id: "history-2", name: "second history"),
                    ]),
                    "nextCursor": .null,
                ])
            }
        case "thread/read":
            let threadID = request["params"]?["threadId"]?.stringValue ?? "history-1"
            if subAgentOutOfOrder, threadID == "child-old" || threadID == "child-new" {
                if threadID == "child-old" {
                    methodEventContinuation.yield("thread/read:child-old")
                    for await _ in childNewReadEvents { break }
                } else {
                    childNewReadEventContinuation.yield()
                }
                result = .object(["thread": childJSON(id: threadID, parent: "live-thread", includeTurns: true)])
            } else {
                result = .object(["thread": threadJSON(id: threadID, includeHistoryItems: true)])
            }
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
        methodEventContinuation.finish()
        childNewReadEventContinuation.finish()
    }

    func receive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }

    func methods() async -> [String] {
        await state.methods()
    }

    func waitForMethod(
        _ method: String,
        timeout: Duration = .seconds(2)
    ) async throws {
        let result = await withTaskGroup(of: AcceptanceWaitRaceResult.self) { group in
            group.addTask { [methodEvents] in
                for await received in methodEvents {
                    if received == method { return .fulfilled }
                }
                return .cancelled
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let result = await group.next() ?? .cancelled
            group.cancelAll()
            await group.waitForAll()
            return result
        }
        switch result {
        case .fulfilled:
            return
        case .timedOut:
            throw AcceptanceWaitError.timedOut(method)
        case .cancelled:
            throw AcceptanceWaitError.streamFinished(method)
        }
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

    private func childJSON(id: String, parent: String, includeTurns: Bool) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string(cwd),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string(id),
            "sessionId": .string("session-(id)"),
            "source": .object(["subAgent": .object(["parentThreadId": .string(parent)])]),
            "status": .object(["type": .string("active"), "activeFlags": .array([])]),
            "turns": .array([]),
            "updatedAt": .number(2),
            "parentThreadId": .string(parent),
            "canAcceptDirectInput": .bool(false),
        ]
        if includeTurns {
            object["turns"] = .array([.object([
                "id": .string("\(id)-turn"),
                "status": .string("inProgress"),
                "items": .array([]),
            ])])
        }
        return .object(object)
    }
}
