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
        #expect(state.jumpTarget(for: "missing", transcriptItemIds: []) == nil)
    }

    @Test("対象 item が消えても processId が別 item に再利用されたら停止確定しない")
    func reusedProcessDoesNotConfirmTermination() async {
        let client = StateClient(lists: [[
            terminal(itemId: "item-1", processId: "process-1"),
        ], [
            terminal(itemId: "item-2", processId: "process-1"),
        ]], terminateResult: true)
        let state = CodexBackgroundTerminalState(client: client, threadId: "thread-1")

        await state.refresh()
        #expect(await state.terminate(itemId: "item-1") == false)
        #expect(state.terminal(itemId: "item-2")?.processId == "process-1")
        #expect(state.confirmedTerminationItemIds.isEmpty)
    }

    @Test("thread が無い・一覧失敗・空一覧をエラーと状態に反映する")
    func unavailableErrorAndEmptyAreObservable() async {
        let unavailable = CodexBackgroundTerminalState(client: StateClient(), threadId: nil)
        await unavailable.refresh()
        #expect(unavailable.items.isEmpty)
        #expect(unavailable.errorMessage != nil)

        let failed = CodexBackgroundTerminalState(client: StateClient(listError: "offline"), threadId: "thread-1")
        await failed.refresh()
        #expect(failed.items.isEmpty)
        #expect(failed.errorMessage?.contains("offline") == true)

        let empty = CodexBackgroundTerminalState(client: StateClient(lists: [[]]), threadId: "thread-1")
        await empty.refresh()
        #expect(empty.items.isEmpty)
        #expect(empty.errorMessage == nil)
    }

    @Test("thread が切り替わった後に返る旧一覧を状態へ適用しない")
    func staleThreadListIsDiscarded() async {
        let client = StateClient(
            lists: [[terminal(itemId: "old", processId: "p-old")]],
            listDelayNanoseconds: 20_000_000
        )
        let state = CodexBackgroundTerminalState(client: client, threadId: "thread-old")
        let refresh = Task { await state.refresh() }
        try? await Task.sleep(nanoseconds: 1_000_000)
        state.updateThreadId("thread-new")
        await refresh.value

        #expect(state.threadId == "thread-new")
        #expect(state.items.isEmpty)
    }

    @Test("一覧にある item でも transcript に無ければ jump しない")
    func jumpRequiresTranscriptMembership() async {
        let item = terminal(itemId: "item-1", processId: "process-1")
        let state = CodexBackgroundTerminalState(client: StateClient(lists: [[item]]), threadId: "thread-1")
        await state.refresh()

        #expect(state.jumpTarget(for: "item-1", transcriptItemIds: []) == nil)
        #expect(state.jumpTarget(for: "item-1", transcriptItemIds: ["item-1"]) == "item-1")
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
    let listError: String?
    let listDelayNanoseconds: UInt64
    var terminateRequests: [(String, String)] = []

    init(
        lists: [[ThreadBackgroundTerminal]] = [],
        terminateResult: Bool = false,
        listError: String? = nil,
        listDelayNanoseconds: UInt64 = 0
    ) {
        self.lists = lists
        self.terminateResult = terminateResult
        self.listError = listError
        self.listDelayNanoseconds = listDelayNanoseconds
    }

    func list() async throws -> [ThreadBackgroundTerminal] {
        if listDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: listDelayNanoseconds)
        }
        if let listError { throw StateClientError.message(listError) }
        return lists.isEmpty ? [] : lists.removeFirst()
    }

    func terminate(threadId: String, processId: String) -> Bool {
        terminateRequests.append((threadId, processId))
        return terminateResult
    }

    var lastTerminate: (String, String)? { terminateRequests.last }
}

private enum StateClientError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let value): value }
    }
}

private final class StateClient: CodexBackgroundTerminalProviding, @unchecked Sendable {
    private let recorder: StateClientRecorder

    init(
        lists: [[ThreadBackgroundTerminal]] = [],
        terminateResult: Bool = false,
        listError: String? = nil,
        listDelayNanoseconds: UInt64 = 0
    ) {
        recorder = StateClientRecorder(
            lists: lists,
            terminateResult: terminateResult,
            listError: listError,
            listDelayNanoseconds: listDelayNanoseconds
        )
    }

    func threadBackgroundTerminalsList(
        _ params: ThreadBackgroundTerminalsListParams
    ) async throws -> ThreadBackgroundTerminalsListResponse {
        ThreadBackgroundTerminalsListResponse(data: try await recorder.list())
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
