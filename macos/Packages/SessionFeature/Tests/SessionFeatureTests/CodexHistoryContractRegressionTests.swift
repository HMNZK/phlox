import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import SessionFeature

@Suite("Regression: Codex history contracts")
@MainActor
struct CodexHistoryContractRegressionTests {
    @Test("repeated nextCursor は有限回で停止し明示エラーを残す")
    func repeatedCursorStopsRefresh() async throws {
        let transport = HistoryContractTransport(mode: .repeatedCursor)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        await history.refresh()

        #expect(await transport.listRequestCount == 2)
        #expect(history.threads.isEmpty)
        #expect(history.errorMessage?.contains("repeated nextCursor") == true)
        await client.close()
    }

    @Test("response の parent/source を検査し main thread だけを保持する")
    func responseFiltersChildrenAndPreservesSource() async throws {
        let transport = HistoryContractTransport(mode: .mixedSources)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        let history = CodexSessionHistory(client: client, workingDirectory: "/workspace")

        await history.refresh()

        #expect(history.threads.map(\.id) == ["main-cli"])
        #expect(history.threads.first?.source == .cli)
        #expect(history.threads.first?.source.displayName == "CLI")
        await client.close()
    }

    @Test("resume と read が一体で失敗した場合は元 active thread を保持する")
    func failedResumeReadKeepsActiveThread() async throws {
        let transport = HistoryContractTransport(mode: .readFailure)
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams(cwd: "/workspace"))
        let history = CodexSessionHistory(client: adapter, workingDirectory: "/workspace")

        #expect(await adapter.activeThreadId() == "active")
        #expect(await history.resumeIfPossible(threadID: "next") == nil)
        #expect(await adapter.activeThreadId() == "active")
        #expect(history.errorMessage?.contains("read failed") == true)
        await adapter.close()
    }

    @Test("raw resume 後の read 失敗でも adapter の active thread を元へ戻す")
    func failedRawResumeReadRollsBackActiveThread() async throws {
        let transport = HistoryContractTransport(mode: .readFailure)
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams(cwd: "/workspace"))
        let history = CodexSessionHistory(client: adapter, workingDirectory: "/workspace")

        _ = try await history.resume(threadID: "next")
        #expect(await adapter.activeThreadId() == "next")
        #expect(await history.readIfPossible(threadID: "next") == nil)
        #expect(await adapter.activeThreadId() == "active")

        _ = try await history.resume(threadID: "next-again")
        #expect(await adapter.activeThreadId() == "next-again")
        #expect(await history.readIfPossible(threadID: "next-again") == nil)
        #expect(await adapter.activeThreadId() == "active")
        await adapter.close()
    }

    @Test("Codex restore の read 失敗は VM と adapter の元 identity を保持する")
    func failedRestoreKeepsViewModelIdentity() async throws {
        let transport = HistoryContractTransport(mode: .readFailure)
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: adapter,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/workspace"
        )
        do {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            #expect(viewModel.threadId == "active")
            await viewModel.restore(
                threadId: "next",
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            #expect(viewModel.threadId == "active")
            #expect(await adapter.activeThreadId() == "active")
            guard case .failed(let message) = viewModel.restoreState else {
                Issue.record("Codex restore failure was not observable")
                await viewModel.terminate()
                await adapter.close()
                return
            }
            #expect(message.contains("read failed"))
        } catch {
            await viewModel.terminate()
            await adapter.close()
            throw error
        }
        await viewModel.terminate()
        await adapter.close()
    }

    @Test("resume A/B の逆順応答でも最後の選択 ID だけを active にする")
    func resumeRaceCommitsLatestSelection() async throws {
        let transport = HistoryContractTransport(mode: .resumeRace)
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        await adapter.start()
        _ = try await adapter.threadStart(ThreadStartParams(cwd: "/workspace"))
        let history = CodexSessionHistory(client: adapter, workingDirectory: "/workspace")

        let first = Task { await history.resumeIfPossible(threadID: "A") }
        try await transport.waitForResumeRequest(count: 1)
        let second = Task { await history.resumeIfPossible(threadID: "B") }
        try await transport.waitForResumeRequest(count: 2)

        await transport.releaseResume(threadID: "B")
        await transport.releaseResume(threadID: "A")
        _ = await first.value
        _ = await second.value

        #expect(await adapter.activeThreadId() == "B")
        #expect(history.selectedThreadID == "B")
        await adapter.close()
    }

}

private enum HistoryResumeWaitError: Error {
    case timedOut
    case streamFinished
}

private final class HistoryContractTransport: AppServerTransport, @unchecked Sendable {
    enum Mode: Sendable, Equatable {
        case repeatedCursor
        case mixedSources
        case readFailure
        case resumeRace
    }

    private actor State {
        var listRequestCount = 0
        var resumeRequestCount = 0
        var resumeWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        func noteListRequest() { listRequestCount += 1 }
        func noteResumeRequest(_ threadID: String) -> Int {
            resumeRequestCount += 1
            return resumeRequestCount
        }

        func waitForResume(threadID: String) async {
            await withCheckedContinuation { continuation in
                resumeWaiters[threadID, default: []].append(continuation)
            }
        }

        func releaseResume(threadID: String) {
            resumeWaiters.removeValue(forKey: threadID)?.forEach { $0.resume() }
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let mode: Mode
    private let state = State()
    private let resumeRequestEvents: AsyncStream<Int>
    private let resumeRequestEventContinuation: AsyncStream<Int>.Continuation

    init(mode: Mode) {
        self.mode = mode
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
        var resumeRequestCaptured: AsyncStream<Int>.Continuation?
        resumeRequestEvents = AsyncStream(bufferingPolicy: .unbounded) {
            resumeRequestCaptured = $0
        }
        resumeRequestEventContinuation = resumeRequestCaptured!
    }

    var listRequestCount: Int {
        get async { await state.listRequestCount }
    }

    var resumeRequestCount: Int {
        get async { await state.resumeRequestCount }
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        guard let id = request["id"]?.intValue,
              let method = request["method"]?.stringValue else { return }

        let result: JSONValue
        switch method {
        case "initialize":
            result = .object([
                "codexHome": .string("/tmp/codex"),
                "platformFamily": .string("macOS"),
                "platformOs": .string("macOS"),
                "userAgent": .string("history-contract-test"),
            ])
        case "thread/start":
            result = .object(["thread": threadJSON(id: "active")])
        case "thread/list":
            await state.noteListRequest()
            result = listResponse(request: request)
        case "thread/resume":
            let threadID = request["params"]?["threadId"]?.stringValue ?? ""
            let requestCount = await state.noteResumeRequest(threadID)
            resumeRequestEventContinuation.yield(requestCount)
            if mode == .resumeRace {
                await state.waitForResume(threadID: threadID)
            }
            result = .object(["thread": threadJSON(id: threadID)])
        case "thread/read":
            let threadID = request["params"]?["threadId"]?.stringValue ?? ""
            if mode == .readFailure {
                let response = JSONValue.object([
                    "jsonrpc": .string("2.0"),
                    "id": .number(Double(id)),
                    "error": .object(["code": .number(-32000), "message": .string("read failed")]),
                ])
                continuation.yield(try JSONEncoder().encode(response))
                return
            }
            result = .object(["thread": threadJSON(id: threadID)])
        default:
            result = .object([:])
        }

        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "result": result,
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async { continuation.finish() }

    func releaseResume(threadID: String) async {
        await state.releaseResume(threadID: threadID)
    }

    func waitForResumeRequest(count expected: Int, timeout: Duration = .seconds(2)) async throws {
        guard await resumeRequestCount < expected else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [resumeRequestEvents] in
                for await count in resumeRequestEvents where count >= expected {
                    return
                }
                throw HistoryResumeWaitError.streamFinished
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HistoryResumeWaitError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func listResponse(request: JSONValue) -> JSONValue {
        switch mode {
        case .repeatedCursor:
            return .object([
                "data": .array([]),
                "nextCursor": .string("stuck"),
            ])
        case .mixedSources:
            return .object([
                "data": .array([
                    threadJSON(id: "main-cli", source: "cli"),
                    threadJSON(id: "child", source: .object(["subAgent": .string("review")]), parent: "main-cli"),
                    threadJSON(id: "parent-child", source: "appServer", parent: "main-cli"),
                    threadJSON(id: "exec", source: "exec"),
                ]),
                "nextCursor": .null,
            ])
        case .readFailure, .resumeRace:
            return .object(["data": .array([]), "nextCursor": .null])
        }
    }

    private func threadJSON(
        id: String,
        source: String = "appServer",
        parent: String? = nil
    ) -> JSONValue {
        threadJSON(id: id, source: .string(source), parent: parent)
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
            "source": source,
            "status": .object(["type": .string("idle")]),
            "turns": .array([]),
            "updatedAt": .number(2),
        ]
        if let parent { object["parentThreadId"] = .string(parent) }
        return .object(object)
    }
}
