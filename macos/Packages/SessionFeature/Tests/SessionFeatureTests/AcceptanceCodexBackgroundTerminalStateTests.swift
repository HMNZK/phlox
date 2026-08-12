import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex background terminal state")
@MainActor
struct AcceptanceCodexBackgroundTerminalStateTests {
    @Test("一覧・詳細は itemId をキーにし、停止は processId と threadId を送る")
    func statePreservesDistinctIdentity() async throws {
        let client = StateClient(
            lists: [[
                terminal(itemId: "item-1", processId: "process-1", command: "one"),
                terminal(itemId: "item-2", processId: "process-2", command: "two"),
            ], []],
            terminateResult: true
        )
        let state = CodexBackgroundTerminalState(client: client, threadId: "thread-1")

        await state.refresh()
        #expect(state.items.map(\.itemId) == ["item-1", "item-2"])
        #expect(state.detail(for: "item-2")?.processId == "process-2")
        #expect(state.select(itemId: "item-2"))
        #expect(await state.terminate(itemId: "item-2"))
        let request = await client.lastTerminate
        #expect(request?.0 == "thread-1")
        #expect(request?.1 == "process-2")
        #expect(state.terminal(itemId: "item-2") == nil)
    }

    @Test("terminate=false は一覧を勝手に消さず、missing item は jump しない")
    func stateDoesNotConfirmUnverifiedTermination() async {
        let item = terminal(itemId: "item-1", processId: "process-1")
        let client = StateClient(lists: [[item]], terminateResult: false)
        let state = CodexBackgroundTerminalState(client: client, threadId: "thread-1")

        await state.refresh()
        #expect(await state.terminate(itemId: "item-1") == false)
        #expect(state.terminal(itemId: "item-1") == item)
        #expect(state.jumpTarget(for: "missing") == nil)
    }

    private static func terminal(
        itemId: String,
        processId: String,
        command: String = "echo test"
    ) -> ThreadBackgroundTerminal {
        ThreadBackgroundTerminal(
            itemId: itemId,
            processId: processId,
            command: command,
            cwd: "/tmp"
        )
    }

    private func terminal(
        itemId: String,
        processId: String,
        command: String = "echo test"
    ) -> ThreadBackgroundTerminal {
        Self.terminal(itemId: itemId, processId: processId, command: command)
    }
}

private actor StateClientRecorder {
    var lists: [[ThreadBackgroundTerminal]]
    var terminateResult: Bool
    var terminateRequests: [(String, String)] = []

    init(lists: [[ThreadBackgroundTerminal]], terminateResult: Bool) {
        self.lists = lists
        self.terminateResult = terminateResult
    }

    func list() -> [ThreadBackgroundTerminal] {
        lists.isEmpty ? [] : lists.removeFirst()
    }

    func terminate(threadId: String, processId: String) -> Bool {
        terminateRequests.append((threadId, processId))
        return terminateResult
    }

    var lastTerminate: (String, String)? { terminateRequests.last }
}

private final class StateClient: CodexBackgroundTerminalProviding, @unchecked Sendable {
    private let recorder: StateClientRecorder

    init(lists: [[ThreadBackgroundTerminal]], terminateResult: Bool) {
        recorder = StateClientRecorder(lists: lists, terminateResult: terminateResult)
    }

    func threadBackgroundTerminalsList(
        _ params: ThreadBackgroundTerminalsListParams
    ) async throws -> ThreadBackgroundTerminalsListResponse {
        ThreadBackgroundTerminalsListResponse(data: await recorder.list())
    }

    func threadBackgroundTerminalsTerminate(
        _ params: ThreadBackgroundTerminalsTerminateParams
    ) async throws -> ThreadBackgroundTerminalsTerminateResponse {
        ThreadBackgroundTerminalsTerminateResponse(
            terminated: await recorder.terminate(threadId: params.threadId, processId: params.processId)
        )
    }

    var lastTerminate: (String, String)? {
        get async { await recorder.lastTerminate }
    }
}
