import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Regression: Codex child read stale")
@MainActor
struct CodexSubAgentReadStaleTests {
    @Test("refresh の read 失敗は該当 child だけを stale にし、成功 read で復元する")
    func refreshFailureRejectsStopThenRecovers() async throws {
        let client = ChildReadClient(parentID: "parent")
        try await withViewModel(client: client) { viewModel in
            await viewModel.refreshCodexSubAgents()
            let failed = try #require(viewModel.codexSubAgentState?.children.first)
            #expect(failed.id == "child")
            #expect(failed.status == "stale")
            #expect(viewModel.codexSubAgentState?.stopState(for: "child") == .stale)
            #expect(viewModel.codexSubAgentError != nil)

            await viewModel.stopCodexSubAgent(threadID: "child")
            #expect(await client.interruptCount == 0)

            await client.setMode(.success)
            await viewModel.refreshCodexSubAgents()
            let recovered = try #require(viewModel.codexSubAgentState?.children.first)
            #expect(recovered.activeTurnId == "child-turn")
            #expect(viewModel.codexSubAgentState?.stopState(for: "child") == .available)
            #expect(viewModel.codexSubAgentError == nil)

            await viewModel.stopCodexSubAgent(threadID: "child")
            #expect(await client.interruptCount == 1)
        }
    }

    @Test("detail の identity 不一致は既存 detail と停止操作を失効し、成功 read で復元する")
    func detailMismatchRejectsStopThenRecovers() async throws {
        let client = ChildReadClient(parentID: "parent")
        try await withViewModel(client: client) { viewModel in
            await client.setMode(.success)
            await viewModel.refreshCodexSubAgents()
            await viewModel.loadCodexSubAgentDetail(threadID: "child")
            #expect(viewModel.codexSubAgentState?.detail(for: "child")?.transcript == ["detail"])

            await client.setMode(.mismatchSource)
            await viewModel.loadCodexSubAgentDetail(threadID: "child")
            #expect(viewModel.codexSubAgentState?.detail(for: "child") == nil)
            #expect(viewModel.codexSubAgentState?.stopState(for: "child") == .stale)
            #expect(viewModel.codexSubAgentError?.contains("identity") == true)

            await viewModel.stopCodexSubAgent(threadID: "child")
            #expect(await client.interruptCount == 0)

            await client.setMode(.success)
            await viewModel.loadCodexSubAgentDetail(threadID: "child")
            #expect(viewModel.codexSubAgentState?.detail(for: "child")?.transcript == ["detail"])
            #expect(viewModel.codexSubAgentState?.stopState(for: "child") == .available)
            #expect(viewModel.codexSubAgentError == nil)
        }
    }

    private func withViewModel(
        client: ChildReadClient,
        operation: (ChatSessionViewModel) async throws -> Void
    ) async throws {
        let viewModel = try await makeViewModel(client: client)
        do {
            try await operation(viewModel)
        } catch {
            await viewModel.terminate()
            throw error
        }
        await viewModel.terminate()
    }

    private func makeViewModel(client: ChildReadClient) async throws -> ChatSessionViewModel {
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/workspace"
        )
        await viewModel.restore(
            threadId: "parent",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        return viewModel
    }
}

private enum ChildReadMode: Sendable {
    case failure
    case mismatchID
    case mismatchSource
    case success
}

private struct ChildReadFailure: Error, Sendable {}

private final class ChildReadClient: StructuredAgentClient, CodexSubAgentProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let parentID: String
    private let state = State()

    init(parentID: String) {
        self.parentID = parentID
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { continuation = $0 }
        continuation?.finish()
    }

    func setMode(_ mode: ChildReadMode) async {
        await state.setMode(mode)
    }

    var interruptCount: Int {
        get async { await state.interruptCount }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}

    func threadList(_ params: ThreadListParams) async throws -> ThreadListResponse {
        ThreadListResponse(data: [thread(id: "child", source: childSource(), turns: [])])
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        switch await state.mode {
        case .failure:
            throw ChildReadFailure()
        case .mismatchID:
            return response(thread: thread(id: "other", source: childSource(), turns: Self.turns))
        case .mismatchSource:
            return response(
                thread: thread(id: "child", source: .subAgent(.string("review")), turns: Self.turns)
            )
        case .success:
            return response(thread: thread(id: "child", source: childSource(), turns: Self.turns))
        }
    }

    func turnInterrupt(_ params: TurnInterruptParams) async throws -> TurnInterruptResponse {
        await state.recordInterrupt()
        return try! JSONDecoder().decode(TurnInterruptResponse.self, from: Data("{}".utf8))
    }

    private func childSource() -> ThreadSessionSource {
        .subAgent(.object(["parentThreadId": .string(parentID)]))
    }

    private func thread(
        id: String,
        source: ThreadSessionSource,
        turns: [TurnSummary]?
    ) -> ThreadSummary {
        ThreadSummary(
            id: id,
            cliVersion: "test",
            createdAt: 0,
            cwd: "/workspace",
            ephemeral: false,
            modelProvider: "test",
            preview: id,
            sessionId: "session-\(id)",
            source: source,
            status: .active(flags: []),
            turns: turns,
            updatedAt: 0,
            parentThreadId: parentID,
            canAcceptDirectInput: false
        )
    }

    private func response(thread: ThreadSummary) -> ThreadReadResponse {
        let threadJSON = try! JSONEncoder().encode(thread)
        let object = try! JSONDecoder().decode(JSONValue.self, from: threadJSON)
        let response = JSONValue.object(["thread": object])
        return try! JSONDecoder().decode(
            ThreadReadResponse.self,
            from: JSONEncoder().encode(response)
        )
    }

    private static let turns: [TurnSummary] = {
        let data = Data(#"[{"id":"child-turn","status":"inProgress","items":[{"id":"item","type":"agentMessage","text":"detail"}]}]"#.utf8)
        return try! JSONDecoder().decode([TurnSummary].self, from: data)
    }()

    private actor State {
        var mode: ChildReadMode = .failure
        var interruptCount = 0

        func setMode(_ mode: ChildReadMode) {
            self.mode = mode
        }

        func recordInterrupt() {
            interruptCount += 1
        }
    }
}
