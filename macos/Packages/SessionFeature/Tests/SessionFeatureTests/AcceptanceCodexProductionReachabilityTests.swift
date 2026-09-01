import Foundation
import Observation
import AppKit
import ApplicationServices
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// Codex の本番構成（app-server transport → structured client → ViewModel）を通し、
/// 履歴・plan の既存 surface が実際の状態を受け取れることを検査する。
@Suite("Acceptance: Codex production reachability")
@MainActor
struct AcceptanceCodexProductionReachabilityTests {
    private let cwd = "/workspace/codex"

    @Test("orderedEvents は実 Codex client から VM の plan と transcript へ同順で届く")
    func orderedEventsReachPlanStateAndTranscript() async throws {
        try await withStack { viewModel, _, transport in
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
            try await waitFor("commandExecution item が transcript へ届く") {
                viewModel.transcriptItemIDs.contains("background-item")
            }
        }
    }

    @Test("thread/list の空 turns を child read で補完し、遅い古い refresh を捨てる")
    func codexSubAgentRefreshUsesReadAndGenerationGuard() async throws {
        try await withStack(subAgentOutOfOrder: true) { viewModel, _, transport in
            let first = Task { await viewModel.refreshCodexSubAgents() }
            try await withTaskCleanup(first) {
                try await transport.waitForMethod("thread/read:child-old")
                let second = Task { await viewModel.refreshCodexSubAgents() }
                try await withTaskCleanup(second) {
                    await first.value
                    await second.value

                    let child = try #require(viewModel.codexSubAgentState?.children)
                    #expect(child.map(\.id) == ["child-new"])
                    #expect(child.first?.activeTurnId == "child-new-turn")
                    #expect(await transport.methods().filter { $0 == "thread/read" }.count == 2)

                    await viewModel.stopCodexSubAgent(threadID: "child-new")
                    #expect(viewModel.codexSubAgentState?.stopState(for: "child-new") == .stopping)
                    #expect((await transport.methods()).contains("turn/interrupt"))
                }
            }
        }
    }

    @Test("CodexSessionSurface は実状態の plan/subagent を識別できる")
    func codexSessionSurfaceExposesProductionStateAndActions() async throws {
        try await withStack(subAgentOutOfOrder: true) { viewModel, _, transport in
            let threadID = try #require(viewModel.threadId)
            transport.receive(planNotification(threadID: threadID))
            try await waitFor("surface plan state") {
                viewModel.codexPlanTaskState?.tasks.map(\.title) == ["inspect", "verify"]
            }

            let firstRefresh = Task { await viewModel.refreshCodexSubAgents() }
            try await withTaskCleanup(firstRefresh) {
                try await transport.waitForMethod("thread/read:child-old")
                let secondRefresh = Task { await viewModel.refreshCodexSubAgents() }
                try await withTaskCleanup(secondRefresh) {
                    await firstRefresh.value
                    await secondRefresh.value
                    let child = try #require(viewModel.codexSubAgentState?.children.first)
                    #expect(child.id == "child-new")
                    await viewModel.loadCodexSubAgentDetail(threadID: child.id)
                    let childDetail = try #require(viewModel.codexSubAgentState?.detail(for: child.id))

                    #expect(viewModel.codexPlanTaskState?.tasks.map(\.title) == ["inspect", "verify"])
                    #expect(child.summary == "child-new")
                    #expect(childDetail.threadId == child.id)

                    let surface = CodexSessionSurface(viewModel: viewModel)
                        .accessibilityElement(children: .contain)
                    let app = NSApplication.shared
                    app.setActivationPolicy(.prohibited)
                    app.finishLaunching()
                    let hosting = NSHostingView(rootView: surface)
                    hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 720)
                    let window = NSWindow(
                        contentRect: hosting.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    window.isReleasedWhenClosed = false
                    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                    window.alphaValue = 0
                    window.contentView = hosting
                    defer { window.close() }
                    window.orderBack(nil)
                    settleHeadlessView(hosting)

                    let elements = axElements(in: app)
                    let expectedIdentifiers = [
                        "CodexSessionSurface",
                        "CodexPlanTaskList",
                        "CodexSubAgent.\(child.id)",
                    ]
                    for identifier in expectedIdentifiers {
                        #expect(
                            elements.contains { $0.identifier == identifier },
                            "実ランタイムAXツリーに identifier がない: \(identifier)"
                        )
                    }
                    #expect(elements.contains { $0.identifier?.hasPrefix("CodexBackgroundTerminal.") == true } == false)
                    let displayedText = Set(elements.flatMap { [$0.title, $0.value, $0.description].compactMap { $0 } })
                    #expect(displayedText.contains { $0.contains("inspect") })
                    #expect(displayedText.contains { $0.contains("child-new") })

                }
            }
        }
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
        do {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
        } catch {
            await viewModel.terminate()
            await client.close()
            throw error
        }
        return (viewModel, client, transport)
    }

    private func withStack(
        subAgentOutOfOrder: Bool = false,
        _ body: @MainActor (
            ChatSessionViewModel,
            CodexStructuredAgentClient,
            CodexProductionTransport
        ) async throws -> Void
    ) async throws {
        let (viewModel, client, transport) = try await makeStack(
            subAgentOutOfOrder: subAgentOutOfOrder
        )
        do {
            try await body(viewModel, client, transport)
        } catch {
            await viewModel.terminate()
            await client.close()
            throw error
        }
        await viewModel.terminate()
        await client.close()
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

    private func withTaskCleanup<Value, Result>(
        _ task: Task<Value, Never>,
        operation: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation()
        } catch {
            task.cancel()
            _ = await task.value
            throw error
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

}

@MainActor
private func settleHeadlessView(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    for _ in 0..<3 {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        view.layoutSubtreeIfNeeded()
    }
}

private struct AXTestElement {
    let identifier: String?
    let title: String?
    let value: String?
    let description: String?
    let role: String?
}

@MainActor
private func axElements(in app: NSApplication) -> [AXTestElement] {
    let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    let windows = axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.flatMap(axElements(in:))
}

private func axElements(in element: AXUIElement) -> [AXTestElement] {
    let result = AXTestElement(
        identifier: axValue(element, kAXIdentifierAttribute) as? String,
        title: axValue(element, kAXTitleAttribute) as? String,
        value: axValue(element, kAXValueAttribute) as? String,
        description: axValue(element, kAXDescriptionAttribute) as? String,
        role: axValue(element, kAXRoleAttribute) as? String
    )
    let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [result] + children.flatMap(axElements(in:))
}

private func axValue(_ element: AXUIElement, _ attribute: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
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

final class CodexProductionTransport: AppServerTransport, @unchecked Sendable {
    private actor State {
        private var requests: [JSONValue] = []
        private var subAgentListCalls = 0
        private var skillListResponses: [JSONValue]
        private var skillListCalls = 0

        init(skillListResponses: [JSONValue]) {
            self.skillListResponses = skillListResponses
        }

        func append(_ request: JSONValue) {
            requests.append(request)
        }

        func methods() -> [String] {
            requests.compactMap { $0["method"]?.stringValue }
        }

        func nextSubAgentListCall() -> Int {
            subAgentListCalls += 1
            return subAgentListCalls
        }

        func nextSkillListResponse() -> JSONValue? {
            guard !skillListResponses.isEmpty else { return nil }
            let index = min(skillListCalls, skillListResponses.count - 1)
            skillListCalls += 1
            return skillListResponses[index]
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    let methodEvents: AsyncStream<String>
    private let methodEventContinuation: AsyncStream<String>.Continuation
    private let childNewReadEvents: AsyncStream<Void>
    private let childNewReadEventContinuation: AsyncStream<Void>.Continuation
    private let state: State
    private let cwd: String
    private let subAgentOutOfOrder: Bool

    init(
        cwd: String,
        subAgentOutOfOrder: Bool = false,
        skillListResponses: [JSONValue] = []
    ) {
        self.cwd = cwd
        self.subAgentOutOfOrder = subAgentOutOfOrder
        self.state = State(skillListResponses: skillListResponses)
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
            result = await state.nextSkillListResponse()
                ?? .object(["data": .array([])])
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
                "items": .array([.object([
                    "id": .string("\(id)-item"),
                    "type": .string("agentMessage"),
                    "text": .string("\(id) detail"),
                ])]),
            ])])
        }
        return .object(object)
    }
}
